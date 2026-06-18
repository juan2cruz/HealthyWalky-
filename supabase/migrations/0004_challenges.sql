-- Challenges (competitions within a company)
CREATE TABLE challenges (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      uuid NOT NULL REFERENCES companies(id),
  title           text NOT NULL,
  description     text,
  start_date      date NOT NULL,
  end_date        date NOT NULL,
  rules           jsonb NOT NULL DEFAULT '{}',
  enrollment_type text NOT NULL DEFAULT 'individual' CHECK (enrollment_type IN ('individual', 'team')),
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'completed')),
  created_by      uuid REFERENCES profiles(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT valid_dates CHECK (end_date > start_date)
);

CREATE INDEX challenges_company_status_idx ON challenges (company_id, status);
CREATE INDEX challenges_company_dates_idx ON challenges (company_id, start_date, end_date);

ALTER TABLE challenges ENABLE ROW LEVEL SECURITY;

CREATE POLICY "challenges_select_own_company" ON challenges
  FOR SELECT USING (
    company_id = (SELECT company_id FROM profiles WHERE id = auth.uid())
  );

CREATE POLICY "challenges_admin_write" ON challenges
  FOR ALL USING (
    company_id = (SELECT company_id FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- Challenge enrollments (individual users or whole teams)
CREATE TABLE challenge_enrollments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id  uuid NOT NULL REFERENCES challenges(id),
  user_id       uuid REFERENCES profiles(id),
  team_id       uuid REFERENCES teams(id),
  enrolled_at   timestamptz NOT NULL DEFAULT now(),
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'withdrawn')),
  CONSTRAINT enrollment_target CHECK (
    (user_id IS NOT NULL AND team_id IS NULL) OR
    (team_id IS NOT NULL AND user_id IS NULL)
  ),
  UNIQUE NULLS NOT DISTINCT (challenge_id, user_id),
  UNIQUE NULLS NOT DISTINCT (challenge_id, team_id)
);

CREATE INDEX enrollments_challenge_id_idx ON challenge_enrollments (challenge_id);
CREATE INDEX enrollments_user_id_idx ON challenge_enrollments (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX enrollments_team_id_idx ON challenge_enrollments (team_id) WHERE team_id IS NOT NULL;

ALTER TABLE challenge_enrollments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "enrollments_select_own_company" ON challenge_enrollments
  FOR SELECT USING (
    challenge_id IN (
      SELECT id FROM challenges
      WHERE company_id = (SELECT company_id FROM profiles WHERE id = auth.uid())
    )
  );

CREATE POLICY "enrollments_member_insert_own" ON challenge_enrollments
  FOR INSERT WITH CHECK (
    user_id = auth.uid() OR
    (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
  );

CREATE POLICY "enrollments_admin_manage" ON challenge_enrollments
  FOR ALL USING (
    (SELECT role FROM profiles WHERE id = auth.uid()) = 'admin'
  );
