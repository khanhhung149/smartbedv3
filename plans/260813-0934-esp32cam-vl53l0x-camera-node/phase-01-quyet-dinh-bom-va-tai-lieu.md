---
phase: 1
title: "Quyết định, BOM & tài liệu"
status: completed
priority: P1
dependencies: []
---

# Phase 1: Quyết định, BOM & tài liệu

## Overview

Khoá quyết định BOM vào văn bản trước khi mua hàng/lắp — tránh lắp cụm cũ rồi tháo ra. Không viết code ở phase này.

## Requirements

- Functional: mọi tài liệu nhắc "Camera nhiệt" hoặc MLX90614 ở phạm vi Phase 01/03 phải phản ánh đúng quyết định mới.
- Non-functional: ranh giới riêng tư (video chỉ bench-test) phải bằng văn bản, không chỉ nằm trong đầu.

## Architecture

Không đổi kiến trúc 3 tầng. Node camera là MCU thứ 6 cùng tầng Safety/real-time (ESP32) như `sensor-node/`, nhưng không chạm actuator — không có yêu cầu an toàn real-time như `mech-handler/`.

## Related Code Files

- Modify: `plans/260713-1019-smartbed-v3-mvp/phase-00-nen-tang-kien-truc-an-toan.md` (bảng BOM, dòng "Camera nhiệt")
- Modify: `plans/260713-1019-smartbed-v3-mvp/phase-01-cum-cam-bien-va-data-pipeline.md` (bảng phần cứng, mục "Việc phải làm" #1, DoD nếu liên quan)
- Modify: `plans/260713-1019-smartbed-v3-mvp/phase-03-moi-truong-nhiet-anh-sang-am-thanh.md` (dòng 22, bỏ "và MLX90614 (thân nhiệt)")
- Modify: `docs/system-architecture.md` (§6.1 bảng cảm biến, dòng "Thermal / MLX90614")
- Modify: `docs/safety/hazard-analysis.md` (thêm hazard mới cho video lưu cục bộ — theo mẫu H-23)
- Modify: `firmware/README.md` (thêm dòng `esp32cam-node/` vào bảng module; cập nhật dòng toolchain cuối file)
- Modify: `firmware/camera-node/README.md` (thêm 1 dòng phân biệt với `esp32cam-node/` mới, tránh nhầm hai node)

## Implementation Steps

1. Sửa `phase-00-*.md`: dòng BOM "Camera nhiệt | Giữ | Thân nhiệt bề mặt" → "ESP32-CAM (OV2640) + VL53L0X | Thay hẳn Camera nhiệt/MLX90614 | Quan sát hành vi ngủ (bench-test), khoảng cách người-camera". Ghi chú 1 dòng: quyết định 13/08, lý do đảo (xem report brainstorm).
2. Sửa `phase-01-*.md`: bảng phần cứng — xoá dòng "Camera nhiệt / MLX90614", thêm dòng "ESP32-CAM (OV2640) + VL53L0X | SCCB (I2C, GPIO26/27) | Hướng vào vùng ngủ | Frame ảnh, khoảng cách". Mục "Việc phải làm" #1 sửa "5 cụm" → "6 cụm (bao gồm node camera)".
3. Sửa `phase-03-*.md` dòng 22: "đọc SHT (nhiệt độ + độ ẩm khoang) và MLX90614 (thân nhiệt) → điều chỉnh" → "đọc SHT (nhiệt độ + độ ẩm khoang) → điều chỉnh". Xoá mọi tham chiếu MLX90614 còn lại trong phase này nếu có.
4. Sửa `docs/system-architecture.md` §6.1: đổi dòng "Thermal / MLX90614 | I2C | Forehead/neck | Surface body temperature" → "ESP32-CAM (OV2640) + VL53L0X | SCCB (I2C) | Aimed at sleep area | Behavior video (bench-test only, local SD), distance-to-person". Thêm ghi chú 1 câu: video không đi qua bus MQTT/manifest — lưu cục bộ, không phải kênh dữ liệu thời gian thực của framework.
5. Sửa `docs/safety/hazard-analysis.md`: thêm hàng mới (ví dụ `H-25`) trong bảng "Information — the hazards that are not physical": Hazard = "Video hành vi ngủ lưu cục bộ trên node camera (bench-test) bị hiểu nhầm là chính sách sản xuất, hoặc rò rỉ nếu thẻ SD bị lấy đi"; Sev = **S2**; Mitigation = "Chỉ bật ghi khi cờ build `BENCH_TEST_MODE=1`; production build không có code path ghi ảnh ra đĩa (đúng 5 nguyên tắc riêng tư Phase 05); thẻ SD vật lý nằm trong bench rig có kiểm soát truy cập; không WiFi stream luồng ghi chính thức"; Phase = "amendment camera-node"; Verify = "Build production (`BENCH_TEST_MODE=0`), lục firmware xác nhận không có lệnh ghi SD nào chạy được".
6. Sửa `firmware/README.md`: thêm dòng `esp32cam-node/ | amendment (thay Phase 01 cụm camera nhiệt) | Chụp OV2640 + đo khoảng cách VL53L0X, ghi cục bộ SD, chỉ bench-test`. Đổi dòng cuối "Toolchain: PlatformIO (or ESP-IDF). Not chosen yet — Phase 00 task." → "Toolchain: PlatformIO với `framework = espidf` (không dùng Arduino framework) — theo tiền lệ `esp32-presence-ac/firmware/voice-node/`, chốt 13/08 khi thêm `esp32cam-node/`." Đây là quyết định của Hưng, đóng luôn câu hỏi tồn đọng của Phase 00 (không chỉ áp cho node camera).
7. Sửa `firmware/camera-node/README.md`: thêm câu đầu "Không nhầm với `firmware/esp32cam-node/` — node đó là thiết bị riêng cho Phase 01 (ghi video bench-test), khác cụm camera Phase 05 mô tả dưới đây."
8. Việc không-chặn (không block phase 2): báo Michael ngắn gọn về đổi BOM, ghi lại đã báo ở đâu (email/chat) — không cần chờ phản hồi để tiếp tục.

## Success Criteria

- [ ] `grep -rn "Camera nhiệt" plans/260713-1019-smartbed-v3-mvp/` chỉ còn xuất hiện trong ngữ cảnh lịch sử (nếu có), không còn ở bảng BOM/hardware đang hiệu lực
- [ ] `grep -rn "MLX90614" plans/260713-1019-smartbed-v3-mvp/phase-03-*.md` không còn kết quả
- [ ] `docs/safety/hazard-analysis.md` có hazard mới cho video, đủ 6 cột như các hàng khác
- [ ] `firmware/README.md` và `firmware/camera-node/README.md` không còn gây nhầm lẫn hai node
- [ ] `firmware/README.md` dòng toolchain không còn "Not chosen yet"

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Sửa nhầm lan sang phần khác của phase-00/01/03 (các cụm khác) | Chỉ sửa đúng dòng/đoạn liệt kê ở Implementation Steps, diff review trước commit |
| Hazard mới trùng ID với hazard tương lai khác thêm sau | Dùng ID kế tiếp thật tại thời điểm sửa (kiểm tra ID cao nhất hiện có trước khi đặt `H-25`), không cố định cứng số trong plan |
