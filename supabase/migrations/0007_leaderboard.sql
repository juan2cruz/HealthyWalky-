-- Leaderboard snapshot table for Realtime subscriptions
CREATE TABLE leaderboard_snapshots (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id    uuid NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
  rank            integer NOT NULL,
  entity_type     text NOT NULL CHECK (entity_type IN ('user', 'team')),
  entity_id       uuid NOT NULL,
  entity_name     text NOT NULL,
  total_steps     bigint NOT NULL DEFAULT 0,
  avg_steps       numeric(10,2) NOT NULL DEFAULT 0,
  member_count    integer NOT NULL DEFAULT 1,
  snapshot_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX leaderboard_challenge_rank_idx ON leaderboard_snapshots (challenge_id, rank);

ALTER TABLE leaderboard_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "leaderboard_select_own_company" ON leaderboard_snapshots
  FOR SELECT USING (
    challenge_id IN (
      SELECT id FROM challenges
      WHERE company_id = (SELECT company_id FROM profiles WHERE id = auth.uid())
    )
  );

-- RPC function: leaderboard for a TEAM challenge (ranked by average steps per member)
CREATE OR REPLACE FUNCTION public.get_team_leaderboard(p_challenge_id uuid)
RETURNS TABLE (
  rank          bigint,
  team_id       uuid,
  team_name     text,
  member_count  bigint,
  total_steps   bigint,
  avg_steps     numeric
) LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    RANK() OVER (ORDER BY COALESCE(AVG(ds.step_count), 0) DESC) AS rank,
    t.id                                   AS team_id,
    t.name                                 AS team_name,
    COUNT(DISTINCT tm.user_id)             AS member_count,
    COALESCE(SUM(ds.step_count), 0)        AS total_steps,
    COALESCE(AVG(ds.step_count), 0)        AS avg_steps
  FROM challenge_enrollments ce
  JOIN teams t ON t.id = ce.team_id
  JOIN team_members tm ON tm.team_id = t.id
  LEFT JOIN daily_steps ds
    ON ds.user_id = tm.user_id
    AND ds.is_canonical = true
    AND ds.step_date BETWEEN (SELECT start_date FROM challenges WHERE id = p_challenge_id)
                         AND (SELECT end_date   FROM challenges WHERE id = p_challenge_id)
  WHERE ce.challenge_id = p_challenge_id
    AND ce.team_id IS NOT NULL
    AND ce.status = 'active'
  GROUP BY t.id, t.name
  ORDER BY avg_steps DESC;
$$;

-- RPC function: leaderboard for an INDIVIDUAL challenge (ranked by total steps)
CREATE OR REPLACE FUNCTION public.get_individual_leaderboard(p_challenge_id uuid)
RETURNS TABLE (
  rank          bigint,
  user_id       uuid,
  display_name  text,
  total_steps   bigint
) LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    RANK() OVER (ORDER BY COALESCE(SUM(ds.step_count), 0) DESC) AS rank,
    p.id           AS user_id,
    p.display_name AS display_name,
    COALESCE(SUM(ds.step_count), 0) AS total_steps
  FROM challenge_enrollments ce
  JOIN profiles p ON p.id = ce.user_id
  LEFT JOIN daily_steps ds
    ON ds.user_id = p.id
    AND ds.is_canonical = true
    AND ds.step_date BETWEEN (SELECT start_date FROM challenges WHERE id = p_challenge_id)
                         AND (SELECT end_date   FROM challenges WHERE id = p_challenge_id)
  WHERE ce.challenge_id = p_challenge_id
    AND ce.user_id IS NOT NULL
    AND ce.status = 'active'
  GROUP BY p.id, p.display_name
  ORDER BY total_steps DESC;
$$;

-- RPC: register company + admin user in one atomic operation
CREATE OR REPLACE FUNCTION public.register_company(
  p_company_name  text,
  p_company_slug  text,
  p_display_name  text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_company_id uuid;
BEGIN
  INSERT INTO companies (name, slug)
  VALUES (p_company_name, p_company_slug)
  RETURNING id INTO v_company_id;

  INSERT INTO profiles (id, company_id, display_name, role)
  VALUES (auth.uid(), v_company_id, p_display_name, 'admin');

  RETURN v_company_id;
END;
$$;

-- RPC: accept invite and bind user to company
CREATE OR REPLACE FUNCTION public.accept_invite(p_token text, p_display_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_company_id uuid;
BEGIN
  SELECT company_id INTO v_company_id
  FROM profiles
  WHERE invite_token = p_token
    AND invite_accepted_at IS NULL;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or already used invite token';
  END IF;

  INSERT INTO profiles (id, company_id, display_name, role, invite_accepted_at)
  VALUES (auth.uid(), v_company_id, p_display_name, 'member', now());

  -- Invalidate the token
  UPDATE profiles
  SET invite_token = NULL
  WHERE invite_token = p_token;
END;
$$;

-- RPC: upsert daily steps (manual entry)
CREATE OR REPLACE FUNCTION public.upsert_steps(
  p_step_date  date,
  p_step_count integer
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_company_id uuid;
BEGIN
  SELECT company_id INTO v_company_id FROM profiles WHERE id = auth.uid();

  INSERT INTO daily_steps (user_id, company_id, step_date, step_count, source, is_canonical)
  VALUES (auth.uid(), v_company_id, p_step_date, p_step_count, 'manual', true)
  ON CONFLICT (user_id, step_date, source)
  DO UPDATE SET step_count = EXCLUDED.step_count, updated_at = now();
END;
$$;
