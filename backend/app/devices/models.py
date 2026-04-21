"""Pydantic schemas for device endpoints."""

from datetime import datetime

from pydantic import BaseModel, Field


class DevicePair(BaseModel):
    device_id: str = Field(min_length=1, max_length=32)
    name: str | None = Field(default=None, max_length=100)


class DeviceOut(BaseModel):
    device_id: str
    name: str | None
    paired_at: datetime
    last_seen: datetime | None
    online: bool


class DevicePairOut(DeviceOut):
    """Extends DeviceOut with the MQTT credentials Flutter must write over BLE.

    Credentials come from the server env (shared across devices) because the
    ACL enforces topic isolation via the %c (client_id) pattern, so shared
    auth is sufficient. Empty in dev (anonymous broker).
    """
    mqtt_username: str
    mqtt_password: str
    mqtt_host: str
    mqtt_scheme: str          # "tcp" (dev) | "wss" (prod via cloudflared)


class DeviceStatus(BaseModel):
    device_id: str
    online: bool
    last_seen: datetime | None
