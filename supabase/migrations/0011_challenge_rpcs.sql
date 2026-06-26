-- Migration 0011: Challenge RPCs (SDD spec)
-- create_challenge, activate_challenge, enroll_individual, complete_overdue_challenges
-- All writes go through SECURITY DEFINER RPCs; RLS policies already in place (0009).

-- ── create_challenge ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_challenge(
  p_title          text,
  p_description    text,
  p_start_date     date,
  p_end_date       date,
  p_enrollment_type text
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_company_id uuid;
  v_challenge_id uuid;
BEGIN
  IF (SELECT role FROM profiles WHERE id = auth.uid()) != 'admin' THEN
    RAISE EXCEPTION 'Only admins can create challenges';
  END IF;

  IF p_end_date <= p_start_date THEN
    RAISE EXCEPTION 'end_date must be after start_date';
  END IF;

  IF p_enrollment_type NOT IN ('individual', 'team') THEN
    RAISE EXCEPTION 'enrollment_type must be individual or team';
  END IF;

  v_company_id := public.my_company_id();

  INSERT INTO challenges (company_id, title, description, start_date, end_date, enrollment_type, created_by)
  VALUES (v_company_id, p_title, p_description, p_start_date, p_end_date, p_enrollment_type, auth.uid())
  RETURNING id INTO v_challenge_id;

  RETURN v_challenge_id;
END;
$$;

-- ── activate_challenge ────────────────────────────────────────────────────
-- Transitions a draft challenge to active.
-- Blocked if another challenge is already active for the same company.
CREATE OR REPLACE FUNCTION public.activate_challenge(p_challenge_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_company_id uuid;
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
END;
$$;

-- ── enroll_individual ─────────────────────────────────────────────────────
-- Any member can enroll themselves in an individual challenge while it is draft.
CREATE OR REPLACE FUNCTION public.enroll_individual(p_challenge_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_enrollment_type text;
  v_status          text;
  v_company_id      uuid;
BEGIN
  v_company_id := public.my_company_id();

  SELECT enrollment_type, status
  INTO v_enrollment_type, v_status
  FROM challenges
  WHERE id = p_challenge_id AND company_id = v_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Challenge not found';
  END IF;

  IF v_enrollment_type != 'individual' THEN
    RAISE EXCEPTION 'This challenge is team-based; individuals cannot enroll directly';
  END IF;

  IF v_status != 'draft' THEN
    RAISE EXCEPTION 'Enrollment is only allowed while the challenge is in draft status';
  END IF;

  INSERT INTO challenge_enrollments (challenge_id, user_id)
  VALUES (p_challenge_id, auth.uid());
  -- Duplicate enrollment is blocked by the UNIQUE NULLS NOT DISTINCT index on (challenge_id, user_id)
END;
$$;

-- ── complete_overdue_challenges ───────────────────────────────────────────
-- Called daily by pg_cron. Closes any active challenge whose end_date has passed.
CREATE OR REPLACE FUNCTION public.complete_overdue_challenges()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE challenges
  SET status = 'completed'
  WHERE status = 'active'
    AND end_date < CURRENT_DATE;
END;
$$;

-- ── pg_cron setup (manual step, outside migration) ───────────────────────
-- To schedule complete_overdue_challenges() daily, enable pg_cron first:
--   Dashboard → Database → Extensions → pg_cron → Enable
-- Then run once in SQL Editor:
--   SELECT cron.schedule('complete-overdue-challenges','0 1 * * *',
--     $$ SELECT public.complete_overdue_challenges(); $$);
