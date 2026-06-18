-- Dedicated invite tokens table (replaces invite_token on profiles)
CREATE TABLE company_invites (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  token       text NOT NULL UNIQUE DEFAULT gen_random_uuid()::text,
  created_by  uuid NOT NULL REFERENCES profiles(id),
  used_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX company_invites_company_idx ON company_invites (company_id);
CREATE INDEX company_invites_token_idx   ON company_invites (token) WHERE used_at IS NULL;

ALTER TABLE company_invites ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invites_admin_manage" ON company_invites
  FOR ALL USING (
    company_id = (SELECT company_id FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- Replace the accept_invite RPC to use company_invites
CREATE OR REPLACE FUNCTION public.accept_invite(p_token text, p_display_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_company_id uuid;
  v_invite_id  uuid;
BEGIN
  SELECT id, company_id INTO v_invite_id, v_company_id
  FROM company_invites
  WHERE token = p_token AND used_at IS NULL;

  IF v_invite_id IS NULL THEN
    RAISE EXCEPTION 'Invalid or already used invite token';
  END IF;

  INSERT INTO profiles (id, company_id, display_name, role)
  VALUES (auth.uid(), v_company_id, p_display_name, 'member');

  UPDATE company_invites SET used_at = now() WHERE id = v_invite_id;
END;
$$;

-- RPC: create an invite token (admin only)
CREATE OR REPLACE FUNCTION public.create_invite()
RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_company_id uuid;
  v_token      text;
BEGIN
  SELECT company_id INTO v_company_id FROM profiles WHERE id = auth.uid() AND role = 'admin';
  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'Only admins can create invites';
  END IF;

  INSERT INTO company_invites (company_id, created_by)
  VALUES (v_company_id, auth.uid())
  RETURNING token INTO v_token;

  RETURN v_token;
END;
$$;
