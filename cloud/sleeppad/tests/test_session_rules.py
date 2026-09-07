"""Session state machine — the boundary rules from the Legact protocol PDF.

Pure functions, no database. Run from backend/:  python -m pytest tests/ -v
"""

import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "app"))

from sessions.rules import Sample, build_sessions, is_on_bed  # noqa: E402

T0 = datetime(2026, 8, 18, 23, 0, 0, tzinfo=timezone.utc)


def run(spec: list[tuple[int, bool]], *, status_at: dict[int, int] | None = None,
        skip: set[int] | None = None) -> list:
    """Build a per-second sample list from (duration_seconds, on_bed) segments.

    `skip` drops seconds by offset so a data gap can be expressed; `status_at`
    stamps an event code on one second.
    """
    status_at = status_at or {}
    skip = skip or set()
    samples = []
    offset = 0
    for seconds, on_bed in spec:
        for _ in range(seconds):
            if offset not in skip:
                samples.append(
                    Sample(
                        t=T0 + timedelta(seconds=offset),
                        hr=62 if on_bed else 0,
                        rr=15.0 if on_bed else 0.0,
                        status=status_at.get(offset),
                    )
                )
            offset += 1
    return samples


@pytest.mark.parametrize(
    ("hr", "rr", "expected"),
    [(62, 15.0, True), (0, 15.0, True), (62, 0.0, True), (0, 0.0, False),
     (None, None, False), (0, None, False)],
)
def test_is_on_bed(hr, rr, expected):
    # p.4 2.4.1 — either reading being non-zero means the bed is occupied.
    assert is_on_bed(hr, rr) is expected


def test_29_seconds_does_not_open_a_session():
    assert build_sessions(run([(29, True), (60, False)])) == []


def test_30_seconds_opens_exactly_one_session():
    out = build_sessions(run([(30, True), (60 * 60, False)]))
    assert len(out) == 1
    assert out[0].started_at == T0
    assert out[0].ended_at == T0 + timedelta(seconds=30)


def test_absence_of_25_minutes_does_not_split_the_night():
    out = build_sessions(
        run([(3600, True), (25 * 60, False), (3600, True), (60 * 60, False)])
    )
    assert len(out) == 1


def test_absence_of_31_minutes_splits_and_ends_at_the_moment_of_leaving():
    left_at = T0 + timedelta(seconds=3600)
    out = build_sessions(
        run([(3600, True), (31 * 60, False), (3600, True), (60 * 60, False)])
    )
    assert len(out) == 2
    # Not the moment the 30-minute timer expired — that would add half an hour
    # of bed time that never happened.
    assert out[0].ended_at == left_at
    assert out[1].started_at == T0 + timedelta(seconds=3600 + 31 * 60)


def test_continuous_occupancy_is_cut_at_the_1440_minute_cap():
    out = build_sessions(run([(1500 * 60, True)]))
    assert out[0].started_at == T0
    assert out[0].ended_at == T0 + timedelta(minutes=1440)
    # The cap ends the recording, not the occupancy: the remaining hour is a
    # session of its own rather than silently discarded data.
    assert len(out) == 2
    assert out[1].started_at == T0 + timedelta(minutes=1440)


def test_data_gap_of_40_minutes_closes_the_session():
    # Drop 40 minutes of rows outright — a hole is not evidence of presence.
    gap = set(range(3600, 3600 + 40 * 60))
    out = build_sessions(run([(3600, True), (40 * 60, True), (3600, True),
                              (60 * 60, False)], skip=gap))
    assert len(out) == 2
    assert out[0].ended_at == T0 + timedelta(seconds=3599)


def test_event_codes_are_counted_within_the_session():
    out = build_sessions(
        run([(600, True), (60 * 60, False)],
            status_at={100: 0x03, 200: 0x03, 300: 0x05, 400: 0x07}),
    )
    assert len(out) == 1
    assert out[0].sit_up_count == 2
    assert out[0].wake_count == 1


def test_still_in_bed_at_the_end_leaves_the_session_open():
    out = build_sessions(run([(3600, True)]))
    assert len(out) == 1
    assert out[0].ended_at is None


def test_thresholds_are_parameters_not_constants():
    # R1: the on-bed rule is an inference, so the boundaries must stay tunable.
    assert build_sessions(run([(10, True), (60 * 60, False)]), open_seconds=10)
    assert build_sessions(run([(10, True), (60 * 60, False)])) == []


def test_data_that_simply_stops_closes_the_session_at_the_last_sample():
    # The pad unplugged in the morning: no "off bed" rows ever arrive. Without
    # `now` the night would stay open forever and the app would show a session
    # with no end time.
    samples = run([(3600, True)])
    last = samples[-1].t
    out = build_sessions(samples, now=last + timedelta(minutes=31))
    assert len(out) == 1
    assert out[0].ended_at == last


def test_recent_silence_leaves_the_session_open():
    # Only 5 minutes quiet — the person may simply still be in bed.
    samples = run([(3600, True)])
    out = build_sessions(samples, now=samples[-1].t + timedelta(minutes=5))
    assert out[0].ended_at is None


def test_jitter_duoi_nguong_khong_lam_hong_viec_mo_phien():
    """Mẫu 1 Hz lệch vài chục mili-giây vẫn phải mở được phiên.

    Cột `time` do backend đóng dấu lúc nhận, nên một luồng khoẻ vẫn cho ra
    1,02s / 1,05s / 1,1s. Bản trước coi mọi khoảng > 1,0s là mất dữ liệu và xoá
    chuỗi đang chờ, nên trên pad thật chuỗi liên tục dài nhất chỉ 4 giây và phiên
    không bao giờ mở. Dựng lại đúng hình dạng đó ở đây.
    """
    samples = [
        Sample(t=T0 + timedelta(milliseconds=int(i * 1050)), hr=60, rr=15.0, status=None)
        for i in range(120)
    ]
    windows = build_sessions(samples, now=samples[-1].t)

    assert len(windows) == 1, "jitter 1,05s/mẫu phải mở được đúng một phiên"
    assert windows[0].started_at == samples[0].t
    assert windows[0].ended_at is None, "vẫn đang nằm thì phiên phải còn mở"


def test_mat_han_mot_mau_van_tinh_la_dut():
    """Trên ngưỡng thì phải giữ nguyên hành vi cũ — nới jitter không được nới thật.

    Một khoảng 5 giây là mất mẫu thật, phải cắt chuỗi đang chờ nên 20 giây trước
    đó không cộng dồn vào 20 giây sau để thành 40 giây đủ mở phiên.
    """
    truoc = [Sample(t=T0 + timedelta(seconds=i), hr=60, rr=15.0, status=None) for i in range(20)]
    sau = [Sample(t=T0 + timedelta(seconds=25 + i), hr=60, rr=15.0, status=None) for i in range(20)]

    windows = build_sessions(truoc + sau, now=sau[-1].t)

    assert windows == [], "khoảng đứt 5 giây phải chặn việc cộng dồn hai đoạn 20 giây"
