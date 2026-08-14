---
phase: 2
title: "Firmware esp32cam-stream"
status: completed
priority: P1
dependencies: [1]
---

# Phase 2: Firmware `esp32cam-stream`

## Overview

Firmware ESP-IDF mới, một chức năng duy nhất: khởi động camera OV2640, nối WiFi, phục vụ MJPEG stream qua HTTP. Không SD, không I2C, không NTP.

## Requirements

- Functional: `GET /stream` trả `multipart/x-mixed-replace` MJPEG VGA liên tục; `GET /` trả trang HTML kiểm tra bằng mắt.
- Non-functional: không tồn tại code path nào ghi frame ra bộ nhớ bền (điều kiện của H-25 mới). Không dùng thư viện SD/FATFS.

## Architecture

```
boot
 ├─ esp_camera_init()      VGA, PIXFORMAT_JPEG, quality 12, fb_count 2, fb_location PSRAM
 ├─ wifi_init_sta()        từ config.h, chờ IP, in ra serial
 └─ httpd_start()
      ├─ cổng 80: GET /        -> index_handler   (HTML tĩnh, <img> trỏ sang :81)
      └─ cổng 81: GET /stream  -> stream_handler  (vòng lặp vô hạn)
                          esp_camera_fb_get()
                          httpd_resp_send_chunk(boundary + Content-Type + Content-Length)
                          httpd_resp_send_chunk(fb->buf, fb->len)
                          esp_camera_fb_return(fb)
```

Boundary: `--frame`. Content type: `multipart/x-mixed-replace;boundary=frame`. Đây là định dạng duy nhất `cv2.VideoCapture(url)` đọc trực tiếp được — RTSP/WebRTC trên ESP32 cần thư viện nặng hoặc client riêng, đã loại ở brainstorm.

## Related Code Files

**Create:**
- `firmware/esp32cam-stream/platformio.ini`
- `firmware/esp32cam-stream/sdkconfig.defaults`
- `firmware/esp32cam-stream/CMakeLists.txt`
- `firmware/esp32cam-stream/README.md`
- `firmware/esp32cam-stream/include/config.h.example`
- `firmware/esp32cam-stream/src/CMakeLists.txt`
- `firmware/esp32cam-stream/src/idf_component.yml`
- `firmware/esp32cam-stream/src/main.c`
- `firmware/esp32cam-stream/src/camera_config.h`
- `firmware/esp32cam-stream/src/stream_handler.c`
- `firmware/esp32cam-stream/src/stream_handler.h` — **thêm ngoài danh sách plan.** `main.c` cần prototype của `start_webserver()`; khai báo extern trong `main.c` là cách giấu ranh giới module, không phải cách bỏ bớt file

**Modify:** không có.

<!-- Updated: Validation Session 1 - .gitignore đã phủ sẵn, bỏ bước thừa -->
`.gitignore` **không cần sửa** ở phase này: dòng 15 đã có `.pio/`, dòng 27 đã có `firmware/**/config.h` (glob phủ luôn `esp32cam-stream`). Verify bằng `git check-ignore -v firmware/esp32cam-stream/include/config.h` sau khi tạo file.

## Implementation Steps

1. `platformio.ini`:
   ```ini
   [env:esp32cam]
   platform = espressif32@55.3.311   ; ghim version — bài học từ node cũ, KHÔNG để resolve mặc định
   board = esp32cam
   framework = espidf
   monitor_speed = 115200
   ```
2. `sdkconfig.defaults`: bật PSRAM, tăng `CONFIG_HTTPD_MAX_REQ_HDR_LEN`, stack cho httpd task. PSRAM là **bắt buộc** — VGA JPEG `fb_count=2` không vừa SRAM nội.

   <!-- Updated: thực thi 14/08 - tên key PSRAM trong plan sai -->
   **Key PSRAM đúng là `CONFIG_SPIRAM=y` + `CONFIG_SPIRAM_USE_MALLOC=y` + `CONFIG_SPIRAM_MODE_QUAD=y`**, không phải `CONFIG_ESP32_SPIRAM_SUPPORT=y` như plan ghi (tên cũ của IDF v4, ESP-IDF 5 bỏ rồi — đặt sai thì key bị làm ngơ im lặng và camera init fail với `ESP_ERR_NO_MEM`). Ba key này lấy từ node cũ, đã verify trên phần cứng thật 13/08. Đã xác nhận có mặt trong `sdkconfig.esp32cam` sinh ra sau build.
