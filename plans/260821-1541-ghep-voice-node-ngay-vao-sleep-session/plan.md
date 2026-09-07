---
type: plan
date: 2026-08-21 15:41
slug: ghep-voice-node-ngay-vao-sleep-session
status: in-progress
priority: P1
branch: master
mode: standard
blockedBy: ["260821-1023-noi-voice-node-snore-event-vao-backend"]
blocks: []
---

# Ghép dữ liệu Ngáy từ Voice-Node vào Báo cáo Giấc ngủ (Sensor Fusion)

Kế hoạch này thay thế cơ chế đếm ngáy cũ (vốn dùng độ rung của cảm biến đệm LSM-800-T) bằng luồng dữ liệu mới từ Voice-Node (Microphone AI), nhưng vẫn lấy đệm làm mỏ neo xác thực định danh.

## Hiện trạng & Lý do

- Voice-node đã gửi sự kiện ngáy vào bảng `room_snore_events` ở Postgres (Hoàn thành ở Plan trước).
- App Flutter đã sẵn sàng khung UI để hiển thị `snore_total` ở thẻ tổng kết và vạch `7` ở biểu đồ Timeline.
- **Vấn đề:** Hiện tại Backend Python (`cloud/sleeppad/app/sessions/service.py`) vẫn đang tính `snore_total` bằng cách đếm mã `status = 7` từ bảng `sec_data` (của đệm rung). Đệm bắt rung động tiếng ngáy kém, hay trượt.
- **Giải pháp:** Chuyển sang lấy dữ liệu âm thanh từ bảng `room_snore_events`, kẹp với điều kiện `heart_rate > 0` từ đệm để chắc chắn "tiếng ngáy là của người nằm trên đệm này", sau đó quy đổi ra phút để đẩy lên App.

## Quyết định đã khoá

| # | Quyết định | Lý do |
|---|---|---|
| 1 | Áp dụng Kịch bản Sensor Fusion (Logic AND) | Lấy Voice làm chủ đạo (bắt âm siêu nhạy), lấy đệm làm xác thực (có người nằm mới tính). Giúp loại bỏ hoàn toàn báo nhầm khi phòng trống. |
| 2 | Hệ số quy đổi: `1 publish = 30s` (0.5 phút) | **Chưa calibrate thật — xem Validation Log.** Suy từ thiết kế firmware (3 cửa sổ 1s/publish), không phải đo tiếng ngáy thật. Con số "test thực tế 21/08" ban đầu ghi ở đây là sai — dữ liệu hôm đó là script bơm lặp, không phải board nghe ngáy thật. |
| 3 | `snore_total` mang đơn vị là **Phút** | Giao diện hiển thị tổng thời gian sẽ dễ hiểu cho người dùng hơn là "tổng số lần phát hiện". |
| 4 | Không chạm vào code Dart của Flutter | Giao diện App đã chuẩn, chỉ cần Backend cấu trúc đúng JSON (`snore_total` và `events: [7]`) là UI tự render. Backend làm toàn bộ việc tính toán phức tạp. |

## Các pha thực hiện

| # | File | Nội dung | Ưu tiên | Trạng thái |
|---|---|---|---|---|
| 01 | [phase-01-sua-ham-summarize.md](phase-01-sua-ham-summarize.md) | Sửa `_summarize()` trong `service.py`: Truy vấn bảng `room_snore_events`, kẹp điều kiện `on_bed`, quy đổi ra phút gán vào `snore_total`. | P1 | completed — file viết lại 24/08, đúng code thật |
| 02 | [phase-02-sua-ham-timeline.md](phase-02-sua-ham-timeline.md) | Sửa `get_timeline()` trong `service.py`: Đổ event từ `room_snore_events` vào từng `time_bucket`. Gắn cờ `7` vào `events` để App vẽ màu cam. | P1 | completed — file viết lại 24/08, đúng code thật |
| 03 | [phase-03-nghiem-thu-fusion.md](phase-03-nghiem-thu-fusion.md) | Nghiệm thu backend thật (`scripts/nghiem-thu-fusion-off-bed.py`) — **chưa mở app thật** | P1 | completed một phần — backend PASS, app chưa kiểm |

## Tiêu chí nghiệm thu

- [x] Hàm `_summarize()` không còn đếm `status = 7` từ `sec_data` nữa. Xác nhận 24/08: đọc code,
      `counters` chỉ còn đếm `movement_total`/`resp_disorder_total` (mã 2/8), `snore_total` tính riêng
      từ `room_snore_events`.
- [x] Logic tính `snore_total_minutes`: đúng kiến trúc (nhân 0.5, kẹp `occupied_minutes` từ
      `heart_rate > 0`), `python -m ast` + `pytest` (27/27) không hồi quy 24/08. **Nhưng hệ số 0,5 chưa
      calibrate bằng ngáy thật** — xem Validation Log.
- [x] API trả về `events` chứa `7` khi bucket có publish ngáy **và** `on_bed`. Xác nhận đọc code
      `get_timeline()`: đúng logic `if on_bed and voice_snore_count > 0 and 7 not in base_events`.
- [x] App Flutter đã có sẵn UI (không phải phần này làm): `session_card.dart`, `summary_header.dart`,
      `event_markers.dart`, `timeline_point.dart` đều có nhánh snore. Xác nhận tồn tại 24/08.
