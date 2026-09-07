"""Deterministic sleep scoring on top of the measured feature layer.

The score is arithmetic over SleepFeatures, never model output. The language
model receives the finished breakdown and explains it; it cannot move a single
point. That keeps the number reproducible: the same night always scores the
same, which is what lets the app chart scores across days.

Each component maps a measured value onto 0..1 through a piecewise-linear ramp
between a "full credit" and a "zero credit" anchor, then scales by its weight.
Anchors follow consumer sleep-staging conventions (7-9h adult sleep target,
85% efficiency floor, AASM RDI bands) rather than invented thresholds.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass

from ai.sleep_features import SleepFeatures

# Total sleep bounds: full credit inside 420-540 min (7-9h), zero at <=180 or >=660.
DUR_FULL_LO, DUR_FULL_HI, DUR_ZERO_LO, DUR_ZERO_HI = 420, 540, 180, 660

SCORE_BANDS = ((85, "excellent"), (70, "good"), (55, "fair"), (0, "poor"))


@dataclass(frozen=True)
class ScoreComponent:
    key: str
    label: str
    weight: int          # points available
    value: float | None  # the measured input, unit depends on the component
    unit: str
    points: float        # earned, 0..weight

    @property
    def pct(self) -> float:
        return round(self.points / self.weight * 100, 1)


@dataclass(frozen=True)
class SleepScore:
    device_id: str
    session_start: str
    session_end: str
    total: int           # 0..100
    band: str            # excellent | good | fair | poor
    components: list[ScoreComponent]

    def as_dict(self) -> dict:
        data = asdict(self)
        for c in data["components"]:
            c["pct"] = round(c["points"] / c["weight"] * 100, 1)
        return data

    def as_prompt_facts(self) -> dict:
        """Flat score facts merged into the narration prompt."""
        facts = {
            "sleep_score": self.total,
            "sleep_score_band": self.band,
        }
        for c in self.components:
            facts[f"score_{c.key}_points"] = round(c.points, 1)
            facts[f"score_{c.key}_max"] = c.weight
        return facts


def _ramp(value: float, full: float, zero: float) -> float:
    """1.0 at `full`, 0.0 at `zero`, linear between. Works in both directions."""
    if full == zero:
        return 1.0
    t = (value - zero) / (full - zero)
    return max(0.0, min(1.0, t))


def _duration_credit(minutes: int) -> float:
    """Full inside the 7-9h band, sloping to zero when far too short or long."""
    if DUR_FULL_LO <= minutes <= DUR_FULL_HI:
        return 1.0
    if minutes < DUR_FULL_LO:
        return _ramp(minutes, DUR_FULL_LO, DUR_ZERO_LO)
    return _ramp(minutes, DUR_FULL_HI, DUR_ZERO_HI)


# LƯU Ý TỪ SMARTBED: rdi_proxy được tính từ số lần "respiratory disorder" 
# do đệm gửi qua trường count của khung 0x86 (sau pha 01). Nếu theo thời gian quan sát 
# thấy giá trị này luôn bằng 0 (nghĩa là đệm không báo lỗi hoặc tính năng này không 
# hoạt động trên board -T), cần xem xét lại độ tin cậy của điểm thành phần này.
# (Tham chiếu rủi ro R2 trong plan.md).
def _breathing_credit(rdi: float) -> float:
    """AASM band edges: <5 clean, 15 mild ceiling, 30+ severe."""
    if rdi < 5.0:
        return 1.0
    return _ramp(rdi, 5.0, 30.0)


def score(features: SleepFeatures) -> SleepScore:
    f = features
    hours = max(f.total_sleep_min / 60.0, 1 / 60.0)

    # Out-of-bed exits: excluded minutes are the pad's off-bed/unusable time
    # inside the session span, so per-hour normalization keeps short and long
    # nights comparable.
    oob_per_hour = f.excluded_min / hours

    parts = [
        ("duration", "Sleep duration", 25, f.total_sleep_min, "min",
         _duration_credit(f.total_sleep_min)),
        ("efficiency", "Sleep efficiency", 15, f.sleep_efficiency_pct, "%",
         _ramp(f.sleep_efficiency_pct, 95.0, 70.0)),
        ("latency", "Sleep onset", 10, f.sleep_onset_latency_min, "min",
         _ramp(f.sleep_onset_latency_min, 15.0, 60.0)),
        ("awakenings", "Awakenings", 10, f.awakenings, "times",
         _ramp(f.awakenings, 1.0, 6.0)),
        ("out_of_bed", "Out of bed", 5, round(oob_per_hour, 1), "min/h",
         _ramp(oob_per_hour, 1.0, 8.0)),
        ("movement", "Restlessness", 10, f.movement_index, "moves/h",
         _ramp(f.movement_index, 15.0, 60.0)),
        ("snore", "Snoring", 10, f.snore_index, "snores/h",
         _ramp(f.snore_index, 10.0, 80.0)),
        ("breathing", "Breathing", 10, f.rdi_proxy, "events/h",
         _breathing_credit(f.rdi_proxy)),
        ("hr_dip", "HR nocturnal dip", 5, f.hr_dip_pct, "%",
         _ramp(f.hr_dip_pct, 10.0, 0.0) if f.hr_dip_pct is not None else None),
    ]

    components: list[ScoreComponent] = []
    earned = 0.0
    available = 0
    for key, label, weight, value, unit, credit in parts:
        if credit is None:
            # Unmeasurable component (e.g. no HR lock): excluded from both the
            # earned and the available side so the night is not punished for a
            # sensor gap.
            continue
        pts = round(weight * credit, 1)
        components.append(ScoreComponent(key, label, weight, value, unit, pts))
        earned += pts
        available += weight

    total = round(earned / available * 100) if available else 0
    band = next(name for floor, name in SCORE_BANDS if total >= floor)

    return SleepScore(
        device_id=f.device_id,
        session_start=f.session_start.isoformat(),
        session_end=f.session_end.isoformat(),
        total=total,
        band=band,
        components=components,
    )
