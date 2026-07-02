-- Migration 0015: Fix team enrollment on challenge activation
-- Problem: activate_challenge only changed challenge.status; it never created
-- challenge_enrollments rows for approved teams.  As a result, refresh_leaderboard
-- JOIN-ed against an empty challenge_enrollments and produced no snapshot rows.
--
-- Fix A: modify activate_challenge to auto-enroll every approved/enrolled team.
-- Fix B: add admin_enroll_team for retroactive enrollment on already-active challenges.

-- ── A. activate_challenge (updated) ──────────────────────────────────────────
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

    -- Propagate challenge_id to their active members.
    UPDATE team_members
    SET challenge_id = p_challenge_id
    WHERE team_id IN (
      SELECT id FROM teams
      WHERE company_id = v_company_id AND challenge_id = p_challenge_id
    )
    AND status = 'active'
    AND challenge_id IS NULL;
  END IF;
END;
$$;

-- ── B. admin_enroll_team — retroactive enrollment for already-active challenges ─
-- Use this when a team was approved AFTER the challenge was activated, or when
-- the old activate_challenge left teams unenrolled.
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
END;
$$;
