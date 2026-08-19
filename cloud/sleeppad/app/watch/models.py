"""Pydantic schemas for smart watch ingestion."""

from typing import Any

from pydantic import BaseModel, Field, model_validator


class WatchDataIngest(BaseModel):
    data: list[dict[str, Any]] = Field(default_factory=list)
    hash: str | None = Field(default=None, max_length=128)
    meta: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def require_device_id(self) -> "WatchDataIngest":
        device_id = self.meta.get("deviceId")
        if not isinstance(device_id, str) or not device_id.strip():
            raise ValueError("meta.deviceId is required")
        return self


class WatchDataQueued(BaseModel):
    status: str
    device_id: str
