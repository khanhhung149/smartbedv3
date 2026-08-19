"""Pydantic response schemas for data endpoints."""

from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel


class HistoryRange(str, Enum):
    hour = "hour"      # 1-minute buckets over last hour — used by Home sparklines
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
    # Only populated for `hour` range — temp is per-minute in min_data.
    temp: float | None = None


class HistoryResponse(BaseModel):
    range: HistoryRange
    points: list[HistoryPoint]


class SyncSleepPadPoint(BaseModel):
    time: datetime
    device_id: str
    status: int | None
    heart_rate: int | None
    resp_rate: float | None
    movement: int | None
    snore_count: int | None
    resp_disorder: int | None
    pthd: int | None
    temp: float | None


class SyncWatchPoint(BaseModel):
    time: datetime
    received_at: datetime
    device_id: str
    type: str
    hash: str
    raw_data: dict[str, Any]
    batch_hash: str | None
    meta: dict[str, Any] | None


class SyncDataResponse(BaseModel):
    from_time: datetime
    to_time: datetime
    sleep_pad: list[SyncSleepPadPoint]
    smart_watch: list[SyncWatchPoint]
