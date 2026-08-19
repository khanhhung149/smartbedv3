"""Pydantic schemas for device sharing."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr


class ShareInvite(BaseModel):
    device_id: str
    email: EmailStr


class ShareOut(BaseModel):
    id: UUID
    device_id: str
    invited_email: EmailStr
    accepted: bool
    created_at: datetime
    accepted_at: datetime | None


class SharedDeviceOut(BaseModel):
    """A device shared WITH me — includes minimal device info for list screens."""
    share_id: UUID
    device_id: str
    name: str | None
    owner_email: EmailStr
    accepted_at: datetime


class PendingInviteOut(BaseModel):
    """An unaccepted invite addressed to the caller's email.

    Included in Devices screen above "SHARED WITH ME" so the invitee sees
    they have something to act on.
    """
    share_id: UUID
    device_id: str
    device_name: str | None
    owner_email: EmailStr
    created_at: datetime
