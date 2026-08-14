# Phase 00 — Nền tảng, BOM, khung an toàn

- **Ưu tiên:** P0 (chặn mọi phase khác)
- **Trạng thái:** chưa bắt đầu
- **Ước lượng:** 2 tuần
- **Rủi ro:** thấp

## Mục tiêu

Chốt kiến trúc, chốt linh kiện, dựng bàn test. Không viết tính năng nào. Phase này tồn tại để 6 tháng sau không phải đập đi làm lại.

## Quyết định phải chốt (và lý do)

> Cập nhật 13/07 theo buổi onboarding Hưng (meet `xvk-oxqt-fod`). Các quyết định dưới đây đã được Michael chốt trực tiếp, không cần bàn lại.

### 1. Compute: Jetson Orin ngay từ đầu, bỏ Coral

- **Jetson Orin** làm bộ não chính — **đã có sẵn thiết bị**, không phải mua. MediaPipe Pose (Phase 05) chạy trên GPU của nó.
- **Coral USB: bỏ.** Trùng chức năng, ràng buộc model TFLite int8, không đáng.
- Orange Pi 5 Plus vẫn dùng được cho tầng thu thập cảm biến nếu tiện, nhưng không phải trục chính nữa.

### 2. MCU an toàn: ESP32 — thống nhất một dòng duy nhất

**ESP32 lo toàn bộ chuyển động và an toàn. Bỏ STM32.** Được dùng nhiều biến thể ESP32 khác nhau tuỳ nhu cầu (ESP32-S3, ESP8266 cho việc nhẹ như LED), nhưng không xen thêm dòng MCU khác.

Lý do thống nhất: một toolchain, một hệ sinh thái, một kho kinh nghiệm. Team nhỏ không đủ người để nuôi hai dòng MCU song song.

Nguyên tắc kiến trúc giữ nguyên: **tầng AI (Linux/Jetson) không được ra lệnh chuyển động trực tiếp.** Nó gửi "yêu cầu tư thế" xuống ESP32 qua UART/CAN, và **ESP32 có quyền từ chối**. Linux không real-time; actuator đang đè lên người mà kernel bận 200ms là đủ gây thương tích. ESP32 phải giữ được ba việc kể cả khi Linux treo: dừng khẩn cấp, phát hiện kẹt, khoá vị trí khi mất điện.

### 3. Cảm biến — chốt BOM

| Linh kiện trong spec | Quyết định | Lý do |
|---|---|---|
| **HLK-LD2510B** (radar 24GHz) | **Giữ, lõi — nâng cấp từ LD2410B** | 2510B track được **nhiều người cùng lúc + vị trí thật**. 2410B chỉ cho khoảng cách gần đúng. Gắn trên đầu giường chiếu xuống. Presence + nhịp thở + nhịp tim (gần đúng) |
| **Piezoelectric pad** | **Giữ, lõi — thay loadcell** | Thay hoàn toàn loadcell 150kg. Phát hiện hiện diện + BCG (ballistocardiogram) |
| **Mic đa hướng** | **Giữ** | Dùng con Quân vừa đưa. Gắn đầu giường. **KHÔNG phải mic định hướng** (mic định hướng là loại cục dài kiểu shotgun — không cần) |
| ~~Camera nhiệt~~ **ESP32-CAM (OV2640)** | **Thay hẳn** (chốt 13/08; đổi sang stream 14/08, xem `plans/260814-1237-esp32cam-stream-mediapipe-poc/`) | Cụm gốc "Camera nhiệt/MLX90614" thực ra nhắm quan sát hành vi ngủ, không phải đo nhiệt — trùng mục tiêu với thiết bị quan sát hình ảnh. Node camera thứ 6: **stream MJPEG qua HTTP trong LAN, không lưu ở đâu cả**, chỉ giai đoạn bench-test (không dùng khi có khách hàng thật) |
| SHT (nhiệt độ + độ ẩm) | **Giữ** | Môi trường khoang |
| ~~Loadcell 150kg~~ | **Cắt** | Thay bằng piezo pad |
| ~~MAX30102 (HR/SpO2)~~ | **Để sau** | Cảm biến tiếp xúc, phải chạm da. Mâu thuẫn triết lý non-contact |
| ~~MPS20N400D (huyết áp)~~ | **Để sau** | Cảm biến áp suất khí, không đo được huyết áp |
| ~~MQ303B (đo cồn)~~ | **Để sau** | Không đóng góp gì cho chất lượng giấc ngủ |
| ~~Coral USB~~ | **Cắt** | Jetson lo hết |