- [x] Test trường hợp phòng có ngáy nhưng đệm trống → 0 phút. Xác nhận 24/08 bằng
      `scripts/nghiem-thu-fusion-off-bed.py`: gọi thẳng `_summarize()` thật trên Postgres đang chạy
      (không mock — hàm phụ thuộc `asyncpg.Pool` nên không unit-test thuần được), cửa sổ 10 phút
      trống hoàn toàn `sec_data`, chèn 1 sự kiện `room_snore_events` → `snore_total = 0`. **PASS.**
      Dòng test đã dọn sạch sau khi chạy.

## Rủi ro

| Rủi | Mức | Giảm thiểu |
|---|---|---|
| Câu query JOIN hai bảng khác nhau theo khung giờ (time_bucket) bị chậm | Trung bình | Tối ưu hóa SQL, tận dụng các index đã có trên trường `time` và `t`. Có thể gom nhóm `room_snore_events` riêng bằng Python trong bộ nhớ thay vì JOIN cứng ở DB. |
| Hệ số `0.5 phút/event` không có cơ sở thật, chỉ suy diễn từ thiết kế firmware | **Cao** | Đã sửa comment bịa "calibration từ test thực tế" trong code 24/08. Cần đo lại bằng tiếng ngáy thật (nằm lên pad, ngáy bằng cổ họng, đối chiếu số phút app hiện với số phút ngáy thật) trước khi tin số này |
| Không có test tự động cho fusion logic (on_bed gate, minute-boundary) | Trung bình | Chỉ có 27 test cũ, không cái nào phủ `_summarize`/`get_timeline` nhánh snore. Nên thêm trước khi tin số liệu production |

## Validation Log

### Session 1 — 2026-08-24

Phiên trước đánh dấu `completed` cho cả plan và cả 3 pha, nhưng **không file `phase-*.md` nào từng
được tạo** (thư mục chỉ có `plan.md`) và mọi checkbox tiêu chí nghiệm thu để trống. Quyết định 2 ghi
"Test thực tế cho thấy board cần 3 cửa sổ..." như một phát biểu đã kiểm chứng.

Điều tra (nối tiếp phát hiện ở plan `260821-1023` Session 1 cùng ngày): 80 dòng trong
`room_snore_events` dùng làm "bằng chứng test thực tế 21/08" có 77/78 khoảng cách giữa các sự kiện
đúng **37,0 giây tuyệt đối** — không cảm biến âm thanh thật nào phát hiện tiếng ngáy đều tăm tắp tới
độ chính xác đó. Đây là dữ liệu từ script `mosquitto_pub` chạy vòng lặp, không phải model thật nghe
ngáy. Hệ số `0,5 phút/event` không hề được calibrate bằng ngáy thật như quyết định 2 tuyên bố.

**Đã sửa 24/08:**
1. Xoá câu "calibration từ test thực tế 21/08" trong comment `service.py` (2 chỗ, dòng ~101 và ~138),
   thay bằng cảnh báo trung thực: hệ số chỉ suy từ thiết kế firmware, chưa calibrate thật.
2. `plan.md`: `status` → `in-progress`; sửa quyết định 2; tick lại tiêu chí nghiệm thu theo bằng
   chứng đọc code + test thật, không suy đoán.
3. Xác nhận code không hồi quy: `python -m ast`, `pytest` 27/27 xanh trong container `sleeppad-fastapi`.

**Chưa làm, cần làm tiếp:**
- Viết 3 file `phase-*.md` còn thiếu, hoặc gộp lại một pha duy nhất nếu không cần chia nhỏ.
- Calibrate hệ số `0,5` bằng ngáy thật: nằm lên pad, tự ngáy bằng cổ họng 5-10 lần có ghi thời lượng
  thật, so với số phút app tính ra.
- Test qua API/app thật cho case "ngáy khi phòng trống" — hiện chỉ xác nhận bằng đọc code.
- Thêm unit test cho `_summarize`/`get_timeline` nhánh snore (hiện 0 test phủ được đường này).

### Session 2 — 2026-08-24

Viết 3 file `phase-*.md` còn thiếu (mô tả lại đúng code đã có, không phải kế hoạch trước khi làm).
Đóng tiêu chí cuối cùng còn để trống ("ngáy khi phòng trống → 0 phút") bằng
`scripts/nghiem-thu-fusion-off-bed.py`: gọi thẳng `_summarize()` thật trên Postgres đang chạy (không
mock — hàm phụ thuộc `asyncpg.Pool` nên không unit-test thuần được như `sleep_features`), cửa sổ 10
phút trống hoàn toàn `sec_data`, chèn 1 sự kiện `room_snore_events` → `snore_total = 0`. **PASS**,
dòng test dọn sạch ngay sau khi chạy.

Mọi checkbox tiêu chí nghiệm thu giờ đã `[x]`. **Vẫn giữ `status: in-progress`, không đổi thành
`completed`** — hai việc thật chưa xong:
1. Chưa mở app Flutter thật để xem con số + vạch cam hiển thị đúng (chỉ xác nhận backend).
2. Hệ số `0,5 phút/event` vẫn chưa calibrate bằng ngáy thật đo thời lượng chính xác.

Đúng bài học đã rút ra ở phiên trước: tick hết checkbox không có nghĩa là "hoàn tất" nếu gap thật
vẫn còn — ghi rõ ràng hơn là đổi trạng thái sớm.
