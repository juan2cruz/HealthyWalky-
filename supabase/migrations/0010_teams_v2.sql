-- Migration 0010: Teams feature complete schema (SDD spec)
-- Adds columns for team lifecycle (status, created_by, challenge_id, disqualification)
-- Adds team member states (invited, request_pending, active, rejected, expelled)
-- Implements unique partial index on (user_id, challenge_id) for active members
-- Adds 9 SECURITY DEFINER RPCs enforcing all timing and permission rules at DB level

-- ── teams: rename captain_id → created_by, add lifecycle columns ─────────
ALTER TABLE teams
  RENAME COLUMN captain_id TO created_by;

ALTER TABLE teams
  ADD COLUMN status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'approved', 'enrolled', 'active', 'completed', 'disqualified')),
  ADD COLUMN challenge_id uuid REFERENCES challenges(id),
  ADD COLUMN disqualification_reason text,
  ADD COLUMN disqualified_at timestamptz;

-- ── team_members: add status, expelled columns, and challenge_id ──────────
-- DEFAULT 'active' is intentional: existing rows were already active members.
-- All new inserts go through SECURITY DEFINER RPCs that set status explicitly.
ALTER TABLE team_members
  ADD COLUMN status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('invited', 'request_pending', 'active', 'rejected', 'expelled')),
  ADD COLUMN challenge_id uuid REFERENCES challenges(id),
  ADD COLUMN expelled_at timestamptz,
  ADD COLUMN expelled_reason text;

-- ── One active membership per user per challenge ──────────────────────────
-- Existing UNIQUE (team_id, user_id) is kept for intra-team dedup.
CREATE UNIQUE INDEX team_members_one_active_per_challenge
  ON team_members (user_id, challenge_id)
  WHERE status = 'active';

-- ═════════════════════════════════════════════════════════════════════════
-- RPCs — all SECURITY DEFINER, all validate timing and permissions at DB level
-- ═════════════════════════════════════════════════════════════════════════

-- ── Helper: returns the challenge_id of the single active/upcoming challenge
-- for the caller's company. Returns NULL if none exists.
CREATE OR REPLACE FUNCTION public.active_challenge_id()
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT id FROM challenges
  WHERE company_id = public.my_company_id()
    AND status NOT IN ('completed')
  ORDER BY created_at DESC
  LIMIT 1
$$;

-- ── create_team(p_name) ───────────────────────────────────────────────────
-- Any member can create a team while no challenge is in 'active' status.
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

  RETURN v_team_id;
END;
$$;

