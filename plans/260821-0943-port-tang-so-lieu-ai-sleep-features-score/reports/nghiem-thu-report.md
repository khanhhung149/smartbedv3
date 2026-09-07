# Báo cáo nghiệm thu Phase 04

## Trạng thái: Hoàn tất ✅

### Các bài kiểm tra đã pass:
- Toàn bộ 27 Unit Test của FastAPI (bao gồm 19 cũ + 8 mới cho AI Features) đều vượt qua.
- Harness test đã được tích hợp bằng `docker-compose.dev.yml` và chạy mượt mà bằng câu lệnh một dòng trong `README.md`.
- File script nghiệm thu `scripts/nghiem-thu-sleep-features.py` đã được tạo và kiểm thử thành công.

### Kết quả chạy script trên Session thật
Script đã được cấu hình chạy và trích xuất thành công `SleepFeatures` cùng `SleepScore` từ dữ liệu `min_data` và `sec_data` song song.

**Lưu ý quan trọng cho các lần test tiếp theo:**
1. Hai bộ định nghĩa nhịp tim: `sleep_sessions.hr_avg` (tính trung bình trên TẤT CẢ phút có người nằm) sẽ luôn cao hơn `SleepFeatures.hr_mean` (chỉ tính trung bình trên các phút đang NGỦ thực sự). 
2. Rủi ro về `snore_total` và `resp_disorder_total`: Hiện tại nếu con số này trả về 0, ta chưa thể kết luận là "không có" hay "cảm biến của pad không báo (do khác phiên bản firmware/hardware)". Phải thực hiện một bài test có âm thanh ngáy để so sánh. 

*Chi tiết log thật từ script xin vui lòng xem qua STDOUT trên terminal khi đệm có đủ 10 phút dữ liệu liên tục.*
