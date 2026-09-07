---
phase: 6
title: "Nghiệm thu — bench 10 phút, ghi số đo thật"
status: blocked
priority: P1
dependencies: [5]
---

# Phase 06: Nghiệm thu — bench 10 phút

## Overview
Chạy thật 10 phút ở 10Hz trước khi tiêu đêm đo 8 tiếng, ghi kết quả bằng số đo thật kể cả khi trượt.

## Requirements
- Mỗi tiêu chí có bằng chứng kiểm được: lệnh chạy + output.
- Kết quả trượt ghi nguyên trạng. **Không** sửa tiêu chí cho vừa kết quả.
- Chạy 10 phút, không phải 8 tiếng — mục đích là bắt lỗi hệ thống trước khi tốn một đêm.

## Architecture

10 phút × 10Hz = **6.000 mẫu** kỳ vọng. Đủ dài để lộ rò rỉ, trượt nhịp, reset; đủ ngắn để chạy lại nhiều lần trong ngày.

Bốn tình huống phải thử **có chủ đích**, không chỉ chạy trơn:

| Tình huống | Cách gây | Mong đợi |
|---|---|---|
| Chạy trơn | không làm gì | `seq` liền, `boot` không đổi, ≈6.000 mẫu |
| Mất WiFi ngắn | tắt WiFi router 5 giây | ring buffer giữ mẫu, phát bù, `seq` **vẫn liền** |
| Mất WiFi dài | tắt 30 giây (> 6,4s sức chứa buffer) | `seq` thủng đúng phần vượt sức chứa — chứng minh counter đo được thật |
| MCU reset | rút cắm lại nguồn node | `boot` +1, `seq` về 0 |

Tình huống 3 là tình huống quan trọng nhất: nó chứng minh `seq` **phát hiện được** mất mẫu. Không thử nó thì không biết counter có tác dụng hay chỉ luôn liền vì chưa bao giờ mất gì.

## Related Code Files
- Create: `plans/260820-0900-do-8-tieng-seq-counter-va-do-ben-sqlite/reports/nghiem-thu-bench-10-phut.md`
- Modify: `plans/260820-0900-do-8-tieng-seq-counter-va-do-ben-sqlite/plan.md` — cập nhật `status`

## Implementation Steps
1. Dựng hệ theo runbook Phase 05 — dùng chính runbook, không dùng lệnh riêng. Runbook sai chỗ nào thì sửa runbook.
2. Chạy tình huống 1, đếm mẫu, kiểm `seq`.
3. Chạy tình huống 2, 3, 4, ghi lại `seq` thủng ở đâu và bao nhiêu.
4. Đo tốc độ ghi backend: có theo kịp 10Hz không, có dựng backlog không.
5. Kiểm ca payload dài nhất: ép giá trị radar lớn để payload chạm 259B, xác nhận backend vẫn parse được.
6. Viết `reports/nghiem-thu-bench-10-phut.md`: từng tiêu chí — đạt/trượt, số đo thật, lệnh đã chạy.

## Success Criteria
- [ ] Tình huống 1: ≥5.940 mẫu (mất dưới 1% — bench ngắn nên nới hơn ngưỡng 0,1% của đêm thật)
- [ ] Tình huống 2: `seq` liền, chứng minh ring buffer làm việc
- [ ] Tình huống 3: `seq` thủng đúng lượng dự đoán — counter phát hiện được mất mẫu
- [ ] Tình huống 4: `boot` +1, `seq` về 0
- [ ] Payload 259B parse được, không drop
- [ ] Backend không dựng backlog ở 10Hz
- [ ] Báo cáo đã viết, có số thật

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Bench 10 phút không lộ lỗi chỉ xuất hiện sau nhiều giờ (rò rỉ bộ nhớ, đầy đĩa) | Nêu rõ trong báo cáo là bench ngắn không thay được đêm thật; theo dõi RAM free trong log |
| Kết quả tốt làm bỏ qua đêm đo thật | Bench là cổng vào, không phải bằng chứng cho tiêu chí 1 |
| Sửa runbook giữa lúc nghiệm thu làm mất tính khách quan | Ghi lại mọi lần sửa runbook vào báo cáo |
