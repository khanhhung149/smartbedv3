# Phase 01 — Cụm cảm biến phi tiếp xúc + data pipeline

- **Ưu tiên:** P0
- **Trạng thái:** chưa bắt đầu
- **Ước lượng:** 3-4 tuần
- **Rủi ro:** thấp (không có bộ phận chuyển động, không có người nằm dưới máy móc)
- **Phụ thuộc:** Phase 00

## Mục tiêu

Giường ghi được dữ liệu thật của một người ngủ suốt đêm, liên tục, không mất mẫu. Chưa cần thuật toán thông minh. Chỉ cần dữ liệu sạch, có timestamp chuẩn, lưu được, xem lại được.

Đây là nền của mọi thứ phía sau: không có dữ liệu thật thì không có AI, không có apnea, không có gì cả.

## Vì sao làm cái này trước

Rẻ nhất, nhanh nhất, rủi ro gần bằng không, mà lại mở khoá cho Phase 02 (là sản phẩm bán được đầu tiên). Toàn bộ bài take-home tuyển dụng đã chạy trên dữ liệu giả lập 10Hz với đúng schema này. Phase 01 chỉ là thay dữ liệu giả bằng dữ liệu thật.

## Phần cứng

> Cập nhật 13/07: radar nâng lên **LD2510B**, loadcell **thay bằng piezo pad**, mic **đa hướng** (không phải định hướng).

| Cảm biến | Giao tiếp | Vị trí | Cho ra |
|---|---|---|---|
| **HLK-LD2510B** (radar 24GHz) | UART | Trên đầu giường, chiếu xuống | Presence, **vị trí thật**, **track nhiều người cùng lúc**, biên độ thở, nhịp tim thô |
| **Piezoelectric pad** | ADC | Dưới nệm, vùng thân | Hiện diện, BCG (ballistocardiogram), chuyển động, trở mình |
| SHT (SHT10/SHT31) | I2C | Trong khoang, tránh hơi thở trực tiếp | Nhiệt độ + độ ẩm môi trường |
| **Mic đa hướng** (con Quân đưa) | I2S | **Gắn đầu giường** | Âm thanh thở, ngáy, ồn môi trường |
| **ESP32-CAM (OV2640) + VL53L0X** | SCCB (I2C, GPIO26/27), địa chỉ VL53L0X `0x29` | Hướng vào vùng ngủ | Frame ảnh JPEG (quan sát hành vi), khoảng cách người-camera. **Node MCU riêng (thứ 6)** — không cắm vào ESP32 thu thập của 4 cụm còn lại |

**Vì sao LD2510B thay LD2410B:** 2410B chỉ cho *approximate distance*. 2510B track được **nhiều người cùng lúc và vị trí thật** — cần thiết cho giường đôi và cho việc phân biệt người nằm vs người đi ngang qua.

**Vì sao piezo pad thay loadcell:** piezo cho tín hiệu BCG (nhịp tim/thở qua rung cơ học) mà loadcell không cho được, lại không bị trôi theo nhiệt độ. Rẻ hơn, lắp đơn giản hơn.

**Vì sao ESP32-CAM+VL53L0X thay Camera nhiệt/MLX90614 (chốt 13/08):** cụm gốc thực ra nhắm "quan sát hành động lúc ngủ", không phải đo nhiệt — camera OV2640 không đo được nhiệt độ, không có điểm chung vật lý với chức năng cũ. Chi tiết quyết định, kiến trúc, ranh giới riêng tư (chỉ ghi video giai đoạn bench-test, không dùng khi có khách hàng thật): `plans/260813-0934-esp32cam-vl53l0x-camera-node/`. **Hệ quả:** Phase 03 mất input thân nhiệt cá nhân (MLX90614), đã quyết định bỏ hẳn, không bù lại — vòng kín điều hoà môi trường Phase 03 chỉ còn dùng SHT.

**MCU thu thập:** **ESP32** (thống nhất toàn hệ, xem Phase 00). Đọc cảm biến, đóng gói frame, đẩy lên Jetson qua UART hoặc Ethernet/MQTT.

## Phần mềm

