"""TimescaleDB queries for data endpoints."""

import json
from uuid import UUID

import asyncpg

# (bucket_size, interval) tuples per range
_RANGE_PARAMS = {
    "hour":  ("1 minute",  "1 hour"),   # Home sparkline preload (HR/RR/Temp)
    "day":   ("5 minutes", "1 day"),
    "week":  ("1 hour",    "7 days"),
    "month": ("3 hours",   "30 days"),
}


async def user_can_access_device(
    pool: asyncpg.Pool, user_id: UUID, device_id: str
) -> bool:
    """True if user owns the device OR has an accepted share for it."""
    row = await pool.fetchrow(
        """
        SELECT 1
        FROM devices d
        LEFT JOIN device_shares s
          ON s.device_id = d.id
          AND s.shared_with_id = $2
          AND s.accepted = TRUE
        WHERE d.id = $1
          AND (d.owner_id = $2 OR s.id IS NOT NULL)
        LIMIT 1
        """,
        device_id,
        user_id,
    )
    return row is not None


async def get_user_device_ids(
    pool: asyncpg.Pool, user_id: UUID
) -> dict[str, list[str]]:
    """Device ids the user can stream, split by type.

    sleep_pad: owned OR accepted-share (realtime fan-in source).
    watch: owned only (watch_data is keyed by owning user).
    """
    rows = await pool.fetch(
        """
        SELECT d.id, d.device_type
        FROM devices d
        LEFT JOIN device_shares s
          ON s.device_id = d.id
          AND s.shared_with_id = $1
          AND s.accepted = TRUE
        WHERE d.owner_id = $1 OR s.id IS NOT NULL
        """,
        user_id,
    )
    sleep_pad: list[str] = []
    watch: list[str] = []
    for row in rows:
        if row["device_type"] == "smart_watch":
            watch.append(row["id"])
        else:
            sleep_pad.append(row["id"])
    return {"sleep_pad": sleep_pad, "watch": watch}


def _num(value) -> float | None:
    """Best-effort numeric coercion for JSONB text values."""
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


async def get_watch_snapshot(pool: asyncpg.Pool, user_id: UUID) -> dict | None:
    """Latest smartwatch snapshot for a user: spo2, hrv, glucose, blood pressure
    (latest reading) + steps (today's running total).

    Steps records are per-bucket deltas, so the watch shows the daily SUM (reset
    at local midnight). We sum the most recent local day instead of taking the
    last bucket. Other metrics keep "latest reading" semantics.
    """
    rows = await pool.fetch(
        """
        SELECT DISTINCT ON (type) type, device_id, time, raw_data
        FROM watch_data
        WHERE user_id = $1 AND type IN ('combined', 'blood_pressure')
        ORDER BY type, time DESC
        """,
        user_id,
    )
    steps, steps_at, step_device = await _steps_today(pool, user_id)
    if not rows and steps is None:
        return None

    snap: dict = {
        "device_id": None,
        "synced_at": None,
        "spo2": None,
        "spo2_at": None,
        "steps": None,
        "steps_at": None,
        "systolic": None,
        "diastolic": None,
        "bp_at": None,
        "hrv": None,
        "hrv_at": None,
        "blood_glucose": None,
        "glucose_at": None,
    }
    # Steps = today's running total (summed daily deltas).
    snap["steps"] = steps
    snap["steps_at"] = steps_at
    snap["device_id"] = step_device

    latest_time = steps_at and _parse_iso(steps_at)
    for row in rows:
        raw = row["raw_data"]
        if isinstance(raw, str):
            raw = json.loads(raw)
        snap["device_id"] = snap["device_id"] or row["device_id"]
        # Per-metric measurement time (UTC ISO) — client converts to local.
        row_at = row["time"].isoformat() if row["time"] else None
        if latest_time is None or row["time"] > latest_time:
            latest_time = row["time"]
        if row["type"] == "combined":
            spo2 = _num(raw.get("bloodOxygen"))
            snap["spo2"] = int(spo2) if spo2 else None
            snap["spo2_at"] = row_at
            hrv = _num(raw.get("hrv"))
            snap["hrv"] = int(hrv) if hrv else None
            snap["hrv_at"] = row_at
            glucose = _num(raw.get("bloodGlucose"))
            snap["blood_glucose"] = glucose if glucose else None
            snap["glucose_at"] = row_at
        elif row["type"] == "blood_pressure":
            sys = _num(raw.get("systolicBloodPressure"))
            dia = _num(raw.get("diastolicBloodPressure"))
            snap["systolic"] = int(sys) if sys else None
            snap["diastolic"] = int(dia) if dia else None
            snap["bp_at"] = row_at
    snap["synced_at"] = latest_time.isoformat() if latest_time else None
    return snap


