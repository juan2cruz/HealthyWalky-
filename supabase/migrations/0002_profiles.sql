-- User profiles (extends auth.users)
CREATE TABLE profiles (
  id                    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id            uuid NOT NULL REFERENCES companies(id),
  display_name          text NOT NULL,
  avatar_url            text,
  role                  text NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
  invite_token          text UNIQUE,
  invite_accepted_at    timestamptz,
  external_employee_id  text,
  created_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX profiles_company_id_idx ON profiles (company_id);
CREATE INDEX profiles_invite_token_idx ON profiles (invite_token) WHERE invite_token IS NOT NULL;

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles_select_own_company" ON profiles
  FOR SELECT USING (
    company_id = (SELECT company_id FROM profiles WHERE id = auth.uid())
  );

CREATE POLICY "profiles_update_own" ON profiles
  FOR UPDATE USING (id = auth.uid());

-- JWT custom claim: inject company_id so RLS policies avoid subqueries
CREATE OR REPLACE FUNCTION public.set_claim_company_id()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE auth.users
  SET raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', NEW.company_id)
  WHERE id = NEW.id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_profile_created
  AFTER INSERT ON profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_claim_company_id();

-- Políticas de "companies" que dependen de profiles (movidas desde 0001_companies.sql,
-- ya que requieren que esta tabla exista primero)
CREATE POLICY "company_admin_select" ON companies
  FOR SELECT USING (
    id IN (SELECT company_id FROM profiles WHERE id = auth.uid())
  );

CREATE POLICY "company_admin_update" ON companies
  FOR UPDATE USING (
    id IN (SELECT company_id FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );
