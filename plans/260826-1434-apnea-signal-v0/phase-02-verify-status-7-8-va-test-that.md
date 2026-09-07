---
phase: 2
title: "Verify status 7/8 thật + test apnea qua đêm"
status: pending
priority: P2
dependencies: [1]
---

# Phase 2: Verify status 7/8 thật + test qua đêm

## Overview
Xác nhận hardware sleep-pad thật có bao giờ phát `status==7` (SNORE) hoặc `8` (WEAK_BREATHING) không, và test `apnea_events` trên 1 đêm ngủ thật — gộp chung với đêm test của plan `260826-1241-phase2-v0-sleep-state-machine` (Phase 2) nếu làm cùng lúc, không cần 2 đêm riêng.

## Requirements
- Functional: nằm lên pad, thử ngáy/nín thở nhẹ vài giây, sau đó query `sec_data` xem `status` có từng = 7/8 không.
- Non-functional: ghi lại kết quả (có hoặc không) vào plan này — không chặn dùng tín hiệu B nếu A không bao giờ trigger.

## Related Code Files
- Không sửa code trừ khi Phase 1 cần tinh chỉnh ngưỡng sau khi thấy dữ liệu thật.

## Implementation Steps
1. Nằm lên sleep-pad, đợi ~30s cho status ổn định (status=0, on-bed thường).
2. Ngáy giả vài giây, nín thở nhẹ vài giây.
3. Query: `SELECT DISTINCT status FROM sec_data WHERE device_id='CNU190440C' AND time >= '<giờ vừa test>' ORDER BY 1;`
4. Ghi kết quả vào phần Risk Assessment dưới đây (cập nhật file này).
5. Nếu đi cùng đêm test 8 tiếng (plan khác): sau khi dậy, gọi `morning-report` cho khoảng đêm đó, xem `apnea_events` có hợp lý so với cảm nhận thực tế không (có thức giấc thở gấp/khó thở không, nếu nhớ được).

## Success Criteria
- [ ] Biết chắc status 7/8 có xuất hiện trên hardware này không (ghi vào plan, không cần đúng kỳ vọng nào).
- [ ] `apnea_events` từ 1 đêm thật không tràn lan báo giả (dưới vài event/đêm là hợp lý cho v0).

## Risk Assessment
- Risk: nếu status=7/8 không bao giờ xuất hiện, tín hiệu A vô dụng vĩnh viễn trên hardware này — chấp nhận, thiết kế OR-fusion đã tính, chỉ còn tín hiệu B hoạt động.
- **Kết quả verify status 7/8 (2026-08-26, ~07:56-07:59 UTC)**: CHỈ thấy status 0/1/2 trong suốt bài test (nằm yên, đè chân, nín thở). KHÔNG bao giờ thấy 7 (SNORE)/8 (WEAK_BREATHING) → **tín hiệu A xác nhận không hoạt động trên hardware này**, giống vụ min_data/0x20 đã gặp trước đó. Chỉ còn tín hiệu B (resp_rate==0 && heart_rate>0) khả dụng.
- **Vấn đề mới phát hiện khi test tín hiệu B**: lúc nín thở, cơ thể gồng/cử động khiến `status` nhảy 0→2 (MOVEMENT)→1 (GET_OUT_OF_BED) dao động ~15s thay vì giữ yên — `heart_rate`/`resp_rate` về 0 do pad hiểu là rời giường (đúng theo protocol), KHÔNG phải "tim đập nhưng thở không đo được". Tín hiệu B chưa trigger đúng ý trong lần test này. **Cần test lại: nằm thật yên, không gồng người, khi nín thở** để giữ `status==0` ổn định trong lúc `resp_rate` về 0 — đây mới đúng điều kiện tín hiệu B thiết kế.
