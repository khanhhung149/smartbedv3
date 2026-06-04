"""Background MQTT subscriber.

Flow per message:
1. Parse topic → device_id
2. Validate JSON payload (SecData or MinData)
3. Verify device is paired (reject orphan publishes)
4. Insert row into TimescaleDB using server now() as authoritative time
5. Update last_seen on devices table + Redis online key (TTL 70s)
6. Publish serialized payload to Redis channel realtime:{device_id}

Design notes:
- Server `now()` is used for the `time` column (not the device ts), so
  TimescaleDB buckets stay accurate even with device clock skew. Device ts
  is discarded; add a `device_ts` column later if forensic replay is needed.
- Messages are dispatched to bounded concurrent tasks so a slow insert
  does not block ingestion from other devices.
"""

import asyncio
import json
import logging
from datetime import datetime, timezone

import aiomqtt
import asyncpg
import redis.asyncio as redis

from config import get_settings
from mqtt.parser import device_id_from_topic, parse_env, parse_min, parse_sec
from redis_client import PAIRED_DEVICES_KEY, online_key

logger = logging.getLogger(__name__)

_ONLINE_TTL_SECONDS = 70
_CONCURRENCY = 32


async def run_subscriber(pool: asyncpg.Pool, rds: redis.Redis, stop: asyncio.Event) -> None:
    """Long-running loop — reconnects on broker restart with exponential backoff."""
    settings = get_settings()
    backoff = 1
    sem = asyncio.Semaphore(_CONCURRENCY)
    while not stop.is_set():
        try:
            async with aiomqtt.Client(
                hostname=settings.mqtt_host,
                port=settings.mqtt_port,
                username=settings.mqtt_username or None,
                password=settings.mqtt_password or None,
                identifier="sleeppad-fastapi-subscriber",
            ) as client:
                logger.info("mqtt connected host=%s port=%s", settings.mqtt_host, settings.mqtt_port)
                backoff = 1
                await client.subscribe("sleeppad/+/sec")
                await client.subscribe("sleeppad/+/min")
                await client.subscribe("sleeppad/+/temp")
                await client.subscribe("sleeppad/+/status")
                async for msg in client.messages:
                    if stop.is_set():
                        break
                    # dispatch concurrently so slow inserts don't block ingestion
                    asyncio.create_task(_dispatch(sem, pool, rds, msg))
        except aiomqtt.MqttError as exc:
            logger.warning("mqtt error: %s (reconnect in %ds)", exc, backoff)
            try:
                await asyncio.wait_for(stop.wait(), timeout=backoff)
            except asyncio.TimeoutError:
                pass
            backoff = min(backoff * 2, 30)


async def _dispatch(sem: asyncio.Semaphore, pool, rds, msg) -> None:
    async with sem:
        try:
            await _handle_message(pool, rds, msg)
        except Exception as exc:  # noqa: BLE001
            logger.exception("handler failed: %s", exc)


