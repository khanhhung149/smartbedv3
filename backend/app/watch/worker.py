"""Background worker for Redis List backed smart watch ingestion."""

import asyncio
import json
import logging
import re
from datetime import datetime, timezone
from typing import Any
from uuid import UUID

import asyncpg
import redis.asyncio as redis

from redis_client import online_key
from watch.service import WATCH_DATA_DEAD_QUEUE, WATCH_DATA_QUEUE

logger = logging.getLogger(__name__)

_ONLINE_TTL_SECONDS = 70
_BLPOP_TIMEOUT_SECONDS = 5
_DATA_SUFFIX = "Data"


async def run_watch_data_worker(
    pool: asyncpg.Pool,
    rds: redis.Redis,
    stop: asyncio.Event,
) -> None:
    """Process queued smart watch payloads until stopped."""
    logger.info("watch data worker started")
    while not stop.is_set():
        try:
            item = await rds.blpop(WATCH_DATA_QUEUE, timeout=_BLPOP_TIMEOUT_SECONDS)
            if item is None:
                continue
            _, raw_job = item
            await _handle_job(pool, rds, raw_job)
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.exception("watch worker loop failed: %s", exc)
    logger.info("watch data worker stopped")


async def _handle_job(pool: asyncpg.Pool, rds: redis.Redis, raw_job: str) -> None:
    try:
        job = json.loads(raw_job)
        user_id = UUID(str(job["user_id"]))
        device_id = str(job["device_id"])
        payload = job["payload"]
        if not isinstance(payload, dict):
            raise ValueError("payload must be an object")
    except Exception as exc:  # noqa: BLE001
        logger.warning("invalid watch job moved to dead queue: %s", exc)
        await rds.rpush(WATCH_DATA_DEAD_QUEUE, raw_job)
        return

    batch_hash = job.get("batch_hash")
    meta = payload.get("meta") if isinstance(payload.get("meta"), dict) else {}
    total = 0
    inserted = 0
    skipped = 0

    for section in payload.get("data") or []:
        if not isinstance(section, dict):
            skipped += 1
            continue
        for key, records in section.items():
            if not key.endswith(_DATA_SUFFIX) or not isinstance(records, list):
                continue
            data_type = _type_from_key(key)
            for record in records:
                total += 1
                ok = await _process_record(
                    pool,
                    user_id=user_id,
                    device_id=device_id,
                    data_type=data_type,
                    record=record,
                    batch_hash=batch_hash,
                    meta=meta,
                )
                if ok:
                    inserted += 1
                else:
                    skipped += 1

    try:
        await _mark_watch_seen(pool, rds, device_id)
    except Exception as exc:  # noqa: BLE001
        logger.warning("watch seen update failed device=%s: %s", device_id, exc)
    logger.info(
        "watch job processed device=%s total=%d inserted=%d skipped=%d",
        device_id,
        total,
        inserted,
        skipped,
    )


async def _process_record(
    pool: asyncpg.Pool,
    *,
    user_id: UUID,
    device_id: str,
    data_type: str,
    record: Any,
    batch_hash: str | None,
    meta: dict[str, Any],
) -> bool:
    try:
        if not isinstance(record, dict):
            logger.warning("skip watch item: record is not an object")
            return False
        item_hash = record.get("hash")
        if not isinstance(item_hash, str) or not item_hash.strip():
            logger.warning("skip watch item: missing hash")
            return False

        exists = await pool.fetchrow(
            """
            SELECT 1
            FROM watch_data
            WHERE device_id = $1 AND type = $2 AND hash = $3
            LIMIT 1
            """,
            device_id,
            data_type,
            item_hash,
        )
        if exists:
            return False

        ts = _record_time(record)
        if ts is None:
            logger.warning("skip watch item hash=%s: missing timestamp", item_hash)
            return False

        await pool.execute(
            """
            INSERT INTO watch_data
              (time, device_id, user_id, type, hash, raw_data, batch_hash, meta)
            VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, $8::jsonb)
            """,
            ts,
            device_id,
            user_id,
            data_type,
            item_hash,
            json.dumps(record, separators=(",", ":")),
            batch_hash,
            json.dumps(meta, separators=(",", ":")),
        )
        return True
    except Exception as exc:  # noqa: BLE001
        logger.warning("skip watch item type=%s: %s", data_type, exc)
        return False


def _record_time(record: dict[str, Any]) -> datetime | None:
    timestamp = record.get("timestamp")
    if isinstance(timestamp, str) and timestamp.strip():
        try:
            value = timestamp.strip()
            if value.endswith("Z"):
                value = value[:-1] + "+00:00"
            dt = datetime.fromisoformat(value)
            if dt.tzinfo is None:
                return dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc)
        except ValueError:
            pass

    start_ts = record.get("startTimeStamp")
    if isinstance(start_ts, (int, float)):
        return datetime.fromtimestamp(start_ts, tz=timezone.utc)
    return None


def _type_from_key(key: str) -> str:
    base = key.removesuffix(_DATA_SUFFIX)
    return re.sub(r"(?<!^)(?=[A-Z])", "_", base).lower()


async def _mark_watch_seen(pool: asyncpg.Pool, rds: redis.Redis, device_id: str) -> None:
    now = datetime.now(tz=timezone.utc)
    await pool.execute("UPDATE devices SET last_seen = $1 WHERE id = $2", now, device_id)
    try:
        await rds.set(online_key(device_id), "1", ex=_ONLINE_TTL_SECONDS)
    except Exception as exc:  # noqa: BLE001
        logger.warning("watch online set failed: %s", exc)
