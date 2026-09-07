---
phase: 1
title: "Sửa _summarize() dùng room_snore_events"
status: completed
priority: P1
dependencies: []
---

# Phase 01: Sửa `_summarize()` — sensor fusion Voice Node + Pad

**Viết lại sau khi code đã tồn tại thật (24/08)** — file này bị bỏ sót lúc làm, đánh dấu
`completed` trên `plan.md` mà không có tài liệu tương ứng. Mô tả đúng những gì đã chạy thật, không
phải kế hoạch trước khi làm.

## Overview

Thay `_summarize()` đếm `status = 7` từ `sec_data` (đệm rung, kém nhạy với tiếng ngáy) bằng số liệu
từ `room_snore_events` (voice-node, AI), kẹp điều kiện đệm phải có người nằm.

## Kiến trúc thật

`cloud/sleeppad/app/sessions/service.py:56-151`:

1. Đếm phút có người nằm (`occupied_minutes`): `SELECT DISTINCT date_trunc('minute', time) FROM
   sec_data WHERE heart_rate > 0` trong cửa sổ phiên.
2. Lấy toàn bộ sự kiện ngáy từ `room_snore_events` trong cùng cửa sổ.
3. Logic AND: chỉ đếm sự kiện nào rơi vào phút thuộc `occupied_minutes`.
4. Quy đổi: `snore_total_minutes = round(snore_events_on_bed * 0.5)` — **hệ số 0,5 chưa calibrate
   bằng ngáy thật**, xem cảnh báo trong comment tại dòng ~101 và Validation Log của `plan.md`.

## Related Code Files

- Modify: `cloud/sleeppad/app/sessions/service.py` (`_summarize`, dòng 56-151)

## Success Criteria

- [x] Không còn đếm `status = 7` từ `sec_data`.
- [x] `snore_total` tính từ `room_snore_events`, kẹp `occupied_minutes`.
- [x] `pytest` 27/27 không hồi quy.
- [x] Test off-bed → 0 phút (`scripts/nghiem-thu-fusion-off-bed.py`, xem `plan.md`).

## Risk Assessment

Hệ số `0.5` chưa calibrate — xem `plan.md` Session 5, rủi ro chính đã ghi ở đó. Không lặp lại ở đây.
