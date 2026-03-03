-- Push notification tokens (Pushy.me)
CREATE TABLE IF NOT EXISTS muevete.push_tokens (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_uuid   UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_token TEXT       NOT NULL,
  platform    TEXT        NOT NULL DEFAULT 'android',  -- 'android' | 'ios'
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_uuid, device_token)
);

-- Index for fast lookup by user
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_uuid ON muevete.push_tokens(user_uuid);

-- RLS: users can manage their own tokens
ALTER TABLE muevete.push_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own tokens"
  ON muevete.push_tokens FOR INSERT
  WITH CHECK (auth.uid() = user_uuid);

CREATE POLICY "Users can read their own tokens"
  ON muevete.push_tokens FOR SELECT
  USING (auth.uid() = user_uuid);

CREATE POLICY "Users can update their own tokens"
  ON muevete.push_tokens FOR UPDATE
  USING (auth.uid() = user_uuid);

CREATE POLICY "Users can delete their own tokens"
  ON muevete.push_tokens FOR DELETE
  USING (auth.uid() = user_uuid);

-- Service role can read all tokens (for edge function)
CREATE POLICY "Service role can read all tokens"
  ON muevete.push_tokens FOR SELECT
  TO service_role
  USING (true);
