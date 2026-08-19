"""Pydantic response schemas for the sleep-session endpoints."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class SessionOut(BaseModel):
    """One night. Every metric is nullable on purpose.

    A null means "not enough valid data to compute", which is a different fact
    from a zero and must stay distinguishable all the way to the screen — the
    app renders null as an em dash rather than inventing a 0.
    """

    id: UUID
    device_id: str
    started_at: datetime
    ended_at: datetime | None       # null = session still in progress
    duration_s: int | None
    hr_avg: float | None
    hr_min: int | None
    hr_max: int | None
    rr_avg: float | None
    movement_total: int | None
    snore_total: int | None
    resp_disorder_total: int | None
    sit_up_count: int | None
    wake_count: int | None


class TimelinePoint(BaseModel):
    """One bucket of a night.

    New keys (presence, ambient temperature, AC state) can be added here later
    without breaking existing clients, which ignore unknown keys.
    """

    t: datetime
    hr: float | None
    rr: float | None
    movement: int | None
    snore: int | None
    resp_disorder: int | None
    bed_state: str                  # "on_bed" | "off_bed"
    events: list[int] = []          # raw status codes seen in this bucket


class TimelineResponse(BaseModel):
    session_id: UUID
    bucket: str
    points: list[TimelinePoint]
