-- Sleep Pad Platform — Initial Schema
-- TimescaleDB hypertables for time-series data + relational tables for auth/devices/alerts/sharing

CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- for gen_random_uuid()

-- =========================================================================
-- Users
-- =========================================================================
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  fcm_token TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);

-- =========================================================================
-- Devices
-- =========================================================================
CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,                                 -- 10-char ASCII (e.g. CNU2000001)
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT,
  paired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_devices_owner ON devices (owner_id);

-- =========================================================================
-- Per-second readings (0x85 frame)
-- =========================================================================
CREATE TABLE IF NOT EXISTS sec_data (
  time TIMESTAMPTZ NOT NULL,
  device_id TEXT NOT NULL,
  status SMALLINT,
  heart_rate SMALLINT,
  resp_rate REAL,
  sdata SMALLINT,
  pdata SMALLINT
);

SELECT create_hypertable('sec_data', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS idx_sec_device_time ON sec_data (device_id, time DESC);

-- =========================================================================
-- Per-minute readings (0x86 frame)
-- =========================================================================
CREATE TABLE IF NOT EXISTS min_data (
  time TIMESTAMPTZ NOT NULL,
  device_id TEXT NOT NULL,
  status SMALLINT,
  heart_rate SMALLINT,
  resp_rate REAL,
  movement SMALLINT,
  snore_count SMALLINT,
  resp_disorder SMALLINT,
  pthd SMALLINT,
  temp REAL
);

SELECT create_hypertable('min_data', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS idx_min_device_time ON min_data (device_id, time DESC);

-- =========================================================================
-- Alert thresholds (per device, per user)
-- Owner and every shared user can have their own thresholds
-- =========================================================================
CREATE TABLE IF NOT EXISTS alert_thresholds (
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  hr_high SMALLINT NOT NULL DEFAULT 120,
  hr_low SMALLINT NOT NULL DEFAULT 40,
  rr_high REAL NOT NULL DEFAULT 30,
  rr_low REAL NOT NULL DEFAULT 5,
  resp_disorder_count SMALLINT NOT NULL DEFAULT 5,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (device_id, user_id)
);

-- =========================================================================
-- Alert history
-- =========================================================================
CREATE TABLE IF NOT EXISTS alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  metric TEXT NOT NULL,         -- 'hr_high' | 'hr_low' | 'rr_high' | 'rr_low' | 'resp_disorder'
  value REAL NOT NULL,
  threshold REAL NOT NULL,
  triggered_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_alerts_device_time ON alerts (device_id, triggered_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_user_time ON alerts (user_id, triggered_at DESC);

-- =========================================================================
-- Device sharing (invite family by email)
-- =========================================================================
CREATE TABLE IF NOT EXISTS device_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  shared_with_id UUID REFERENCES users(id) ON DELETE CASCADE,  -- null until invite accepted
  invited_email TEXT NOT NULL,
  accepted BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at TIMESTAMPTZ,
  UNIQUE (device_id, invited_email)
);

CREATE INDEX IF NOT EXISTS idx_shares_shared_with ON device_shares (shared_with_id) WHERE accepted = TRUE;
CREATE INDEX IF NOT EXISTS idx_shares_invited_email ON device_shares (invited_email);
