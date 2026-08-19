"""Sharing endpoints — /share/invite, /share/{id}/accept, /share/my-devices, DELETE /share/{id}."""

from uuid import UUID

import asyncpg
from fastapi import APIRouter, Depends, HTTPException, status

from alerts.service import ensure_threshold
from database import get_db_pool_from_request
from dependencies import get_current_user_id
from sharing.models import PendingInviteOut, ShareInvite, ShareOut, SharedDeviceOut
from sharing.service import (
    accept_invite,
    create_invite,
    delete_share,
    list_pending_for_me,
    list_shared_with_me,
    list_shares_for_device,
)

router = APIRouter(prefix="/share", tags=["share"])


@router.post("/invite", response_model=ShareOut, status_code=status.HTTP_201_CREATED)
async def invite(
    payload: ShareInvite,
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> ShareOut:
    row = await create_invite(pool, user_id, payload.device_id, payload.email)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "device not found or not owned")
    return ShareOut(**row)


@router.post("/{share_id}/accept", status_code=status.HTTP_204_NO_CONTENT)
async def accept(
    share_id: UUID,
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> None:
    ok = await accept_invite(pool, user_id, share_id)
    if not ok:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "invite not found or not for you")
    # After acceptance, seed default thresholds for the new viewer so they get alerts too.
    row = await pool.fetchrow(
        "SELECT device_id FROM device_shares WHERE id = $1", share_id,
    )
    if row:
        await ensure_threshold(pool, row["device_id"], user_id)


@router.get("/pending", response_model=list[PendingInviteOut])
async def pending_invites(
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> list[PendingInviteOut]:
    rows = await list_pending_for_me(pool, user_id)
    return [PendingInviteOut(**r) for r in rows]


@router.get("/my-devices", response_model=list[SharedDeviceOut])
async def my_shared_devices(
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> list[SharedDeviceOut]:
    rows = await list_shared_with_me(pool, user_id)
    return [SharedDeviceOut(**r) for r in rows]


@router.get("/device/{device_id}", response_model=list[ShareOut])
async def list_device_shares(
    device_id: str,
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> list[ShareOut]:
    """Owner-only view: who this device has been invited to."""
    rows = await list_shares_for_device(pool, user_id, device_id)
    return [ShareOut(**r) for r in rows]


@router.delete("/{share_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke(
    share_id: UUID,
    user_id: UUID = Depends(get_current_user_id),
    pool: asyncpg.Pool = Depends(get_db_pool_from_request),
) -> None:
    if not await delete_share(pool, user_id, share_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "share not found")
