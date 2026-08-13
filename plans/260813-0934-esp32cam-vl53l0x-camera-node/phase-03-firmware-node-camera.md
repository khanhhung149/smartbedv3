---
phase: 3
title: "Firmware node camera (ESP32-CAM + VL53L0X)"
status: in-progress  # code viết xong + build thật + code-review + fix; 4/5 Success Criteria cần phần cứng thật (Phase 4)
priority: P1
dependencies: [2]
---

# Phase 3: Firmware node camera (ESP32-CAM + VL53L0X)

## Overview

Firmware cho node thứ 6: chụp ảnh OV2640, đọc khoảng cách VL53L0X qua cùng bus SCCB, ghi frame + khoảng cách + timestamp vào microSD cục bộ. Chỉ hoạt động ở chế độ bench-test.

## Requirements

- Functional:
  - Chụp JPEG SVGA (800×600), tốc độ mục tiêu ~5fps ổn định.
  - Đọc VL53L0X trên cùng bus I2C/SCCB (GPIO26/27), địa chỉ `0x29`, không xung đột với địa chỉ camera.
  - Ghi mỗi frame + khoảng cách (mm) + timestamp vào SD, có cấu trúc thư mục theo đêm.
  - Rotation: xoá thư mục đêm cũ nhất khi vượt 30 đêm.
- Non-functional:
  - Timestamp gắn tại MCU (đúng nguyên tắc Phase 01 gốc — không tin giờ Linux).
  - Không stream WiFi cho luồng ghi chính thức.
  - Toàn bộ đường ghi SD chỉ compile khi `BENCH_TEST_MODE=1` — production build (`BENCH_TEST_MODE=0`) không có code path ghi ảnh ra đĩa.
  - Nguồn riêng, không chia sẻ nguồn với node khác.

## Architecture

```
OV2640 (DVP song song, dữ liệu ảnh)  ──┐
SCCB/I2C (GPIO26/27, cấu hình)        ─┼─► ESP32-CAM ──► SD (SPI/SDMMC, local)
VL53L0X (I2C addr 0x29, dùng chung SCCB) ┘
```

- Bus SCCB dùng chung cho cấu hình camera VÀ VL53L0X — tránh chiếm thêm GPIO trên board AI-Thinker vốn đã ít chân trống khi dùng khe SD tích hợp (GPIO2,4,12,13,14,15 bị khe SD chiếm).
- Timestamp: đồng bộ NTP một lần lúc boot nếu có WiFi (chỉ để set giờ, không dùng cho streaming), sau đó chạy bằng đồng hồ nội bộ (`millis()`) cộng offset.

## Toolchain

**PlatformIO với `framework = espidf` thuần** — theo đúng tiền lệ Hưng đã dùng ở `esp32-presence-ac/firmware/voice-node/` (không phải `framework = arduino` như door-node/radar-node/room-node, cũng không mix `arduino, espidf` như voice-node). Vẫn dùng PlatformIO làm lớp orchestrator (`pio run`, `pio device monitor`, OTA env, `include/config.h` + `config.h.example` + `.gitignore` cho credentials) — chỉ khác framework bên trong là ESP-IDF thuần, dùng thẳng managed component `espressif/esp32-camera` qua `idf_component.yml`.

Đây cũng là câu trả lời cho `firmware/README.md`'s "Toolchain: ... Not chosen yet — Phase 00 task": node này chốt ESP-IDF, và Phase 1 cập nhật dòng đó thành đã chọn (xem `phase-01-quyet-dinh-bom-va-tai-lieu.md`).

## Related Code Files

- Create: `firmware/esp32cam-node/` (thư mục mới, xem ghi chú trùng tên ở Phase 1)
  - `firmware/esp32cam-node/platformio.ini` — `framework = espidf`, board AI-Thinker ESP32-CAM, cờ build `BENCH_TEST_MODE`
  - `firmware/esp32cam-node/CMakeLists.txt` — gốc, `include($ENV{IDF_PATH}/tools/cmake/project.cmake)` (PlatformIO tự sinh khi build lần đầu với `framework = espidf`, không cần viết tay)
  - `firmware/esp32cam-node/src/main.cpp` — vòng lặp chính: init camera, init VL53L0X, init SD, loop chụp+đo+ghi
  - `firmware/esp32cam-node/src/camera_config.h` — cấu hình OV2640 (SVGA, JPEG quality)
  - `firmware/esp32cam-node/src/storage.cpp` — ghi file, cấu trúc thư mục theo đêm, rotation 30 đêm
  - `firmware/esp32cam-node/idf_component.yml` — khai `espressif/esp32-camera` làm managed component
  - `firmware/esp32cam-node/include/config.h.example` — WiFi SSID (chỉ để NTP boot-sync), commit được; `config.h` thật bị `.gitignore`
  - `firmware/esp32cam-node/README.md` — mô tả node, ranh giới bench-test-only (đối chiếu 5 nguyên tắc riêng tư Phase 05)

## Implementation Steps

