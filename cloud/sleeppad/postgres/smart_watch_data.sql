-- Smart Watch Data Ingest Schema
-- Apply this after postgres/init.sql for existing or fresh databases.

CREATE EXTENSION IF NOT EXISTS timescaledb;

ALTER TABLE devices ADD COLUMN IF NOT EXISTS device_type TEXT NOT NULL DEFAULT 'sleep_pad';

CREATE INDEX IF NOT EXISTS idx_devices_owner_type ON devices (owner_id, device_type);

CREATE TABLE IF NOT EXISTS watch_data (
  time TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  hash TEXT NOT NULL,
  raw_data JSONB NOT NULL,
  batch_hash TEXT,
  meta JSONB
);

SELECT create_hypertable('watch_data', 'time', if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS idx_watch_data_hash ON watch_data (device_id, type, hash);
CREATE INDEX IF NOT EXISTS idx_watch_data_user_time ON watch_data (user_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_watch_data_device_time ON watch_data (device_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_watch_data_type_time ON watch_data (type, time DESC);
