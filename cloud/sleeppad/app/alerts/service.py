"""DB queries for alert thresholds + history."""

from uuid import UUID

import asyncpg

DEFAULT_THRESHOLDS = dict(
    hr_high=120,
    hr_low=40,
    rr_high=30.0,
    rr_low=5.0,
    resp_disorder_count=5,
)


async def ensure_threshold(
    pool: asyncpg.Pool, device_id: str, user_id: UUID
) -> None:
    """Insert default threshold row if one doesn't exist for (device, user)."""
    await pool.execute(
        """
        INSERT INTO alert_thresholds
          (device_id, user_id, hr_high, hr_low, rr_high, rr_low, resp_disorder_count)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        ON CONFLICT (device_id, user_id) DO NOTHING
        """,
        device_id, user_id,
        DEFAULT_THRESHOLDS["hr_high"],
        DEFAULT_THRESHOLDS["hr_low"],
        DEFAULT_THRESHOLDS["rr_high"],
        DEFAULT_THRESHOLDS["rr_low"],
        DEFAULT_THRESHOLDS["resp_disorder_count"],
    )


async def get_threshold(
    pool: asyncpg.Pool, device_id: str, user_id: UUID
) -> dict | None:
    row = await pool.fetchrow(
        """
        SELECT device_id, hr_high, hr_low, rr_high, rr_low, resp_disorder_count
        FROM alert_thresholds
        WHERE device_id = $1 AND user_id = $2
        """,
        device_id, user_id,
    )
    return dict(row) if row else None


async def update_threshold(
    pool: asyncpg.Pool, device_id: str, user_id: UUID, changes: dict
) -> dict | None:
    """Partial update — only keys present in `changes` are written."""
    # First ensure a row exists so the UPDATE has something to hit
    await ensure_threshold(pool, device_id, user_id)
    if changes:
        # Build dynamic SET clause from known-safe column names (keys are validated by Pydantic)
        set_parts = ", ".join(f"{col} = ${i+3}" for i, col in enumerate(changes))
        sql = (
            f"UPDATE alert_thresholds SET {set_parts}, updated_at = now() "
            "WHERE device_id = $1 AND user_id = $2"
        )
        await pool.execute(sql, device_id, user_id, *changes.values())
    return await get_threshold(pool, device_id, user_id)


async def list_alerts(
    pool: asyncpg.Pool, device_id: str, user_id: UUID, limit: int = 100
) -> list[dict]:
    rows = await pool.fetch(
        """
        SELECT id, device_id, metric, value, threshold, triggered_at
        FROM alerts
        WHERE device_id = $1 AND user_id = $2
        ORDER BY triggered_at DESC
        LIMIT $3
        """,
        device_id, user_id, limit,
    )
    return [dict(r) for r in rows]
