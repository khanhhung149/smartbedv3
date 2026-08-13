# Plan — Thay "Camera nhiệt / MLX90614" bằng ESP32-CAM (OV2640) + VL53L0X

- **Ngày lập:** 2026-08-13
- **Trạng thái:** in-progress — Phase 1 xong, Phase 2 xong (4/4 hạng mục, SD 16GB thay 256GB), Phase 3 **flash thật lên board thành công, camera+SD chạy ổn định** (VL53L0X chưa cắm dây), Phase 4 đang chạy dở (bench bring-up)
- **Nguồn:** `plans/reports/brainstorm-260813-0923-thay-camera-nhiet-bang-esp32cam-vl53l0x-report.md`
- **Loại:** Amendment — sửa BOM/docs của `plans/260713-1019-smartbed-v3-mvp/` (phase 00, 01, 03), không phải phase mới trong đánh số 00-07 chính thức
- **Rủi ro tổng:** thấp (không chuyển động, không actuator) nhưng **đảo một quyết định BOM đã chốt miệng 13/07** — xem §Quyết định đã khoá

## Quyết định đã khoá (từ brainstorm + hỏi lại khi lập plan)

| # | Câu hỏi | Quyết định |
|---|---|---|
| 1 | Thay hẳn hay thêm cụm mới? | **Thay hẳn** cụm "Camera nhiệt / MLX90614" (Phase 01) bằng node camera thứ 6: ESP32-CAM (OV2640) + VL53L0X |
| 2 | Báo Michael trước khi sửa docs? | **Không cần chờ duyệt lại** — Hưng chốt đây là quyết định kỹ thuật thuộc thẩm quyền mình. Vẫn để 1 việc không-chặn trong Phase 1: báo Michael song song, cho minh bạch |
| 3 | Bù thân nhiệt cho Phase 03 (mất input MLX90614)? | **Bỏ hẳn**, không thêm MLX90614 rời. Vòng kín điều hoà môi trường Phase 03 dùng SHT (nhiệt độ khoang) một mình |
| 4 | Video ghi thông số nào? | **SVGA 800×600, giữ rotating 30 đêm** — khớp chính sách retention DoD Phase 01 gốc. Kế hoạch ban đầu ~5fps (~5GB/đêm) → thẻ SD 256GB exFAT. **Cập nhật 13/08 sau bring-up thật:** fps đo được trên phần cứng thật chỉ ~1.5fps (~670ms/vòng lặp, chưa tối ưu, đã chốt chấp nhận — xem plan.md Bench Bring-up Log). Ước tính lại (JPEG size vẫn dùng số giả định ~35KB/frame, **chưa đo thật**): ~1.5GB/đêm → thẻ 16GB hiện có đủ cho **~10 đêm** trước khi rotation phải xoá, không phải ~3 đêm như tính với 5fps |
| 5 | Kiến trúc node | MCU riêng (node thứ 6). ~~VL53L0X dùng chung bus SCCB (GPIO26/27) của camera~~ **SAI — sửa 13/08 khi bring-up thật:** GPIO26/27 chỉ nối nội bộ tới đầu nối FPC camera, không ra header ngoài để hàn thêm dây. VL53L0X đi bus I2C **riêng** trên GPIO4 (SDA) + GPIO13 (SCL), địa chỉ `0x29` — 2 chân trống khi SD chạy 1-bit mode, verify bằng `esp_gpio_reserve` bitmask thật trên phần cứng (không chỉ đọc code). Tránh GPIO12 (bootstrap MTDI, rủi ro không boot) và GPIO16 (đã bị PSRAM chiếm CS) |
| 6 | Lưu trữ | microSD cục bộ trên chính node, **không stream WiFi cho luồng ghi chính thức**. Nguồn riêng, không lấy từ laptop (quy tắc phần cứng chuẩn dự án) |
| 7 | Ngoại lệ lưu video | **Chỉ áp dụng giai đoạn kỹ sư tự test (bench rig)** — cấm khi có người dùng thật, đối lập 5 nguyên tắc riêng tư Phase 05 (không lưu ảnh/video). Phải có cờ/flag rõ ràng trong code + ghi vào hazard-analysis.md |
| 8 | Toolchain firmware | **PlatformIO với `framework = espidf` thuần** (không Arduino) — theo tiền lệ `esp32-presence-ac/firmware/voice-node/` (project riêng của Hưng, tại `/mnt/d/esp32-presence-ac`). Đóng luôn câu hỏi tồn đọng "Not chosen yet" của Phase 00, áp dụng cho `esp32cam-node/` và cập nhật `firmware/README.md` |
| 9 | WiFi & timestamp | Cho phép WiFi **chỉ để NTP sync lúc boot**, tắt hẳn trước khi vào vòng ghi chính thức — tách rõ "đồng bộ giờ 1 lần" khỏi "streaming liên tục" đã cấm |
| 10 | SCCB bus dự phòng | Không mua I2C mux (TCA9548A) trước — YAGNI, xử lý bằng fallback giảm tần suất poll nếu xung đột thật xảy ra ở Phase 3 |

