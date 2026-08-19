"""Smart watch device registration and Redis queue helpers."""

import json
from datetime import datetime, timezone
from typing import Any
from uuid import UUID

import asyncpg
import redis.asyncio as redis

WATCH_DEVICE_TYPE = "smart_watch"
WATCH_DATA_QUEUE = "watch:data:queue"
WATCH_DATA_DEAD_QUEUE = "watch:data:dead"


async def upsert_watch_device(
    pool: asyncpg.Pool,
    user_id: UUID,
    device_id: str,
    name: str | None,
) -> dict:
    """Create/update a watch device for this user; report conflict if owned elsewhere."""
    existing = await pool.fetchrow(
        "SELECT owner_id, device_type FROM devices WHERE id = $1",
        device_id,
    )
    if existing is not None:
        if existing["owner_id"] != user_id or existing["device_type"] != WATCH_DEVICE_TYPE:
            return {"conflict": True}
        row = await pool.fetchrow(
            """
            UPDATE devices
            SET name = COALESCE($3, name)
            WHERE id = $1 AND owner_id = $2
            RETURNING id, owner_id, name, paired_at, last_seen, device_type
            """,
            device_id,
            user_id,
            name,
        )
        return dict(row)

    try:
        row = await pool.fetchrow(
            """
            INSERT INTO devices (id, owner_id, name, device_type)
            VALUES ($1, $2, $3, $4)
            RETURNING id, owner_id, name, paired_at, last_seen, device_type
            """,
            device_id,
            user_id,
            name,
            WATCH_DEVICE_TYPE,
        )
    except asyncpg.UniqueViolationError:
        return {"conflict": True}
    return dict(row)


async def enqueue_watch_payload(
    rds: redis.Redis,
    *,
    user_id: UUID,
    device_id: str,
    payload: dict[str, Any],
) -> None:
    """Push an ingest job to the Redis list for background processing."""
    job = {
        "user_id": str(user_id),
        "device_id": device_id,
        "batch_hash": payload.get("hash"),
        "payload": payload,
        "queued_at": datetime.now(tz=timezone.utc).isoformat(),
    }
    await rds.rpush(WATCH_DATA_QUEUE, json.dumps(job, separators=(",", ":")))
