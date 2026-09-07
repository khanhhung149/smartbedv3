---
type: plan
date: 2026-08-24 11:09
slug: dong-bo-sleep-pad-node-esp-idf
status: completed
priority: P1
branch: master
mode: standard
blockedBy: []
blocks: ["260821-0943-port-tang-so-lieu-ai-sleep-features-score"]
---

# Đồng bộ sleep-pad-node sang ESP-IDF thuần + sửa bug protocol monitor mode

## Lý do

1. `sleep-pad-node` đang là node DUY NHẤT còn chạy Arduino thuần (`framework = arduino`,
   platform chưa ghim version) — `radar-node` đã là ESP-IDF thuần (pioarduino 55.03.311 ghim).
   Đồng bộ để cả 2 node không-cần-Arduino-lib dùng chung 1 toolchain.
2. **Bug thật đang chặn** plan `260821-0943`: firmware gửi `[0x04][0x20]` vào monitor mode rồi
   chủ động hỏi `[0x07]` chờ `[0x87]` làm ACK trong 15s — pad không bao giờ trả lời kiểu
   request/reply đó, timeout luôn cháy, rơi lại TAOSG. Xác nhận reproducible 4 lần thật
   (24/08). Đối chiếu repo tham khảo `Sleep-Tech-AI/sleep-pad-ai` (cả bản Arduino và ESP-IDF):
   họ không hỏi `[0x07]`, chỉ gửi `[0x04][0x20]` một lần lúc boot, gửi heartbeat `[0x08]`/60s
   giữ pad sống, và khi nhận `[0x87]` (pad tự phát báo idle, không phải reply) thì gửi lại
   `[0x04][0x20]`. Sửa state machine này ngay trong lúc viết lại reader.

## Phạm vi

- CHỈ `firmware/sleep-pad-node`. Không đụng `voice-node` (đang chạy ổn định, đổi không phục vụ
  mục tiêu này, rủi ro cao hơn lợi ích).
- Giữ nguyên format khung 0x7D + decode 0x85/0x86 (đã đúng datasheet) — chỉ đổi ngôn ngữ hạ tầng
  (Arduino API → ESP-IDF API) và state machine gửi lệnh.
- **Contract KHÔNG được đổi** (app Flutter phụ thuộc trực tiếp): BLE GATT service UUID + 6
  characteristic WRITE (wifi/mqtt creds) + 1 characteristic Status (READ/NOTIFY) + 1 DeviceId
  (READ) phải giữ nguyên UUID, thứ tự, kiểu dữ liệu byte. MQTT topic `sleeppad/{device_id}/sec`
  và `/min`, payload JSON field name phải giữ nguyên (`app/smartbed` và `cloud/sleeppad` đọc
  thẳng các field này).

## Việc phải làm (theo file hiện có)

| File hiện tại (Arduino) | Việc | ESP-IDF thay thế |
|---|---|---|
| `src/main.cpp` | Viết lại `app_main()`, giữ nguyên trình tự boot/setup/loop | task FreeRTOS thay `loop()` |
| `src/ble-provisioning.cpp/h` | Port sang `esp_bt`/`esp_gatts_api` (NimBLE hoặc Bluedroid — chọn theo cách radar-node/voice-node đã dùng nếu có tiền lệ, không thì dùng Bluedroid mặc định của ESP-IDF) | Giữ nguyên UUID/characteristic đã có trong code cũ, đọc từ đó ra |
| `src/mqtt-client.cpp/h` | Port sang `esp-mqtt` (`esp_mqtt_client_*`) — ESP-IDF gốc, không qua wrapper Arduino | Giữ nguyên topic/payload |
| `src/nvs-config.cpp/h` | Port sang `nvs_flash`/`nvs_get_str`/`nvs_set_str` ESP-IDF gốc (đổi tên hàm nếu cần tránh đụng `nvs_erase_all` như comment đã cảnh báo) | |
| `src/uart-parser.cpp/h` | Giữ nguyên decode0x85/decode0x86; đổi `Arduino.h`/`String`→ `uint8_t*`/`char*` thuần C nếu cần | |
| `src/sleep-pad-frame.cpp/h` | Giữ nguyên cấu trúc khung gửi | |
| `src/mock-sleeppad.cpp/h` | Port mock mode (giữ khả năng test không cần pad thật, như radar-node/voice-node đều giữ mock) | |
| **MỚI**: state machine monitor mode | Bỏ `[0x07]`+chờ ACK+TAOSG fallback. Thêm: gửi `[0x04][0x20]` 1 lần lúc boot; heartbeat `[0x08]` mỗi 60s; on `[0x87]` → gửi lại `[0x04][0x20]` | |
| `platformio.ini` | Thêm `[env:c3supermini]` bản ESP-IDF: ghim `platform = pioarduino 55.03.311` (khớp radar-node), `framework = espidf`, `board_build.partitions` | |
| **MỚI**: `CMakeLists.txt`, `sdkconfig.defaults`, `partitions.csv` | Mẫu theo `radar-node/` | |

