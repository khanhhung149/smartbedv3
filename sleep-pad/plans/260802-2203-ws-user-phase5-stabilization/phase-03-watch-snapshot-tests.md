---
phase: 3
title: "Test get_watch_snapshot"
status: pending
priority: P1
dependencies: [1]
---

# Phase 3: Test `get_watch_snapshot`

## Overview

Test đúng đắn query snapshot watch với `watch_data` seed sẵn. Ưu tiên case
steps = tổng ngày — bug thật vừa fix ở commit `9ff259e` (trước đó lấy bucket cuối
nên Home hiện ít bước hơn đồng hồ nhiều).

Đối tượng: `backend/app/data/service.py` — `get_watch_snapshot` (~70 LOC),
`_steps_today` (~35 LOC).

## Requirements

**Functional**
- Không có dữ liệu → trả `None`
- `type='combined'` → map `bloodOxygen`→`spo2`, `hrv`→`hrv`, `bloodGlucose`→`blood_glucose`
- `type='blood_pressure'` → map `systolicBloodPressure`/`diastolicBloodPressure`
- `type='step'` → **tổng** delta của ngày local gần nhất, không phải bản ghi cuối
- `synced_at` = thời điểm lớn nhất trong mọi metric
- Mỗi metric có `_at` riêng

## Architecture

### Ngữ nghĩa steps cần khoá chặt

```sql
WHERE local_day = (SELECT MAX(local_day) FROM s)
```

Là **ngày local gần nhất có dữ liệu**, không phải "hôm nay". Nếu đồng hồ 3 ngày chưa
sync thì vẫn trả tổng của ngày cuối có dữ liệu. Đây là hành vi cố ý — test phải khoá lại
để refactor sau không đổi ngầm.

### Biên timezone

`_STEP_DAY_TZ = "Asia/Ho_Chi_Minh"` (UTC+7). Bản ghi `2026-08-02T18:00:00Z` =
`2026-08-03 01:00` giờ local → thuộc ngày local **03**, không phải 02. Đây là case dễ vỡ
nhất, phải có test riêng.

### Lọc step không phải số

`raw_data->>'step' ~ '^[0-9]+$'` loại giá trị rác. Test bằng bản ghi `step: "abc"` lẫn
trong dữ liệu hợp lệ.

### Quan sát (không sửa đợt này)

`snap["spo2"] = int(spo2) if spo2 else None` — giá trị `0` bị coi là falsy → thành `None`.
Áp dụng cho `spo2`, `hrv`, `blood_glucose`, `systolic`, `diastolic`. Với SpO2 và huyết áp
thì 0 không có nghĩa sinh lý nên chấp nhận được; HRV = 0 thì tranh cãi được. **Không sửa
đợt này** (ràng buộc user). Ghi lại ở đây để sau quyết định. Test viết theo hành vi hiện
tại, không theo hành vi mong muốn.

## Related Code Files

**Create**
- `backend/tests/test_watch_snapshot.py`

**Read only**
- `backend/app/data/service.py:79-190`
- `backend/postgres/smart_watch_data.sql`

**Không sửa** file backend nào.

## Implementation Steps

1. Helper seed `watch_data` trong conftest hoặc tại chỗ: `(time, device_id, user_id, type, hash, raw_data)`
2. `test_snapshot_none_when_empty` — user không có dữ liệu → `None`
3. `test_snapshot_combined_fields` — 1 bản ghi `combined` với
   `{"bloodOxygen":98,"hrv":42,"bloodGlucose":5.4}` → map đúng 3 field + `_at`
4. `test_snapshot_blood_pressure` — `{"systolicBloodPressure":118,"diastolicBloodPressure":76}`
5. `test_steps_sums_daily_deltas` — **case chính**: seed 4 bản ghi step cùng ngày local
   (`10, 25, 39, 12`) → `steps == 86`, không phải `12`. Đây là hồi quy cho `9ff259e`.
6. `test_steps_excludes_previous_day` — thêm bản ghi ngày local trước → không cộng vào
7. `test_steps_timezone_boundary` — bản ghi `18:00Z` thuộc ngày local hôm sau; seed
   `17:00Z` và `18:00Z` cùng ngày UTC → phải tách thành 2 ngày local khác nhau
8. `test_steps_ignores_non_numeric` — lẫn `{"step":"abc"}` → bỏ qua, không crash
9. `test_synced_at_is_max_time` — nhiều metric thời điểm khác nhau → `synced_at` = lớn nhất
10. `test_combined_and_bp_latest_only` — 2 bản ghi `combined` → lấy bản mới nhất
    (`DISTINCT ON (type) ... ORDER BY type, time DESC`)

## Success Criteria

- [ ] 9 test pass, tổng < 3s
- [ ] `test_steps_sums_daily_deltas` fail nếu revert `9ff259e` (chứng minh test có giá trị)
- [ ] Không sửa dòng nào trong `backend/app/`

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Test timezone phụ thuộc ngày chạy | Seed thời gian tuyệt đối cố định, không dùng `now()` |
| Test steps xanh giả nếu chỉ có 1 bản ghi | Bắt buộc ≥3 bản ghi, và tổng ≠ giá trị bản ghi cuối |
| `create_hypertable` yêu cầu chèn đúng thứ tự time | Không quan trọng với timescale, chèn tuỳ ý được |
| Ràng buộc FK `device_id`/`user_id` | Seed user + device trước qua fixture Phase 1 |