async def _handle_message(pool: asyncpg.Pool, rds: redis.Redis, msg) -> None:
    topic = str(msg.topic)
    device_id = device_id_from_topic(topic)
    if device_id is None:
        return

    if topic.endswith("/status"):
        status = msg.payload.decode(errors="ignore").strip().lower()
        # Mark online + bump last_seen as soon as the device's MQTT session is up
        # — even before any sec/min telemetry arrives. Otherwise a healthy chip
        # with the sleep pad unplugged (or still booting) reads as "offline" /
        # "last seen unknown" in the app despite an active broker session.
        # Sec/min handlers refresh the same key + last_seen on every frame, so
        # the TTL keeps rolling once telemetry starts.
        try:
            if status == "online":
                await rds.set(online_key(device_id), "1", ex=_ONLINE_TTL_SECONDS)
                await pool.execute(
                    "UPDATE devices SET last_seen = $1 WHERE id = $2",
                    datetime.now(tz=timezone.utc), device_id,
                )
            elif status == "offline":
                await rds.delete(online_key(device_id))
        except Exception as exc:  # noqa: BLE001
            logger.warning("status update failed: %s", exc)
        return

    # Only accept data from paired devices (prevents orphan rows via spoofed topic).
    if not await _is_paired(pool, rds, device_id):
        logger.debug("drop publish from unpaired device_id=%s", device_id)
        return

    now = datetime.now(tz=timezone.utc)

    if topic.endswith("/sec"):
        payload = parse_sec(msg.payload)
        if payload is None or payload.device_id != device_id:
            return
        await _insert_sec(pool, now, payload)
        await _mark_online(pool, rds, device_id, now)
        await rds.publish(f"realtime:{device_id}", payload.model_dump_json())
    elif topic.endswith("/min"):
        payload = parse_min(msg.payload)
        if payload is None or payload.device_id != device_id:
            return
        await _insert_min(pool, now, payload)
        await _mark_online(pool, rds, device_id, now)
        # Also forward min frames to the realtime channel so the app can show
        # the fields only present in min (movement, snore_count).
        # NOTE: MinData.temp is body temp (currently 0); ambient temperature
        # comes from the /temp topic below and is what the app displays.
        await rds.publish(f"realtime:{device_id}", payload.model_dump_json())
    elif topic.endswith("/temp"):
        payload = parse_env(msg.payload)
        if payload is None or payload.device_id != device_id:
            return
        await _mark_online(pool, rds, device_id, now)
        # Forward ambient temp + humidity on the realtime channel using distinct
        # keys so they don't collide with MinData.temp (body temp). /ws/user maps
        # env_temp → pad.temp and humidity → pad.humidity.
        await rds.publish(
            f"realtime:{device_id}",
            json.dumps(
                {
                    "device_id": device_id,
                    "ts": payload.ts,
                    "env_temp": payload.temp,
                    "humidity": payload.humi,
                },
                separators=(",", ":"),
            ),
        )


async def _is_paired(pool: asyncpg.Pool, rds: redis.Redis, device_id: str) -> bool:
    """Redis set membership check with SQL fallback (populates cache on hit)."""
    try:
        if await rds.sismember(PAIRED_DEVICES_KEY, device_id):
            return True
    except Exception as exc:  # noqa: BLE001
        logger.warning("redis sismember failed, falling back to SQL: %s", exc)
    row = await pool.fetchrow("SELECT 1 FROM devices WHERE id = $1", device_id)
    if row is None:
        return False
    # Backfill cache so subsequent publishes skip the SQL hop
    try:
        await rds.sadd(PAIRED_DEVICES_KEY, device_id)
    except Exception:  # noqa: BLE001
        pass
    return True


async def _insert_sec(pool: asyncpg.Pool, ts: datetime, p) -> None:
    await pool.execute(
        """
        INSERT INTO sec_data (time, device_id, status, heart_rate, resp_rate, sdata, pdata)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        """,
        ts, p.device_id, p.status,
        p.heart_rate, p.resp_rate, p.sdata, p.pdata,
    )


async def _insert_min(pool: asyncpg.Pool, ts: datetime, p) -> None:
    await pool.execute(
        """
        INSERT INTO min_data
          (time, device_id, status, heart_rate, resp_rate,
           movement, snore_count, resp_disorder, pthd, temp)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        """,
        ts, p.device_id, p.status,
        p.heart_rate, p.resp_rate, p.movement,
        p.snore_count, p.resp_disorder, p.pthd, p.temp,
    )


async def _mark_online(
    pool: asyncpg.Pool, rds: redis.Redis, device_id: str, ts: datetime
) -> None:
    """Refresh Redis online flag (TTL) + update devices.last_seen."""
    try:
        await rds.set(online_key(device_id), "1", ex=_ONLINE_TTL_SECONDS)
    except Exception as exc:  # noqa: BLE001
        logger.warning("redis online set failed: %s", exc)
    await pool.execute("UPDATE devices SET last_seen = $1 WHERE id = $2", ts, device_id)
