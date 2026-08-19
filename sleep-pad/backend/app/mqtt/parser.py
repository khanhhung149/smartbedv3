"""Validate + parse MQTT JSON payloads from ESP32.

Topics:
  sleeppad/{device_id}/sec    → SecData (0x85 per-second frame)
  sleeppad/{device_id}/min    → MinData (0x86 per-minute frame)
  sleeppad/{device_id}/temp   → EnvData (ambient temperature + humidity)
  sleeppad/{device_id}/status → online/offline LWT (raw string)
"""

from datetime import datetime, timezone

from pydantic import BaseModel, Field, ValidationError


class SecDataPayload(BaseModel):
    device_id: str = Field(min_length=1, max_length=32)
    ts: int = Field(ge=0)                       # unix seconds — gắn tại MCU (NTP sync)
    ts_pad: int | None = Field(default=None, ge=0)  # mốc pad báo trong frame (có thể lệch)
    status: int = Field(ge=0, le=255)
    heart_rate: int = Field(ge=0, le=255)
    resp_rate: float = Field(ge=0, le=100)
    sdata: int = Field(ge=0, le=65535)
    pdata: int = Field(ge=0, le=65535)
    uart_ok: bool = Field(default=True)         # cờ lỗi: False = mẫu không hợp lệ

    # Doanh nghiệp suy ra từ trường raw: heart_rate = 0 là dropout pad báo (đánh dấu lỗi).
    @property
    def on_bed(self) -> bool:
        return self.status != 0 or self.heart_rate > 0 or self.resp_rate > 0


class MinDataPayload(BaseModel):
    device_id: str = Field(min_length=1, max_length=32)
    ts: int = Field(ge=0)
    ts_pad: int | None = Field(default=None, ge=0)
    status: int = Field(ge=0, le=255)
    heart_rate: int = Field(ge=0, le=255)
    resp_rate: float = Field(ge=0, le=100)
    movement: int = Field(ge=0, le=255)
    snore_count: int = Field(ge=0, le=65535)
    resp_disorder: int = Field(ge=0, le=65535)
    pthd: int = Field(ge=0, le=255)
    temp: float = Field(ge=0, le=60)
    uart_ok: bool = Field(default=True)


class EnvDataPayload(BaseModel):
    """Ambient environment frame on sleeppad/{id}/temp — room temp + humidity.

    Distinct from MinData.temp (body temperature, currently always 0); this is
    the sensor's surrounding temperature shown as the Home "Temperature".
    """
    device_id: str = Field(min_length=1, max_length=32)
    ts: int = Field(ge=0)
    temp: float = Field(ge=-50, le=100)   # ambient °C
    humi: float = Field(ge=0, le=100)     # relative humidity %


def device_id_from_topic(topic: str) -> str | None:
    """Extract device_id from 'sleeppad/{id}/sec' or 'sleeppad/{id}/min'."""
    parts = topic.split("/")
    if len(parts) != 3 or parts[0] != "sleeppad":
        return None
    return parts[1] or None


def to_timestamptz(ts: int) -> datetime:
    return datetime.fromtimestamp(ts, tz=timezone.utc)


def parse_sec(raw: bytes | str) -> SecDataPayload | None:
    try:
        return SecDataPayload.model_validate_json(raw)
    except ValidationError:
        return None


def parse_min(raw: bytes | str) -> MinDataPayload | None:
    try:
        return MinDataPayload.model_validate_json(raw)
    except ValidationError:
        return None


def parse_env(raw: bytes | str) -> EnvDataPayload | None:
    try:
        return EnvDataPayload.model_validate_json(raw)
    except ValidationError:
        return None
