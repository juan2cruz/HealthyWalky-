-- Migration 0018: Weight team avg_steps by days elapsed since challenge start
--
-- avg_steps previously divided total team steps only by member_count, giving a
-- cumulative per-member total rather than a fair daily average. Teams are now
-- compared on a per-day, per-member basis by also dividing by the number of
-- qualifying days elapsed since the challenge started (respecting
-- count_weekends). Days with no logged steps count as 0 in the average, so a
-- team can't game the ranking by logging once and skipping the rest.

-- ── get_team_leaderboard (supersedes 0017 version) ───────────────────────────
CREATE OR REPLACE FUNCTION public.get_team_leaderboard(p_challenge_id uuid)
RETURNS TABLE (
  ranking      bigint,
  team_id      uuid,
  team_name    text,
  member_count bigint,
  avg_steps    numeric
)
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_start          date;
  v_end            date;
  v_count_weekends boolean;
  v_days_elapsed   integer;
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

  SELECT GREATEST(count(*), 1)::integer INTO v_days_elapsed
  FROM generate_series(v_start, v_end, interval '1 day') AS d(day)
  WHERE v_count_weekends OR EXTRACT(DOW FROM d.day) NOT IN (0, 6);

  RETURN QUERY
  SELECT
    RANK() OVER (ORDER BY
      COALESCE(SUM(ds.step_count)::numeric / NULLIF(COUNT(DISTINCT tm.user_id) * v_days_elapsed, 0), 0) DESC
    )                                                                   AS ranking,
    t.id                                                                AS team_id,
    t.name                                                              AS team_name,
    COUNT(DISTINCT tm.user_id)                                          AS member_count,
    COALESCE(
      ROUND(SUM(ds.step_count)::numeric / NULLIF(COUNT(DISTINCT tm.user_id) * v_days_elapsed, 0)),
      0
    )                                                                   AS avg_steps
  FROM teams t
  JOIN challenge_enrollments ce
    ON ce.team_id      = t.id
   AND ce.challenge_id = p_challenge_id
   AND ce.status       = 'active'
  LEFT JOIN team_members tm
    ON tm.team_id      = t.id
   AND tm.challenge_id = p_challenge_id        -- only members of THIS challenge
   AND tm.status       = 'active'
  LEFT JOIN daily_steps ds
    ON ds.user_id      = tm.user_id
   AND ds.is_canonical = true
   AND ds.step_date BETWEEN v_start AND v_end
   AND (
     v_count_weekends = true
     OR EXTRACT(DOW FROM ds.step_date) NOT IN (0, 6)
   )
  GROUP BY t.id, t.name
  ORDER BY avg_steps DESC;
END;
$$;

-- ── refresh_leaderboard (supersedes 0017 version) ─────────────────────────────
CREATE OR REPLACE FUNCTION public.refresh_leaderboard(p_challenge_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_start          date;
  v_end            date;
  v_count_weekends boolean;
  v_days_elapsed   integer;
BEGIN
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

  SELECT GREATEST(count(*), 1)::integer INTO v_days_elapsed
  FROM generate_series(v_start, v_end, interval '1 day') AS d(day)
  WHERE v_count_weekends OR EXTRACT(DOW FROM d.day) NOT IN (0, 6);

  DELETE FROM leaderboard_snapshots WHERE challenge_id = p_challenge_id;

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
      t.id                                                             AS team_id,
      t.name                                                           AS team_name,
      COALESCE(SUM(ds.step_count), 0)                                 AS total_steps,
      COALESCE(
        ROUND(SUM(ds.step_count)::numeric / NULLIF(COUNT(DISTINCT tm.user_id) * v_days_elapsed, 0)),
        0
      )                                                                AS avg_steps,
      COUNT(DISTINCT tm.user_id)                                       AS member_count
    FROM teams t
    JOIN challenge_enrollments ce
      ON ce.team_id      = t.id
     AND ce.challenge_id = p_challenge_id
     AND ce.status       = 'active'
    LEFT JOIN team_members tm
      ON tm.team_id      = t.id
     AND tm.challenge_id = p_challenge_id        -- only members of THIS challenge
     AND tm.status       = 'active'
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
