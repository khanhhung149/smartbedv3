---
phase: 1
title: "Xoá firmware + tài liệu cũ"
status: completed
priority: P1
dependencies: []
---

# Phase 1: Xoá firmware + tài liệu cũ

## Overview

Gỡ sạch node `esp32cam-node` (firmware, plan, docs) và sửa mọi tham chiếu chéo còn trỏ tới nó — gồm 3 file của plan MVP đang trỏ vào plan sắp xoá.

## Requirements

- Functional: sau phase này `grep` không còn kết quả về node cũ; không còn link chết.
- Non-functional: giữ nguyên `firmware/camera-node/` (thiết bị khác); giữ H-25; xoá H-26 kèm lý do rõ ràng.

## Related Code Files

**Delete:**
- `firmware/esp32cam-node/` — toàn bộ thư mục (gồm `src/vl53l0x.cpp`, `vl53l0x.h` đang dirty chưa commit; `storage.*`; `managed_components/`; `.pio/`)
- `plans/260813-0934-esp32cam-vl53l0x-camera-node/` — cả 5 file
- `plans/reports/brainstorm-260813-0923-thay-camera-nhiet-bang-esp32cam-vl53l0x-report.md`

**Modify:**
- `firmware/README.md` — bảng module: gỡ dòng `esp32cam-node/`, thêm `esp32cam-stream/`
- `docs/system-architecture.md` — dòng 199 (bảng sensor) + đoạn 206
- `docs/safety/hazard-analysis.md` — H-25 viết lại, H-26 xoá
- `plans/260713-1019-smartbed-v3-mvp/phase-00-nen-tang-kien-truc-an-toan.md:37`
- `plans/260713-1019-smartbed-v3-mvp/phase-01-cum-cam-bien-va-data-pipeline.md:29,35,59`
- `plans/260713-1019-smartbed-v3-mvp/phase-03-moi-truong-nhiet-anh-sang-am-thanh.md:22`

**Không đụng:**
- `firmware/camera-node/` — placeholder Phase 05, camera RGB+IR gắn Jetson
- `plans/260713-1019-smartbed-v3-mvp/phase-05-camera-edge-ai.md` — vẫn là chủ MediaPipe production

## Implementation Steps

<!-- Updated: Validation Session 1 - commit dirty code trước khi xoá; dùng scripts/check-doc-links.sh làm gate -->

0. ~~Commit `src/vl53l0x.cpp` + `vl53l0x.h` đang dirty trước khi xoá.~~ **Bỏ — Hưng quyết định 14/08 khi thực thi.** 408 dòng sửa chưa commit của `vl53l0x.cpp/h` bị xoá thẳng, không vào git history. Bản commit trước đó của 2 file vẫn còn trong history (commit `ea6e95b` trở về trước) nếu sau này VL53L0X quay lại. Quyết định này đảo lại kết luận validate session 1 — ghi ở đây để không ai tưởng là sơ suất.
1. `git rm -r firmware/esp32cam-node plans/260813-0934-esp32cam-vl53l0x-camera-node` + xoá report brainstorm cũ. Xác nhận `.pio/` đã trong `.gitignore` (dòng 15) nên không nằm trong index.
2. `firmware/README.md`: đổi dòng bảng thành `esp32cam-stream/ | amendment (thay esp32cam-node) | Stream MJPEG cho PoC vision, bench-test only, không ghi đĩa`. Giữ nguyên câu chốt toolchain `framework = espidf`.
3. `docs/system-architecture.md`:
   - Dòng 199: thay bằng mô tả node stream — camera OV2640, **không VL53L0X**, output là MJPEG stream LAN (không lưu, không qua MQTT bus, không vào capability manifest §5).
   - Đoạn 206: giữ lý do "cụm Camera nhiệt/MLX90614 bị thay vì mục tiêu thật là quan sát hành vi", đổi phần mô tả node sang stream, trỏ link sang plan mới `plans/260814-1237-esp32cam-stream-mediapipe-poc/`.
