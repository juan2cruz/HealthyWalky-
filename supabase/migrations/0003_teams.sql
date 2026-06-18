-- Teams within a company
CREATE TABLE teams (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES companies(id),
  name        text NOT NULL,
  description text,
  captain_id  uuid REFERENCES profiles(id),
  avatar_url  text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, name)
);

CREATE INDEX teams_company_id_idx ON teams (company_id);

ALTER TABLE teams ENABLE ROW LEVEL SECURITY;

CREATE POLICY "teams_select_own_company" ON teams
  FOR SELECT USING (
    company_id = (SELECT company_id FROM profiles WHERE id = auth.uid())
  );

CREATE POLICY "teams_admin_write" ON teams
  FOR ALL USING (
    company_id = (SELECT company_id FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- Team membership junction
CREATE TABLE team_members (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id     uuid NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES profiles(id),
  joined_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (team_id, user_id)
);

CREATE INDEX team_members_user_id_idx ON team_members (user_id);
CREATE INDEX team_members_team_id_idx ON team_members (team_id);

ALTER TABLE team_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "team_members_select_own_company" ON team_members
  FOR SELECT USING (
    team_id IN (SELECT id FROM teams WHERE company_id = (SELECT company_id FROM profiles WHERE id = auth.uid()))
  );

CREATE POLICY "team_members_admin_write" ON team_members
  FOR ALL USING (
    team_id IN (
      SELECT t.id FROM teams t
      JOIN profiles p ON p.company_id = t.company_id
      WHERE p.id = auth.uid() AND p.role = 'admin'
    )
  );
