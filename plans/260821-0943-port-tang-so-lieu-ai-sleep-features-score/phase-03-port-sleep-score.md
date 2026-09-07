---
phase: 3
title: "Port sleep_score.py"
status: completed
priority: P2
dependencies: [2]
---

# Phase 03: Port `sleep_score.py`

<!-- Updated: Validation Session 1 - rdi_proxy giờ là số thật do pad đếm; rủi ro chuyển thành R2 -->

## Overview

Mang `backend/app/ai/sleep_score.py` sang **nguyên văn, không sửa dòng nào**. Là số học thuần trên
`SleepFeatures`, không phụ thuộc ngoài, không gọi mạng.

## Requirements

**Chức năng**

- Chấm điểm 0–100 từ một `SleepFeatures`, kèm phân rã theo thành phần và nhãn
  `excellent | good | fair | poor`.
- Tái lập tuyệt đối: cùng một phiên luôn ra cùng điểm.

**Phi chức năng**

- **Không sửa dòng nào.** Mọi ngưỡng theo quy ước có nguồn (7–9 giờ ngủ, sàn hiệu suất 85%, dải AASM),
  không phải ngưỡng tự đặt.

## Architecture

Mỗi thành phần ánh xạ một giá trị đo được lên `0..1` qua đoạn tuyến tính giữa mốc "đủ điểm" và mốc
"không điểm", rồi nhân trọng số.

```python
DUR_FULL_LO, DUR_FULL_HI, DUR_ZERO_LO, DUR_ZERO_HI = 420, 540, 180, 660
SCORE_BANDS = ((85, "excellent"), (70, "good"), (55, "fair"), (0, "poor"))
```

### Thành phần hô hấp — điểm rủi ro đã biết

```python
def _breathing_credit(rdi: float) -> float:
    if rdi < 5.0:
        return 1.0
    return _ramp(rdi, 5.0, 30.0)
```

Sau pha 01, `resp_disorder_total` đến từ trường `[Number of respiratory disorders]` của khung `0x86`
— **số thật do pad đếm**, không phải suy diễn. Rủi ro của bản kế hoạch đầu (điểm bị thổi lên vì
`rdi_proxy` luôn bằng 0) hạ xuống đáng kể.

Còn lại một khả năng: pad có thể luôn báo 0 nếu không phát hiện rối loạn hô hấp nào, hoặc nếu tính
năng đó không hoạt động trên bản `-T`. Chưa xác minh được cho tới khi `min_data` có dữ liệu thật.

**Hưng đã quyết giữ nguyên hành vi upstream** (quyết định 8 trong `plan.md`). Pha này **không** tự ý sửa.

Việc phải làm: ghi vào comment ngay tại `_breathing_credit` rằng thành phần này chỉ đáng tin khi
`rdi_proxy` đã được xác minh là số pad thật đo, dẫn chiếu R2, để người đọc sau không tưởng đó là điểm
đã được xác thực.

## Related Code Files

- Create: `cloud/sleeppad/app/ai/sleep_score.py`
- Create: `cloud/sleeppad/tests/test_sleep_score.py`
- Reference: `github.com/Sleep-Tech-AI/sleep-pad-ai` → `backend/app/ai/sleep_score.py` (nhánh `main`)

## Implementation Steps

1. Copy nguyên văn `sleep_score.py`.
2. Kiểm import: file này `from ai.sleep_features import SleepFeatures` — khớp bố cục pha 02, không đổi.
3. Thêm comment tại `_breathing_credit`: `rdi_proxy` đến từ khung `0x86`; nếu quan sát thấy nó luôn
   bằng 0 qua nhiều đêm thì phải xác minh pad có thật sự đo rối loạn hô hấp không, trước khi tin điểm
   thành phần này. Dẫn chiếu R2 trong `plan.md`.
4. Không thêm gì khác. Nếu thấy chỗ muốn "cải tiến" thì dừng lại và hỏi — lệch khỏi upstream ở đây
   khiến điểm giữa hai hệ không so sánh được nữa.

## Success Criteria

- [ ] `SleepScore` dựng được từ `SleepFeatures` của một phiên có `min_data`.
- [ ] Chạy hai lần trên cùng phiên → cùng `total`, cùng từng `points` của mọi thành phần.
- [ ] Tổng `points` của các thành phần = `total` (làm tròn nhất quán).
- [ ] `total` nằm trong 0–100 với mọi input trong tiêu chí nghiệm thu.
- [ ] Test: phiên 85 phút cho điểm thời lượng thấp (dưới ngưỡng 420 phút) — chứng minh
      `_duration_credit` hoạt động chứ không phải luôn trả 1.0.
- [ ] Test ghi nhận hành vi thành phần hô hấp: `rdi = 0` → đủ điểm. Đặt tên test nêu rõ đây là hành
      vi **đã biết và đã chấp nhận**, dẫn chiếu R2, để nếu sau này đổi quyết định thì test đỏ đúng chỗ.

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| `rdi_proxy` luôn 0 vì pad không đo rối loạn hô hấp (R2) | Sau pha 01 là số thật do pad đếm. Nếu quan sát thấy luôn 0 qua nhiều đêm thì xác minh lại trước khi tin |
| Sửa vặt làm điểm lệch khỏi upstream | Quy tắc pha: không sửa. Thấy chỗ muốn sửa thì hỏi |
| `_duration_credit` phạt nặng phiên ngắn khiến điểm demo trông tệ | Đúng như thiết kế — 85 phút không phải một đêm ngủ. Không phải lỗi |
