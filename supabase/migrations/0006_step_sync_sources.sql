-- Registry of connected health platforms per user (populated in Phase 2)
CREATE TABLE step_sync_sources (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  source_type         text NOT NULL
                        CHECK (source_type IN ('google_fit', 'apple_health', 'samsung_health')),
  access_token        text,   -- store encrypted via Vault in production
  refresh_token       text,
  token_expires_at    timestamptz,
  external_user_id    text,
  last_synced_at      timestamptz,
  sync_enabled        boolean NOT NULL DEFAULT true,
  platform_metadata   jsonb NOT NULL DEFAULT '{}',  -- scopes, permissions, data types
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, source_type)
);

CREATE INDEX sync_sources_pending_idx ON step_sync_sources (last_synced_at)
  WHERE sync_enabled = true;

ALTER TABLE step_sync_sources ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sync_sources_own_user" ON step_sync_sources
  FOR ALL USING (user_id = auth.uid());
