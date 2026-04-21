"""Device endpoints — /devices/pair, /devices/mine, /devices/{id}/status."""

from uuid import UUID

import asyncpg
import redis.asyncio as redis
from fastapi import APIRouter, Depends, HTTPException, status

from alerts.service import ensure_threshold
from config import get_settings
from database import get_db_pool_from_request
from dependencies import get_current_user_id
from devices.models import DeviceOut, DevicePair, DevicePairOut, DeviceStatus
from devices.service import get_device_status, list_user_devices, pair_device
from redis_client import get_redis_from_request

router = APIRouter(prefix="/devices", tags=["devices"])


def _mqtt_scheme_from_domain(domain: str) -> str:
    """Infer scheme Flutter should tell ESP32 to use. wss:// → wss, ws:// → tcp-ws, else tcp."""
    if domain.startswith("wss://"):
        return "wss"
    if domain.startswith("ws://"):
        return "ws"
    return "tcp"


def _mqtt_host_from_domain(domain: str) -> str:
    """Strip scheme for raw hostname (ESP32 parses separately)."""
    for prefix in ("wss://", "ws://", "mqtt://", "tcp://"):
        if domain.startswith(prefix):
            return domain[len(prefix):]
    return domain


@router.post("/pair", response_model=DevicePairOut, status_code=status.HTTP_200_OK)
async def pair(
    payload: DevicePair,
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
    rds: redis.Redis = Depends(get_redis_from_request),
) -> DevicePairOut:
    row = await pair_device(pool, rds, user_id, payload.device_id, payload.name)
    if row.get("conflict"):
        raise HTTPException(
            status.HTTP_409_CONFLICT, "device already paired to another account"
        )
    # Seed default alert thresholds so the owner starts receiving alerts immediately.
    await ensure_threshold(pool, row["id"], user_id)
    from devices.service import _is_online  # re-use private helper
    online = await _is_online(rds, row["id"])
    settings = get_settings()
    return DevicePairOut(
        device_id=row["id"],
        name=row["name"],
        paired_at=row["paired_at"],
        last_seen=row["last_seen"],
        online=online,
        mqtt_username=settings.mqtt_device_username,
        mqtt_password=settings.mqtt_device_password,
        mqtt_host=_mqtt_host_from_domain(settings.mqtt_domain),
        mqtt_scheme=_mqtt_scheme_from_domain(settings.mqtt_domain),
    )


@router.get("/mine", response_model=list[DeviceOut])
async def list_mine(
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
    rds: redis.Redis = Depends(get_redis_from_request),
) -> list[DeviceOut]:
    rows = await list_user_devices(pool, rds, user_id)
    return [DeviceOut(**row) for row in rows]


@router.get("/{device_id}/status", response_model=DeviceStatus)
async def device_status(
    device_id: str,
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
    rds: redis.Redis = Depends(get_redis_from_request),
) -> DeviceStatus:
    row = await get_device_status(pool, rds, user_id, device_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "device not found")
    return DeviceStatus(**row)