4. `docs/safety/hazard-analysis.md`:
   - **H-25 viết lại:** rủi ro giờ là *stream video LAN bị hiểu nhầm là chính sách production, hoặc bị truy cập từ thiết bị khác trong mạng*. Mitigation: node chỉ tồn tại giai đoạn bench-test; **không có code path nào ghi frame ra đĩa** (mạnh hơn bản cũ vốn ghi SD); stream chỉ trong LAN, mất khi tắt nguồn; không cần cờ `BENCH_TEST_MODE` vì không còn tầng lưu trữ để loại bỏ. Verify: `grep` toàn firmware không có API ghi file/SD.
   - **H-26 xoá:** thêm 1 dòng vào phần ghi chú/lịch sử của file nêu rõ H-26 được gỡ ngày 14/08 vì VL53L0X bị bỏ khỏi thiết kế → GPIO4 không còn bị I2C toggle → đèn flash không nhấp nháy. **Không xoá âm thầm** — người đọc sau phải biết vì sao nó biến mất.
5. Plan MVP — sửa 3 file:
   - `phase-00:37` — bảng quyết định: giữ "thay hẳn Camera nhiệt", đổi mô tả sang stream, trỏ link plan mới.
   - `phase-01:29` — dòng BOM: bỏ VL53L0X và mô tả 2 bus I2C; chỉ còn camera + WiFi stream.
   - `phase-01:35` — đoạn giải thích: đổi "chỉ ghi video giai đoạn bench-test" thành "chỉ stream LAN giai đoạn bench-test, không lưu"; trỏ link plan mới. Giữ nguyên câu về hệ quả Phase 03 mất MLX90614 (vẫn đúng).
   - `phase-01:59` — "6 cụm cảm biến (bao gồm node camera ESP32-CAM+VL53L0X)" → bỏ VL53L0X khỏi ngoặc.
   - `phase-03:22` — chỉ đổi tên plan được trỏ tới; nội dung quyết định bỏ MLX90614 giữ nguyên.
6. Chạy verify: grep + `./scripts/check-doc-links.sh` (script sẵn có trong repo, dùng nó thay vì tự kiểm link bằng mắt).

## Success Criteria

- [x] `firmware/esp32cam-node/` không còn tồn tại (gồm cả `.pio/`, `managed_components/`, `include/config.h` untracked). WiFi creds trong `config.h` đã sao lưu ngoài repo cho Phase 2 dùng lại
- [x] `firmware/camera-node/` vẫn là placeholder Phase 05, phạm vi không đổi. **Ngoại lệ (Hưng chốt 14/08):** dòng 3 của `README.md` — đoạn "Not to be confused with `firmware/esp32cam-node/`" — bị **xoá hẳn**, vì nó trỏ thư mục đã xoá và mô tả sai chính sách lưu trữ ("writes video to local SD"). Tiêu chí `git diff` trống ban đầu không lường được tham chiếu chết này
- [x] `grep -ri "esp32cam-node\|vl53l0x\|260813-0934" docs/ firmware/ plans/260713-1019-smartbed-v3-mvp/` → 0 kết quả. `MLX90614` **cố ý giữ** (bản ghi quyết định, xem `plan.md`)
- [x] `hazard-analysis.md` có H-25 phiên bản stream, không có H-26 trong bảng, và có mục "Retired hazards" giải thích H-26 bị gỡ vì sao + điều kiện nó quay lại
- [x] `./scripts/check-doc-links.sh` chạy sạch, không báo link chết
- [x] ~~Commit bảo toàn `vl53l0x.*`~~ — Hưng bỏ, xem bước 0

## Risk Assessment

| Rủi ro | Xử lý |
|---|---|
| Xoá mất `vl53l0x.cpp/h` đang dirty chưa commit | **Đã xảy ra, có chủ đích.** Hưng bỏ bước 0 khi thực thi 14/08 → 408 dòng sửa mất vĩnh viễn. Bản commit cũ của 2 file vẫn còn trong history. Xem bước 0 |
| Xoá H-26 làm mất bài học "GPIO4 = SDA + đèn flash trên AI-Thinker" | Bắt buộc ghi dòng lịch sử ở bước 4. Nếu sau này VL53L0X quay lại, hazard phải được phục hồi |
| Sửa plan MVP đang được người khác dùng (Michael/anh Khanh) | Thay đổi là làm khớp thực tế, không đảo quyết định sản phẩm. Không cần duyệt lại (theo tiền lệ quyết định #2 của plan cũ) |
| Sót tham chiếu ở file chưa quét | Verify bằng grep toàn repo, không chỉ 3 file đã biết |