**Nguyên tắc mới (từ định vị framework):** thu thập **tất cả** data, kể cả cái hôm nay chưa dùng. Developer sau này sẽ cần. Không cắt cảm biến chỉ vì "chưa dùng tới" — chỉ cắt cái **sai về mặt vật lý** hoặc **vi phạm non-contact**.

### 4. Cơ khí: 3 mảng, không phải 10 điểm

10 điểm nâng → **3 mảng**: 1 mảng trên (nâng đầu), 1 mảng giữa rộng, 1 mảnh nhỏ dưới (nâng chân). Cung độ nhỏ, tốc độ chậm, độ ồn thấp. 10 điểm đẩy sang Phase 07.

Phase 00 chỉ cần **vẽ vị trí 3 mảng trên khung**, chưa lắp.

### 5. Định vị: wellness, không claim y tế

Mọi output gắn nhãn tham khảo. Không dùng chữ "chẩn đoán", "đo huyết áp", "phát hiện bệnh" trên UI hay marketing.

### 6. Bỏ Home Assistant / Node-RED

Build hệ thống quản trị riêng. Automation dựa trên AI hiểu intent, không phải người kéo-thả. (Michael: HA mạnh nhưng "sẽ thành cản trở" khi có AI.)

## Việc phải làm

1. Dựng repo `smartbed-v3` (monorepo): `firmware/` (ESP32), `edge/` (Python, Jetson), `cloud/`, `mech/` (CAD), `docs/`, `plans/`.
2. Viết `docs/system-architecture.md`: sơ đồ 3 tầng, giao thức giữa các tầng (UART/CAN frame format), luồng dữ liệu. **Thiết kế contract như API công khai ngay từ đầu** — đây là framework, không phải app đóng.
3. Viết `docs/safety/hazard-analysis.md`: liệt kê mọi cách giường có thể làm đau người (kẹp, đè, nhốt, ngạt, cháy, điện giật), mỗi hazard gắn với biện pháp giảm thiểu và phase nào xử lý.
4. BOM v3 với giá thật, có link nhà cung cấp, ra tổng chi phí một bộ. **Cần trần ngân sách từ Michael.**
5. Dựng bench rig: khung gỗ/nhôm định hình, chỗ gắn cảm biến, nguồn bench, không có actuator.
6. Chốt hệ toạ độ và vị trí **3 mảng nâng** trên khung (chưa lắp, chỉ vẽ).
7. Setup ESP32 toolchain. Flash thử WLED trên ESP8266 để làm quen (dùng ở Phase 03).
8. Đặt mua: **LD2510B**, **piezoelectric pad**. Hạn 18/07.

## Định nghĩa hoàn thành

- [ ] Repo có cấu trúc, CI chạy lint cơ bản
- [ ] `system-architecture.md` được Michael duyệt — **có định nghĩa API/contract mở**
- [ ] `hazard-analysis.md` liệt kê tối thiểu 15 hazard
- [ ] BOM có giá, tổng chi phí biết trước khi mua
- [ ] Bench rig đứng được trong phòng lab
- [ ] ESP32 toolchain chạy, flash được firmware trống

## Quy tắc phần cứng (Michael dặn 13/07)

**Luôn cấp nguồn riêng cho mạch. Không lấy nguồn từ laptop.** Sụt áp gây lỗi random cực khó debug — kinh nghiệm đã mất nhiều thời gian vì chuyện này.

## Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Bàn về kiến trúc kéo dài vô tận | Giới hạn cứng 2 tuần. Quyết định nào chưa rõ thì chọn phương án đảo ngược được, ghi lại lý do |
| BOM vượt ngân sách | Ra số sớm trong tuần 1, không đợi cuối phase |
