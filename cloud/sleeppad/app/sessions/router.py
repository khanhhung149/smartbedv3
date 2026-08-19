"""Sleep-session endpoints.

Authorization copies data/router.py: a device the caller cannot reach returns
404, never 403 and never an empty 200. A 403 would confirm the device id exists
to someone who should not know that, and an empty 200 would read as "you have no
data" instead of "this is not yours".
"""

from datetime import datetime
from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, Query, status

from data.service import user_can_access_device
from database import get_db_pool_from_request
from dependencies import get_current_user_id
from sessions.models import SessionOut, TimelinePoint, TimelineResponse
from sessions.service import (
    get_session,
    get_timeline,
    list_sessions,
)

router = APIRouter(tags=["sessions"])

# Whitelisted because the value is interpolated into time_bucket(). Same shape as
# data/service.py _RANGE_PARAMS: the query string never reaches SQL, only a key
# used to look up a server-owned constant.
BUCKETS = {"1m": "1 minute", "5m": "5 minutes"}


@router.get("/sessions", response_model=list[SessionOut])
async def list_device_sessions(
    device_id: str,
    from_time: datetime | None = Query(default=None, alias="from"),
    to_time: datetime | None = Query(default=None, alias="to"),
    limit: int = Query(default=30, ge=1, le=200),
    user_id=Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> list[SessionOut]:
    if not await user_can_access_device(pool, user_id, device_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "device not found")
    rows = await list_sessions(pool, device_id, from_time, to_time, limit)
    return [SessionOut(**dict(r)) for r in rows]


@router.get("/sessions/{session_id}", response_model=SessionOut)
async def read_session(
    session_id: UUID,
    user_id=Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> SessionOut:
    row = await get_session(pool, session_id)
    # Same 404 for "no such session" and "not yours" — the caller learns nothing
    # about sessions belonging to other people.
    if row is None or not await user_can_access_device(pool, user_id, row["device_id"]):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "session not found")
    return SessionOut(**dict(row))


@router.get("/sessions/{session_id}/timeline", response_model=TimelineResponse)
async def read_timeline(
    session_id: UUID,
    bucket: str = Query(default="1m"),
    user_id=Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> TimelineResponse:
    if bucket not in BUCKETS:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            f"bucket must be one of {sorted(BUCKETS)}",
        )
    row = await get_session(pool, session_id)
    if row is None or not await user_can_access_device(pool, user_id, row["device_id"]):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "session not found")

    points = await get_timeline(
        pool,
        device_id=row["device_id"],
        start=row["started_at"],
        end=row["ended_at"],
        interval=BUCKETS[bucket],
    )
    return TimelineResponse(
        session_id=session_id,
        bucket=bucket,
        points=[TimelinePoint(**p) for p in points],
    )