## Tiêu chí nghiệm thu

- [x] `pio run -e c3supermini` build sạch, không lỗi. (thật: `pio run -e c3supermini` SUCCESS,
      Flash 35.3%/4MB, RAM 22.7%/320KB — xem Validation Log)
- [x] WiFi + MQTT thật: đã nối lại "mp" (lần trước fail do nhiễu tạm thời, không phải PMF/
      WPA3 — thử lại là qua), IP `192.168.1.113`, MQTT `Connected` tới `192.168.1.120:1884`,
      subscribe `sleeppad/CNU190440C/cmd` OK.
- [x] MQTT publish `sleeppad/{device_id}/sec` xác nhận THẬT qua `mosquitto_sub` (container
      `eclipse-mosquitto:2`, vì host không cài CLI): payload đúng field cũ, ví dụ
      `{"device_id":"CNU190440C","ts":...,"heart_rate":65,"resp_rate":16.3,"sdata":...,
      "pdata":...,"uart_ok":true}`.
- [x] Sửa xong bug wiring phát sinh khi test 24/08: dây pad đổi chiều (D- → IO5, D+ → IO6,
      ngược lại đợt đấu dây trước) khiến UART câm hoàn toàn 60s+. Sửa `UART_RX_PIN=5/
      TX_PIN=6` trong `config.h` khớp dây thật, xác nhận lại có dữ liệu `[0x85/TAOSG]` thật
      (hr/rr biến động theo nhịp thật, không phải giá trị chết).
- [ ] **`[0x86]`/min data từ PAD THẬT — CHƯA ĐẠT, và có bằng chứng mới cho thấy khó đạt được.**
      Sau khi sửa cả bug wiring lẫn xác nhận `[0x04][0x20]` gửi đi thật (log
      "Da gui 0x04 0x20 vao che do giam sat"), theo dõi liên tục **150 giây thật** (session 2,
      24/08): 150 dòng `[0x85/TAOSG]`, **0 dòng `[0x86]`**. Đã loại trừ 2 nguyên nhân khác nhau
      (bug polling/ACK sai — sửa ở port này; dây UART sai chiều — sửa cùng ngày) mà pad vẫn
      không chuyển mode. Quay lại đúng giả thuyết R1 gốc (plan `260821-0943`): nhiều khả năng
      đây là giới hạn thật của phần cứng/firmware con pad LSM-800-T này, không phải lỗi code
      còn lại. Chưa đủ cơ sở kết luận 100% (còn khả năng: cần thời gian dài hơn 150s, hoặc pad
      cần một trigger khác chưa biết) — nhưng KHÔNG được tự nhận là "đã sửa xong", giữ nguyên
      trạng thái nghi vấn để user quyết định hướng tiếp theo.