## Ghi chú kiến trúc quan trọng (phát hiện khi scout, không phải quyết định mới)

- **Trùng tên thư mục:** `firmware/camera-node/` đã tồn tại (placeholder cho Phase 05 — vai trò MCU phụ trợ camera Jetson, KHÔNG xử lý/lưu ảnh). Node mới là thiết bị khác hẳn (tự chụp, tự lưu). Dùng thư mục mới `firmware/esp32cam-node/`, không đụng `camera-node/`.
- **Chồng mục tiêu với Phase 05:** cả hai đều "quan sát hành vi lúc ngủ" nhưng khác tầng — node mới là công cụ debug/training-data thô cho kỹ sư (Phase 01, bench-test), Phase 05 là pipeline sản xuất chạy real-time trên Jetson, không lưu gì. Không gộp, không thay thế quyết định camera Phase 05 (RGB+IR). Rủi ro hiểu nhầm hai node là một — flag trong docs.
- **Report `schema-defect-analysis-260731-...`** đang treo, đề xuất sẵn schema DB mới (`env_temp_c`, `body_temp_c`, `radar_target`, view `takehome_csv`). Plan này **không đụng vào schema Jetson/DB** — video ở lại trên SD cục bộ của node, không đồng bộ Jetson trong MVP (YAGNI, đúng tinh thần "ngoại lệ bench-test"). Việc tích hợp video vào pipeline trung tâm để dành cho sau, ghi thành câu hỏi tồn đọng.

## Phases

| # | Tên | Ra được gì | Phụ thuộc | Trạng thái |
|---|---|---|---|---|
| [1](phase-01-quyet-dinh-bom-va-tai-lieu.md) | Quyết định, BOM & tài liệu | phase-00/01/03 + system-architecture.md + hazard-analysis.md cập nhật khớp quyết định | — | **completed** |
| [2](phase-02-mua-sam-phan-cung.md) | Mua sắm phần cứng | ESP32-CAM, VL53L0X, thẻ SD 256GB, nguồn riêng trong tay | Phase 1 (BOM chốt) | pending (hành động vật lý — Hưng tự làm) |
| [3](phase-03-firmware-node-camera.md) | Firmware node camera | `firmware/esp32cam-node/` chạy được: chụp + đo khoảng cách + ghi SD | Phase 2 | **in-progress** (code viết + build thật + code-review + fix xong; 4/5 Success Criteria cần phần cứng thật, xem Phase 4) |
| [4](phase-04-bench-validation-dod.md) | Bench validation & DoD | Node #6 lắp lên rig, chạy 1 đêm thật, DoD đóng | Phase 3 | pending (hành động vật lý — Hưng tự làm, 1 tiêu chí đã pre-verify tĩnh, xem phase file) |