3. `src/idf_component.yml`: khai báo `espressif/esp32-camera`.
4. `camera_config.h`: pin-map AI-Thinker (PWDN 32, RESET -1, XCLK 0, SIOD 26, SIOC 27, D7..D0 35/34/39/36/21/19/18/5, VSYNC 25, HREF 23, PCLK 22), `FRAMESIZE_VGA`, `jpeg_quality = 12`, `fb_count = 2`, `fb_location = CAMERA_FB_IN_PSRAM`, `grab_mode = CAMERA_GRAB_LATEST`.
5. `config.h.example`: `#define WIFI_SSID "..."` / `#define WIFI_PASS "..."` + comment nhắc copy sang `config.h` (gitignored).
6. `main.c`: `esp_camera_init` → `wifi_init_sta` (chờ `IP_EVENT_STA_GOT_IP`, in IP) → `start_webserver`. Xử lý `nvs_flash_init()` gotcha (`ESP_ERR_NVS_NO_FREE_PAGES` / `NEW_VERSION_FOUND` → erase + retry) — bài học từ node cũ. Lỗi camera/WiFi log rõ ràng, **không** dùng `ESP_ERROR_CHECK` gây reboot loop.
7. `stream_handler.c`: 2 handler như Architecture. Trong vòng stream, `fb == NULL` thì log + `continue`, không abort. Thoát vòng khi `httpd_resp_send_chunk` trả lỗi (client ngắt).

   <!-- Updated: thực thi 14/08 - "log + continue" trần là bug -->
   **`continue` trần ở nhánh `fb == NULL` là lỗi**, phát hiện khi tự review trước lúc bàn giao: không có lệnh nhường CPU nào trong nhánh đó, nên camera hỏng biến vòng lặp thành vòng quay tít → task watchdog kích và log ngập, che mất nguyên nhân thật. Đã thêm `vTaskDelay(10ms)`, chỉ log ở lần lỗi đầu tiên, và ngắt stream sau `MAX_CONSECUTIVE_FB_FAILURES = 100` lần liên tiếp (~1 giây) để client biết mà kết nối lại thay vì nhìn khung hình đứng im tưởng bình thường.
8. `README.md`: mục đích, pin-map, cảnh báo bench-test-only + trỏ H-25, hướng dẫn `cp include/config.h.example include/config.h` → `pio run -t upload -e esp32cam` → `pio device monitor`, và ghi rõ **không đụng `firmware/camera-node/`**.
9. Build, flash, mở trình duyệt.

## Success Criteria

- [x] `pio run -e esp32cam` build **SUCCESS** (14/08, PlatformIO 6.1.19, 683s lần đầu). Flash 23.2% (971 KB/4 MB), RAM 14.4%, IRAM 89.9% — IRAM sát trần, thêm component lớn vào node này cần đo lại
- [x] `pio run -t upload -e esp32cam --upload-port /dev/ttyUSB0` nạp được, hash verified. Serial in `192.168.1.119`, OV2640 detect (PID=0x26), frame buffer 61440 B ×2 cấp phát trong PSRAM
- [x] `http://<ip>/` trả trang OK 200 trong 0.05s; stream `http://<ip>:81/stream` trả đúng `multipart/x-mixed-replace`. **Chưa có người nhìn bằng mắt xác nhận "mượt"** — mới xác nhận bằng đo đạc phía client
- [x] fps đo thật, đã ghi vào `README.md`: **20.3 fps** VGA (30s liên tục, 10.0 KB/frame, 1.67 Mbit/s, RSSI −64); **23.2 fps** khi đồng thời phục vụ trang ở cổng 80. Node cũ chỉ 1.5 fps SVGA ghi SD
- [x] `grep -ri "sdmmc\|fatfs\|f_open\|fopen\|esp_vfs" firmware/esp32cam-stream/src/` → 0 kết quả (điều kiện H-25). Comment trong `stream_handler.c` và `src/CMakeLists.txt` cố ý **không viết ra các tên API này** dù đang nói về chúng, nếu không chính comment làm gate đỏ
- [x] **Kiểm chứng mạnh hơn (thêm khi thực thi):** `xtensa-esp32-elf-nm firmware.elf | grep -Ec "sdmmc_|esp_vfs_fat|f_mount|f_open|f_write|sdcard"` → **0**. Grep source chỉ chứng minh mình không gọi; symbol trong ELF chứng minh không có đường ghi đĩa nào được **link vào firmware thật**. Không thay gate của plan, chỉ bổ sung
- [x] `git check-ignore -v` xác nhận cả 3 thứ bị ignore đúng: `include/config.h` (`.gitignore:27`), `sdkconfig.esp32cam` (`:24`), `.pio/` (`:15`)

## Risk Assessment

| Rủi ro | Xử lý |
|---|---|
| Quên bật PSRAM → camera init fail hoặc VGA không cấp phát được | Bước 2 bắt buộc; nếu `esp_camera_init` trả `ESP_ERR_NO_MEM` thì kiểm tra PSRAM trước tiên |
| Không ghim platform version → toolchain drift, build gãy sau vài tháng | Ghim `@55.3.311` (bài học đã trả giá ở node cũ) |
| Stream treo khi client ngắt đột ngột | Thoát vòng khi `send_chunk` lỗi; test bằng cách đóng tab giữa chừng |
| WiFi yếu → frame drop | Chấp nhận ở phase này; xử lý retry ở phía client (Phase 3) |
| Nguồn không đủ dòng → brownout khi WiFi TX | Dùng nguồn 5V/2A riêng, không cấp từ cổng USB laptop (quy tắc phần cứng chuẩn dự án) |
