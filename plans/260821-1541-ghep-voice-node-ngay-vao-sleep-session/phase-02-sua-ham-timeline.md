---
phase: 2
title: "Sửa get_timeline() gắn cờ 7 cho ngáy"
status: completed
priority: P1
dependencies: [1]
---

# Phase 02: Sửa `get_timeline()` — đổ sự kiện ngáy vào từng bucket

**Viết lại sau khi code đã tồn tại thật (24/08)** — cùng lý do như phase-01.

## Overview

Đổ số sự kiện ngáy từ `room_snore_events` vào từng `time_bucket` của timeline một đêm, gắn mã `7`
vào mảng `events` khi bucket đó có ngáy **và** đệm đang `on_bed` — để app vẽ vạch màu cam đúng chỗ.

## Kiến trúc thật

`cloud/sleeppad/app/sessions/service.py:261-...` (`get_timeline`):

- Truy vấn `room_snore_events` bucket theo `time_bucket()`, đếm số sự kiện mỗi bucket
  (dòng ~317).
- Với mỗi điểm timeline: `voice_snore_count = snore_by_bucket.get(t, 0)`; nếu `on_bed` **và**
  `voice_snore_count > 0` **và** `7` chưa có trong `events` thì thêm vào.
- Trường `snore` trong response = `voice_snore_count if on_bed else 0` — thay cho
  `min_data.snore_count` vốn luôn rỗng với pad LSM-800-T.

## Related Code Files

- Modify: `cloud/sleeppad/app/sessions/service.py` (`get_timeline`)

## Success Criteria

- [x] `events` chứa `7` đúng lúc bucket có publish ngáy và đang `on_bed`.
- [x] Không gắn `7` khi phòng trống (off-bed) dù có sự kiện ngáy — xác nhận qua Phase 01's test.
- [x] `pytest` 27/27 không hồi quy.

## Risk Assessment

Không có rủi ro riêng ngoài những gì đã ghi ở `plan.md` (hệ số calibration, thiếu test tự động cho
biên phút).
