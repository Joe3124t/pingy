CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY,
  username VARCHAR(40) NOT NULL,
  phone_number VARCHAR(20) NOT NULL UNIQUE,
  email VARCHAR(255) UNIQUE,
  password_hash TEXT NOT NULL,
  current_device_id VARCHAR(128),
  last_login_at TIMESTAMPTZ,
  avatar_url TEXT,
  bio TEXT NOT NULL DEFAULT '',
  is_online BOOLEAN NOT NULL DEFAULT FALSE,
  show_online_status BOOLEAN NOT NULL DEFAULT TRUE,
  read_receipts_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  theme_mode VARCHAR(12) NOT NULL DEFAULT 'auto' CHECK (theme_mode IN ('light', 'dark', 'auto')),
  default_wallpaper_url TEXT,
  last_seen TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS bio TEXT NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS show_online_status BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS read_receipts_enabled BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS theme_mode VARCHAR(12) NOT NULL DEFAULT 'auto';
ALTER TABLE users ADD COLUMN IF NOT EXISTS default_wallpaper_url TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_number VARCHAR(20);
ALTER TABLE users ADD COLUMN IF NOT EXISTS current_device_id VARCHAR(128);
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

ALTER TABLE users
  ALTER COLUMN email DROP NOT NULL;

DO $$
BEGIN
  ALTER TABLE users
    DROP CONSTRAINT users_username_key;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_number
  ON users (phone_number)
  WHERE phone_number IS NOT NULL;

DO $$
BEGIN
  ALTER TABLE users
    ADD CONSTRAINT users_theme_mode_check
    CHECK (theme_mode IN ('light', 'dark', 'auto'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY,
  type VARCHAR(20) NOT NULL DEFAULT 'direct' CHECK (type IN ('direct')),
  unique_key TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_message_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS conversation_participants (
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_read_message_id UUID,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (conversation_id, user_id)
);

ALTER TABLE conversation_participants ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

DO $$
BEGIN
  CREATE TYPE message_type AS ENUM ('text', 'image', 'video', 'file', 'voice');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY,
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reply_to_message_id UUID,
  type message_type NOT NULL,
  body TEXT,
  is_encrypted BOOLEAN NOT NULL DEFAULT FALSE,
  media_url TEXT,
  media_name TEXT,
  media_mime TEXT,
  media_size BIGINT,
  voice_duration_ms INTEGER,
  client_id VARCHAR(80),
  delivered_at TIMESTAMPTZ,
  seen_at TIMESTAMPTZ,
  deleted_for_everyone_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (body IS NOT NULL OR media_url IS NOT NULL)
);

ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_encrypted BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS deleted_for_everyone_at TIMESTAMPTZ;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS reply_to_message_id UUID;

DO $$
BEGIN
  ALTER TABLE messages
    ADD CONSTRAINT messages_reply_to_message_fk
    FOREIGN KEY (reply_to_message_id)
    REFERENCES messages(id)
    ON DELETE SET NULL;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS message_reactions (
  message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  emoji VARCHAR(16) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_message_reactions_message
  ON message_reactions (message_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_idempotency
  ON messages (conversation_id, sender_id, client_id)
  WHERE client_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
  ON messages (conversation_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_reply_to
  ON messages (reply_to_message_id);

CREATE INDEX IF NOT EXISTS idx_messages_recipient_pending
  ON messages (recipient_id, delivered_at, seen_at);

CREATE INDEX IF NOT EXISTS idx_participants_user
  ON conversation_participants (user_id);

CREATE TABLE IF NOT EXISTS refresh_tokens (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id VARCHAR(128) NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  replaced_by_hash TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE refresh_tokens ADD COLUMN IF NOT EXISTS device_id VARCHAR(128);
UPDATE refresh_tokens
SET device_id = COALESCE(NULLIF(device_id, ''), 'legacy-device')
WHERE device_id IS NULL OR device_id = '';

ALTER TABLE refresh_tokens
  ALTER COLUMN device_id SET NOT NULL;

CREATE TABLE IF NOT EXISTS password_reset_codes (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_password_reset_codes_user
  ON password_reset_codes (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_password_reset_codes_expiry
  ON password_reset_codes (expires_at);

CREATE TABLE IF NOT EXISTS user_public_keys (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  device_id VARCHAR(128),
  public_key_jwk JSONB NOT NULL,
  algorithm VARCHAR(40) NOT NULL DEFAULT 'ECDH-Curve25519',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE user_public_keys ADD COLUMN IF NOT EXISTS device_id VARCHAR(128);

CREATE TABLE IF NOT EXISTS phone_otp_codes (
  id UUID PRIMARY KEY,
  phone_number VARCHAR(20) NOT NULL,
  purpose VARCHAR(20) NOT NULL CHECK (purpose IN ('register', 'reset')),
  code_hash TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_phone_otp_codes_phone
  ON phone_otp_codes (phone_number, purpose, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_phone_otp_codes_expiry
  ON phone_otp_codes (expires_at);

CREATE TABLE IF NOT EXISTS user_blocks (
  blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked_id ON user_blocks (blocked_id);

CREATE TABLE IF NOT EXISTS user_conversation_settings (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  wallpaper_url TEXT,
  blur_intensity INTEGER NOT NULL DEFAULT 0 CHECK (blur_intensity >= 0 AND blur_intensity <= 20),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, conversation_id)
);

CREATE TABLE IF NOT EXISTS conversation_wallpaper_settings (
  conversation_id UUID PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
  wallpaper_url TEXT,
  blur_intensity INTEGER NOT NULL DEFAULT 0 CHECK (blur_intensity >= 0 AND blur_intensity <= 20),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_push_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, endpoint)
);

CREATE INDEX IF NOT EXISTS idx_user_push_subscriptions_user
  ON user_push_subscriptions (user_id);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_conversations_updated_at ON conversations;
CREATE TRIGGER trg_conversations_updated_at
BEFORE UPDATE ON conversations
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_user_public_keys_updated_at ON user_public_keys;
CREATE TRIGGER trg_user_public_keys_updated_at
BEFORE UPDATE ON user_public_keys
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_user_conversation_settings_updated_at ON user_conversation_settings;
CREATE TRIGGER trg_user_conversation_settings_updated_at
BEFORE UPDATE ON user_conversation_settings
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_conversation_wallpaper_settings_updated_at ON conversation_wallpaper_settings;
CREATE TRIGGER trg_conversation_wallpaper_settings_updated_at
BEFORE UPDATE ON conversation_wallpaper_settings
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_user_push_subscriptions_updated_at ON user_push_subscriptions;
CREATE TRIGGER trg_user_push_subscriptions_updated_at
BEFORE UPDATE ON user_push_subscriptions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_message_reactions_updated_at ON message_reactions;
CREATE TRIGGER trg_message_reactions_updated_at
BEFORE UPDATE ON message_reactions
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();
