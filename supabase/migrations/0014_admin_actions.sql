-- Migration 0014: Admin destructive actions
-- 1. abort_team      — soft-delete a team, free its members
-- 2. kick_user       — hard-delete a member's profile + all their data
-- 3. cancel_challenge — permanently cancel an active challenge

-- ── 1a. Add 'archived' to teams.status ────────────────────────────────────
ALTER TABLE teams DROP CONSTRAINT IF EXISTS teams_status_check;
ALTER TABLE teams ADD CONSTRAINT teams_status_check
  CHECK (status IN ('draft', 'approved', 'enrolled', 'active', 'completed', 'disqualified', 'archived'));

-- ── 1b. abort_team(p_team_id) ─────────────────────────────────────────────
-- Admin only. Soft-deletes the team (status → 'archived'), frees its active/pending
-- members so they can join other teams, and withdraws any challenge enrollment.
CREATE OR REPLACE FUNCTION public.abort_team(p_team_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF (SELECT role FROM profiles WHERE id = auth.uid()) != 'admin' THEN
    RAISE EXCEPTION 'Only admins can abort teams';
  END IF;

  UPDATE teams
  SET status = 'archived'
  WHERE id = p_team_id
    AND company_id = public.my_company_id()
    AND status NOT IN ('archived', 'completed');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Team not found or cannot be aborted in its current state';
  END IF;

  -- Free members so they can enroll in other teams
  DELETE FROM team_members
  WHERE team_id = p_team_id
    AND status IN ('active', 'invited', 'request_pending');

  -- Withdraw from any active challenge enrollment
  UPDATE challenge_enrollments
  SET status = 'withdrawn'
  WHERE team_id = p_team_id AND status = 'active';

  -- Remove stale leaderboard entries
  DELETE FROM leaderboard_snapshots
  WHERE entity_id = p_team_id AND entity_type = 'team';
END;
$$;

-- ── 2a. Cascade FK on daily_steps.user_id ─────────────────────────────────
ALTER TABLE daily_steps DROP CONSTRAINT IF EXISTS daily_steps_user_id_fkey;
ALTER TABLE daily_steps ADD CONSTRAINT daily_steps_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;

-- ── 2b. Cascade FK on team_members.user_id ────────────────────────────────
ALTER TABLE team_members DROP CONSTRAINT IF EXISTS team_members_user_id_fkey;
ALTER TABLE team_members ADD CONSTRAINT team_members_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;

-- ── 2c. Cascade FK on challenge_enrollments.user_id ───────────────────────
ALTER TABLE challenge_enrollments DROP CONSTRAINT IF EXISTS challenge_enrollments_user_id_fkey;
ALTER TABLE challenge_enrollments ADD CONSTRAINT challenge_enrollments_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;

-- ── 2d. kick_user(p_user_id) ──────────────────────────────────────────────
-- Admin only. Transfers team ownership then deletes the member's profile.
-- Cascades remove daily_steps, team_members, and individual challenge_enrollments.
-- The auth.users row is preserved (user sees empty app if they try to log in).
CREATE OR REPLACE FUNCTION public.kick_user(p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_target_company uuid;
  v_target_role    text;
BEGIN
  IF (SELECT role FROM profiles WHERE id = auth.uid()) != 'admin' THEN
    RAISE EXCEPTION 'Only admins can kick users';
  END IF;

  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'You cannot kick yourself';
  END IF;

  SELECT company_id, role INTO v_target_company, v_target_role
  FROM profiles WHERE id = p_user_id;

  IF v_target_company IS NULL OR v_target_company != public.my_company_id() THEN
    RAISE EXCEPTION 'User not found in your company';
  END IF;

  IF v_target_role = 'admin' THEN
    RAISE EXCEPTION 'Cannot kick an admin user';
  END IF;

  -- Transfer ownership of any teams this user created to the calling admin
  UPDATE teams
  SET created_by = auth.uid()
  WHERE created_by = p_user_id
    AND company_id = public.my_company_id();

  -- Delete profile; ON DELETE CASCADE handles daily_steps, team_members,
  -- and individual challenge_enrollments automatically.
  DELETE FROM profiles WHERE id = p_user_id;
END;
$$;

-- ── 3a. Add 'cancelled' to challenges.status ──────────────────────────────
ALTER TABLE challenges DROP CONSTRAINT IF EXISTS challenges_status_check;
ALTER TABLE challenges ADD CONSTRAINT challenges_status_check
  CHECK (status IN ('draft', 'active', 'completed', 'cancelled'));

-- ── 3b. cancel_challenge(p_challenge_id) ─────────────────────────────────
-- Admin only. Permanently cancels an active challenge.
-- Resets enrolled teams so they can enter a future challenge.
CREATE OR REPLACE FUNCTION public.cancel_challenge(p_challenge_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF (SELECT role FROM profiles WHERE id = auth.uid()) != 'admin' THEN
    RAISE EXCEPTION 'Only admins can cancel challenges';
  END IF;

  UPDATE challenges
  SET status = 'cancelled'
  WHERE id = p_challenge_id
    AND company_id = public.my_company_id()
    AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active challenge not found in your company';
  END IF;

  -- Reset teams so they can enroll in a future challenge
  UPDATE teams
  SET status = 'approved', challenge_id = NULL
  WHERE challenge_id = p_challenge_id
    AND status IN ('enrolled', 'active', 'disqualified');

  -- Clear the challenge link from all associated team members
  UPDATE team_members
  SET challenge_id = NULL
  WHERE challenge_id = p_challenge_id;

  -- Remove leaderboard snapshots for this challenge
  DELETE FROM leaderboard_snapshots WHERE challenge_id = p_challenge_id;
END;
$$;
