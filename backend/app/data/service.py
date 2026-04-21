"""TimescaleDB queries for data endpoints."""

from uuid import UUID

import asyncpg

# (bucket_size, interval) tuples per range
_RANGE_PARAMS = {
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
          MAX(resp_disorder)     AS resp_disorder
        FROM min_data
        WHERE device_id = $1
          AND time > now() - interval '{interval}'
        GROUP BY bucket
        ORDER BY bucket ASC
    """
    rows = await pool.fetch(sql, device_id)
    return [dict(r) for r in rows]