## Phụ thuộc chéo với plan khác

- Sửa file thuộc `plans/260713-1019-smartbed-v3-mvp/` (phase-00, phase-01, phase-03) — không phải quan hệ block/blockedBy, là quan hệ **amends**. Thực hiện Phase 1 của plan này trước khi Phase 01 gốc (MVP) bắt đầu lắp cụm cảm biến, để tránh lắp xong rồi tháo ra.
- Không đụng Phase 05 (camera Jetson) — chỉ ghi chú làm rõ ranh giới trong docs.

## Tiêu chí chấp nhận (toàn plan)

- [x] BOM + docs (`phase-00`, `phase-01`, `phase-03`, `system-architecture.md`, `hazard-analysis.md`) phản ánh đúng quyết định, không còn nhắc "Camera nhiệt" hay MLX90614 ở Phase 01/03 theo nghĩa cũ — Phase 1, verify bằng grep
- [ ] Node camera thứ 6 chạy độc lập trên bench rig, ghi được ít nhất 1 đêm (8h) thật — chờ Phase 2 (mua phần cứng) + Phase 4
- [ ] Thẻ SD đúng dung lượng tính toán, format exFAT, rotation 30 đêm hoạt động (verify bằng cách giả lập >30 thư mục đêm) — logic đã build/verify tĩnh ở Phase 3, chưa test trên SD thật
- [x] Flag/ranh giới bench-test-only tồn tại rõ ràng trong code và trong `hazard-analysis.md` — Phase 3, verify bằng `nm`/symbol-check thật (xem Code Review Log)
- [ ] `docs/sensor-characterization.md` có mục cho node mới — Phase 4

| 11 | Toolchain version | Ghim `platform = espressif32@55.3.311` trong `platformio.ini` (không để mặc định resolve mới nhất) — bài học tự áp dụng từ chính Risk Assessment của phase-03, bị code review bắt sót ở lần viết đầu |

## Code Review Log

### Session 1 — 2026-08-13 (sau khi build 2 env lần đầu thành công)

**Trigger:** cook workflow Step 5 (mandatory) — spawn `code-reviewer` review 11 file firmware mới + 7 file doc đã sửa + `.gitignore`.

**Điểm ban đầu:** 5.5/10.

**Critical (đã sửa):**
- `main.cpp` dùng `esp_timer_get_time()` (uptime từ boot) làm epoch giây thay vì `time(nullptr)` (epoch thật sau NTP sync) → thư mục đêm luôn ra `19700101`, và `s_frame_seq` reset về 0 mỗi lần reboot ghi đè âm thầm lên frame đã ghi trước đó cùng ngày. Sửa: dùng `time(nullptr)`; thêm `recover_frame_seq()` trong `storage.cpp` scan thư mục đêm đã tồn tại để khôi phục seq thay vì luôn về 0.

**High (đã sửa):**
- `platformio.ini` không ghim version `platform = espressif32`, trái với Risk Assessment tự đặt ra trong `phase-03-firmware-node-camera.md`. Sửa: ghim `@55.3.311` (version đã build SUCCESS thật).
- Vòng lặp chính dùng `vTaskDelay` cố định không trừ thời gian xử lý → fps thực < TARGET_FPS. Sửa: deadline-based delay (trừ `elapsed_ms`).
- `sync_time_once_then_disable_wifi()` dùng `ESP_ERROR_CHECK` (abort/reboot) mâu thuẫn với comment "best-effort"; thiếu xử lý `nvs_flash_init()` gotcha kinh điển (`ESP_ERR_NVS_NO_FREE_PAGES`/`NEW_VERSION_FOUND` → erase+retry). Sửa cả hai, hàm giờ trả `bool time_synced` thay vì abort khi lỗi.

