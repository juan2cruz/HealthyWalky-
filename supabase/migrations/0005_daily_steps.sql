-- Daily step records (the hot table — append-heavy, aggregate reads)
CREATE TABLE daily_steps (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES profiles(id),
  company_id          uuid NOT NULL REFERENCES companies(id),  -- denormalized for RLS efficiency
  step_date           date NOT NULL,
  step_count          integer NOT NULL DEFAULT 0 CHECK (step_count >= 0),
  source              text NOT NULL DEFAULT 'manual'
                        CHECK (source IN ('manual', 'google_fit', 'apple_health', 'samsung_health')),
  sync_status         text NOT NULL DEFAULT 'synced'
                        CHECK (sync_status IN ('pending', 'synced', 'conflict', 'rejected')),
  external_record_id  text,
  raw_payload         jsonb,
  is_canonical        boolean NOT NULL DEFAULT true,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, step_date, source)
);

-- Dedup index for incoming API records
CREATE UNIQUE INDEX daily_steps_external_dedup_idx
  ON daily_steps (external_record_id, source)
  WHERE external_record_id IS NOT NULL;

CREATE INDEX daily_steps_user_date_idx ON daily_steps (user_id, step_date);
CREATE INDEX daily_steps_company_date_idx ON daily_steps (company_id, step_date);
CREATE INDEX daily_steps_pending_idx ON daily_steps (sync_status) WHERE sync_status = 'pending';

ALTER TABLE daily_steps ENABLE ROW LEVEL SECURITY;

CREATE POLICY "steps_select_own_company" ON daily_steps
  FOR SELECT USING (
    company_id = (SELECT company_id FROM profiles WHERE id = auth.uid())
  );

CREATE POLICY "steps_insert_own" ON daily_steps
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "steps_update_own" ON daily_steps
  FOR UPDATE USING (user_id = auth.uid());

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TRIGGER daily_steps_updated_at
  BEFORE UPDATE ON daily_steps
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