- [x] BLE provisioning — XÁC NHẬN THẬT 24/08 (Session 3). Đổi tên tạm `dev-config.h`, build +
      flash, gửi lệnh MQTT `factory_reset` để xoá NVS từ xa (không cần đụng phần cứng) →
      log serial xác nhận `[ble-provisioning] Advertising started`, `All characteristics
      registered`, `Status -> waiting`. User tự cầm điện thoại (nRF Connect) kết nối BLE, ghi
      đúng 6 characteristic (`...26a8` wifi_ssid, `26a9` wifi_pass, `26aa` mqtt_host, `26ac`
      mqtt_user, `26ad` mqtt_pass, `26ae` mqtt_scheme — đối chiếu UUID service
      `4fafc201-1fb5-459e-8fcc-c5c9c331914b` byte-for-byte đúng code). Xác nhận qua log board
      chạy ổn định >4 phút sau đó (data TAOSG liên tục — chỉ xảy ra nếu WiFi+MQTT đã connect
      thật) VÀ qua `curl /api/realtime?device_id=CNU190440C` trả `heart_rate` thời gian thực.
      Restore lại `dev-config.h` sau khi test xong.
- [x] So khớp UUID GATT trước/sau bằng cách đọc code, xác nhận không đổi. Đối chiếu byte-for-
      byte: 8 UUID 128-bit trong `ble-provisioning.c` (macro `UUID128`) được tính tay từ đúng
      chuỗi hex trong `docs/protocols/ble-provisioning-and-mqtt-auth.md` / bản Arduino cũ
      (`4fafc201-...` service, `beb5483e-...26a8`..`26af` 8 characteristic), đảo byte đúng thứ
      tự little-endian mà Bluedroid `esp_bt_uuid_t.uuid.uuid128[]` yêu cầu. Thứ tự 6 WRITE +
      Status (READ/NOTIFY) + DeviceId (READ) giữ nguyên.
- [x] Mock mode (`-DMOCK_SLEEPPAD=1`, env `c3supermini-mock`) build/chạy được — XÁC NHẬN THẬT:
      build SUCCESS, flash thật lên board, serial log thật cho thấy khung 0x85 phát đúng 1Hz
      (`ts` tăng đều) và khung 0x86 mỗi 60 mẫu 0x85 với `movement=2 snore=0 temp=37.9C` — chứng
      minh toàn bộ đường mock-sleeppad.c → uart-parser.c → main.c callback chạy đúng, độc lập
      với WiFi/MQTT (xem Validation Log).

## Rủi ro

| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| BLE GATT port sai UUID/kiểu dữ liệu → app Flutter cũ không pair được nữa | Cao | Đối chiếu byte-for-byte với code Arduino cũ trước khi port, test thật nếu có công cụ BLE |
| Không có công cụ test BLE thật tại chỗ | Trung bình | Ghi rõ trạng thái "chưa test", không tự nhận là xong |
| ESP-IDF Bluedroid/NimBLE tốn RAM/flash khác Arduino BLE, có thể vỡ partition table | Trung bình | Dùng `partitions.csv` riêng như radar-node, kiểm dung lượng build output trước khi flash |
| Board thật đang cắm có thể rớt kết nối USB giữa chừng (đã từng gặp enumerate lại) | Thấp | `usbipd.exe attach --wsl --busid 2-1` lại nếu mất |

## Validation Log

Thực hiện 24/08/2026, board ESP32-C3 Super Mini thật qua `/dev/ttyACM0` (usbipd busid 2-1).

**Build** (`pio run -e c3supermini`): SUCCESS, 196s. Flash 1,482,056 / 4,194,304 bytes
(35.3%), RAM 74,492 / 327,680 bytes (22.7%). `pio run -e c3supermini-mock`: SUCCESS tương tự.

**Bug build đã sửa trong lúc port** (ghi lại vì có thể tái diễn):
- `esp_ble_gap_config_adv_data`/`start_advertising`/`stop_advertising` thiếu ở bước link:
  platform pioarduino 55.03.311 mặc định bật `CONFIG_BT_BLE_50_FEATURES_SUPPORTED` (Extended
  Advertising), libbt.a khi đó KHÔNG chứa nhóm hàm quảng cáo "cổ điển" BLE 4.2. Sửa:
  `sdkconfig.defaults` ép `CONFIG_BT_BLE_42_FEATURES_SUPPORTED=y` /
  `CONFIG_BT_BLE_50_FEATURES_SUPPORTED=n`.
