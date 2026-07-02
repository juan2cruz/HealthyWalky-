-- Migration 0021: Allow re-inviting users whose previous membership ended
--
-- Problem: team_members keeps rejected/expelled rows forever, and both
-- invite_to_team and request_join_team do a plain INSERT.  The UNIQUE
-- (team_id, user_id) constraint means anyone with a historical row in a team
-- (rejected invitation, rejected join request, expulsion, or an invite expired
-- by the 0020 roster freeze) can never be invited to — or request to join —
-- that team again.  The client also filtered them out of the invitable list
-- (fixed separately in invitableMembersProvider).
--
-- Fix: when the target user has a *terminal* row (rejected/expelled), recycle
-- it back to invited/request_pending, clearing expulsion metadata and any
-- stale challenge link.  Pending or active rows still raise clear errors.

-- ── invite_to_team: recycle terminal rows ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.invite_to_team(p_team_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_creator  uuid;
  v_existing text;
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

  SELECT status INTO v_existing
  FROM team_members
  WHERE team_id = p_team_id AND user_id = p_user_id;

  IF v_existing IN ('invited', 'request_pending') THEN
    RAISE EXCEPTION 'User already has a pending invitation or join request';
  ELSIF v_existing = 'active' THEN
    RAISE EXCEPTION 'User is already an active member of this team';
  ELSIF v_existing IS NOT NULL THEN
    -- rejected / expelled: recycle the row into a fresh invitation
    UPDATE team_members
    SET status = 'invited',
        challenge_id = NULL,
        expelled_at = NULL,
        expelled_reason = NULL
    WHERE team_id = p_team_id AND user_id = p_user_id;
  ELSE
    INSERT INTO team_members (team_id, user_id, status)
    VALUES (p_team_id, p_user_id, 'invited');
  END IF;
END;
$$;

-- ── request_join_team: same recycling for the requester ──────────────────
CREATE OR REPLACE FUNCTION public.request_join_team(p_team_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_challenge_id uuid;
  v_existing     text;
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

  SELECT status INTO v_existing
  FROM team_members
  WHERE team_id = p_team_id AND user_id = auth.uid();

  IF v_existing IN ('invited', 'request_pending') THEN
    RAISE EXCEPTION 'You already have a pending invitation or join request for this team';
  ELSIF v_existing = 'active' THEN
    RAISE EXCEPTION 'You are already an active member of this team';
  ELSIF v_existing IS NOT NULL THEN
    -- rejected / expelled: recycle the row into a fresh join request
    UPDATE team_members
    SET status = 'request_pending',
        challenge_id = NULL,
        expelled_at = NULL,
        expelled_reason = NULL
    WHERE team_id = p_team_id AND user_id = auth.uid();
  ELSE
    INSERT INTO team_members (team_id, user_id, status)
    VALUES (p_team_id, auth.uid(), 'request_pending');
  END IF;
END;
$$;
