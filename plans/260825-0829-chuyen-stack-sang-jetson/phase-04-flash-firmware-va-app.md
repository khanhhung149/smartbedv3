---
phase: 4
title: "Flash lại firmware ESP32 và cập nhật app"
status: completed
priority: P1
dependencies: [3]
---

# Phase 4: Flash lại firmware ESP32 và cập nhật app

## Overview
Sửa `MQTT_HOST` trong `config.h` từng ESP32 node trỏ IP Jetson, flash lại, và kiểm tra app Flutter không còn hardcode IP laptop cũ.

## Requirements
- Functional: mỗi node kết nối được broker đúng của nó trên Jetson (radar-node → 1883, sleep-pad-node → 1884, voice-node theo hệ nào nó thuộc).
- Non-functional: đọc `config.h` thật hiện có trước khi sửa (bị gitignore, không tự bịa credentials — theo development-rules.md).

## Architecture
Không đổi kiến trúc, chỉ đổi 1 giá trị compile-time (`MQTT_HOST`) mỗi node rồi flash qua cổng USB (không OTA lần này vì đổi broker, node cần kết nối được broker mới trước khi OTA hoạt động).

## Related Code Files
- Modify: `firmware/radar-node/include/config.h` (thật, gitignored), `firmware/sleep-pad-node/include/config.h`, `firmware/voice-node/include/config.h` (xác nhận có tồn tại, voice-node dùng MQTT).
- **Xác nhận qua code:** app Flutter đọc `API_BASE_URL` qua `--dart-define` với default trong `app/smartbed/lib/core/app_config.dart:23`, và giá trị này **override được ngay trong app** qua SharedPreferences (`app_config.dart:36,44`) — không bắt buộc build lại app, có thể chỉ cần đổi trong màn hình settings của app.
- `camera-node` không dùng MQTT — bỏ qua bước flash, chỉ kiểm tra URL stream trong app/dashboard.

## Implementation Steps
1. Đọc `config.h` thật hiện tại của từng node (radar-node, sleep-pad-node, voice-node nếu áp dụng) trước khi sửa.
2. Đổi `MQTT_HOST` thành `192.168.1.125` (hoặc IP tĩnh đã chốt ở Phase 1 nếu khác), giữ nguyên `MQTT_PORT`/`MQTT_USER`/`MQTT_PASS`/topic — không đổi giá trị nào khác trừ khi có lý do.
3. Flash lại từng node qua USB (theo quy trình build hiện có của mỗi firmware — PlatformIO/ESP-IDF tuỳ node).
4. Mở app trên điện thoại/máy đang test, vào màn hình settings đổi `baseUrl` sang IP Jetson (không cần rebuild) — chỉ rebuild với `--dart-define=API_BASE_URL=...` mới nếu muốn đổi default cho lần cài mới.
5. Verify từng node lên lại broker: theo dõi log broker trên Jetson (`docker compose logs -f mosquitto` hoặc tương đương) thấy node connect + publish.

## Success Criteria
- [x] radar-node connect broker 1883 trên Jetson — verify qua log `home-mqtt`: `New client connected ... as radar-node`, IP thật board `192.168.1.93`.
- [x] sleep-pad-node connect broker 1884 trên Jetson, publish `sleeppad/<id>/sec` — verify: `sec_data` có 10 dòng, timestamp mới nhất khớp thời gian test.
- [x] Không node nào "mất tích" âm thầm — radar-node, voice-node, sleep-pad-node đều đã verify connect qua log broker + dữ liệu DB thật.
- [x] App Flutter trỏ đúng backend Jetson — sửa default trong code (không phải chỉ `--dart-define` runtime).

## Kết quả thực thi (2026-08-25) — radar-node
- Board vào WSL2 qua `usbipd attach`, xuất hiện tại `/dev/ttyACM0`.
- `config.h` thật đọc trước khi sửa — chỉ đổi `MQTT_HOST` từ `192.168.1.120` (máy Windows cũ) sang `192.168.1.125` (Jetson), giữ nguyên user/pass/topic/port.
- `pio run -t upload -e lolin_s2_mini --upload-port /dev/ttyACM0` — SUCCESS 27s, không cần bấm nút BOOT/RST tay (board tự vào bootloader qua auto-reset DTR/RTS).
- Verify qua log broker Jetson: `radar-node` connect thành công ~10s sau khi flash xong.
- Disconnect "exceeded timeout" ~4 phút sau đó — do user rút board ra (đổi sang cắm voice-node), không phải lỗi. Cần cắm lại radar-node khi vào Phase 5 để verify ổn định 10 phút.

