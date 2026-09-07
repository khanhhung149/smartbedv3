---
phase: 4
title: "Nghiệm thu trên dữ liệu thật"
status: completed
priority: P1
dependencies: [3]
---

# Phase 04: Nghiệm thu trên dữ liệu thật

<!-- Updated: Validation Session 1 - nguồn là min_data thật; số kỳ vọng đổi sang đối chiếu chéo -->

## Overview

Nối ba pha trước thành một đường chạy được, thiết lập mốc đối chiếu đầu tiên trên `min_data` thật,
và sửa harness test để lần sau chạy được mà không phải thao tác thủ công.

## Requirements

**Chức năng**

- Một loader nhận `session_id`, đọc cửa sổ từ `sleep_sessions`, nạp `min_data` trong cửa sổ đó,
  rồi gọi `extract()` → `score()`.
- Một script nghiệm thu in ra `SleepFeatures` và `SleepScore` cho một phiên bất kỳ.

**Phi chức năng**

- `pytest` chạy được bằng **một lệnh**, không cần `docker cp` thủ công.

## Architecture

### Loader

```python
async def features_for_session(pool, session_id) -> SleepFeatures | None:
    """Đọc cửa sổ từ sleep_sessions, nạp min_data trong cửa sổ, rồi extract."""
```

Cửa sổ lấy từ `sleep_sessions.started_at` / `ended_at`. Phiên đang mở (`ended_at IS NULL`) thì lấy
`now()` làm mốc cuối.

**Không** dùng `SESSION_GAP_HOURS` của upstream (quyết định 6). Hệ này đã có định nghĩa "một đêm"
trong bảng `sleep_sessions`; thêm định nghĩa thứ hai là tự tạo mâu thuẫn.

### Harness test

Vấn đề hiện tại: `requirements-dev.txt` có `pytest==8.3.4` nhưng không có chỗ nào chạy được —
host không cài được (hook chặn `venv`), container không có sẵn. Sáng 21/08 phải `docker cp tests`
thủ công, không lặp lại được.

Cách sửa: mount thư mục `tests` vào container ở `docker-compose.dev.yml`, cùng chỗ đã mount `./app`
và `./scripts`.

```yaml
  fastapi:
    volumes:
      - ./app:/app
      - ./scripts:/app/scripts:ro
      - ./tests:/tests:ro                 # thêm
      - ./requirements-dev.txt:/requirements-dev.txt:ro   # thêm
```

Lệnh chạy test, ghi vào `cloud/sleeppad/README.md`:

```bash
docker compose exec fastapi pip install -q -r /requirements-dev.txt
docker compose exec -w /app fastapi python -m pytest /tests -q
```

## Related Code Files

- Create: `cloud/sleeppad/app/ai/service.py`
- Create: `cloud/sleeppad/scripts/nghiem-thu-sleep-features.py`
- Modify: `cloud/sleeppad/docker-compose.dev.yml` — mount `tests` + `requirements-dev.txt`
- Modify: `cloud/sleeppad/README.md` — mục cách chạy test

## Implementation Steps

1. Viết `app/ai/service.py` với `features_for_session()` và `score_for_session()`.
2. Viết `scripts/nghiem-thu-sleep-features.py`: nhận `device_id` (hoặc `session_id`), in `SleepFeatures`,
   `SleepScore`, và bảng đối chiếu chéo với `sec_data` cùng `sleep_sessions`.
3. Sửa `docker-compose.dev.yml` thêm hai mount.
4. Ghi cách chạy test vào `README.md`.
5. Chạy script trên một phiên **có `min_data`** (tức sau khi pha 01 xong và pad đã chạy ≥ 10 phút ở
   chế độ `0x20`), dán kết quả thật vào báo cáo nghiệm thu ở `plans/260821-0943-.../reports/`.
6. Chạy `pytest` toàn bộ — phải xanh cả 19 test cũ lẫn test mới.

## Success Criteria

- [ ] `docker compose exec -w /app fastapi python -m pytest /tests -q` chạy được từ máy sạch, không
      thao tác thủ công.
- [ ] Toàn bộ test xanh (19 cũ + test mới của pha 01–03).
- [ ] Script nghiệm thu chạy trên một phiên có `min_data` và thoả toàn bộ bảng dưới:

| Kiểm tra | Cách đối chiếu |
|---|---|
| `time_in_bed_min` | ≈ số dòng `min_data` có `status` thuộc `OCCUPIED` trong cửa sổ phiên |
| `movement_total` | cùng bậc độ lớn với số đợt mã 2 suy từ `sec_data` trên cùng cửa sổ |
| `hr_mean` | **thấp hơn** `sleep_sessions.hr_avg` một cách có hệ thống — upstream chỉ tính trên phút `ASLEEP` |
| `hr_max` | **thấp hơn** `sleep_sessions.hr_max` vì đỉnh thường rơi vào phút cử động |
| `snore_total` | bằng `SUM(min_data.snore_count)` trên cửa sổ |
| `sleep_score.total` | tái lập qua 2 lần chạy |

**Không** đóng cứng số kỳ vọng tuyệt đối: `min_data` là số pad tự tính, chưa ai quan sát nó trên phần
cứng này. Vòng nghiệm thu đầu là để **thiết lập** mốc, không phải để khớp mốc có sẵn.

- [ ] Báo cáo nghiệm thu ghi rõ hai định nghĩa nhịp tim khác nhau (`sleep_sessions` = "khi có người
      nằm", `SleepFeatures` = "khi đang ngủ") kèm số thật của cả hai, để lần sau không ai tưởng là lỗi.
- [ ] Báo cáo ghi rõ nếu `snore_total` và `resp_disorder_total` bằng 0: chưa phân biệt được "không có"
      với "pad không đo được", cho tới khi có bài thử ngáy.

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Mount `tests` làm hỏng container đang chạy | Chỉ thêm ở `docker-compose.dev.yml`, không đụng `docker-compose.yml` |
| Script nghiệm thu đóng cứng `device_id` rồi vô dụng cho đêm sau | Nhận tham số dòng lệnh, mặc định là phiên mới nhất |
| Kết quả "đẹp" che mất việc `snore_count` chưa xác minh (R2) | Bắt buộc có mục cảnh báo trong báo cáo nghiệm thu |
| Số kỳ vọng lệch nhẹ do làm tròn khác nhau | Dùng khoảng, không dùng bằng tuyệt đối, cho các giá trị trung bình |