**Medium (đã sửa):**
- `.gitignore` thiếu `firmware/**/sdkconfig.*` (chỉ có `sdkconfig.old`) — node ESP-IDF thuần đầu tiên của repo mới sinh `sdkconfig.<env>`, gap trước giờ vô hình vì các node cũ dùng Arduino. Verify bằng `git add -n` trước/sau. Sửa.
- `storage_write_frame()`: lỗi `fopen(index.csv)` không tăng `s_frame_seq` → lần ghi kế tiếp ghi đè lên `.jpg` vừa ghi thành công. Sửa: tăng seq ngay sau khi jpg ghi OK, không phụ thuộc kết quả index.csv.

**Không sửa (chấp nhận là rủi ro đã biết, ghi lại):**
- SCCB dùng chung GPIO26/27 giữa camera driver và `i2c_driver_install(I2C_NUM_1,...)` — reviewer nghi ngờ có thể "cướp" GPIO-matrix route camera đã set. Không đủ bằng chứng để sửa mù (không có phần cứng thật để đo), giữ nguyên fallback đã ghi trong Risk Assessment phase-03 (giảm tần suất poll nếu xung đột thật).

**Verify lại sau khi sửa:**
- `pio run -e esp32cam` + `pio run -e esp32cam_production_check` — cả 2 SUCCESS (rebuild đầy đủ, không phải chỉ đọc log cũ).
- `nm firmware.elf` re-run trên cả 2 env: production_check vẫn **0 kết quả** cho `storage_*`/`esp_wifi_connect`/`recover_frame_seq`/`sync_time_once*`; bench-test có đủ symbol — ranh giới riêng tư còn nguyên sau khi sửa.
- `git add -n firmware/esp32cam-node/` — không còn `sdkconfig.*`/`config.h` trong danh sách sẽ commit.

**Unresolved sau review:** 0 (2 câu hỏi tồn đọng của reviewer — persist `s_frame_seq` qua NVS, và thời điểm ghim platform version — đã xử lý: recovery bằng scan thư mục thay vì NVS (đơn giản hơn, YAGNI), version ghim ngay).

## Câu hỏi tồn đọng (không chặn plan này, để lại cho sau)

1. Khi nào/làm sao đưa video vào pipeline trung tâm (Jetson) nếu Phase 05 sau này cần dữ liệu training thật — chưa thiết kế, chỉ ghi nhận.
2. Báo Michael về đổi BOM — không chặn, làm song song (xem Phase 1, việc không-blocking).

## Validation Log

### Session 1 — 2026-08-13
**Trigger:** `/ck:plan validate` ngay sau khi viết plan lần đầu
**Questions asked:** 4

#### Questions & Answers

1. **[Assumptions]** Firmware cần WiFi để NTP sync giờ lúc boot (Phase 3, step 5). Brainstorm nói "không stream WiFi realtime cho luồng ghi chính thức" — điều đó có cấm luôn WiFi cho mục đích đồng bộ giờ không?
   - Options: Cho phép WiFi chỉ để NTP lúc boot, tắt hẳn khi ghi (Recommended) | Không dùng WiFi luôn | Dùng RTC rời (DS3231)
   - **Answer:** Cho phép WiFi chỉ để NTP lúc boot, tắt hẳn khi ghi
   - **Rationale:** Tách rõ "đồng bộ giờ 1 lần" khỏi "streaming liên tục" — không thêm phần cứng, không vi phạm tinh thần điều khoản gốc
