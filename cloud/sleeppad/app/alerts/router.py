"""Alert endpoints — /alerts/{device_id}/thresholds, /alerts/{device_id}/history."""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from alerts.models import AlertOut, ThresholdOut, ThresholdUpdate
from alerts.service import get_threshold, list_alerts, update_threshold
from data.service import user_can_access_device
from database import get_db_pool_from_request
from dependencies import get_current_user_id

router = APIRouter(prefix="/alerts", tags=["alerts"])


@router.get("/{device_id}/thresholds", response_model=ThresholdOut)
async def get_thresholds(
    device_id: str,
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> ThresholdOut:
    if not await user_can_access_device(pool, user_id, device_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "device not found")
    row = await get_threshold(pool, device_id, user_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "no threshold set yet")
    return ThresholdOut(**row)


@router.put("/{device_id}/thresholds", response_model=ThresholdOut)
async def put_thresholds(
    device_id: str,
    payload: ThresholdUpdate,
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> ThresholdOut:
    if not await user_can_access_device(pool, user_id, device_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "device not found")
    changes = {k: v for k, v in payload.model_dump().items() if v is not None}
    row = await update_threshold(pool, device_id, user_id, changes)
    return ThresholdOut(**row)


@router.get("/{device_id}/history", response_model=list[AlertOut])
async def alert_history(
    device_id: str,
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> list[AlertOut]:
    if not await user_can_access_device(pool, user_id, device_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "device not found")
    rows = await list_alerts(pool, device_id, user_id)
    return [AlertOut(**r) for r in rows]
