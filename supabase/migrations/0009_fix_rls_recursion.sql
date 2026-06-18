-- Fix: infinite recursion in profiles RLS policy.
-- The policy "profiles_select_own_company" queried profiles from within
-- profiles, causing PostgreSQL to recurse indefinitely.
--
-- Solution: a SECURITY DEFINER helper function that bypasses RLS when
-- called internally, breaking the cycle. All cross-table company_id
-- lookups are rewritten to use this function.

CREATE OR REPLACE FUNCTION public.my_company_id()
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT company_id FROM profiles WHERE id = auth.uid()
$$;

-- ── profiles ──────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "profiles_select_own_company" ON profiles;
CREATE POLICY "profiles_select_own_company" ON profiles
  FOR SELECT USING (
    company_id = public.my_company_id()
  );

DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
CREATE POLICY "profiles_update_own" ON profiles
  FOR UPDATE USING (id = auth.uid());

-- ── companies ─────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "company_admin_select" ON companies;
CREATE POLICY "company_admin_select" ON companies
  FOR SELECT USING (id = public.my_company_id());

DROP POLICY IF EXISTS "company_admin_update" ON companies;
CREATE POLICY "company_admin_update" ON companies
  FOR UPDATE USING (
    id = public.my_company_id()
    AND (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
  );

-- ── teams ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "teams_select_own_company" ON teams;
CREATE POLICY "teams_select_own_company" ON teams
  FOR SELECT USING (company_id = public.my_company_id());

DROP POLICY IF EXISTS "teams_admin_write" ON teams;
CREATE POLICY "teams_admin_write" ON teams
  FOR ALL USING (
    company_id = public.my_company_id()
    AND (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
  );

-- ── team_members ──────────────────────────────────────────────────────
DROP POLICY IF EXISTS "team_members_select_own_company" ON team_members;
CREATE POLICY "team_members_select_own_company" ON team_members
  FOR SELECT USING (
    team_id IN (SELECT id FROM teams WHERE company_id = public.my_company_id())
  );

DROP POLICY IF EXISTS "team_members_admin_write" ON team_members;
CREATE POLICY "team_members_admin_write" ON team_members
  FOR ALL USING (
    team_id IN (SELECT id FROM teams WHERE company_id = public.my_company_id())
    AND (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
  );

-- ── challenges ────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "challenges_select_own_company" ON challenges;
CREATE POLICY "challenges_select_own_company" ON challenges
  FOR SELECT USING (company_id = public.my_company_id());

DROP POLICY IF EXISTS "challenges_admin_write" ON challenges;
CREATE POLICY "challenges_admin_write" ON challenges
  FOR ALL USING (
    company_id = public.my_company_id()
    AND (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
  );

-- ── challenge_enrollments ─────────────────────────────────────────────
DROP POLICY IF EXISTS "enrollments_select_own_company" ON challenge_enrollments;
CREATE POLICY "enrollments_select_own_company" ON challenge_enrollments
  FOR SELECT USING (
    challenge_id IN (SELECT id FROM challenges WHERE company_id = public.my_company_id())
  );

DROP POLICY IF EXISTS "enrollments_member_insert_own" ON challenge_enrollments;
CREATE POLICY "enrollments_member_insert_own" ON challenge_enrollments
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "enrollments_admin_manage" ON challenge_enrollments;
CREATE POLICY "enrollments_admin_manage" ON challenge_enrollments
  FOR ALL USING (
    (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
  );

-- ── daily_steps ───────────────────────────────────────────────────────
DROP POLICY IF EXISTS "steps_select_own_company" ON daily_steps;
CREATE POLICY "steps_select_own_company" ON daily_steps
  FOR SELECT USING (company_id = public.my_company_id());

DROP POLICY IF EXISTS "steps_insert_own" ON daily_steps;
CREATE POLICY "steps_insert_own" ON daily_steps
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "steps_update_own" ON daily_steps;
CREATE POLICY "steps_update_own" ON daily_steps
  FOR UPDATE USING (user_id = auth.uid());

-- ── leaderboard_snapshots ─────────────────────────────────────────────
DROP POLICY IF EXISTS "leaderboard_select_own_company" ON leaderboard_snapshots;
CREATE POLICY "leaderboard_select_own_company" ON leaderboard_snapshots
  FOR SELECT USING (
    challenge_id IN (SELECT id FROM challenges WHERE company_id = public.my_company_id())
  );

-- ── company_invites ───────────────────────────────────────────────────
DROP POLICY IF EXISTS "invites_admin_manage" ON company_invites;
CREATE POLICY "invites_admin_manage" ON company_invites
  FOR ALL USING (
    company_id = public.my_company_id()
    AND (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
  );
