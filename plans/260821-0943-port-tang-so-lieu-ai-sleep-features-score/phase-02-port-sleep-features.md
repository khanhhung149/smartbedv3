---
phase: 2
title: "Port sleep_features.py"
status: completed
priority: P1
dependencies: [1]
---

# Phase 02: Port `sleep_features.py`

<!-- Updated: Validation Session 1 - bỏ hai chỗ lệch có chủ ý; nguồn đổi từ tầng chiếu sang min_data thật -->

## Overview

Mang `backend/app/ai/sleep_features.py` từ repo Sleep-Tech-AI sang **nguyên văn**. Sau pha 01,
`min_data` có dữ liệu do chính pad tính, đúng hình dạng mà `extract()` mong đợi — không còn lý do
nào để sửa.

## Requirements

**Chức năng**

- `extract(device_id, minutes) -> SleepFeatures | None`, chữ ký và các trường giữ nguyên upstream.
- `minutes` là các dòng `min_data` đã sắp theo `time`.

**Phi chức năng**

- **Không sửa logic.** Chỉ được thêm log. Mọi sai lệch phải quay lại hỏi.
- Không thêm dependency.

## Architecture

Không có kiến trúc mới. Đây là bản sao.

### Vì sao bản đầu định lệch, và vì sao giờ không cần

Bản đầu định thêm `STATUS_SIT_UP = 3`, `STATUS_AWAKE = 5` và mở rộng `OCCUPIED`, vì tầng chiếu tự
nghĩ ra phải tự quyết mã đại diện cho mỗi phút. Pha 01 đã bỏ tầng chiếu: **pad tự phán mã phút**, và
tập mã phút của hãng (`0x86`) chỉ có `0x01`–`0x06`. `OCCUPIED`/`ASLEEP` của upstream ăn khớp trực tiếp.

### Một điều đã biết về upstream

`OCCUPIED` và `ASLEEP` của upstream chứa `STATUS_SNORING = 7` và `STATUS_WEAK_BREATHING = 8`, nhưng
tài liệu hãng nói tập mã ở **mức phút** chỉ tới `0x06`. Hai mục đó là **code chết** — không dòng
`min_data` thật nào khớp được.

**Không sửa.** Giữ nguyên để merge upstream sau này không vướng. Chỉ ghi một comment nêu phát hiện,
dẫn chiếu mục 2.4 tài liệu `数据传输协议英文版.xlsx`.

Ngáy vẫn được đếm đủ, qua trường `snore_count` riêng của khung `0x86`, không qua mã trạng thái.

## Related Code Files

- Create: `cloud/sleeppad/app/ai/__init__.py`
- Create: `cloud/sleeppad/app/ai/sleep_features.py`
- Create: `cloud/sleeppad/tests/test_sleep_features.py`
- Reference: `github.com/Sleep-Tech-AI/sleep-pad-ai` → `backend/app/ai/sleep_features.py` (nhánh `main`)

## Implementation Steps

1. Tạo `app/ai/__init__.py` rỗng.
2. Copy nguyên văn `sleep_features.py`.
3. Thêm comment tại `OCCUPIED`/`ASLEEP` về `STATUS_SNORING`/`STATUS_WEAK_BREATHING` là code chết ở
   mức phút, kèm dẫn chiếu tài liệu. **Không đổi giá trị.**
4. Thêm log mức `warning` khi `extract()` trả `None`, kèm lý do (`không có phút nào` / `dưới 10 phút
   có người`). Không im lặng — lỗi `relation "samples" does not exist` đã giấu mình cả đêm 20/08.
5. Viết test bằng dữ liệu `min_data` dựng tay, không cần DB (`extract()` là hàm thuần trên list dict).

## Success Criteria

- [ ] `extract()` trả object khác `None` trên một phiên có ít nhất 10 phút `min_data`.
- [ ] So từng dòng với bản upstream: **chỉ khác ở comment và log**, không khác logic.
- [ ] Test: chuỗi 90 phút mã `4` → `time_in_bed_min` = 90, `total_sleep_min` = 90,
      `sleep_efficiency_pct` = 100,0.
- [ ] Test: xen 3 phút mã `5` (awake) sau khi đã ngủ → `awakenings` = 1 (chuỗi ≥ `AWAKENING_MIN_MINUTES`).
- [ ] Test: 1 phút mã `5` lẻ → `awakenings` = 0 (dưới ngưỡng, là trở mình chứ không phải tỉnh giấc).
- [ ] Test: dưới 10 phút có người → trả `None` **và** ghi log cảnh báo.
- [ ] Test: phút mã `6` (vật nặng) không được tính vào `time_in_bed_min`.

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Vô tình "cải tiến" làm lệch upstream | Quy tắc pha: chỉ thêm comment và log. Thấy chỗ muốn sửa thì dừng và hỏi |
| Pha 01 thất bại, `min_data` vẫn rỗng | Pha này không nghiệm thu được. Đó là lý do pha 01 chặn tất cả |
| `sleep_efficiency_pct` chia cho 0 | Upstream đã chặn bằng `if len(occupied) < 10: return None` |