1. Dựng skeleton PlatformIO `framework = espidf` cho board AI-Thinker ESP32-CAM, theo đúng cấu trúc `esp32-presence-ac/firmware/voice-node/` (platformio.ini + CMakeLists.txt gốc + `src/`). Nếu ESP-IDF không tự nhận thư mục `src/` làm main component, đổi tên thành `main/` theo chuẩn ESP-IDF mặc định — không mất thời gian đoán, thử build là biết ngay.
2. Khai `espressif/esp32-camera` trong `idf_component.yml`, init camera: frame size SVGA, format JPEG, `xclk_freq_hz` chuẩn theo ví dụ AI-Thinker của component này.
3. Init VL53L0X trên cùng bus I2C (dùng driver I2C của ESP-IDF trực tiếp + C API gốc của ST cho VL53L0X, hoặc port ESP-IDF có sẵn nếu tìm được component phù hợp trong registry — quyết định cụ thể lúc code, không chặn plan), verify đọc được giá trị hợp lệ (không timeout) cùng lúc camera đang hoạt động — đây là điểm rủi ro chính (SCCB dùng chung).
4. Init SD (SDMMC 1-bit mode qua GPIO2/14/15, dùng driver `sdmmc` của ESP-IDF, đúng cấu hình chuẩn ESP32-CAM+SD).
5. Lấy timestamp: nếu có WiFi credential trong `config.h`, NTP sync một lần lúc boot bằng `esp_sntp`, sau đó **tắt WiFi hẳn** trước khi vào vòng ghi chính thức (đúng ranh giới đã chốt: WiFi chỉ cho đồng bộ giờ, không cho streaming lúc ghi); nếu không có credential, dùng `esp_timer` offset từ epoch cấu hình cứng lúc build (đủ cho bench-test, không cần chính xác tuyệt đối).
6. Vòng lặp chính: chụp frame → đọc khoảng cách → ghi vào `/sdcard/<YYYYMMDD>/frame_<seq>.jpg` + append dòng vào `/sdcard/<YYYYMMDD>/index.csv` (`t_ms, frame_file, distance_mm`).
7. Rotation: lúc boot hoặc mỗi nửa đêm, đếm số thư mục `YYYYMMDD`, nếu >30 thì xoá thư mục cũ nhất.
8. Bọc toàn bộ bước 5-7 (WiFi/NTP, ghi SD, rotation) trong `#if BENCH_TEST_MODE` — build production (`BENCH_TEST_MODE=0`) compile ra firmware không có đường ghi SD nào và không bật WiFi, chỉ còn optional live-view (nếu làm) qua WiFi cho lúc bench.
9. Viết `firmware/esp32cam-node/README.md`: mô tả rõ đây LÀ node ghi video cục bộ, CHỈ bench-test, đối lập 5 nguyên tắc Phase 05 — không được copy pattern này sang camera sản xuất. Theo mẫu `config.h.example` của `door-node`/`room-node` (comment giải thích từng define, không commit giá trị thật).

## Success Criteria

- [ ] Camera + VL53L0X đọc được đồng thời trên cùng bus SCCB, không timeout/conflict — cần phần cứng thật, xem Phase 4
- [ ] Ghi liên tục ổn định ≥5fps trong ít nhất 30 phút thử nghiệm bench, không tràn buffer/crash — cần phần cứng thật, xem Phase 4
- [ ] File JPEG + `index.csv` đọc lại được, khoảng cách hợp lý (so tay bằng thước) — cần phần cứng thật, xem Phase 4
- [x] Build `BENCH_TEST_MODE=0` — grep binary/symbol xác nhận không link hàm ghi SD nào vào production build — **verify thật:** `nm firmware.elf | grep storage_*` ra 0 kết quả trên production, đủ symbol trên bench-test (xem plan.md Code Review Log, re-verify sau fix)
- [ ] Rotation xoá đúng thư mục cũ nhất khi giả lập >30 thư mục đêm — logic viết xong (`storage_rotate()`), chỉ chạy được trên filesystem thật của thẻ SD/ESP32, cần phần cứng để verify — xem Phase 4

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| SCCB bus không đủ băng thông/ổn định khi chia sẻ giữa camera config và VL53L0X polling liên tục — **chưa test được trên phần cứng thật, đã có thêm nghi vấn GPIO-matrix từ code review** (`i2c_driver_install` trên I2C_NUM_1 có thể remap route camera driver đã set trên GPIO26/27) | Test sớm tuần đầu Phase 4; nếu xung đột thật, fallback: đọc VL53L0X ở tần số thấp hơn (1Hz) xen giữa các lần chụp thay vì polling liên tục. Không sửa mù phần code review nghi ngờ — cần đo thật trước |
| Ghi SD chậm hơn tốc độ chụp, rớt frame | **Đã sửa (code review Session 1):** vòng lặp chính dùng deadline-based delay (trừ thời gian xử lý thật) thay vì `vTaskDelay` cố định — log cảnh báo khi vòng lặp chậm hơn target thay vì âm thầm chạy chậm |
| Nhầm build production còn sót đường ghi SD | **Verify thật, không chỉ đọc code:** `nm firmware.elf \| grep storage_*` trên bản `esp32cam_production_check` ra 0 kết quả, trên bản `esp32cam` ra đủ symbol — xem plan.md Code Review Log |
| Timestamp trôi do không có RTC pin (mất điện reset về 0) | **Đã sửa (code review Session 1):** dùng `time(nullptr)` sau NTP sync thay vì `esp_timer_get_time()` (bug cũ khiến mọi thư mục đêm ra `19700101`); thêm `recover_frame_seq()` khôi phục seq khi thư mục đêm đã tồn tại (reboot giữa đêm không còn ghi đè âm thầm). Nếu NTP thật sự thất bại vẫn chấp nhận epoch giả cho bench-test, có log cảnh báo rõ ràng |
| `framework = espidf` trong PlatformIO có thể phát sinh vênh phiên bản platform/IDF (đã từng gặp ở `voice-node` — Arduino 2.0.17 dựng trên IDF 4.4 xung đột khi mix framework) | **Đã sửa (code review Session 1):** ghim `platform = espressif32@55.3.311` trong `platformio.ini` — version đã build SUCCESS thật, không để mặc định resolve mới nhất |
