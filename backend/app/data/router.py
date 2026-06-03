"""Data endpoints — realtime + history REST + WebSocket stream."""

import asyncio
import json
import logging
import time
from datetime import datetime, timezone

import asyncpg
import redis.asyncio as redis
from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    WebSocket,
    WebSocketDisconnect,
    status,
)

from auth.service import decode_access_token
from data.models import (
    HistoryPoint,
    HistoryRange,
    HistoryResponse,
    RealtimeData,
    SyncDataResponse,
    SyncSleepPadPoint,
    SyncWatchPoint,
)
from data.service import (
    get_history,
    get_latest_sec,
    get_sync_data,
    get_user_device_ids,
    get_watch_snapshot,
    user_can_access_device,
)
from database import get_db_pool_from_request
from dependencies import get_current_user_id
from redis_client import online_key

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


@router.get("/data/sync", response_model=SyncDataResponse)
async def sync_data(
    from_time: datetime = Query(alias="from"),
    to_time: datetime = Query(alias="to"),
    user_id=Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> SyncDataResponse:
    if from_time.tzinfo is None:
        from_time = from_time.replace(tzinfo=timezone.utc)
    if to_time.tzinfo is None:
        to_time = to_time.replace(tzinfo=timezone.utc)
    if from_time > to_time:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "from must be before to")
    sleep_pad, smart_watch = await get_sync_data(pool, user_id, from_time, to_time)
    return SyncDataResponse(
        from_time=from_time,
        to_time=to_time,
        sleep_pad=[SyncSleepPadPoint(**row) for row in sleep_pad],
        smart_watch=[SyncWatchPoint(**row) for row in smart_watch],
    )


# ── /ws/user — user-keyed combined stream (sleep pad + watch) ──────────────────
# NOTE: must be registered BEFORE /ws/{device_id}; Starlette matches routes in
# definition order, so the literal /ws/user would otherwise be captured by the
# /ws/{device_id} path param (device_id="user").


def _merge_pad_frame(pad: dict, frame: dict) -> None:
    """Merge a sec/min frame into the running pad snapshot (last-known wins).

    sec frames carry hr/rr/status; min frames add movement/snore/temp. Missing
    fields preserve the previous value so the UI never blanks between frame types.
    Records a per-field receive timestamp (UTC ISO) so the client can show when
    each metric was last updated; only refreshed when the field actually arrives.
    """
    now_iso = datetime.now(tz=timezone.utc).isoformat()
    pad["device_id"] = frame.get("device_id", pad.get("device_id"))
    if frame.get("heart_rate") is not None:
        pad["hr"] = frame["heart_rate"]
        pad["hr_at"] = now_iso
    if frame.get("resp_rate") is not None:
        pad["rr"] = frame["resp_rate"]
        pad["rr_at"] = now_iso
    if frame.get("temp") is not None:
        pad["temp"] = frame["temp"]
        pad["temp_at"] = now_iso
    if frame.get("movement") is not None:
        pad["movement"] = frame["movement"]
        pad["movement_at"] = now_iso
    if frame.get("snore_count") is not None:
        pad["snore"] = frame["snore_count"]
        pad["snore_at"] = now_iso
    if frame.get("status") is not None:
        pad["status"] = frame["status"]


async def _pad_online(rds: redis.Redis, device_ids: list[str]) -> bool:
    """True if any of the user's sleep pads has a live online flag in Redis."""
    for d in device_ids:
        try:
            if await rds.get(online_key(d)):
                return True
        except Exception:  # noqa: BLE001
            continue
    return False


def _watch_payload(snapshot: dict | None, watch_ids: list[str]) -> dict | None:
    """Watch slice of the combined payload.

    Falls back to a metrics-empty object when the user owns a watch but has no
    synced data yet — so the Home status row still shows "Watch · Not synced"
    instead of hiding the device entirely.
    """
    if snapshot:
        return snapshot
    if watch_ids:
        return {
            "device_id": watch_ids[0],
            "synced_at": None,
            "spo2": None,
            "spo2_at": None,
            "steps": None,
            "steps_at": None,
            "systolic": None,
            "diastolic": None,
            "bp_at": None,
            "hrv": None,
            "hrv_at": None,
            "blood_glucose": None,
            "glucose_at": None,
        }
    return None