1. **Firmware thu thập** (`firmware/sensor-node/`)
   - Vòng lặp 10Hz cố định, không jitter. Timestamp gắn tại MCU, không gắn ở Linux.
   - Ring buffer chống mất mẫu khi Linux bận.
   - Đánh dấu mẫu lỗi rõ ràng (ví dụ `hr_bpm = 0` khi cảm biến dropout) thay vì bịa số. Downstream phải biết đâu là dữ liệu thật.

2. **Collector trên Jetson** (`edge/collector/`)
   - Nhận frame, validate, ghi vào SQLite (hoặc TimescaleDB nếu dữ liệu lớn).
   - Schema khớp đúng CSV của bài take-home: `t, presence, hr_bpm, resp_amplitude, motion, weight_kg, spo2, temp_c, humidity`.
   - **Lưu TẤT CẢ kênh dữ liệu, kể cả kênh chưa có ai dùng.** Đây là yêu cầu từ định vị framework: developer sau này sẽ cần data mà hôm nay ta chưa nghĩ ra công dụng. Đĩa rẻ hơn dữ liệu đã mất.
   - Xoay file theo đêm, nén, giữ 30 đêm gần nhất.

3. **Dashboard local** (`edge/dashboard/`)
   - Biểu đồ real-time đơn giản (web, chạy trên chính Jetson).
   - Xem lại một đêm bất kỳ.
   - Chưa cần đẹp. Đây là công cụ debug cho kỹ sư, không phải UI khách hàng.

## Việc phải làm

1. Lắp 6 cụm cảm biến (bao gồm node camera ESP32-CAM+VL53L0X) lên bench rig, đi dây gọn, có thể tháo rời từng cụm (spec yêu cầu modular, giữ nguyên yêu cầu này).
2. Viết firmware thu thập trên **ESP32**, verify 10Hz bằng oscilloscope hoặc đếm mẫu.
3. Viết collector + schema DB.
4. Chạy thử 3 đêm với người thật (Michael hoặc Hưng tự nằm). Kiểm tra: mất bao nhiêu mẫu, radar có bắt được nhịp thở khi nằm nghiêng không, piezo pad có bắt được BCG qua nệm dày không.
5. Hiệu chuẩn piezo pad: xác định ngưỡng phân biệt có người / rời giường / giường trống.
6. Test LD2510B với **2 người nằm cùng lúc** — đây là lý do chính chọn 2510B thay 2410B, phải verify sớm.
7. Ghi lại giới hạn thực tế của từng cảm biến vào `docs/sensor-characterization.md` (radar mất tín hiệu khi nào, mic bắt được ngáy từ khoảng cách nào).

## Định nghĩa hoàn thành

- [ ] Ghi liên tục 8 tiếng, mất dưới 0.1% mẫu
- [ ] Nhịp thở từ radar khớp với đếm bằng mắt (sai số dưới 2 brpm) ở tư thế nằm ngửa và nằm nghiêng
- [ ] **LD2510B track được 2 người cùng lúc, ra được vị trí từng người**
- [ ] Piezo pad phân biệt được người trên giường / rời giường / giường trống
- [ ] Có 3 đêm dữ liệu thật lưu trong DB, xem lại được trên dashboard
- [ ] `docs/sensor-characterization.md` ghi rõ giới hạn từng cảm biến

## Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Radar nhiễu khi có chăn dày, hoặc mất tín hiệu khi nằm nghiêng | Rủi ro thật, đã gặp trong project autogate. Test sớm ngay tuần 1. Nếu yếu quá thì đổi sang radar 60GHz (ví dụ Infineon BGT60) hoặc bù bằng BCG từ piezo pad |
| Piezo pad không xuyên được nệm dày | Test với nhiều độ dày nệm ngay tuần 1. Nếu không đạt, cân nhắc đặt piezo trên mặt nệm dưới ga, hoặc quay lại loadcell như phương án dự phòng |
| LD2510B khó mua / khan hàng ở VN | Đặt sớm (hạn 18/07). Có sẵn LD2410B làm dự phòng để không chặn tiến độ |
| Hơi thở làm ẩm cảm biến SHT | Đặt lệch khỏi luồng thở, ghi rõ vị trí trong tài liệu |
