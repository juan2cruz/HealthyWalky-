-- Companies (tenants)
CREATE TABLE companies (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  slug        text NOT NULL UNIQUE,
  logo_url    text,
  plan        text NOT NULL DEFAULT 'free',
  settings    jsonb NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

-- Admins can read/update their own company; insert handled by registration function
CREATE POLICY "company_admin_select" ON companies
  FOR SELECT USING (
    id IN (SELECT company_id FROM profiles WHERE id = auth.uid())
  );

CREATE POLICY "company_admin_update" ON companies
  FOR UPDATE USING (
    id IN (SELECT company_id FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );
