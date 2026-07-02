-- Migration 0022: Voluntary exit and pre-challenge member removal
--
-- Dead-ends fixed:
-- 1. No way to leave a team: expel_team_member only works while a challenge is
--    ACTIVE, so a member who accepted the wrong invitation was stuck until the
--    admin aborted the whole team or hard-deleted the user.  New leave_team RPC
--    lets any non-creator member exit while no challenge is active.
-- 2. The creator could not manage their roster: new remove_team_member RPC lets
--    the creator withdraw a member (active/invited/request_pending) before the
--    challenge starts.  Rows are DELETEd (same as abort_team) so the user can
--    be re-invited or request to join again later.
-- 3. Double membership pre-enrollment: the unique index (user_id, challenge_id)
--    WHERE active only bites when challenge_id is NOT NULL, so a user could be
--    active in two teams before enrollment; enroll_team's challenge_id
--    propagation then hit the index and the team could never enroll.
--    respond_invitation / respond_join_request now refuse to accept when the
--    user is already active in another current (non archived/completed) team.

-- ── leave_team(p_team_id) ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.leave_team(p_team_id uuid)
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

  IF v_creator = auth.uid() THEN
    RAISE EXCEPTION 'The team creator cannot leave; abort the team instead';
  END IF;

  IF EXISTS (
    SELECT 1 FROM challenges
    WHERE company_id = public.my_company_id() AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Cannot leave a team while the challenge is active';
  END IF;

  DELETE FROM team_members
  WHERE team_id = p_team_id
    AND user_id = auth.uid()
    AND status IN ('active', 'invited', 'request_pending');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'You are not a member of this team';
  END IF;
END;
$$;

-- ── remove_team_member(p_team_member_id) ──────────────────────────────────
-- Team creator withdraws a member before the challenge starts.
CREATE OR REPLACE FUNCTION public.remove_team_member(p_team_member_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_team_id     uuid;
  v_target_user uuid;
  v_creator     uuid;
BEGIN
  SELECT tm.team_id, tm.user_id, t.created_by
  INTO v_team_id, v_target_user, v_creator
  FROM team_members tm
  JOIN teams t ON t.id = tm.team_id
  WHERE tm.id = p_team_member_id
    AND t.company_id = public.my_company_id()
    AND tm.status IN ('active', 'invited', 'request_pending');

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'Team member not found';
  END IF;

  IF v_creator != auth.uid() THEN
    RAISE EXCEPTION 'Only the team creator can remove members';
  END IF;

  IF v_target_user = v_creator THEN
    RAISE EXCEPTION 'The creator cannot remove themselves';
  END IF;

  IF EXISTS (
    SELECT 1 FROM challenges
    WHERE company_id = public.my_company_id() AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Cannot remove members while the challenge is active; use expulsion instead';
  END IF;

  DELETE FROM team_members WHERE id = p_team_member_id;
END;
$$;

-- ── respond_invitation: block double membership on accept ─────────────────
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
    -- One current team at a time: block accepting while active elsewhere
    IF EXISTS (
      SELECT 1 FROM team_members tm
      JOIN teams t ON t.id = tm.team_id
      WHERE tm.user_id = auth.uid()
        AND tm.status = 'active'
        AND tm.team_id != v_team_id
        AND t.status NOT IN ('archived', 'completed')
    ) THEN
      RAISE EXCEPTION 'You are already an active member of another team; leave it first';
    END IF;

    SELECT challenge_id INTO v_challenge_id FROM teams WHERE id = v_team_id;

    UPDATE team_members
    SET status = 'active', challenge_id = v_challenge_id
    WHERE id = p_team_member_id;
  ELSE
    UPDATE team_members SET status = 'rejected' WHERE id = p_team_member_id;
  END IF;
END;
$$;

-- ── respond_join_request: same guard for the requester ────────────────────
CREATE OR REPLACE FUNCTION public.respond_join_request(p_team_member_id uuid, p_accept bool)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_team_id      uuid;
  v_requester    uuid;
  v_challenge_id uuid;
BEGIN
  SELECT team_id, user_id INTO v_team_id, v_requester
  FROM team_members
  WHERE id = p_team_member_id AND status = 'request_pending';

  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'Join request not found';
  END IF;

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
    IF EXISTS (
      SELECT 1 FROM team_members tm
      JOIN teams t ON t.id = tm.team_id
      WHERE tm.user_id = v_requester
        AND tm.status = 'active'
        AND tm.team_id != v_team_id
        AND t.status NOT IN ('archived', 'completed')
    ) THEN
      RAISE EXCEPTION 'This user is already an active member of another team';
    END IF;

    SELECT challenge_id INTO v_challenge_id FROM teams WHERE id = v_team_id;

    UPDATE team_members
    SET status = 'active', challenge_id = v_challenge_id
    WHERE id = p_team_member_id;
  ELSE
    UPDATE team_members SET status = 'rejected' WHERE id = p_team_member_id;
  END IF;
END;
$$;
