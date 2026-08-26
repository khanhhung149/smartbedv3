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
- (Điền sau khi test) Kết quả verify status 7/8: _chưa test_.