## Kết quả thực thi (2026-08-25) — voice-node
- Board mới (CH340, COM3 bên Windows) attach qua `usbipd.exe attach --wsl --busid 2-1` (tôi tự chạy qua Windows interop từ WSL2, không cần user thao tác PowerShell tay).
- `config.h` thật có **2 địa chỉ** cần đổi (khác radar-node): `MQTT_HOST` (broker) VÀ `BACKEND_WS_HOST` (WebSocket audio tới backend Go, cổng 8080) — cả hai đổi từ `192.168.1.120` sang `192.168.1.125`.
- `pio run -t upload -e esp32s3_kws --upload-port /dev/ttyUSB0` — SUCCESS 137s.
- Verify qua log broker Jetson: `voice-node` connect thành công.
- Còn lại: bước app Flutter — chưa làm.

## Kết quả thực thi (2026-08-25) — sleep-pad-node
- **Phát hiện quan trọng:** node này KHÔNG cấu hình MQTT_HOST qua `config.h` như radar-node/voice-node — `config.h` chỉ chứa pin UART cố định. Địa chỉ WiFi/MQTT lưu trong NVS, set qua **BLE provisioning từ app điện thoại** (xem `ble-provisioning.h`, `nvs-config.h`).
- Board attach qua `usbipd.exe attach --wsl --busid 2-1` (tự làm qua Windows interop), `/dev/ttyACM0`.
- `pio run -t upload -e c3supermini --upload-port /dev/ttyACM0` — SUCCESS 137s. Không đổi code vì không có gì cần đổi trong repo cho việc chuyển host.
- **Flash lại KHÔNG xoá NVS** — pad vẫn nhớ IP máy Windows cũ. Cần user tự pair lại qua app (màn hình BLE provisioning) trỏ MQTT sang `192.168.1.125` — nằm ngoài khả năng tự động hoá qua SSH/CLI, cần thao tác tay trên app.
- **Nguyên nhân sâu hơn phát hiện khi user hỏi "vẫn dính cấu hình cũ thì sao":** không phải NVS cũ trơ lì đơn thuần — `include/dev-config.h` (gitignored) build-cứng `DEV_MQTT_HOST="192.168.1.120:1884"` vào firmware, và code (`main.cpp`) tự nạp lại giá trị này vào NVS mỗi khi NVS trống, khiến `erase_flash` một mình không đủ — reflash xong lại tự "có creds" ngay, không bao giờ vào BLE provisioning.
- User chọn: **xoá hẳn `dev-config.h`** (không sửa IP) để khôi phục đúng luồng BLE pairing thủ công. Sau khi xoá file, build lại + `erase_flash` + reflash lần 2 — verify qua serial boot log: `[Boot] No WiFi credentials - starting BLE provisioning`, advertising `SleepPad-90440C`. Đúng như kỳ vọng.
- Bảng thông tin đưa cho user để pair qua app: WiFi `mp`/`Zxcasdqwe123`, MQTT host `192.168.1.125`, port `1884` (khác cổng radar-node `1883`), user/pass để trống (broker sleeppad không bật auth).
- User pair tay qua nRF Connect (ghi 6 characteristic) — pad connect broker thành công (`CNU190440C` trong log `sleeppad-mosquitto`), nhưng **frame bị drop im lặng** vì `devices` table trống — pairing MQTT-level (BLE) và pairing tài khoản (API `/devices/pair`, cần JWT) là **2 việc tách biệt**, đúng cảnh báo đã ghi trong brainstorm 260820 ("thiết bị chưa pair thì mọi frame bị drop im lặng").
- Phát hiện thêm: `app/smartbed` (app đang test) KHÔNG có màn hình pair sleep-pad — màn đó nằm ở `app/sleep-pad` (project Flutter riêng, có `ble_provision_*` screens đầy đủ). Build APK app này gặp 2 lỗi thiếu credential thật không tự bịa được: `google-services.json` (Firebase — tắt tạm plugin trong `build.gradle.kts`, dùng `firebase_options.dart` đã có config thật thay thế) và release keystore (chuyển sang build `--debug`).
- File debug APK quá lớn để gửi qua tool kể cả sau `--split-per-abi` (~96-117MB > giới hạn 30MB) — để tại `app/sleep-pad/build/app/outputs/flutter-apk/`, user tự lấy qua đường dẫn Windows `D:\smartbedv3\...` (repo nằm trên ổ D:).
- **Quyết định cuối:** theo yêu cầu user ("không cần auth, đang test mà") — bỏ qua việc cài app/sleep-pad để pair qua UI, **INSERT thẳng SQL** vào Jetson: tạo 1 user test (`test@jetson.local`) + 1 row `devices` gắn `CNU190440C` vào user đó. Verify ngay: `sec_data` có 10 dòng, timestamp mới nhất khớp thời gian thật — xác nhận toàn tuyến pad → broker → FastAPI → TimescaleDB hoạt động đầy đủ trên Jetson.

