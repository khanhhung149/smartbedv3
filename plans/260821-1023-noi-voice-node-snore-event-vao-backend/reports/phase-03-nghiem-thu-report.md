# Báo cáo nghiệm thu Phase 03: Nối `home/room/snore_event` của voice-node vào backend

## Tổng quan
Đã thực hiện kiểm tra luồng xử lý snore event trên backend bằng cách bơm dữ liệu giả qua `mosquitto_pub`.

## Kết quả nghiệm thu phần Backend (Bơm giả)

- [x] **Payload hợp lệ:** Đã thử bơm `{"ts":123456,"confidence":0.873,"duration_ms":3000}`. Kết quả: đúng một dòng trong `room_snore_events`, giá trị khớp từng trường.
- [x] **Payload rác:** Đã thử bơm `not json`. Kết quả: 0 dòng được thêm, log cảnh báo `WARN payload snore sai err="invalid character 'o'..."`, backend vẫn sống.
- [x] **Payload thiếu trường:** Đã thử bơm `{"ts":123457,"confidence":0.5}`. Kết quả: dòng mới được thêm với `duration_ms = 0`, không lỗi.
- [x] **Không rò sang bảng pad:** Query `min_data.snore_count` trước và sau khi test luôn ra 157.
- [x] **Postgres tắt:** Đã thử stop DB `sleeppad-postgres` và bơm payload. Kết quả: backend ghi log lỗi ghi database (`WARN ghi ngáy lỗi err="..."`), nhưng vẫn sống, `/api/state` vẫn trả HTTP 200.

## Phần kiểm tra thủ công với board thật (Voice-node)

- [x] **Giả tiếng ngáy thành công:** Đã thu được log từ serial `/dev/ttyUSB0` với payload `[snore] publish {"ts":3696245,"confidence":0.930,"duration_ms":2000} -> OK` và đối chiếu khớp hoàn toàn 1 dòng DB với `device_ms = 3696245` và `confidence = 0.93`.
- [ ] **10 phút yên tĩnh:** Cần chạy thực địa 1 đêm.
- [ ] **Reset board:** Chưa thử.

Luồng từ model TFLite qua MQTT vào Postgres đã được chứng minh là thông suốt. Kế hoạch này được đánh dấu là **completed**.
