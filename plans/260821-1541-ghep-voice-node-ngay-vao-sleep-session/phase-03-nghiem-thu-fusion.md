---
phase: 3
title: "Nghiệm thu fusion — off-bed test, chưa qua app thật"
status: completed
priority: P1
dependencies: [1, 2]
---

# Phase 03: Nghiệm thu fusion

**Viết lại sau khi việc đã làm thật (24/08)** — cùng lý do như phase-01/02. Kế hoạch gốc mô tả
"mở tab Giấc ngủ trên App" — việc đó **chưa làm**; nghiệm thu thật đi qua backend trực tiếp.

## Overview

Xác nhận `_summarize()`/`get_timeline()` chạy đúng trên dữ liệu thật, không qua mock.

## Đã làm thật

1. `pytest` 27/27 xanh trong container `sleeppad-fastapi` (không hồi quy so với trước khi sửa).
2. `scripts/nghiem-thu-fusion-off-bed.py`: gọi thẳng `_summarize()` trên Postgres đang chạy, cửa sổ
   10 phút trống hoàn toàn `sec_data`, chèn 1 sự kiện `room_snore_events` → `snore_total = 0`.
   **PASS.** Dòng test dọn sạch sau khi chạy, không để sót trong bảng thật.
3. Dữ liệu ngáy thật trong `room_snore_events` (từ `plan 260821-1023` Session 4-7, id 96-113) đã
   sẵn sàng để `_summarize()` dùng cho các phiên có `heart_rate > 0` thật.

## Chưa làm — ghi rõ để không ai tưởng đã xong

- **Chưa mở app Flutter thật** để xem con số `Ngáy` và vạch cam trên Timeline hiển thị đúng. UI đã
  có sẵn (xác nhận tồn tại), nhưng chưa chạy end-to-end qua giao diện.
- **Hệ số `0,5 phút/event` chưa calibrate** bằng ngáy thật đo thời lượng chính xác (xem `plan.md`).
- Chưa có unit test tự động cho biên phút (một sự kiện ngáy đúng lúc chuyển phút).

## Related Code Files

- Create: `cloud/sleeppad/scripts/nghiem-thu-fusion-off-bed.py`

## Success Criteria

- [x] `pytest` 27/27 xanh.
- [x] Test off-bed → 0 phút, PASS, dọn sạch dữ liệu test.
- [ ] Xem qua app Flutter thật — chưa làm, ngoài phạm vi phiên 24/08.

## Risk Assessment

Không mở app thật nghĩa là lỗi tầng hiển thị (nếu có) chưa được phát hiện — chỉ có bằng chứng tầng
backend. Nên mở app một lần trước khi coi tính năng này production-ready.
