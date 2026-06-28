-- Migration 0012: Steps registration & leaderboard RPCs (SDD spec Paso 6)
-- Adds count_weekends to challenges, updates create_challenge, adds step RPCs and leaderboard query.

-- ── Schema change ─────────────────────────────────────────────────────────
ALTER TABLE challenges
  ADD COLUMN IF NOT EXISTS count_weekends boolean NOT NULL DEFAULT true;

-- ── create_challenge (updated signature — adds p_count_weekends) ──────────
CREATE OR REPLACE FUNCTION public.create_challenge(
  p_title           text,
  p_description     text,
  p_start_date      date,
  p_end_date        date,
  p_enrollment_type text,
  p_count_weekends  boolean DEFAULT true
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_company_id   uuid;
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

  INSERT INTO challenges (company_id, title, description, start_date, end_date, enrollment_type, count_weekends, created_by)
  VALUES (v_company_id, p_title, p_description, p_start_date, p_end_date, p_enrollment_type, p_count_weekends, auth.uid())
  RETURNING id INTO v_challenge_id;

  RETURN v_challenge_id;
END;
$$;

-- ── upsert_steps ──────────────────────────────────────────────────────────
-- Inserts or updates a daily step record for the calling user.
-- Conflict logic:
--   same (user, date, source)  → update step_count only
--   new source, date already has a canonical record → mark both as 'conflict'
--   new source, no canonical exists  → insert as canonical
CREATE OR REPLACE FUNCTION public.upsert_steps(
  p_step_date  date,
  p_step_count integer,
  p_source     text
)
RETURNS text   -- returns 'ok' or 'conflict'
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_company_id      uuid;
  v_existing_source text;
BEGIN
  IF p_step_count < 0 THEN
    RAISE EXCEPTION 'step_count must be >= 0';
  END IF;

  IF p_source NOT IN ('manual', 'google_fit', 'apple_health') THEN
    RAISE EXCEPTION 'invalid source';
  END IF;

  v_company_id := public.my_company_id();

  -- Case 1: record for same (user, date, source) already exists → update
  IF EXISTS (
    SELECT 1 FROM daily_steps
    WHERE user_id = auth.uid()
      AND step_date = p_step_date
      AND source = p_source
  ) THEN
    UPDATE daily_steps
    SET step_count = p_step_count, updated_at = now()
    WHERE user_id = auth.uid()
      AND step_date = p_step_date
      AND source = p_source;
    RETURN 'ok';
  END IF;

  -- Case 2: a canonical record from a DIFFERENT source already exists → conflict
  SELECT source INTO v_existing_source
  FROM daily_steps
  WHERE user_id = auth.uid()
    AND step_date = p_step_date
    AND is_canonical = true
  LIMIT 1;

  IF FOUND THEN
    -- Insert new record as non-canonical with conflict status
    INSERT INTO daily_steps (user_id, company_id, step_date, step_count, source, is_canonical, sync_status)
    VALUES (auth.uid(), v_company_id, p_step_date, p_step_count, p_source, false, 'conflict');

    -- Flag the existing canonical record as conflict too
    UPDATE daily_steps
    SET sync_status = 'conflict', updated_at = now()
    WHERE user_id = auth.uid()
      AND step_date = p_step_date
      AND source = v_existing_source;

    RETURN 'conflict';
  END IF;

  -- Case 3: no record for this date yet → clean insert
  INSERT INTO daily_steps (user_id, company_id, step_date, step_count, source, is_canonical, sync_status)
  VALUES (auth.uid(), v_company_id, p_step_date, p_step_count, p_source, true, 'synced');

  RETURN 'ok';
END;
$$;

-- ── resolve_step_conflict ─────────────────────────────────────────────────
-- User picks which source wins for a given day.
-- Winning source → is_canonical = true, sync_status = 'synced'
-- All other sources for that day → is_canonical = false, sync_status = 'synced'
CREATE OR REPLACE FUNCTION public.resolve_step_conflict(
  p_step_date      date,
  p_winning_source text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  -- Validate winning source exists for this user/date
  IF NOT EXISTS (
    SELECT 1 FROM daily_steps
    WHERE user_id = auth.uid()
      AND step_date = p_step_date
      AND source = p_winning_source
  ) THEN
    RAISE EXCEPTION 'No step record found for that date and source';
  END IF;

  -- Set all records for (user, date) to non-canonical and resolved
  UPDATE daily_steps
  SET is_canonical = false,
      sync_status  = 'synced',
      updated_at   = now()
  WHERE user_id   = auth.uid()
    AND step_date = p_step_date;

  -- Promote the winner
  UPDATE daily_steps
  SET is_canonical = true,
      updated_at   = now()
  WHERE user_id   = auth.uid()
    AND step_date = p_step_date
    AND source    = p_winning_source;
END;
$$;

-- ── get_my_steps_in_challenge ─────────────────────────────────────────────
-- Returns the calling user's canonical step records for the given challenge range.
CREATE OR REPLACE FUNCTION public.get_my_steps_in_challenge(p_challenge_id uuid)
RETURNS TABLE (
  step_date    date,
  step_count   integer,
  source       text,
  sync_status  text
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_start date;
  v_end   date;
BEGIN
  SELECT start_date, LEAST(end_date, CURRENT_DATE)
  INTO v_start, v_end
  FROM challenges
  WHERE id = p_challenge_id
    AND company_id = public.my_company_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Challenge not found';
  END IF;

  RETURN QUERY
  SELECT ds.step_date, ds.step_count, ds.source, ds.sync_status
  FROM daily_steps ds
  WHERE ds.user_id     = auth.uid()
    AND ds.is_canonical = true
    AND ds.step_date BETWEEN v_start AND v_end
  ORDER BY ds.step_date DESC;
END;
$$;

-- ── get_my_conflicts ──────────────────────────────────────────────────────
-- Returns dates where the calling user has unresolved step conflicts,
-- including both records so the UI can display the choice.
CREATE OR REPLACE FUNCTION public.get_my_conflicts()
RETURNS TABLE (
  step_date    date,
  source       text,
  step_count   integer,
  is_canonical boolean
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
  SELECT ds.step_date, ds.source, ds.step_count, ds.is_canonical
  FROM daily_steps ds
  WHERE ds.user_id    = auth.uid()
    AND ds.sync_status = 'conflict'
  ORDER BY ds.step_date DESC, ds.source;
END;
$$;

-- ── get_team_leaderboard ──────────────────────────────────────────────────
-- Returns ranked teams for the given active challenge.
-- Metric: total canonical steps of all active members / number of active members.
-- Respects count_weekends setting: if false, weekend days are excluded.
CREATE OR REPLACE FUNCTION public.get_team_leaderboard(p_challenge_id uuid)
RETURNS TABLE (
  position     bigint,
  team_id      uuid,
  team_name    text,
  member_count bigint,
  avg_steps    numeric
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_start         date;
  v_end           date;
  v_count_weekends boolean;
BEGIN
  SELECT start_date,
         LEAST(end_date, CURRENT_DATE),
         count_weekends
  INTO v_start, v_end, v_count_weekends
  FROM challenges
  WHERE id = p_challenge_id
    AND company_id = public.my_company_id()
    AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active challenge not found';
  END IF;

  RETURN QUERY
  SELECT
    RANK() OVER (ORDER BY
      COALESCE(SUM(ds.step_count)::numeric / NULLIF(COUNT(DISTINCT tm.user_id), 0), 0) DESC
    )                                                                   AS position,
    t.id                                                                AS team_id,
    t.name                                                              AS team_name,
    COUNT(DISTINCT tm.user_id)                                          AS member_count,
    COALESCE(
      ROUND(SUM(ds.step_count)::numeric / NULLIF(COUNT(DISTINCT tm.user_id), 0)),
      0
    )                                                                   AS avg_steps
  FROM teams t
  JOIN challenge_enrollments ce
    ON ce.team_id = t.id AND ce.challenge_id = p_challenge_id
  JOIN team_members tm
    ON tm.team_id = t.id AND tm.status = 'active'
  LEFT JOIN daily_steps ds
    ON ds.user_id      = tm.user_id
   AND ds.is_canonical = true
   AND ds.step_date BETWEEN v_start AND v_end
   AND (
     v_count_weekends = true
     OR EXTRACT(DOW FROM ds.step_date) NOT IN (0, 6)  -- exclude Sunday(0) and Saturday(6)
   )
  GROUP BY t.id, t.name
  ORDER BY avg_steps DESC;
END;
$$;
