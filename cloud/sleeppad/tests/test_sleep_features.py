import pytest
import logging
from datetime import datetime, timedelta
from ai.sleep_features import extract

def make_minute(start_time: datetime, offset_min: int, status: int, movement=0, snore=0, disorder=0, hr=60, rr=15.0) -> dict:
    return {
        "time": start_time + timedelta(minutes=offset_min),
        "status": status,
        "movement": movement,
        "snore_count": snore,
        "resp_disorder": disorder,
        "heart_rate": hr,
        "resp_rate": rr
    }

def test_90_minutes_perfect_sleep():
    start = datetime(2026, 8, 20, 22, 0, 0)
    minutes = [make_minute(start, i, 4) for i in range(90)]
    
    res = extract("device1", minutes)
    assert res is not None
    assert res.time_in_bed_min == 90
    assert res.total_sleep_min == 90
    assert res.sleep_efficiency_pct == 100.0

def test_awakening_runs():
    start = datetime(2026, 8, 20, 22, 0, 0)
    # Ngủ 30 phút
    m1 = [make_minute(start, i, 4) for i in range(30)]
    # Thức 3 phút (mã 5 = WAKE_UP)
    m2 = [make_minute(start, i, 5) for i in range(30, 33)]
    # Ngủ tiếp 30 phút
    m3 = [make_minute(start, i, 4) for i in range(33, 63)]
    
    res = extract("device1", m1 + m2 + m3)
    assert res is not None
    assert res.awakenings == 1

def test_awakening_too_short():
    start = datetime(2026, 8, 20, 22, 0, 0)
    # Ngủ 30 phút
    m1 = [make_minute(start, i, 4) for i in range(30)]
    # Thức 1 phút (chưa tới ngưỡng 2 phút)
    m2 = [make_minute(start, 30, 5)]
    # Ngủ tiếp 30 phút
    m3 = [make_minute(start, i, 4) for i in range(31, 61)]
    
    res = extract("device1", m1 + m2 + m3)
    assert res is not None
    assert res.awakenings == 0

def test_under_10_minutes(caplog):
    start = datetime(2026, 8, 20, 22, 0, 0)
    # Chỉ 9 phút có người
    minutes = [make_minute(start, i, 4) for i in range(9)]
    
    with caplog.at_level(logging.WARNING):
        res = extract("device1", minutes)
        assert res is None
        assert "dưới ngưỡng 10 phút" in caplog.text

def test_heavy_object_excluded():
    start = datetime(2026, 8, 20, 22, 0, 0)
    # 30 phút mã 4 (ngủ)
    m1 = [make_minute(start, i, 4) for i in range(30)]
    # 20 phút mã 6 (vật nặng)
    m2 = [make_minute(start, i, 6) for i in range(30, 50)]
    
    res = extract("device1", m1 + m2)
    assert res is not None
    assert res.time_in_bed_min == 30  # Vật nặng không được tính vào occupied
