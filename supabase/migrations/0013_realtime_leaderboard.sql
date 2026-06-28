-- Migration 0013: Realtime leaderboard — snapshot refresh RPCs + pg_cron setup
-- Adds refresh_leaderboard() and refresh_all_active_leaderboards() functions.
-- Enables Supabase Realtime on leaderboard_snapshots.

-- ── Enable Realtime on leaderboard_snapshots ──────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE public.leaderboard_snapshots;

-- ── refresh_leaderboard(p_challenge_id) ───────────────────────────────────
-- Clears and repopulates leaderboard_snapshots for one challenge.
-- Safe to call from both the Flutter app (with auth context) and pg_cron (no auth).
CREATE OR REPLACE FUNCTION public.refresh_leaderboard(p_challenge_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_start          date;
  v_end            date;
  v_count_weekends boolean;
BEGIN
  -- If called from app, restrict to caller's company
  IF auth.uid() IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM challenges
      WHERE id = p_challenge_id
        AND company_id = public.my_company_id()
        AND status = 'active'
    ) THEN
      RAISE EXCEPTION 'Active challenge not found';
    END IF;
  END IF;

  SELECT start_date,
         LEAST(end_date, CURRENT_DATE),
         count_weekends
  INTO v_start, v_end, v_count_weekends
  FROM challenges
  WHERE id = p_challenge_id AND status = 'active';

  IF NOT FOUND THEN RETURN; END IF;

  -- Clear existing snapshot for this challenge
  DELETE FROM leaderboard_snapshots WHERE challenge_id = p_challenge_id;

  -- Insert fresh snapshot using same logic as get_team_leaderboard
  INSERT INTO leaderboard_snapshots
    (challenge_id, rank, entity_type, entity_id, entity_name,
     total_steps, avg_steps, member_count, snapshot_at)
  SELECT
    p_challenge_id,
    RANK() OVER (ORDER BY avg_steps DESC)::integer,
    'team',
    team_id,
    team_name,
    total_steps,
    avg_steps,
    member_count,
    now()
  FROM (
    SELECT
      t.id                                                           AS team_id,
      t.name                                                         AS team_name,
      COALESCE(SUM(ds.step_count), 0)                               AS total_steps,
      COALESCE(
        ROUND(SUM(ds.step_count)::numeric / NULLIF(COUNT(DISTINCT tm.user_id), 0)),
        0
      )                                                              AS avg_steps,
      COUNT(DISTINCT tm.user_id)                                     AS member_count
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
       OR EXTRACT(DOW FROM ds.step_date) NOT IN (0, 6)
     )
    GROUP BY t.id, t.name
  ) ranked;
END;
$$;

-- ── refresh_all_active_leaderboards() ────────────────────────────────────
-- Called by pg_cron. Refreshes snapshots for every active challenge.
-- Runs without auth context — does not use auth.uid() or my_company_id().
CREATE OR REPLACE FUNCTION public.refresh_all_active_leaderboards()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_id uuid;
BEGIN
  FOR v_id IN
    SELECT id FROM challenges WHERE status = 'active'
  LOOP
    PERFORM public.refresh_leaderboard(v_id);
  END LOOP;
END;
$$;

-- ── pg_cron setup (manual step) ───────────────────────────────────────────
-- Enable pg_cron: Dashboard → Database → Extensions → pg_cron → Enable
-- Then run once in SQL Editor:
--
--   SELECT cron.schedule(
--     'refresh-leaderboards',
--     '* * * * *',   -- every minute
--     $$ SELECT public.refresh_all_active_leaderboards(); $$
--   );
--
-- To verify: SELECT * FROM cron.job;
-- To remove:  SELECT cron.unschedule('refresh-leaderboards');
