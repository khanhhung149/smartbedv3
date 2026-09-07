"""Deterministic sleep-feature extraction - the grounding layer for the AI tier.

Every number the language model is allowed to talk about is computed here, in
plain Python, from the pad's own minute-resolution telemetry. The model never
infers a clinical fact; it only explains facts this module has already
established. That split is what keeps a generative narrative safe to show a
user: a hallucinated sentence can still be wrong in tone, but it cannot invent
an apnea event that the sensor never recorded.

Status codes are the Legact publish scale the MQTT ingest already speaks:
1 off-bed, 2 body movement, 4 in bed, 6 heavy object (no vitals), 7 snoring,
8 weak breathing.
"""

from __future__ import annotations
import logging

from dataclasses import asdict, dataclass, field
from datetime import datetime
from statistics import mean, pstdev

logger = logging.getLogger(__name__)

STATUS_OFF_BED = 1
STATUS_MOVEMENT = 2
STATUS_IN_BED = 4
STATUS_HEAVY_OBJECT = 6
STATUS_SNORING = 7
STATUS_WEAK_BREATHING = 8

# LƯU Ý TỪ SMARTBED: Theo tài liệu hãng (mục 2.4, file "数据传输协议英文版.xlsx"), 
# tập mã trạng thái ở mức phút (0x86) chỉ từ 0x01 đến 0x06. Do đó STATUS_SNORING (7) 
# và STATUS_WEAK_BREATHING (8) dưới đây là code chết ở mức phút, không có dòng 
# min_data thật nào khớp được. Giữ nguyên theo upstream để tránh conflict khi merge.

# Statuses that mean a person is on the pad. Heavy-object minutes are excluded:
# the pad reports load without vitals, so counting them as sleep would inflate
# time-in-bed with a rolled-up duvet.
OCCUPIED = {STATUS_IN_BED, STATUS_MOVEMENT, STATUS_SNORING, STATUS_WEAK_BREATHING}
# Minutes that count as asleep rather than merely lying down.
ASLEEP = {STATUS_IN_BED, STATUS_SNORING, STATUS_WEAK_BREATHING}

# AASM severity bands for the apnea-hypopnea index. Applied to a device-derived
# proxy, so the output is a screening flag, never a diagnosis.
AHI_NORMAL, AHI_MILD, AHI_MODERATE = 5.0, 15.0, 30.0

# A run of consecutive non-asleep minutes long enough to count as waking up
# rather than turning over.
AWAKENING_MIN_MINUTES = 2


@dataclass(frozen=True)
class SleepFeatures:
    """Verified facts about one sleep session. Every field is measured."""

    device_id: str
    session_start: datetime
    session_end: datetime

    time_in_bed_min: int
    total_sleep_min: int
    sleep_efficiency_pct: float
    sleep_onset_latency_min: int
    awakenings: int
    longest_sleep_block_min: int

    hr_mean: float | None
    hr_min: int | None
    hr_max: int | None
    hr_dip_pct: float | None

    rr_mean: float | None
    rr_min: float | None
    rr_max: float | None
    rr_variability: float | None

    movement_total: int
    movement_index: float

    snore_total: int
    snore_index: float
    resp_disorder_total: int
    rdi_proxy: float
    osa_risk_band: str

    coverage_pct: float
    excluded_min: int
    warnings: list[str] = field(default_factory=list)

    def as_prompt_facts(self) -> dict:
        """Flat dict handed to the model. Datetimes become local ISO strings."""
        data = asdict(self)
        data["session_start"] = self.session_start.isoformat()
        data["session_end"] = self.session_end.isoformat()
        return data


def _risk_band(rdi: float) -> str:
    if rdi < AHI_NORMAL:
        return "normal"
    if rdi < AHI_MILD:
        return "mild"
    if rdi < AHI_MODERATE:
        return "moderate"
    return "severe"


def _runs(values: list[bool]) -> list[int]:
    """Lengths of consecutive True runs."""
    runs, current = [], 0
    for v in values:
        if v:
            current += 1
        elif current:
            runs.append(current)
            current = 0
    if current:
        runs.append(current)
    return runs


