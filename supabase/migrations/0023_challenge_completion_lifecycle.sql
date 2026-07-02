-- Migration 0023: Challenge completion lifecycle
--
-- Dead-ends fixed:
-- 1. Teams stuck as zombies after a challenge ends naturally: cancel_challenge
--    resets teams to 'approved' but nothing did the same on completion, so
--    teams stayed status='active' forever and could never enroll again.
--    complete_overdue_challenges now resets teams, and a new manual
--    complete_challenge RPC lets the admin close an over-date challenge without
--    waiting for the nightly cron.
--    team_members.challenge_id is intentionally NOT cleared: it scopes each
--    membership (and its steps) to the finished challenge, and enroll_team /
--    activate_challenge already relink it on the next enrollment.
-- 2. enroll_team / active_challenge_id treated 'cancelled' challenges as
--    enrollable/upcoming (filters used NOT IN ('active','completed')), so a
--    team could enroll into a cancelled challenge.  Both now whitelist states.
-- 3. pg_cron job scheduled so completion actually runs daily (documented in
--    0011/0013 but never enabled).

-- ── 1. active_challenge_id: cancelled challenges are not "current" ────────
CREATE OR REPLACE FUNCTION public.active_challenge_id()
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT id FROM challenges
  WHERE company_id = public.my_company_id()
    AND status IN ('draft', 'active')
  ORDER BY created_at DESC
  LIMIT 1
$$;

-- ── 2. enroll_team: only draft challenges are enrollable ──────────────────
CREATE OR REPLACE FUNCTION public.enroll_team(p_team_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_challenge_id uuid;
BEGIN
  SELECT id INTO v_challenge_id
  FROM challenges
  WHERE company_id = public.my_company_id()
    AND status = 'draft'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_challenge_id IS NULL THEN
    RAISE EXCEPTION 'No enrollable challenge found for this company';
  END IF;

  UPDATE teams
  SET status = 'enrolled', challenge_id = v_challenge_id
  WHERE id = p_team_id
    AND company_id = public.my_company_id()
    AND status = 'approved';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Team not found or not in approved status';
  END IF;

  UPDATE team_members
  SET challenge_id = v_challenge_id
  WHERE team_id = p_team_id AND status = 'active';

  INSERT INTO challenge_enrollments (challenge_id, team_id)
  VALUES (v_challenge_id, p_team_id)
  ON CONFLICT DO NOTHING;
END;
$$;

-- ── 3. Shared team reset on challenge end ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.reset_teams_after_challenge(p_challenge_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE teams
  SET status = 'approved', challenge_id = NULL
  WHERE challenge_id = p_challenge_id
    AND status IN ('enrolled', 'active', 'disqualified');
END;
$$;

-- ── 4. complete_overdue_challenges: also free the teams ───────────────────
CREATE OR REPLACE FUNCTION public.complete_overdue_challenges()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_id uuid;
BEGIN
  FOR v_id IN
    SELECT id FROM challenges
    WHERE status = 'active' AND end_date < CURRENT_DATE
  LOOP
    UPDATE challenges SET status = 'completed' WHERE id = v_id;
    PERFORM public.reset_teams_after_challenge(v_id);
  END LOOP;
END;
$$;

-- ── 5. complete_challenge: manual admin completion ────────────────────────
-- Allowed once the end date has been reached; cancel_challenge remains the
-- escape hatch for aborting mid-flight.
CREATE OR REPLACE FUNCTION public.complete_challenge(p_challenge_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF (SELECT role FROM profiles WHERE id = auth.uid()) != 'admin' THEN
    RAISE EXCEPTION 'Only admins can complete challenges';
  END IF;

  UPDATE challenges
  SET status = 'completed'
  WHERE id = p_challenge_id
    AND company_id = public.my_company_id()
    AND status = 'active'
    AND end_date <= CURRENT_DATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Challenge not found, not active, or has not reached its end date yet';
  END IF;

  PERFORM public.reset_teams_after_challenge(p_challenge_id);
END;
$$;

-- ── 6. Schedule the nightly completion job ────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_cron;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'complete-overdue-challenges') THEN
    PERFORM cron.unschedule('complete-overdue-challenges');
  END IF;
  PERFORM cron.schedule(
    'complete-overdue-challenges',
    '0 1 * * *',
    'SELECT public.complete_overdue_challenges()'
  );
END $$;
