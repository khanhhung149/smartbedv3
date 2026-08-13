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
  - Chụp JPEG SVGA (800×600), tốc độ mục tiêu ~5fps (đo thật ~1.5fps, đã chấp nhận — xem plan.md Bench Bring-up Log).
  - Đọc VL53L0X trên bus I2C **riêng** (GPIO4=SDA, GPIO13=SCL, port 0), địa chỉ `0x29`. **Cập nhật 13/08:** KHÔNG dùng chung bus SCCB với camera như thiết kế ban đầu — GPIO26/27 không ra header ngoài trên AI-Thinker, không hàn thêm dây được ở đó (xem plan.md Bench Bring-up Log mục 6).
  - Ghi mỗi frame + khoảng cách (mm) + timestamp vào SD, có cấu trúc thư mục theo đêm.
  - Rotation: xoá thư mục đêm cũ nhất khi vượt 30 đêm.
- Non-functional:
  - Timestamp gắn tại MCU (đúng nguyên tắc Phase 01 gốc — không tin giờ Linux).
  - Không stream WiFi cho luồng ghi chính thức.
  - Toàn bộ đường ghi SD chỉ compile khi `BENCH_TEST_MODE=1` — production build (`BENCH_TEST_MODE=0`) không có code path ghi ảnh ra đĩa.
  - Nguồn riêng, không chia sẻ nguồn với node khác.

## Architecture

```
OV2640 (DVP song song, dữ liệu ảnh)
SCCB/I2C nội bộ (GPIO26/27, port 1 — không ra header ngoài)  ─► ESP32-CAM ─► SD (SDMMC, local)
VL53L0X (I2C addr 0x29, bus RIÊNG: GPIO4=SDA/GPIO13=SCL, port 0) ─┘
```

- **Cập nhật 13/08 (bring-up thật):** camera và VL53L0X đi 2 bus I2C hoàn toàn độc lập,
  không chia sẻ. Thiết kế gốc "dùng chung bus SCCB" dựa trên giả định sai rằng
  GPIO26/27 đưa ra được header ngoài — thực tế chỉ nối nội bộ tới đầu nối FPC camera.
  VL53L0X dùng GPIO4+GPIO13 (2 chân trống khi SD chạy 1-bit mode: GPIO2,14,15 bị SD
  chiếm; GPIO12 tránh vì là bootstrap pin rủi ro không boot; GPIO16 đã bị PSRAM chiếm).
- Timestamp: đồng bộ NTP một lần lúc boot nếu có WiFi (chỉ để set giờ, không dùng cho streaming), sau đó chạy bằng `time(nullptr)` (epoch thật sau NTP, hoặc epoch giả đơn điệu tăng nếu NTP thất bại).

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

- [x] Camera + VL53L0X đọc được đồng thời (2 bus I2C riêng — GPIO26/27 camera, GPIO4/13 VL53L0X) — **verify thật 13/08 chiều:** cả 2 bus chạy song song không xung đột, `model_id=0xEE` đọc đúng datasheet, camera vẫn chụp/ghi bình thường cùng lúc. Đo khoảng cách thật (`vl53l0x_read_distance_mm()`) bị timeout — **giới hạn đã biết trước** (driver tối giản, chưa có chuỗi hiệu chuẩn ST, quyết định `/brainstorm` chấp nhận), không phải lỗi bus/wiring
- [ ] Ghi liên tục ổn định ≥5fps trong ít nhất 30 phút thử nghiệm bench, không tràn buffer/crash — **đo thật: ~1.5fps (~670ms/vòng lặp), KHÔNG đạt 5fps mục tiêu.** Không crash/tràn buffer qua nhiều lần reboot. Cần quyết định: chấp nhận 1.5fps (đủ cho mục đích debug/pose training?) hay tối ưu (giảm JPEG quality, bỏ bớt việc trong vòng lặp) — xem Phase 4
- [x] File JPEG + `index.csv` đọc lại được — **verify thật:** `recover_frame_seq()` scan thư mục đêm qua nhiều lần reboot ra đúng seq tăng dần (0→1868→...→4017), chứng minh file ghi/đọc lại được đúng. Cột khoảng cách trong `index.csv` hiện luôn là dropout (-1) do giới hạn driver VL53L0X (xem mục 1 ở trên) — không phải lỗi ghi file
- [x] Build `BENCH_TEST_MODE=0` — grep binary/symbol xác nhận không link hàm ghi SD nào vào production build — **verify thật:** `nm firmware.elf | grep storage_*` ra 0 kết quả trên production, đủ symbol trên bench-test (xem plan.md Code Review Log, re-verify sau fix)
- [ ] Rotation xoá đúng thư mục cũ nhất khi giả lập >30 thư mục đêm — logic viết xong (`storage_rotate()`), chỉ mới có 1 thư mục đêm thật (`20260813`) tích luỹ, chưa test rotation thật — xem Phase 4

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| ~~SCCB bus không đủ băng thông/ổn định khi chia sẻ giữa camera và VL53L0X~~ **Đã loại bỏ 13/08** — VL53L0X không dùng chung bus với camera nữa (GPIO26/27 không ra header ngoài, xem plan.md Bench Bring-up Log mục 6). Rủi ro mới: GPIO4/13 (bus VL53L0X riêng) có thể bị chiếm ngầm bởi driver khác | Đã verify bằng `esp_gpio_reserve` bitmask thật: GPIO4/13 không bị ai giữ trước khi VL53L0X init — an toàn |
| Ghi SD chậm hơn tốc độ chụp, rớt frame | **Đã sửa (code review Session 1):** vòng lặp chính dùng deadline-based delay (trừ thời gian xử lý thật) thay vì `vTaskDelay` cố định — log cảnh báo khi vòng lặp chậm hơn target thay vì âm thầm chạy chậm |
| Nhầm build production còn sót đường ghi SD | **Verify thật, không chỉ đọc code:** `nm firmware.elf \| grep storage_*` trên bản `esp32cam_production_check` ra 0 kết quả, trên bản `esp32cam` ra đủ symbol — xem plan.md Code Review Log |
| Timestamp trôi do không có RTC pin (mất điện reset về 0) | **Đã sửa (code review Session 1):** dùng `time(nullptr)` sau NTP sync thay vì `esp_timer_get_time()` (bug cũ khiến mọi thư mục đêm ra `19700101`); thêm `recover_frame_seq()` khôi phục seq khi thư mục đêm đã tồn tại (reboot giữa đêm không còn ghi đè âm thầm). Nếu NTP thật sự thất bại vẫn chấp nhận epoch giả cho bench-test, có log cảnh báo rõ ràng |
| `framework = espidf` trong PlatformIO có thể phát sinh vênh phiên bản platform/IDF (đã từng gặp ở `voice-node` — Arduino 2.0.17 dựng trên IDF 4.4 xung đột khi mix framework) | **Đã sửa (code review Session 1):** ghim `platform = espressif32@55.3.311` trong `platformio.ini` — version đã build SUCCESS thật, không để mặc định resolve mới nhất |
