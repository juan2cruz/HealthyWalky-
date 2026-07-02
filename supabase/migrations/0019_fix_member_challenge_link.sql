-- Migration 0019: Repair team_members.challenge_id for active challenges
--
-- Symptom: leaderboard showed member_count = 0 and avg_steps = 0 for every
-- enrolled team.  0017 scoped the leaderboard join to
-- tm.challenge_id = p_challenge_id, but several historical paths leave active
-- members with challenge_id NULL or pointing at a previous challenge:
--   * activate_challenge (0015) only propagates WHERE challenge_id IS NULL,
--     so rows still holding a finished challenge's id are never updated
--     (complete_overdue_challenges / older flows don't clear them).
--   * The 0017 creator backfill only ran for creators, and only when
--     teams.challenge_id happened to be non-NULL at migration time.
--   * respond_invitation / respond_join_request copy teams.challenge_id,
--     which is NULL when the member joins before the team enrolls.
-- Any such row is invisible to the scoped join → zero counts.

-- ── 1. Backfill: link active members to their team's active enrollment ──────
-- The NOT EXISTS guard respects the team_members_one_active_per_challenge
-- unique index (user_id, challenge_id) in case a user somehow has active rows
-- in two enrolled teams.
UPDATE team_members tm
SET challenge_id = ce.challenge_id
FROM challenge_enrollments ce
JOIN challenges c
  ON c.id = ce.challenge_id
 AND c.status = 'active'
WHERE ce.team_id = tm.team_id
  AND ce.status = 'active'
  AND tm.status = 'active'
  AND tm.challenge_id IS DISTINCT FROM ce.challenge_id
  AND NOT EXISTS (
    SELECT 1 FROM team_members other
    WHERE other.user_id = tm.user_id
      AND other.challenge_id = ce.challenge_id
      AND other.id != tm.id
  );

-- ── 2. Harden activate_challenge: overwrite stale challenge_ids ─────────────
-- Same body as 0015 except the member propagation no longer requires
-- challenge_id IS NULL, so re-activation always relinks active members.
CREATE OR REPLACE FUNCTION public.activate_challenge(p_challenge_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_company_id   uuid;
  v_enroll_type  text;
BEGIN
  IF (SELECT role FROM profiles WHERE id = auth.uid()) != 'admin' THEN
    RAISE EXCEPTION 'Only admins can activate challenges';
  END IF;

  v_company_id := public.my_company_id();

  IF EXISTS (
    SELECT 1 FROM challenges
    WHERE company_id = v_company_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Another challenge is already active for this company';
  END IF;

  UPDATE challenges
  SET status = 'active'
  WHERE id = p_challenge_id
    AND company_id = v_company_id
    AND status = 'draft';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Challenge not found or not in draft status';
  END IF;

  SELECT enrollment_type INTO v_enroll_type
  FROM challenges WHERE id = p_challenge_id;

  IF v_enroll_type = 'team' THEN
    -- Enroll every approved/enrolled team into the newly-active challenge.
    INSERT INTO challenge_enrollments (challenge_id, team_id)
    SELECT p_challenge_id, t.id
    FROM teams t
    WHERE t.company_id = v_company_id
      AND t.status IN ('approved', 'enrolled')
    ON CONFLICT DO NOTHING;

    -- Transition those teams to 'active' status.
    UPDATE teams
    SET status = 'active', challenge_id = p_challenge_id
    WHERE company_id = v_company_id
      AND status IN ('approved', 'enrolled');

    -- Relink all active members, overwriting NULL or stale challenge_ids.
    UPDATE team_members
    SET challenge_id = p_challenge_id
    WHERE team_id IN (
      SELECT id FROM teams
      WHERE company_id = v_company_id AND challenge_id = p_challenge_id
    )
    AND status = 'active'
    AND challenge_id IS DISTINCT FROM p_challenge_id;
  END IF;
END;
$$;