2. **[Architecture]** Toolchain cho `firmware/esp32cam-node/` mới. `firmware/README.md` tự ghi "Not chosen yet" cho toàn dự án — node này chọn gì?
   - Options: PlatformIO (Recommended) | ESP-IDF native | Arduino IDE thuần
   - **Answer:** ESP-IDF thuần
   - **Custom input:** "xem folder esp32-presence-ac tôi dùng thuần esp-idf thì firmware dùng esp-idf hết luôn"
   - **Rationale:** Scout `/mnt/d/esp32-presence-ac/firmware/voice-node/` xác nhận tiền lệ thật: PlatformIO vẫn là build orchestrator, nhưng `framework = espidf` thuần (không `arduino`, không mix) — khác các node cũ hơn (door/radar/room-node dùng `framework = arduino`). Áp dụng cho `esp32cam-node/`, đóng luôn câu hỏi tồn đọng toolchain của Phase 00 trong `firmware/README.md`
3. **[Risk]** Nếu SCCB bus dùng chung giữa camera và VL53L0X xung đột thật, có mua dự phòng trước ở Phase 2 không?
   - Options: Không mua trước, xử lý bằng fallback nếu gặp lỗi (Recommended) | Mua sẵn I2C mux (TCA9548A)
   - **Answer:** Không mua trước, xử lý bằng fallback nếu gặp lỗi
   - **Rationale:** YAGNI — brainstorm đã xác nhận địa chỉ I2C khác nhau (0x29 vs camera), rủi ro xung đột thấp
4. **[Scope]** Phase 1 có sửa `firmware/camera-node/README.md` (thuộc phạm vi Phase 05) để thêm 1 dòng phân biệt hai node không?
   - Options: Có, chỉ thêm đúng 1 dòng disambiguation (Recommended) | Không đụng file đó
   - **Answer:** Có, chỉ thêm đúng 1 dòng disambiguation
   - **Rationale:** Tránh nhầm hai node khác luật riêng tư, rủi ro thấp vì không đổi quyết định Phase 05 nào khác

#### Confirmed Decisions
- WiFi: chỉ cho NTP boot-sync, tắt khi ghi chính thức — bổ sung Quyết định #9 trong bảng plan.md
- Toolchain: PlatformIO `framework = espidf` thuần, theo tiền lệ `esp32-presence-ac` — bổ sung Quyết định #8, đóng câu hỏi tồn đọng Phase 00
- SCCB dự phòng: không mua trước — bổ sung Quyết định #10
- `firmware/camera-node/README.md`: trong phạm vi, chỉ 1 dòng — đã có sẵn trong Phase 1 step 7 từ bản viết đầu, không cần sửa thêm

#### Action Items
- [x] Phase 3: đổi PlatformIO+Arduino → PlatformIO `framework = espidf` thuần, cập nhật Related Code Files + Implementation Steps + Risk Assessment
- [x] Phase 1: cập nhật Implementation Step 6 để sửa luôn dòng toolchain trong `firmware/README.md`, thêm Success Criteria tương ứng
- [x] plan.md: thêm Quyết định #8/#9/#10

#### Impact on Phases
- Phase 1: thêm việc sửa dòng toolchain `firmware/README.md`
- Phase 3: đổi toolchain + timeline WiFi tắt trước khi ghi (đã cập nhật)

### Whole-Plan Consistency Sweep
- Files reread: `plan.md`, `phase-01-quyet-dinh-bom-va-tai-lieu.md`, `phase-02-mua-sam-phan-cung.md`, `phase-03-firmware-node-camera.md`, `phase-04-bench-validation-dod.md`
- Decision deltas checked: 4 (WiFi/NTP boundary, toolchain ESP-IDF, SCCB fallback, Phase 05 file scope)
- Reconciled stale references: 2 (Phase 3 toolchain section rewritten; Phase 1 step 6 + Success Criteria mở rộng cho dòng toolchain)
- Unresolved contradictions: 0

**Tier:** Standard (4 phases) — Fact Checker + Contract Verifier, xem bảng verification ở đầu phiên validate. Claims checked: 9, Verified: 8, Failed: 0, Unverified: 1 (external hardware fact, không phải lỗi plan).

**Khuyến nghị:** Sẵn sàng cho `/ck:cook` — không còn mâu thuẫn chưa giải.