def _build_combined(pad: dict | None, watch: dict | None, pad_online: bool) -> str:
    pad_out = None
    if pad and pad.get("device_id"):
        pad_out = {
            "device_id": pad.get("device_id"),
            "online": pad_online,
            "hr": pad.get("hr"),
            "hr_at": pad.get("hr_at"),
            "rr": pad.get("rr"),
            "rr_at": pad.get("rr_at"),
            "temp": pad.get("temp"),
            "temp_at": pad.get("temp_at"),
            "movement": pad.get("movement"),
            "movement_at": pad.get("movement_at"),
            "snore": pad.get("snore"),
            "snore_at": pad.get("snore_at"),
            "status": pad.get("status"),
        }
    return json.dumps(
        {
            "type": "combined",
            "ts": int(datetime.now(tz=timezone.utc).timestamp()),
            "pad": pad_out,
            "watch": watch,
        },
        separators=(",", ":"),
    )


@router.websocket("/ws/user")
async def websocket_user(
    websocket: WebSocket,
    token: str | None = None,
) -> None:
    """Combined realtime stream for the authenticated user.

    Fans in all owned/shared sleep_pad realtime channels and attaches the latest
    smartwatch snapshot (SpO2, steps, blood pressure). Auth via ?token=... JWT.
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

    ids = await get_user_device_ids(pool, user_id)
    pad_ids = ids["sleep_pad"]
    watch_ids = ids["watch"]

    await websocket.accept()

    # Seed the pad device id so an offline pad (no frames yet) still surfaces in
    # the status row as "Sleep Pad · Offline" rather than disappearing.
    pad: dict = {"device_id": pad_ids[0]} if pad_ids else {}
    watch = _watch_payload(await get_watch_snapshot(pool, user_id), watch_ids)
    pad_online = await _pad_online(rds, pad_ids)

    pubsub = rds.pubsub()
    pad_channels = [f"realtime:{d}" for d in pad_ids]
    # Per-user channel the watch worker publishes to after ingesting new data —
    # lets us push the fresh watch snapshot immediately instead of waiting.
    watch_channel = f"watch_update:{user_id}"
    all_channels = [*pad_channels, watch_channel]

    # Cap watch-snapshot staleness even when the pad streams continuously (a
    # pad emits ~1 frame/s, so the 30s heartbeat branch would otherwise never
    # run and the watch snapshot would only load once at connect).
    last_watch_refresh = time.monotonic()
    refresh_interval = 10  # seconds

    try:
        await pubsub.subscribe(*all_channels)

        # Initial frame so the client renders immediately on connect.
        await websocket.send_text(_build_combined(pad or None, watch, pad_online))

        while True:
            msg = await pubsub.get_message(
                ignore_subscribe_messages=True, timeout=30
            )
            now = time.monotonic()

            if msg is None:
                # Heartbeat: refresh slow-moving state + keep WS alive.
                watch = _watch_payload(
                    await get_watch_snapshot(pool, user_id), watch_ids
                )
                last_watch_refresh = now
                pad_online = await _pad_online(rds, pad_ids)
                try:
                    await websocket.send_text('{"type":"ping"}')
                    await websocket.send_text(
                        _build_combined(pad or None, watch, pad_online)
                    )
                except WebSocketDisconnect:
                    break
                continue

            channel = msg.get("channel")
            if isinstance(channel, bytes):
                channel = channel.decode()

            if channel == watch_channel:
                # Watch just synced new data — refresh + push immediately.
                watch = _watch_payload(
                    await get_watch_snapshot(pool, user_id), watch_ids
                )
                last_watch_refresh = now
                try:
                    await websocket.send_text(
                        _build_combined(pad or None, watch, pad_online)
                    )
                except WebSocketDisconnect:
                    break
                continue

            # Pad realtime frame.
            data = msg.get("data")
            if data is None:
                continue
            if isinstance(data, bytes):
                data = data.decode()
            try:
                frame = json.loads(data)
            except (TypeError, ValueError):
                continue
            _merge_pad_frame(pad, frame)
            pad_online = True  # a frame just arrived from a pad
            # Refresh the watch snapshot periodically while pad frames flow.
            if now - last_watch_refresh >= refresh_interval:
                watch = _watch_payload(
                    await get_watch_snapshot(pool, user_id), watch_ids
                )
                last_watch_refresh = now
            try:
                await websocket.send_text(_build_combined(pad, watch, pad_online))
            except WebSocketDisconnect:
                break
    except asyncio.CancelledError:
        raise
    except Exception as exc:  # noqa: BLE001
        logger.warning("ws/user error user=%s: %s", user_id, exc)
    finally:
        try:
            await pubsub.unsubscribe(*all_channels)
            await pubsub.aclose()
        except Exception:  # noqa: BLE001
            pass


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