## Kết quả thực thi (2026-08-25) — app Flutter
- **Phát hiện quan trọng, khác giả định ban đầu của plan:** `app_config.dart` (`API_BASE_URL` cho backend chính) chỉ có fallback generic (`10.0.2.2:8000`, dành cho emulator), KHÔNG hardcode IP laptop — không cần sửa file này.
- File thật cần sửa là `app/smartbed/lib/features/radar/providers.dart`: `kDefaultBaseUrl` (`http://192.168.1.120:8080`) và `kDefaultMqttHost` (`192.168.1.120`) — 2 hằng số Dart hardcode IP laptop cũ làm default khi không truyền `--dart-define`.
- Đã sửa cả 2 sang `192.168.1.125` (Jetson), cùng comment liên quan.
- Đã sửa thêm 2 chỗ hint text UI trong `settings_screen.dart` (không phải giá trị thật, chỉ placeholder gợi ý) để nhất quán.
- Verify: `grep` toàn bộ `app/smartbed/lib/` không còn `192.168.1.120`.
- Không cần rebuild app ngay — user hiện tại đổi qua màn Cài đặt vẫn hoạt động (ghi đè runtime); sửa default chỉ có tác dụng cho lần cài mới/reset app sau này.
- User sau đó yêu cầu build APK mới — `flutter build apk --release` thành công, 60.7MB (không gửi qua tool được, vượt 30MB, để tại `build/app/outputs/flutter-apk/app-release.apk`).
- **Bug phát hiện qua test thật trên app (LDPlayer):** app báo "Không đọc được backend — HTTP 503" khi trỏ `http://192.168.1.125:8080/api`. Nguyên nhân: `cloud/presence-ac/.env` có `POSTGRES_URL` trỏ `host.docker.internal:5432` — không tới được Postgres thật (TimescaleDB của Hệ B đổi sang cổng **5433** ở Phase 3, khác network Docker). Backend Go tự tắt hẳn `/api/sessions*` khi ping Postgres lúc khởi động thất bại.
- Fix: sửa `POSTGRES_URL` trong `.env` (trên Jetson) trỏ `192.168.1.125:5433` (IP LAN Jetson + cổng thật), rồi `docker compose up -d --force-recreate backend` (không dùng `restart` — không nạp lại `.env`). Verify log: `sleep sessions pg=postgres://...@192.168.1.125:5433/sleeptech`, không còn warning tắt sessions.

## Phát sinh sau khi phase đóng (2026-08-25, cùng ngày)
- Debug sâu `uart_ok=false` phát hiện **GPIO33 trên board S2 Mini hỏng vật lý** (không phải GND/baud/code như nghi ban đầu — loại trừ từng bước: đo thông mạch GND/TX/RX đều tốt, module xác nhận sống qua app HLK-LD2410 BLE độc lập, code `uart_set_pin` đúng thứ tự tham số).
- Đổi chân nhận UART từ GPIO33 sang **GPIO35** — `raw_bytes/2s` từ 0 lên 460 ngay lập tức, `uart_ok:true`, đọc được số liệu thật (`still_dist_cm`, `still_energy`).
- Đã cập nhật: `firmware/radar-node/src/main.c` (`PIN_RADAR_RX`), `firmware/radar-node/platformio.ini` (comment sơ đồ dây), `docs/presence-ac/system-wiring.md` (bảng wiring). Đã xoá code chẩn đoán tạm (`diag_raw_bytes_2s`/`diag_frame_resets_2s`) sau khi hết bug.
- **Việc vật lý cần làm khi có dịp:** dây TX của cảm biến LD2410C hiện đang nối vào GPIO35 trên board thật — không phải việc phần mềm, ghi chú lại để không nhầm khi bảo trì sau này.

## Risk Assessment
- Quên flash 1 node → node đó không lỗi biên dịch, chỉ không kết nối được, dễ tưởng nhầm là "đã xong" — checklist rõ từng node trước khi coi phase hoàn thành.
- Sai `MQTT_PORT` giữa 2 hệ (1883 vs 1884) khi sửa nhầm node → publish vào broker sai hệ, dữ liệu "biến mất" khỏi DB mong đợi.
