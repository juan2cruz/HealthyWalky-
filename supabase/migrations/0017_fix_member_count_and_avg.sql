-- Migration 0017: Fix member count and avg_steps in team leaderboard
--
-- Bug 1 — creator missing from team_members:
--   create_team only stored created_by on the teams row; it never inserted a
--   team_members row for the creator.  As a result the creator was never joined
--   when computing COUNT(DISTINCT tm.user_id) or SUM(ds.step_count).
--
-- Bug 2 — duplicate step counting across challenges:
--   complete_overdue_challenges does not clean up team_members rows when a
--   challenge ends.  A member who re-enrolls in a second challenge ends up with
--   TWO status='active' rows (one per challenge).  The daily_steps LEFT JOIN
--   fires once per team_members row, doubling (or more) the step totals.
--   Adding AND tm.challenge_id = p_challenge_id restricts the join to only
--   the rows belonging to this specific challenge.

-- ── 1. Fix create_team: auto-enroll creator as active member ─────────────────
CREATE OR REPLACE FUNCTION public.create_team(p_name text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_company_id uuid;
  v_team_id    uuid;
BEGIN
  v_company_id := public.my_company_id();

  IF EXISTS (
    SELECT 1 FROM challenges
    WHERE company_id = v_company_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Cannot create a team while a challenge is active';
  END IF;

  INSERT INTO teams (company_id, name, created_by, status)
  VALUES (v_company_id, p_name, auth.uid(), 'draft')
  RETURNING id INTO v_team_id;

  INSERT INTO team_members (team_id, user_id, status)
  VALUES (v_team_id, auth.uid(), 'active');

  RETURN v_team_id;
END;
$$;

-- ── 2. Backfill creators for existing teams ───────────────────────────────────
-- ON CONFLICT DO NOTHING safely skips teams where the creator already has a row.
INSERT INTO team_members (team_id, user_id, status)
SELECT t.id, t.created_by, 'active'
FROM teams t
WHERE t.created_by IS NOT NULL
ON CONFLICT (team_id, user_id) DO NOTHING;

-- ── 3. Propagate challenge_id to backfilled creator rows ─────────────────────
-- activate_challenge already did this for invited members; creators were skipped
-- because they had no team_members row at that time.
UPDATE team_members tm
SET challenge_id = t.challenge_id
FROM teams t
WHERE tm.team_id    = t.id
  AND tm.user_id    = t.created_by
  AND t.challenge_id IS NOT NULL
  AND tm.challenge_id IS NULL
  AND tm.status     = 'active';

-- ── 4. Fix get_team_leaderboard (supersedes 0016 version) ────────────────────
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
    )                                                                   AS ranking,
    t.id                                                                AS team_id,
    t.name                                                              AS team_name,
    COUNT(DISTINCT tm.user_id)                                          AS member_count,
    COALESCE(
      ROUND(SUM(ds.step_count)::numeric / NULLIF(COUNT(DISTINCT tm.user_id), 0)),
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

-- ── 5. Fix refresh_leaderboard (supersedes 0016 version) ─────────────────────
CREATE OR REPLACE FUNCTION public.refresh_leaderboard(p_challenge_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_start          date;
  v_end            date;
  v_count_weekends boolean;
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
        ROUND(SUM(ds.step_count)::numeric / NULLIF(COUNT(DISTINCT tm.user_id), 0)),
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
