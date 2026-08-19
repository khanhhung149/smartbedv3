"""Smart watch ingestion endpoints."""

from uuid import UUID

import asyncpg
import redis.asyncio as redis
from fastapi import APIRouter, Depends, HTTPException, status

from database import get_db_pool_from_request
from dependencies import get_current_user_id
from redis_client import get_redis_from_request
from watch.models import WatchDataIngest, WatchDataQueued
from watch.service import enqueue_watch_payload, upsert_watch_device

router = APIRouter(prefix="/watch", tags=["watch"])


@router.post("/data", response_model=WatchDataQueued, status_code=status.HTTP_202_ACCEPTED)
async def ingest_watch_data(
    payload: WatchDataIngest,
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
    rds: redis.Redis = Depends(get_redis_from_request),
) -> WatchDataQueued:
    device_id = str(payload.meta["deviceId"]).strip()
    device_name = payload.meta.get("deviceName")
    if device_name is not None:
        device_name = str(device_name)[:100]

    row = await upsert_watch_device(pool, user_id, device_id, device_name)
    if row.get("conflict"):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "device already paired to another account",
        )

    await enqueue_watch_payload(
        rds,
        user_id=user_id,
        device_id=device_id,
        payload=payload.model_dump(mode="json"),
    )
    return WatchDataQueued(status="queued", device_id=device_id)
