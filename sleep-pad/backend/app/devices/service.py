"""Device DB queries."""

from uuid import UUID

import asyncpg
import redis.asyncio as redis

from redis_client import PAIRED_DEVICES_KEY, online_key


async def pair_device(
    pool: asyncpg.Pool,
    rds: redis.Redis,
    owner_id: UUID,
    device_id: str,
    name: str | None,
) -> dict:
    """Upsert: if device exists and is owned by same user, update name. Otherwise create.

    On success, add device_id to the Redis `paired_devices` set so the MQTT
    subscriber can validate membership without a SQL round-trip per message.
    """
    row = await pool.fetchrow(
        """
        INSERT INTO devices (id, owner_id, name)
        VALUES ($1, $2, $3)
        ON CONFLICT (id) DO UPDATE
          SET name = EXCLUDED.name
          WHERE devices.owner_id = EXCLUDED.owner_id
        RETURNING id, owner_id, name, paired_at, last_seen
        """,
        device_id,
        owner_id,
        name,
    )
    if row is None:
        # Conflict where owner_id differs: device already paired by someone else
        return {"conflict": True}
    try:
        await rds.sadd(PAIRED_DEVICES_KEY, device_id)
    except Exception:  # noqa: BLE001
        # Cache miss tolerated — subscriber falls back to SQL
        pass
    return dict(row)


async def warm_paired_cache(pool: asyncpg.Pool, rds: redis.Redis) -> int:
    """Load all paired device_ids into Redis set on startup. Returns count."""
    rows = await pool.fetch("SELECT id FROM devices")
    if not rows:
        return 0
    ids = [r["id"] for r in rows]
    # Replace the set so stale entries from previous runs don't linger
    pipe = rds.pipeline()
    pipe.delete(PAIRED_DEVICES_KEY)
    pipe.sadd(PAIRED_DEVICES_KEY, *ids)
    await pipe.execute()
    return len(ids)


async def list_user_devices(
    pool: asyncpg.Pool,
    rds: redis.Redis,
    user_id: UUID,
    device_type: str | None = None,
) -> list[dict]:
    rows = await pool.fetch(
        """
        SELECT id AS device_id, device_type, name, paired_at, last_seen
        FROM devices
        WHERE owner_id = $1
          AND ($2::text IS NULL OR device_type = $2)
        ORDER BY paired_at ASC
        """,
        user_id,
        device_type,
    )
    result: list[dict] = []
    for row in rows:
        online = await _is_online(rds, row["device_id"])
        result.append({**dict(row), "online": online})
    return result


async def get_device_status(
    pool: asyncpg.Pool,
    rds: redis.Redis,
    user_id: UUID,
    device_id: str,
    device_type: str | None = None,
) -> dict | None:
    row = await pool.fetchrow(
        "SELECT id AS device_id, device_type, last_seen FROM devices "
        "WHERE id = $1 AND owner_id = $2 "
        "AND ($3::text IS NULL OR device_type = $3)",
        device_id,
        user_id,
        device_type,
    )
    if row is None:
        return None
    online = await _is_online(rds, row["device_id"])
    return {**dict(row), "online": online}


async def _is_online(rds: redis.Redis, device_id: str) -> bool:
    """Online if Redis key set by MQTT subscriber (Phase 03) — TTL 70s."""
    try:
        return bool(await rds.exists(online_key(device_id)))
    except Exception:
        return False


async def remove_device(
    pool: asyncpg.Pool, rds: redis.Redis, owner_id: UUID, device_id: str
) -> str | None:
    """Delete device row (cascade removes alerts/thresholds/shares via FK).
    Returns deleted device_type, or None if not owned by caller or not found.
    Caller decides which device types need physical reset side effects."""
    row = await pool.fetchrow(
        """
        DELETE FROM devices
        WHERE id = $1 AND owner_id = $2
        RETURNING device_type
        """,
        device_id,
        owner_id,
    )
    if row is None:
        return None
    try:
        await rds.srem(PAIRED_DEVICES_KEY, device_id)
        await rds.delete(online_key(device_id))
    except Exception:
        pass
    return row["device_type"]
