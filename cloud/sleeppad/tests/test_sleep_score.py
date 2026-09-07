import pytest
from datetime import datetime, timedelta
from ai.sleep_features import SleepFeatures
from ai.sleep_score import score

def create_features(total_sleep_min: int = 480, rdi_proxy: float = 2.0) -> SleepFeatures:
    """Helper tạo SleepFeatures với các giá trị mặc định đẹp"""
    start = datetime(2026, 8, 20, 22, 0, 0)
    end = start + timedelta(minutes=total_sleep_min + 30) # time in bed lớn hơn sleep 30p
    
    return SleepFeatures(
        device_id="test1",
        session_start=start,
        session_end=end,
        time_in_bed_min=total_sleep_min + 30,
        total_sleep_min=total_sleep_min,
        sleep_efficiency_pct=round(total_sleep_min / (total_sleep_min + 30) * 100, 1),
        sleep_onset_latency_min=15,
        awakenings=1,
        longest_sleep_block_min=300,
        hr_mean=60.0,
        hr_min=50,
        hr_max=70,
        hr_dip_pct=15.0,
        rr_mean=15.0,
        rr_min=12.0,
        rr_max=18.0,
        rr_variability=1.5,
        movement_total=10,
        movement_index=round(10 / (total_sleep_min/60.0), 1),
        snore_total=5,
        snore_index=round(5 / (total_sleep_min/60.0), 1),
        resp_disorder_total=int(rdi_proxy * (total_sleep_min/60.0)),
        rdi_proxy=rdi_proxy,
        osa_risk_band="normal",
        coverage_pct=100.0,
        excluded_min=0,
        warnings=[]
    )

def test_score_reproducibility_and_bounds():
    f = create_features()
    
    # Chạy hai lần trên cùng phiên → cùng total, cùng từng points
    s1 = score(f)
    s2 = score(f)
    assert s1.total == s2.total
    for c1, c2 in zip(s1.components, s2.components):
        assert c1.points == c2.points
        
    # Total nằm trong khoảng 0-100
    assert 0 <= s1.total <= 100
    
    # Tổng points của các thành phần = total (hoặc chênh lệch do làm tròn)
    sum_points = sum(c.points for c in s1.components)
    sum_weights = sum(c.weight for c in s1.components)
    calculated_total = round(sum_points / sum_weights * 100)
    assert s1.total == calculated_total

def test_short_duration_punishes_score():
    # Test phiên 85 phút cho điểm thời lượng thấp (dưới ngưỡng 420 phút)
    f = create_features(total_sleep_min=85)
    s = score(f)
    
    duration_comp = next(c for c in s.components if c.key == "duration")
    # Trọng số tối đa của duration là 25. Phiên 85 phút sẽ nhận điểm rất thấp.
    assert duration_comp.points < 25.0

def test_accepted_behavior_breathing_credit_rdi_zero_gets_full_points():
    # R2: Ghi nhận hành vi đã biết và đã chấp nhận - nếu rdi = 0, đạt điểm tuyệt đối (10)
    # Nếu sau này đổi quyết định (do đệm -T luôn báo 0 không hợp lý), test này sẽ đỏ.
    f = create_features(rdi_proxy=0.0)
    s = score(f)
    
    breathing_comp = next(c for c in s.components if c.key == "breathing")
    assert breathing_comp.points == 10.0 # Full weight is 10