def extract(device_id: str, minutes: list[dict]) -> SleepFeatures | None:
    """Compute sleep features from ordered per-minute rows.

    `minutes` is min_data ordered by time ascending. Returns None when the
    session holds too little occupied time to describe honestly.
    """
    if not minutes:
        logger.warning(f"extract({device_id}): Không có phút nào trong session")
        return None

    occupied = [m for m in minutes if m["status"] in OCCUPIED]
    if len(occupied) < 10:
        logger.warning(f"extract({device_id}): Chỉ có {len(occupied)} phút có người, dưới ngưỡng 10 phút")
        return None

    asleep_flags = [m["status"] in ASLEEP for m in minutes]
    asleep = [m for m, flag in zip(minutes, asleep_flags) if flag]

    start, end = minutes[0]["time"], minutes[-1]["time"]
    time_in_bed = len(occupied)
    total_sleep = len(asleep)
    hours_asleep = max(total_sleep / 60.0, 1 / 60.0)

    # Sleep onset: occupied minutes before the first asleep minute.
    first_asleep = next((i for i, f in enumerate(asleep_flags) if f), 0)
    latency = sum(1 for m in minutes[:first_asleep] if m["status"] in OCCUPIED)

    # Awakenings: gaps in sleep after onset that are long enough to be real.
    post_onset = asleep_flags[first_asleep:]
    awake_runs = _runs([not f for f in post_onset])
    awakenings = sum(1 for r in awake_runs if r >= AWAKENING_MIN_MINUTES)
    sleep_runs = _runs(post_onset)

    hrs = [m["heart_rate"] for m in asleep if m.get("heart_rate")]
    rrs = [float(m["resp_rate"]) for m in asleep if m.get("resp_rate")]

    # Nocturnal dip: healthy sleep lowers heart rate below the early-session
    # baseline. A flat or inverted dip is a documented cardiovascular signal.
    hr_dip = None
    if len(hrs) >= 20:
        baseline, deepest = mean(hrs[:10]), min(hrs)
        if baseline:
            hr_dip = round((baseline - deepest) / baseline * 100, 1)

    movement_total = sum(m.get("movement") or 0 for m in occupied)
    snore_total = sum(m.get("snore_count") or 0 for m in occupied)
    disorder_total = sum(m.get("resp_disorder") or 0 for m in occupied)
    rdi = round(disorder_total / hours_asleep, 1)

    span_min = max(int((end - start).total_seconds() // 60) + 1, 1)
    excluded = len(minutes) - len(occupied)

    warnings: list[str] = []
    if total_sleep < 60:
        warnings.append("session shorter than one hour; trends are indicative only")
    if len(occupied) / span_min < 0.8:
        warnings.append("telemetry gaps detected; some minutes are missing")
    if not hrs:
        warnings.append("no heart-rate readings locked during this session")

    return SleepFeatures(
        device_id=device_id,
        session_start=start,
        session_end=end,
        time_in_bed_min=time_in_bed,
        total_sleep_min=total_sleep,
        sleep_efficiency_pct=round(total_sleep / time_in_bed * 100, 1),
        sleep_onset_latency_min=latency,
        awakenings=awakenings,
        longest_sleep_block_min=max(sleep_runs) if sleep_runs else 0,
        hr_mean=round(mean(hrs), 1) if hrs else None,
        hr_min=min(hrs) if hrs else None,
        hr_max=max(hrs) if hrs else None,
        hr_dip_pct=hr_dip,
        rr_mean=round(mean(rrs), 1) if rrs else None,
        rr_min=round(min(rrs), 1) if rrs else None,
        rr_max=round(max(rrs), 1) if rrs else None,
        rr_variability=round(pstdev(rrs), 2) if len(rrs) > 1 else None,
        movement_total=movement_total,
        movement_index=round(movement_total / hours_asleep, 1),
        snore_total=snore_total,
        snore_index=round(snore_total / hours_asleep, 1),
        resp_disorder_total=disorder_total,
        rdi_proxy=rdi,
        osa_risk_band=_risk_band(rdi),
        coverage_pct=round(len(occupied) / span_min * 100, 1),
        excluded_min=excluded,
        warnings=warnings,
    )
