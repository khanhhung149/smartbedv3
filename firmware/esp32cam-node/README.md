# esp32cam-node/ — ESP32-CAM (AI-Thinker, OV2640) + VL53L0X

Node MCU thứ 6 của hệ thống. Thay cụm "Camera nhiệt / MLX90614" gốc của Phase 01 —
mục tiêu thật là **quan sát hành vi lúc ngủ**, không phải đo nhiệt độ (camera OV2640
không đo được nhiệt độ, không có điểm chung vật lý với chức năng cũ).

Quyết định đầy đủ, kiến trúc, ranh giới riêng tư:
`plans/260813-0934-esp32cam-vl53l0x-camera-node/`

**Không nhầm với [`firmware/camera-node/`](../camera-node/README.md)** — đó là placeholder
cho camera RGB+IR của Phase 05 (gắn thẳng Jetson, **không bao giờ lưu ảnh/video ra đĩa**,
theo 5 nguyên tắc riêng tư). Node này thì ngược lại — **có ghi video**, nhưng chỉ trong
giai đoạn kỹ sư tự test.

## Ranh giới riêng tư — ĐỌC TRƯỚC KHI SỬA

- Ghi video **CHỈ áp dụng giai đoạn kỹ sư tự test (bench rig)**. Cấm tuyệt đối khi có
  khách hàng thật trên giường — đối lập trực tiếp 5 nguyên tắc riêng tư Phase 05.
- Cờ build `BENCH_TEST_MODE` (mặc định `1` ở env `esp32cam`) là ranh giới kỹ thuật:
  build production dùng env `esp32cam_production_check` (`BENCH_TEST_MODE=0`) —
  không còn code path nào ghi ảnh ra đĩa hay bật WiFi.
- WiFi **chỉ** bật để đồng bộ giờ (NTP) lúc boot, tắt hẳn trước vòng ghi chính thức —
  không stream ảnh/video qua mạng.
- Xem `docs/safety/hazard-analysis.md` hazard **H-25**.
- **Đèn flash (GPIO4) BẮT BUỘC gỡ vật lý trước khi board chạy với người đang ngủ** — GPIO4
  vừa là SDA I2C của VL53L0X vừa là chân đèn flash trên AI-Thinker (không tách được bằng
  code, không còn GPIO nào khác trống để dời sang). Mỗi giao dịch I2C làm đèn nhấp nháy —
  chấp nhận được lúc bench-test trên bàn, **không chấp nhận được** khi golive thật (ánh
  sáng nhấp nháy trong phòng tối lúc ngủ). Xem hazard **H-26**.

## Phần cứng

| | |
|---|---|
| Camera | OV2640 trên board AI-Thinker ESP32-CAM, SCCB nội bộ GPIO26/27 (không ra header) |
| ToF | VL53L0X, địa chỉ I2C `0x29`, bus I2C **riêng** (SDA=GPIO4, SCL=GPIO13, port 0) — GPIO26/27 không đưa ra header ngoài nên không đấu chung được với camera như dự tính ban đầu (xác nhận 13/08, xem plan.md Bench Bring-up Log). Tránh GPIO12 (bootstrap, rủi ro không boot) và GPIO16 (PSRAM CS) |
| Lưu trữ | microSD 16GB thật (kế hoạch ban đầu 256GB), format FAT32, gắn ngay trên board (SDMMC 1-bit: CLK=14, CMD=15, D0=2) |
| Nguồn | 5V/2A **riêng**, không lấy từ laptop/Jetson (quy tắc phần cứng chuẩn dự án) |

## Toolchain

PlatformIO, `framework = espidf` thuần (không Arduino) — theo tiền lệ
`esp32-presence-ac/firmware/voice-node/`.

```
cp include/config.h.example include/config.h   # điền WiFi thật, chỉ dùng cho NTP boot-sync
pio run -t upload -e esp32cam
pio device monitor
```

Build kiểm tra ranh giới production (Phase 4 Success Criteria — verify không có
đường ghi SD/WiFi nào):

```
pio run -e esp32cam_production_check
```

## Cấu trúc dữ liệu ghi ra

```
/sdcard/<YYYYMMDD>/<HH>/frame_<seq6>.jpg
/sdcard/<YYYYMMDD>/<HH>/index.csv        # t_ms,frame_file,distance_mm
```

Cấp thư mục giờ (`HH`) thêm 13/08 sau khi đo thật: gộp phẳng cả đêm (~144K file ở
~5fps×8h) vào 1 thư mục làm FAT chậm dần liên tục theo số file tồn tại (0→5.24fps,
~1594→1.16fps, ~4300→0.45fps — đo thật, không phải suy đoán). Mỗi thư mục giờ giờ chỉ
còn tối đa ~18K file. Rotation tự xoá NGUYÊN thư mục đêm (đệ quy qua các thư mục giờ
con) cũ nhất khi vượt 30 thư mục — khớp chính sách retention 30 đêm của Phase 01 gốc.

## Trạng thái

**Đã flash thật lên board AI-Thinker ESP32-CAM, chạy ổn định.** Camera + SD + VL53L0X
đều hoạt động xuyên suốt nhiều lần reboot trong buổi bring-up 13/08. Trên thẻ SD sạch:
**~5.0-5.24fps** (đạt mục tiêu ban đầu). Chi tiết đầy đủ + toàn bộ bug/kiến trúc thật
đã bắt và sửa: `plans/260813-0934-esp32cam-vl53l0x-camera-node/plan.md` §Bench
Bring-up Log + §Số liệu DoD chính thức.

Đã verify bằng công cụ thật, không phải khẳng định suông:
- `pio run -e esp32cam` và `pio run -e esp32cam_production_check` — cả 2 SUCCESS, đã flash thật.
- `nm firmware.elf | grep storage_*|esp_wifi_connect` trên bản production → **0 kết quả**
  (ranh giới riêng tư H-25 đúng như thiết kế); trên bản bench-test → đủ symbol.
- Serial log thật xác nhận: camera OV2640 nhận diện đúng, SD mount + ghi/đọc lại đúng
  qua nhiều lần reboot (seq tự khôi phục, không ghi đè), NTP→tắt WiFi đúng thiết kế.

**VL53L0X đã hàn dây thật, bus I2C riêng hoạt động đúng** (GPIO4=SDA, GPIO13=SCL, port
0, `model_id=0xEE` đúng datasheet). Đo khoảng cách thật hiện luôn timeout/dropout —
**giới hạn driver tối giản đã biết trước** (thiếu chuỗi hiệu chuẩn SPAD/VHV/phase của
ST, xem TODO trong `vl53l0x.cpp`), không phải lỗi wiring/code. Đo (kể cả khi
dropout) chạy trên **1 FreeRTOS task nền riêng** (`vl53l0x_start_background_task()`),
tách khỏi vòng lặp camera từ 13/08 sau khi `/brainstorm` phát hiện coupling sai (ToF
timeout ~850ms từng làm camera "đứng khựng" dù 2 cảm biến độc lập phần cứng hoàn
toàn) — xem `vl53l0x.h`/`vl53l0x.cpp` để hiểu kiến trúc.

Việc còn lại: chạy test 8 tiếng liên tục thật (Phase 4 DoD), điều tra 1 lần
POWERON_RESET chưa rõ nguyên nhân, xem
`plans/260813-0934-esp32cam-vl53l0x-camera-node/phase-04-bench-validation-dod.md`.