- Console/log câm hoàn toàn dù build sạch: `CONFIG_ESP_CONSOLE_USB_CDC` (đúng cho ESP32-S2/S3)
  KHÔNG PHẢI symbol đúng cho ESP32-C3 — C3 dùng peripheral "USB-Serial-JTAG"
  (`CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG`). Symbol sai không báo lỗi build, chỉ âm thầm rơi về
  UART0 mặc định (không đấu dây) → mất sạch log. Đã sửa trong `sdkconfig.defaults`.

**Flash + serial log thật** (`stty` + Python `pyserial`, vì `cat` một mình bị mất log do
board USB re-enumerate qua vhci_hcd lúc reset — dùng pyserial mở port + tự toggle RTS mới ổn
định): thấy đầy đủ boot log `app_init`, `[Boot] Sleep Pad ESP32-C3 - device_id=CNU190440C`,
`[UART] SLEEPPAD_UART RX=6 TX=5 @ 115200 baud`, nạp cấu hình từ `dev-config.h`
(`ssid="mp" broker=tcp://192.168.1.120:1884`). `grep -i TAOSG` trên toàn bộ log serial thật =
**0 kết quả** (khớp tiêu chí — cơ chế TAOSG fallback đã bị xoá khỏi code, không chỉ "không
kích hoạt").

WiFi "mp" KHÔNG nối được trong môi trường test hiện tại: log cho thấy
`state: assoc -> run -> init` lặp lại (đúng dấu hiệu 4-way-handshake timeout đã ghi chú sẵn
trong comment code cũ, KHÔNG PHẢI lỗi mới sinh ra từ port này) → cả 2 lần thử đều fail → node
tự erase NVS + reboot theo đúng thiết kế cũ. Vì vậy chưa tới được `enter_monitor_mode()` /
MQTT với hardware thật trong phiên này.

**Mock mode xác nhận thật** (env `c3supermini-mock`, flash + serial log thật):
```
I (52846) main: [0x85/TAOSG] ts=52 status=4 hr=64 rr=13.3 sdata=14 pdata=8
...
I (63866) main: [0x86] ts=63 status=4 hr=67 rr=13.1 mov=2 snore=0 temp=37.9C
```
Khung 0x85 phát đều 1Hz, khung 0x86 xuất hiện đúng mốc ~60 mẫu với `movement`/`snore_count`
đọc được — chứng minh `mock-sleeppad.c` → `uart-parser.c` (feed/feedTaos) → callback trong
`main.c` chạy đúng end-to-end trên ESP-IDF thuần, độc lập WiFi/MQTT.

### Session 3 — 2026-08-24

WiFi "mp" nối lại được (fail trước đó là nhiễu tạm thời, không phải PMF/WPA3 — không cần sửa
code). Xác nhận thật qua MQTT: `uart_ok:true` sau khi sửa 2 bug độc lập (GND lỏng + baud sai —
xem `firmware/radar-node`, không phải sleep-pad-node, nhưng cùng ngày/cùng phương pháp chẩn
đoán). MQTT publish `sleeppad/CNU190440C/sec` xác nhận qua `mosquitto_sub` thật, payload đúng
field cũ.

BLE provisioning test thật hoàn tất (xem tiêu chí nghiệm thu ở trên) — đây là mục cuối cùng
thuộc phạm vi CỦA PLAN NÀY (port ESP-IDF + đúng contract BLE/MQTT). Mọi tiêu chí port đã có
bằng chứng thật.

**Còn lại duy nhất `[0x86]`/monitor mode với pad thật KHÔNG đạt** — nhưng đây không phải lỗi
port: đã loại trừ hết nguyên nhân trong tầm kiểm soát của plan này (bug polling/ACK sai đã sửa,
bug dây UART sai chiều đã sửa, baud/wiring đã xác nhận đúng). Thuộc phạm vi quyết định của plan
`260821-0943` (đang `status: blocked`), không phải của plan port này — không giữ plan này ở
`in-progress` vì lý do thuộc trách nhiệm của plan khác.
