"""Data endpoints — realtime + history REST + WebSocket stream."""

import asyncio
import logging

import asyncpg
import redis.asyncio as redis
from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    WebSocket,
    WebSocketDisconnect,
    status,
)

from auth.service import decode_access_token
from data.models import HistoryPoint, HistoryRange, HistoryResponse, RealtimeData
from data.service import get_history, get_latest_sec, user_can_access_device
from database import get_db_pool_from_request
from dependencies import get_current_user_id

logger = logging.getLogger(__name__)

router = APIRouter(tags=["data"])


@router.get("/data/{device_id}/realtime", response_model=RealtimeData)
async def realtime(
    device_id: str,
    user_id=Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> RealtimeData:
    if not await user_can_access_device(pool, user_id, device_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "device not found")
    row = await get_latest_sec(pool, device_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "no data yet")
    return RealtimeData(**row)


@router.get("/data/{device_id}/history", response_model=HistoryResponse)
async def history(
    device_id: str,
    range: HistoryRange = HistoryRange.day,
    user_id=Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> HistoryResponse:
    if not await user_can_access_device(pool, user_id, device_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "device not found")
    rows = await get_history(pool, device_id, range.value)
    return HistoryResponse(
        range=range,
        points=[HistoryPoint(**r) for r in rows],
    )


@router.websocket("/ws/{device_id}")
async def websocket_realtime(
    websocket: WebSocket,
    device_id: str,
    token: str | None = None,
) -> None:
    """WebSocket stream of realtime SecData for a device.

    Auth: JWT passed as ?token=... query param.
    Authz: user must own the device.
    """
    if not token:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="missing token")
        return
    try:
        user_id = decode_access_token(token)
    except ValueError:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="invalid token")
        return

    pool: asyncpg.Pool = websocket.app.state.db_pool
    rds: redis.Redis = websocket.app.state.redis

    if not await user_can_access_device(pool, user_id, device_id):
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="forbidden")
        return

    await websocket.accept()
    pubsub = rds.pubsub()
    channel = f"realtime:{device_id}"
    try:
        await pubsub.subscribe(channel)
        while True:
            msg = await pubsub.get_message(ignore_subscribe_messages=True, timeout=30)
            if msg is None:
                # heartbeat / keep WS alive through proxies
                try:
                    await websocket.send_text('{"type":"ping"}')
                except WebSocketDisconnect:
                    break
                continue
            data = msg.get("data")
            if data is None:
                continue
            if isinstance(data, bytes):
                data = data.decode()
            try:
                await websocket.send_text(data)
            except WebSocketDisconnect:
                break
    except asyncio.CancelledError:
        raise
    except Exception as exc:  # noqa: BLE001
        logger.warning("ws error device=%s: %s", device_id, exc)
    finally:
        try:
            await pubsub.unsubscribe(channel)
            await pubsub.aclose()
        except Exception:  # noqa: BLE001
            pass
