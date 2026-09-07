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
from mqtt.parser import device_id_from_topic, parse_env, parse_min, parse_sec, to_timestamptz
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
        # Cờ online và kênh realtime đi TRƯỚC bảng samples. Thứ tự cũ đặt
        # _insert_sample lên trên, nên khi bảng samples chưa được tạo thì mỗi
        # frame ném lỗi ngay tại đó: last_seen đứng im và màn hình realtime
        # không nhận gì suốt cả đêm, dù sec_data vẫn ghi đủ.
        await _mark_online(pool, rds, device_id, now)
        await rds.publish(f"realtime:{device_id}", payload.model_dump_json())
        await _insert_sample(pool, device_id, payload, _latest_motion(device_id), _latest_env(device_id))
    elif topic.endswith("/min"):
        payload = parse_min(msg.payload)
        if payload is None or payload.device_id != device_id:
            return
        _cache_motion(device_id, payload)
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
        _cache_env(device_id, payload)
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
    # received_at is stamped here, not by the device: the pad clock drifts and the
    # firmware never sends the 0x0B sync frame, so `time` (device ts) is unreliable.
    # Readers use COALESCE(received_at, time) — rows written before this column
    # existed keep received_at NULL and are not backfilled.
    await pool.execute(
        """
        INSERT INTO sec_data
          (time, device_id, status, heart_rate, resp_rate, sdata, pdata, received_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        """,
        ts, p.device_id, p.status,
        p.heart_rate, p.resp_rate, p.sdata, p.pdata,
        datetime.now(timezone.utc),
    )


async def _insert_min(pool: asyncpg.Pool, ts: datetime, p) -> None:
    # See _insert_sec for why received_at exists.
    await pool.execute(
        """
        INSERT INTO min_data
          (time, device_id, status, heart_rate, resp_rate,
           movement, snore_count, resp_disorder, pthd, temp, received_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        """,
        ts, p.device_id, p.status,
        p.heart_rate, p.resp_rate, p.movement,
        p.snore_count, p.resp_disorder, p.pthd, p.temp,
        datetime.now(timezone.utc),
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


# ---------------------------------------------------------------------------
# Canonical samples (Phase 01) — schema khớp CSV take-home
# ---------------------------------------------------------------------------
# Pad là master đẩy 1Hz; các kênh chỉ có ở frame 0x86 (1/phút) và /temp được ghép vào
# mẫu sec qua cache per-device để 1 dòng samples = đủ TẤT CẢ kênh (không mất kênh nào).
# `t` dùng MCU timestamp (payload.ts) chứ không phải server now() — đúng yêu cầu framework
# "timestamp gắn tại thiết bị". received_at vẫn lưu để đối chiếu độ lệch đồng hồ.
_latest_motion_cache: dict[str, "MinDataPayload"] = {}
_latest_env_cache: dict[str, "EnvDataPayload"] = {}


def _cache_motion(device_id: str, p) -> None:
    _latest_motion_cache[device_id] = p


def _cache_env(device_id: str, p) -> None:
    _latest_env_cache[device_id] = p


def _latest_motion(device_id: str):
    return _latest_motion_cache.get(device_id)


def _latest_env(device_id: str):
    return _latest_env_cache.get(device_id)


async def _insert_sample(pool: asyncpg.Pool, device_id: str, sec, min_p, env_p) -> None:
    """Ghi 1 dòng samples (bảng chuẩn CSV) cho frame sec 0x85 vừa nhận."""
    # t = MCU timestamp (epoch giây) nếu hợp lệ, nếu không dùng received_at.
    ts = to_timestamptz(sec.ts) if sec.ts > 0 else datetime.now(timezone.utc)
    # presence: pad không có chân OUT — suy từ status/hr/rr (cả ba = 0 thì vắng).
    presence = sec.on_bed
    # Các kênh 1/phút lấy từ cache min gần nhất (movement, snore_count, resp_disorder...).
    movement = min_p.movement if min_p else None
    snore = min_p.snore_count if min_p else None
    resp_disorder = min_p.resp_disorder if min_p else None
    pthd = min_p.pthd if min_p else None
    body_temp = (min_p.temp / 10.0) if min_p and min_p.temp else None
    # Kênh môi trường từ topic /temp.
    env_temp = env_p.temp if env_p else None
    humidity = env_p.humi if env_p else None

    await pool.execute(
        """
        INSERT INTO samples
          (t, device_id, presence, hr_bpm, resp_amplitude, motion,
           weight_kg, spo2, temp_c, humidity,
           status, sdata, pdata, movement, snore_count, resp_disorder, pthd, body_temp,
           uart_ok, ts_pad, received_at)
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21)
        """,
        ts, device_id, presence, sec.heart_rate, sec.resp_rate,
        movement, None, None, env_temp, humidity,
        sec.status, sec.sdata, sec.pdata, movement, snore, resp_disorder, pthd, body_temp,
        sec.uart_ok, sec.ts_pad, datetime.now(timezone.utc),
    )
