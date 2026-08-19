-- Sleep sessions — one row per night, derived from sec_data by the session builder.
--
-- received_at is the backend ingest timestamp. The pad's own `ts` is a local-time
-- clock disguised as UTC with unbounded drift (the firmware never sends the 0x0B
-- time-sync frame), so `ts` is kept for cross-checking only and is never used as a
-- join or plot axis. Nullable + no backfill on purpose: filling it on a Timescale
-- hypertable would rewrite every chunk. Readers must use COALESCE(received_at, time).

ALTER TABLE sec_data ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ;
ALTER TABLE min_data ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ;

-- Plain table, not a hypertable: one row per night is not time-series volume.
CREATE TABLE IF NOT EXISTS sleep_sessions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id           TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  started_at          TIMESTAMPTZ NOT NULL,
  ended_at            TIMESTAMPTZ,              -- NULL = session still open
  duration_s          INTEGER,
  hr_avg              REAL,
  hr_min              SMALLINT,
  hr_max              SMALLINT,
  rr_avg              REAL,
  movement_total      INTEGER,
  snore_total         INTEGER,
  resp_disorder_total INTEGER,
  sit_up_count        INTEGER,
  wake_count          INTEGER,
  computed_at         TIMESTAMPTZ,
  -- Lets the builder re-run over the same data without duplicating a night
  -- (service.py upserts ON CONFLICT on this constraint).
  UNIQUE (device_id, started_at)
);

CREATE INDEX IF NOT EXISTS idx_sessions_device_started
  ON sleep_sessions (device_id, started_at DESC);
