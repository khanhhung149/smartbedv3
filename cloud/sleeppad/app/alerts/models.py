"""Pydantic schemas for alert endpoints."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class ThresholdOut(BaseModel):
    device_id: str
    hr_high: int
    hr_low: int
    rr_high: float
    rr_low: float
    resp_disorder_count: int


class ThresholdUpdate(BaseModel):
    hr_high: int | None = Field(default=None, ge=30, le=250)
    hr_low: int | None = Field(default=None, ge=20, le=150)
    rr_high: float | None = Field(default=None, ge=1, le=60)
    rr_low: float | None = Field(default=None, ge=1, le=40)
    resp_disorder_count: int | None = Field(default=None, ge=0, le=60)


class AlertOut(BaseModel):
    id: UUID
    device_id: str
    metric: str
    value: float
    threshold: float
    triggered_at: datetime
