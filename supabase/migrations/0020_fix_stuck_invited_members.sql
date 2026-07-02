-- Migration 0020: Unfreeze members stuck as 'invited' and expire pending
-- invites at challenge activation
--
-- Root cause of the zero member_count on the leaderboard: both members of the
-- enrolled team had team_members.status = 'invited'.  The old create_team never
-- added the creator, so creators self-invited via invite_to_team and stayed
-- 'invited' (0017's backfill hit ON CONFLICT DO NOTHING on those rows).  Once
-- the challenge became active, respond_invitation is blocked, so those
-- invitations can never be answered — the members are frozen out of the
-- leaderboard forever (it only counts status = 'active').
--
-- Repair: activate invited members of teams enrolled in the active challenge
-- (they were invited by the creator before the competition started), plus any
-- creator stuck as 'invited' in their own team.  Prevention: activate_challenge
-- and admin_enroll_team now expire (reject) unanswered invitations/join
-- requests when a team enters competition, so the roster freezes visibly
-- instead of leaving rows in a permanently unanswerable state.

-- ── 1. Activate invited members of teams enrolled in an active challenge ────
UPDATE team_members tm
SET status = 'active'
FROM challenge_enrollments ce
JOIN challenges c
  ON c.id = ce.challenge_id
 AND c.status = 'active'
WHERE ce.team_id = tm.team_id
  AND ce.status = 'active'
  AND tm.status = 'invited';

-- ── 2. Creators stuck as 'invited' in their own team → active ───────────────
UPDATE team_members tm
SET status = 'active'
FROM teams t
WHERE t.id = tm.team_id
  AND t.created_by = tm.user_id
  AND tm.status = 'invited';

-- ── 3. Relink challenge_id for the newly activated rows (same as 0019) ──────
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

-- ── 4. activate_challenge: expire unanswered invites/requests on activation ─
-- Same body as 0019, plus the roster-freeze cleanup at the end.
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

    -- Freeze rosters: expire invitations/join requests nobody answered.
    -- respond_invitation / respond_join_request are blocked while a challenge
    -- is active, so leaving these pending would make them unanswerable.
    UPDATE team_members
    SET status = 'rejected'
    WHERE team_id IN (
      SELECT id FROM teams
      WHERE company_id = v_company_id AND challenge_id = p_challenge_id
    )
    AND status IN ('invited', 'request_pending');
  END IF;
END;
$$;

-- ── 5. admin_enroll_team: same roster freeze on retroactive enrollment ──────
CREATE OR REPLACE FUNCTION public.admin_enroll_team(
  p_team_id      uuid,
  p_challenge_id uuid
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF (SELECT role FROM profiles WHERE id = auth.uid()) != 'admin' THEN
    RAISE EXCEPTION 'Only admins can retroactively enroll teams';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM teams
    WHERE id = p_team_id AND company_id = public.my_company_id()
  ) THEN
    RAISE EXCEPTION 'Team not found in your company';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM challenges
    WHERE id = p_challenge_id
      AND company_id = public.my_company_id()
      AND status = 'active'
      AND enrollment_type = 'team'
  ) THEN
    RAISE EXCEPTION 'Active team challenge not found in your company';
  END IF;

  INSERT INTO challenge_enrollments (challenge_id, team_id)
  VALUES (p_challenge_id, p_team_id)
  ON CONFLICT DO NOTHING;

  UPDATE teams
  SET status = 'active', challenge_id = p_challenge_id
  WHERE id = p_team_id AND company_id = public.my_company_id();

  UPDATE team_members
  SET challenge_id = p_challenge_id
  WHERE team_id = p_team_id AND status = 'active';

  -- Freeze roster: expire unanswered invitations/join requests.
  UPDATE team_members
  SET status = 'rejected'
  WHERE team_id = p_team_id
    AND status IN ('invited', 'request_pending');
END;
$$;