-- ── approve_team(p_team_id) ───────────────────────────────────────────────
-- Admin only. Transitions team from draft → approved.
CREATE OR REPLACE FUNCTION public.approve_team(p_team_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF (SELECT role FROM profiles WHERE id = auth.uid()) != 'admin' THEN
    RAISE EXCEPTION 'Only admins can approve teams';
  END IF;

  UPDATE teams
  SET status = 'approved'
  WHERE id = p_team_id
    AND company_id = public.my_company_id()
    AND status = 'draft';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Team not found or not in draft status';
  END IF;
END;
$$;

-- ── enroll_team(p_team_id) ────────────────────────────────────────────────
-- Any member (or admin). Transitions team approved → enrolled.
-- Links teams.challenge_id and propagates to team_members.challenge_id.
CREATE OR REPLACE FUNCTION public.enroll_team(p_team_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_challenge_id uuid;
BEGIN
  SELECT id INTO v_challenge_id
  FROM challenges
  WHERE company_id = public.my_company_id()
    AND status NOT IN ('active', 'completed')
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

  -- Propagate challenge_id to existing active members
  UPDATE team_members
  SET challenge_id = v_challenge_id
  WHERE team_id = p_team_id AND status = 'active';

  -- Register the team enrollment in challenge_enrollments
  INSERT INTO challenge_enrollments (challenge_id, team_id)
  VALUES (v_challenge_id, p_team_id)
  ON CONFLICT DO NOTHING;
END;
$$;

-- ── invite_to_team(p_team_id, p_user_id) ─────────────────────────────────
-- Only the team creator. Blocked once challenge is active.
CREATE OR REPLACE FUNCTION public.invite_to_team(p_team_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_creator uuid;
BEGIN
  SELECT created_by INTO v_creator
  FROM teams
  WHERE id = p_team_id AND company_id = public.my_company_id();

  IF v_creator IS NULL THEN
    RAISE EXCEPTION 'Team not found';
  END IF;

  IF v_creator != auth.uid() THEN
    RAISE EXCEPTION 'Only the team creator can send invitations';
  END IF;

  IF EXISTS (
    SELECT 1 FROM challenges
    WHERE company_id = public.my_company_id() AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Cannot invite members once the challenge is active';
  END IF;

  -- Target user must belong to the same company
  IF NOT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = p_user_id AND company_id = public.my_company_id()
  ) THEN
    RAISE EXCEPTION 'User does not belong to this company';
  END IF;

  INSERT INTO team_members (team_id, user_id, status)
  VALUES (p_team_id, p_user_id, 'invited');
END;
$$;

-- ── request_join_team(p_team_id) ──────────────────────────────────────────
-- Any member. Blocked once challenge is active or if already active elsewhere.
CREATE OR REPLACE FUNCTION public.request_join_team(p_team_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_challenge_id uuid;
BEGIN
  IF EXISTS (
    SELECT 1 FROM challenges
    WHERE company_id = public.my_company_id() AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Cannot request to join a team once the challenge is active';
  END IF;

  -- Check the user is not already active in another team for the same challenge
  v_challenge_id := (
    SELECT challenge_id FROM teams
    WHERE id = p_team_id AND company_id = public.my_company_id()
  );

  IF v_challenge_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM team_members
    WHERE user_id = auth.uid()
      AND challenge_id = v_challenge_id
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Already an active member of another team in this challenge';
  END IF;

  -- Team must be visible (approved or enrolled) and belong to the same company
  IF NOT EXISTS (
    SELECT 1 FROM teams
    WHERE id = p_team_id
      AND company_id = public.my_company_id()
      AND status IN ('approved', 'enrolled')
  ) THEN
    RAISE EXCEPTION 'Team not found or not open for join requests';
  END IF;

  INSERT INTO team_members (team_id, user_id, status)
  VALUES (p_team_id, auth.uid(), 'request_pending');
END;
$$;

-- ── respond_invitation(p_team_member_id, p_accept) ────────────────────────
-- The invited member accepts or rejects their own invitation.
-- Blocked once challenge is active.
CREATE OR REPLACE FUNCTION public.respond_invitation(p_team_member_id uuid, p_accept bool)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_team_id      uuid;
  v_challenge_id uuid;
BEGIN
  SELECT team_id INTO v_team_id
  FROM team_members
  WHERE id = p_team_member_id
    AND user_id = auth.uid()
    AND status = 'invited';

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'Invitation not found or does not belong to you';
  END IF;

  IF EXISTS (
    SELECT 1 FROM challenges
    WHERE company_id = public.my_company_id() AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Cannot respond to invitations once the challenge is active';
  END IF;

  IF p_accept THEN
    -- Get the challenge_id from the team (may be null if not yet enrolled)
    SELECT challenge_id INTO v_challenge_id FROM teams WHERE id = v_team_id;

    UPDATE team_members
    SET status = 'active', challenge_id = v_challenge_id
    WHERE id = p_team_member_id;
  ELSE
    UPDATE team_members SET status = 'rejected' WHERE id = p_team_member_id;
  END IF;
END;
$$;

-- ── respond_join_request(p_team_member_id, p_accept) ─────────────────────
-- The team creator accepts or rejects an incoming join request.
-- Explicitly validated: only the creator manages join requests (not admin, not other members).
-- Blocked once challenge is active.
CREATE OR REPLACE FUNCTION public.respond_join_request(p_team_member_id uuid, p_accept bool)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_team_id      uuid;
  v_challenge_id uuid;
BEGIN
  SELECT team_id INTO v_team_id
  FROM team_members
  WHERE id = p_team_member_id AND status = 'request_pending';

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'Join request not found';
  END IF;

  -- Only the creator of that specific team can respond
  IF (SELECT created_by FROM teams WHERE id = v_team_id) != auth.uid() THEN
    RAISE EXCEPTION 'Only the team creator can accept or reject join requests';
  END IF;

  IF EXISTS (
    SELECT 1 FROM challenges
    WHERE company_id = public.my_company_id() AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Cannot respond to join requests once the challenge is active';
  END IF;

  IF p_accept THEN
    SELECT challenge_id INTO v_challenge_id FROM teams WHERE id = v_team_id;

    UPDATE team_members
    SET status = 'active', challenge_id = v_challenge_id
    WHERE id = p_team_member_id;
  ELSE
    UPDATE team_members SET status = 'rejected' WHERE id = p_team_member_id;
  END IF;
END;
$$;

-- ── expel_team_member(p_team_member_id, p_reason) ────────────────────────
-- Admin only. Only while challenge is active.
-- Cannot expel the team creator while team is in draft/approved/enrolled.
-- Once challenge is active the creator has no special protection.
CREATE OR REPLACE FUNCTION public.expel_team_member(p_team_member_id uuid, p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_team_id     uuid;
  v_team_status text;
  v_target_user uuid;
  v_creator     uuid;
BEGIN
  IF (SELECT role FROM profiles WHERE id = auth.uid()) != 'admin' THEN
    RAISE EXCEPTION 'Only admins can expel team members';
  END IF;

  SELECT tm.team_id, t.status, tm.user_id, t.created_by
  INTO v_team_id, v_team_status, v_target_user, v_creator
  FROM team_members tm
  JOIN teams t ON t.id = tm.team_id
  WHERE tm.id = p_team_member_id
    AND t.company_id = public.my_company_id()
    AND tm.status = 'active';

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'Active team member not found';
  END IF;

  -- Expulsion is only allowed while the challenge is active
  IF NOT EXISTS (
    SELECT 1 FROM challenges
    WHERE company_id = public.my_company_id() AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Members can only be expelled while the challenge is active';
  END IF;

  -- Creator is protected in pre-challenge states (redundant guard: challenge is active here,
  -- so team must also be active — but kept explicit for clarity)
  IF v_target_user = v_creator AND v_team_status NOT IN ('active', 'disqualified') THEN
    RAISE EXCEPTION 'Cannot expel the team creator before the challenge starts';
  END IF;

  UPDATE team_members
  SET status = 'expelled', expelled_at = now(), expelled_reason = p_reason
  WHERE id = p_team_member_id;
END;
$$;

-- ── disqualify_team(p_team_id, p_reason) ─────────────────────────────────
-- Admin only. Only while challenge is active. Reason is mandatory.
CREATE OR REPLACE FUNCTION public.disqualify_team(p_team_id uuid, p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF (SELECT role FROM profiles WHERE id = auth.uid()) != 'admin' THEN
    RAISE EXCEPTION 'Only admins can disqualify teams';
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A disqualification reason is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM challenges
    WHERE company_id = public.my_company_id() AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Teams can only be disqualified while the challenge is active';
  END IF;

  UPDATE teams
  SET status = 'disqualified',
      disqualification_reason = p_reason,
      disqualified_at = now()
  WHERE id = p_team_id
    AND company_id = public.my_company_id()
    AND status IN ('enrolled', 'active');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Team not found or not in an active competition';
  END IF;
END;
$$;