## Bench Bring-up Log — 2026-08-13

Flash thật lên board AI-Thinker ESP32-CAM (đế ESP32-CAM-MB, USB-TTL CH340 qua WSL
usbipd) + đọc serial log thật (không phải build log). 8 bug/kiến trúc thật bắt được
(mục 4 bị mục 6 supersede), tất cả đã sửa/điều tra và verify lại bằng reflash + đọc log:

1. **I2C driver conflict** — `E i2c: CONFLICT! driver_ng is not allowed to be used
   with this old driver` → `abort()`, crash loop ngay khi boot. Nguyên nhân:
   `espressif/esp32-camera@2.1.7` dùng API I2C mới (`driver/i2c_master.h`,
   "driver_ng") cho SCCB nội bộ; `vl53l0x.cpp` ban đầu viết bằng API cũ
   (`driver/i2c.h`). ESP-IDF không cho 2 API tồn tại chung 1 firmware. **Sửa:** viết
   lại toàn bộ `vl53l0x.cpp` dùng `i2c_master_bus_config_t`/`i2c_new_master_bus`/
   `i2c_master_transmit_receive`.
2. **PSRAM chưa bật** — `cam_dma_config: frame buffer malloc failed`. Chip có 8MB
   PSRAM thật (log: `Found 8MB PSRAM device`) nhưng ESP-IDF không tự bật, cần
   `sdkconfig.defaults` (chưa tạo file này lúc viết skeleton). **Sửa:** thêm
   `firmware/esp32cam-node/sdkconfig.defaults` với `CONFIG_SPIRAM=y` +
   `CONFIG_SPIRAM_USE_MALLOC=y` + `CONFIG_SPIRAM_MODE_QUAD=y`.
3. **FatFs 8.3 filename** — `frame_000000.jpg` (12 ký tự tên) bị `fopen()` từ chối
   lặp lại mỗi frame, trong khi thư mục `20260813` (đúng 8 ký tự) vẫn mkdir bình
   thường — FatFs mặc định ESP-IDF chỉ hỗ trợ short filename 8.3, không có Long File
   Name. **Sửa:** thêm `CONFIG_FATFS_LFN_HEAP=y` vào `sdkconfig.defaults`.
4. **Kiến trúc chia sẻ bus SCCB sai (lần 1)** — `E i2c.common: I2C bus id(1) has
   already been acquired`. VL53L0X và camera **không thể mỗi bên tự tạo 1 bus
   i2c_master riêng** trên cùng GPIO26/27. **Sửa lúc đó:** VL53L0X tạo bus trước,
   camera dùng lại qua `SCCB_Use_Port()`. **⚠️ Superseded bởi mục 6 dưới** — cách sửa
   này đúng về mặt driver nhưng dựa trên giả định sai là GPIO26/27 hàn thêm dây được.