# Day boundary for the daily step total. The NOTT watch resets steps at local
# midnight; sum the deltas for that local day. Product is VN-based.
_STEP_DAY_TZ = "Asia/Ho_Chi_Minh"


async def _steps_today(
    pool: asyncpg.Pool, user_id: UUID
) -> tuple[int | None, str | None, str | None]:
    """Sum step deltas for the most recent local day → (steps, at_iso, device_id)."""
    row = await pool.fetchrow(
        """
        WITH s AS (
            SELECT (raw_data->>'step')::int AS step,
                   time,
                   device_id,
                   (time AT TIME ZONE $2)::date AS local_day
            FROM watch_data
            WHERE user_id = $1
              AND type = 'step'
              AND raw_data->>'step' ~ '^[0-9]+$'
        )
        SELECT SUM(step)::bigint AS total,
               MAX(time) AS at,
               (array_agg(device_id ORDER BY time DESC))[1] AS device_id
        FROM s
        WHERE local_day = (SELECT MAX(local_day) FROM s)
        """,
        user_id,
        _STEP_DAY_TZ,
    )
    if row is None or row["total"] is None:
        return None, None, None
    at = row["at"].isoformat() if row["at"] else None
    return int(row["total"]), at, row["device_id"]


def _parse_iso(value: str):
    from datetime import datetime

    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


async def get_latest_sec(pool: asyncpg.Pool, device_id: str) -> dict | None:
    row = await pool.fetchrow(
        """
        SELECT time, device_id, status, heart_rate, resp_rate, sdata, pdata
        FROM sec_data
        WHERE device_id = $1
        ORDER BY time DESC
        LIMIT 1
        """,
        device_id,
    )
    return dict(row) if row else None


async def get_samples(
    pool: asyncpg.Pool, device_id: str, from_time, to_time
) -> list[dict]:
    """Raw samples (bảng chuẩn CSV take-home) trong cửa sổ [from, to].

    Trả về đúng 9 cột CSV + kênh raw. Dùng cho dashboard local "xem lại một đêm".
    """
    rows = await pool.fetch(
        """
        SELECT
          t, device_id, presence, hr_bpm, resp_amplitude, motion,
          weight_kg, spo2, temp_c, humidity,
          status, sdata, pdata, movement, snore_count, resp_disorder, pthd,
          body_temp, uart_ok, ts_pad, received_at
        FROM samples
        WHERE device_id = $1 AND t >= $2 AND t < $3
        ORDER BY t ASC
        """,
        device_id,
        from_time,
        to_time,
    )
    return [dict(r) for r in rows]


async def get_history(
    pool: asyncpg.Pool, device_id: str, range_key: str
) -> list[dict]:
    bucket, interval = _RANGE_PARAMS[range_key]
    # bucket + interval are server-constants (not user-supplied), so interpolation is safe
    sql = f"""
        SELECT
          time_bucket('{bucket}', time) AS bucket,
          AVG(heart_rate)::real  AS hr,
          AVG(resp_rate)::real   AS rr,
          MAX(resp_disorder)     AS resp_disorder,
          AVG(temp)::real        AS temp
        FROM min_data
        WHERE device_id = $1
          AND time > now() - interval '{interval}'
        GROUP BY bucket
        ORDER BY bucket ASC
    """
    rows = await pool.fetch(sql, device_id)
    return [dict(r) for r in rows]


async def get_sync_data(
    pool: asyncpg.Pool,
    user_id: UUID,
    from_time,
    to_time,
) -> tuple[list[dict], list[dict]]:
    """Return sleep pad and smart watch data for the same user-owned/shared window."""
    sleep_rows = await pool.fetch(
        """
        SELECT m.time, m.device_id, m.status, m.heart_rate, m.resp_rate,
               m.movement, m.snore_count, m.resp_disorder, m.pthd, m.temp
        FROM min_data m
        JOIN devices d ON d.id = m.device_id
        LEFT JOIN device_shares s
          ON s.device_id = d.id
          AND s.shared_with_id = $1
          AND s.accepted = TRUE
        WHERE m.time >= $2
          AND m.time <= $3
          AND d.device_type = 'sleep_pad'
          AND (d.owner_id = $1 OR s.id IS NOT NULL)
        ORDER BY m.time ASC
        """,
        user_id,
        from_time,
        to_time,
    )
    watch_rows = await pool.fetch(
        """
        SELECT time, received_at, device_id, type, hash, raw_data, batch_hash, meta
        FROM watch_data
        WHERE user_id = $1
          AND time >= $2
          AND time <= $3
        ORDER BY time ASC
        """,
        user_id,
        from_time,
        to_time,
    )
    watch_result = []
    for row in watch_rows:
        item = dict(row)
        for key in ("raw_data", "meta"):
            if isinstance(item.get(key), str):
                item[key] = json.loads(item[key])
        watch_result.append(item)
    return [dict(r) for r in sleep_rows], watch_result
