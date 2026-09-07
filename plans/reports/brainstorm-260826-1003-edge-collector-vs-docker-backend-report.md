# Brainstorm — edge/collector/ hay giữ nguyên Docker backend

- **Ngày:** 2026-08-26 · **Branch:** master · **Loại:** brainstorm, quyết định kiến trúc (không implement code, chỉ sửa docs)

## Vấn đề

`edge/README.md` (viết từ đầu dự án) liệt kê `collector/` như 1 module Python sẽ dựng trên Jetson để "nhận frame, validate, ghi DB" (Phase 01). Sau khi chuyển stack laptop→Jetson (260825), phát hiện `edge/collector/` **chưa từng tồn tại** — chỉ có `edge/README.md` + `edge/data/` (dataset mẫu).

## Đối chiếu thực tế

| Việc collector đáng lẽ làm | Ai đang làm thật |
|---|---|
| Nhận frame từ node | MQTT broker (Mosquitto), đã chạy |
| Validate + ghi DB, giữ mọi kênh kể cả chưa dùng | Backend Go (`cloud/presence-ac`, SQLite) + FastAPI (`cloud/sleeppad`, TimescaleDB) |
| Đánh dấu dropout rõ ràng, không bịa số | Cả 2 backend đã làm (`hr_bpm=0`, cờ `uart_ok`) |
| Xoay đêm, giữ N đêm gần nhất | `RetainNights` trong Go backend |
| Dashboard xem lại | Dashboard local + app Flutter, đã verify |

Kết luận: chức năng collector **đã được backend Docker đảm nhiệm đầy đủ**, chỉ khác vị trí code (Go/Python trong `cloud/`, không phải Python trong `edge/`).

## Phương án

1. **Không dựng collector, chỉ sửa README** — không trùng lặp logic, không rủi ro thêm cho hệ đang chạy ổn. Nhược điểm: cần cập nhật doc để không lệch thực tế.
2. **Dựng collector thay thế backend hiện tại** — đúng plan gốc nhưng viết lại thứ đang chạy tốt, vi phạm YAGNI, thêm rủi ro không cần thiết.
3. **Dựng collector làm lớp trung gian phục vụ Phase 02/05 sau này** (đọc lại data cho sleep staging/vision) — hợp lý về nguyên tắc nhưng chưa cần ngay, Phase 02/05 chưa bắt đầu.

## Quyết định

Chọn **phương án 1**. Đã sửa `edge/README.md`:
- Xoá mục `collector/` và `dashboard/` khỏi bảng module (đã có người làm việc này rồi, ở nơi khác).
- Ghi rõ ingestion/storage Phase 01 do backend Docker đảm nhiệm, không tái tạo ở `edge/`.
- Giữ `edge/` cho đúng vai trò: module AI cục bộ cần chạy trực tiếp trên Jetson (`sleep/` Phase 02, `vision/` Phase 05) — khi các phase đó bắt đầu, đọc thẳng từ SQLite/TimescaleDB hiện có, không thu thập lại.

## Việc KHÔNG làm

Không viết code `edge/collector/`. Không đổi kiến trúc backend hiện tại (Go/FastAPI trên Jetson giữ nguyên).

## Câu hỏi tồn đọng

Không còn — quyết định đã chốt.