5. **JPEG "NO-SOI" ở vài frame đầu** — `cam_hal: NO-SOI - JPEG start marker missing`
   ngay sau init, do AEC/AGC chưa ổn định. **Sửa:** thêm vòng lặp chụp bỏ 3 frame đầu
   sau `esp_camera_init()` trước khi vào vòng ghi thật — kỹ thuật tham khảo từ
   [benlazzero/Esp32S3-and-VL53L0X](https://github.com/benlazzero/Esp32S3-and-VL53L0X)
   (`takeImage()` throwaway loop), xác nhận qua `/brainstorm` trước khi áp dụng.
6. **GPIO26/27 không ra header ngoài — kiến trúc "dùng chung bus SCCB" trong plan gốc
   SAI** — Hưng hỏi hàn thẳng dây vào GPIO26/27, verify bằng WebSearch xác nhận 2 chân
   này trên AI-Thinker **chỉ nối nội bộ tới đầu nối FPC camera**, không đưa ra header
   ngoài. Không thể hàn thêm dây VL53L0X vào đó. **Sửa (đảo lại kiến trúc mục 4):**
   camera quay về tự tạo bus riêng (`pin_sccb_sda=CAM_PIN_SIOD` như code gốc trước khi
   sửa mục 4), VL53L0X đi bus I2C **hoàn toàn độc lập** trên GPIO4 (SDA) + GPIO13
   (SCL), port 0 (camera dùng port 1 mặc định, xác nhận qua log `sccb_i2c_port=1`).
   Tránh GPIO12 (bootstrap MTDI — pull-up của VL53L0X có thể làm board không boot
   được) và GPIO16 (đã bị PSRAM chiếm làm CS).
7. **SDMMC giữ ngầm GPIO4/12/13** — `SDMMC_SLOT_CONFIG_DEFAULT()` điền sẵn d1/d2/d3 =
   GPIO4/12/13 (mặc định slot dù chỉ dùng 1-bit mode). **Sửa (phòng ngừa, chưa xác
   nhận là nguyên nhân thật):** set rõ `slot_config.d1/d2/d3 = GPIO_NUM_NC` trong
   `storage_init()`.
8. **Cảnh báo "GPIO not usable, maybe conflict"** khi VL53L0X init — điều tra bằng
   `esp_gpio_reserve(0)` (đọc bitmask, không reserve gì) in ra TRƯỚC khi
   `vl53l0x_init()` chạy: GPIO4/12/13 đều **chưa** bị giữ (chỉ GPIO16/PSRAM đã giữ,
   đúng dự kiến) — kết luận cảnh báo là driver tự reserve 2 lần trong chính nó (vô
   hại, không phải xung đột thật với thứ khác). Lỗi đọc VL53L0X (`Không đọc được bus
   I2C tại 0x29`) là do **VL53L0X chưa cắm dây vật lý**, không phải bug — kỳ vọng hết
   khi Hưng hàn xong.

**Kết quả sau khi sửa cả 5:** camera + SD ổn định qua nhiều lần reboot trong buổi
bring-up (seq tự khôi phục đúng: 0 → 1868 → 1912 qua các lần flash/reset, không ghi
đè). WiFi→NTP→tắt WiFi hoạt động đúng thiết kế (`time_synced=1`, IP thật
`192.168.1.119`, SSID `mp`). Thư mục đêm ra đúng ngày thật `20260813` (xác nhận bug
timestamp đã sửa ở vòng code-review trước đó hoạt động đúng trên phần cứng thật).

**Số liệu thật khác giả định trong plan:** fps thực đo được **~1.5fps** (~670ms/vòng
lặp), không phải 5fps mục tiêu ban đầu (§Quyết định #4). Chưa đo kích thước JPEG
thật để tính lại dung lượng/đêm — nhưng fps thấp hơn 3.3x nghĩa là ít frame hơn dự
kiến, có lợi cho giới hạn thẻ SD 16GB (xem phase-02). Nguyên nhân fps thấp — capture
JPEG SVGA + ghi SD trên thẻ 16GB — chưa phân tích sâu, để `docs/sensor-characterization.md`
ở Phase 4 xử lý.

**VL53L0X chưa cắm dây vật lý lúc bring-up này** — `vl53l0x_init()` fail có kiểm
soát (log rõ ràng, không gọi read mỗi vòng lặp), camera/SD không bị ảnh hưởng. Wiring
đúng (đã đảo sau phát hiện mục 6): VCC→3.3V, GND→GND, **SDA→GPIO4, SCL→GPIO13** — Hưng
được khuyên hàn thẳng (đáng tin cậy hơn jumper), chưa xác nhận đã hàn xong.

**File đổi trong bring-up này (chưa commit):** `src/vl53l0x.{h,cpp}`, `src/main.cpp`,
`src/camera_config.h`, `sdkconfig.defaults` (mới), `vl53l0x.h` TODO comment (tham
chiếu repo brainstorm).
