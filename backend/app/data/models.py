"""Pydantic response schemas for data endpoints."""

from datetime import datetime
from enum import Enum

from pydantic import BaseModel


class HistoryRange(str, Enum):
    day = "day"
    week = "week"
    month = "month"


class RealtimeData(BaseModel):
    time: datetime
    device_id: str
    status: int | None
    heart_rate: int | None
    resp_rate: float | None
    sdata: int | None
    pdata: int | None


class HistoryPoint(BaseModel):
    bucket: datetime
    hr: float | None
    rr: float | None
    resp_disorder: int | None


class HistoryResponse(BaseModel):
    range: HistoryRange
    points: list[HistoryPoint]
