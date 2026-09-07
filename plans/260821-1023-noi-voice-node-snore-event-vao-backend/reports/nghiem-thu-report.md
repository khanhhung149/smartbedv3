# Báo cáo nghiệm thu Phase 03: Nối Voice Node Snore Event vào Backend

## Kết quả nghiệm thu bằng payload giả (mosquitto_pub)

1. **Payload hợp lệ**: Bơm `{"ts":123456,"confidence":0.873,"duration_ms":3000}` → Thành công. DB ghi nhận 1 dòng với `device_ms=123456`, `confidence=0.873`, `duration_ms=3000`.
2. **Payload rác (`not json`)**: Ghi nhận log `WARN payload snore sai err="invalid character..."`. Backend không crash, không insert dòng nào.
3. **Payload thiếu `duration_ms`**: Bơm `{"ts":123456,"confidence":0.873}` → Thành công. DB ghi nhận dòng với `duration_ms=0`.
4. **Kiểm tra rò rỉ**: Không có thay đổi nào ở bảng `min_data`.
5. **Kiểm tra chịu lỗi DB**: Đã tắt Postgres và bơm payload. Backend vẫn sống, chỉ in log `WARN ghi ngáy lỗi err="insert room_snore_events: FATAL: terminating connection due to administrator command"`. 

## Ghi chú về báo nhầm (False Positive)
- Việc test vật lý với board thật và test phòng yên tĩnh 10 phút chưa được thực hiện do hạn chế về môi trường nghiệm thu tự động.
- Cần thực hiện bước nghiệm thu thực địa này trước khi chính thức cho phép App hiển thị dữ liệu cho người dùng. Mẫu 10 phút cũng chỉ là phép đo ban đầu, không thay thế được một đêm ngủ có nhãn thực tế.

**Kết luận**: Backend đã xử lý ổn định các luồng dữ liệu ngáy từ voice-node, sẵn sàng cho nghiệm thu thực địa.
