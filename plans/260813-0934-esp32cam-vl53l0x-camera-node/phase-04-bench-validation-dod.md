---
phase: 4
title: "Bench validation & DoD"
status: pending
priority: P1
dependencies: [3]
---

# Phase 4: Bench validation & DoD

## Overview

Lắp node #6 lên bench rig cùng 5 cụm còn lại, chạy thật, verify các con số đã giả định ở Phase 2/3 (fps, dung lượng, khoảng cách), đóng DoD.

## Requirements

- Functional: node camera hoạt động ổn định cùng lúc với 5 cụm cảm biến khác trên cùng bench rig, không nhiễu lẫn nhau.
- Non-functional: đúng ranh giới riêng tư bench-test-only đã định nghĩa ở Phase 1/3.

## Architecture

Không đổi. Đây là bước tích hợp vật lý + đo đạc.

## Related Code Files

- Create: `docs/sensor-characterization.md` (nếu chưa tồn tại — file này là nợ từ Phase 01 gốc, DoD "Ghi lại giới hạn thực tế của từng cảm biến". Chỉ thêm mục cho node camera mới, không viết hộ 5 cụm còn lại — ngoài phạm vi plan này)

## Implementation Steps

0. **Bắt buộc trước mọi bước dưới đây:** xoá sạch thẻ SD (hoặc format lại) trước khi
   đo số liệu chính thức. Buổi bring-up 13/08 đã dồn ~4300 file vào 1 thư mục đêm qua
   nhiều lần flash lại — nghi ngờ có thật (chưa xác nhận 100%) là driver FAT quét thư
   mục lớn dần làm chậm việc tạo file JPEG mới, khiến fps đo được trong buổi đó
   (~0.45-0.65fps) không đại diện cho một đêm chạy sạch. Xem plan.md Bench Bring-up
   Log mục 12.
1. Lắp ESP32-CAM+VL53L0X lên bench rig, hướng vào vùng ngủ, đi dây gọn, tháo rời được (đúng yêu cầu modular chung của Phase 01).
2. Cấp nguồn riêng, xác nhận không rơi áp khi camera+SD ghi đồng thời (đo bằng đồng hồ vạn năng nếu nghi ngờ).
3. Chạy thử 30 phút ban ngày: verify fps thực tế, chất lượng ảnh đủ nhìn rõ tư thế người.
4. Chạy thử trong điều kiện tối/thiếu sáng giống pod thật ban đêm — OV2640 không có IR illuminator riêng (khác Phase 05), ghi nhận giới hạn thật (có thể ảnh rất tối/nhiễu — đây là dữ liệu characterization, không phải lỗi cần fix ở bench-test).
5. Chạy thử 8 tiếng liên tục 1 đêm (Hưng hoặc Michael tự nằm, giống Phase 01 gốc). Đo: dung lượng SD tiêu thụ thật so với ước tính ~5GB, số frame mất (nếu có), khoảng cách VL53L0X có hợp lý theo tư thế nằm/ngồi/rời giường không.
6. Giả lập rotation: tạo thêm 30+ thư mục đêm giả (đổi tên/ngày), verify firmware xoá đúng thư mục cũ nhất.
7. Verify ranh giới riêng tư: xác nhận WiFi không bật streaming trong lúc ghi chính thức (trừ khi bench-test live-view được bật thủ công và biết rõ đang bật).
8. Ghi kết quả vào `docs/sensor-characterization.md`: fps đạt được, độ trễ ghi SD, giới hạn ánh sáng thấp, tầm đo VL53L0X thực tế (datasheet ghi ~2m, verify thật trong khoang).

## Success Criteria

- [x] Build `BENCH_TEST_MODE=0` không link được hàm ghi SD/WiFi nào — **verify sớm ở Phase 3, không cần phần cứng**: `pio run -e esp32cam_production_check` build SUCCESS, `nm firmware.elf | grep storage_write_frame\|storage_init\|storage_rotate\|storage_open_night\|esp_wifi_connect` ra **0 kết quả** (đối chứng: cùng lệnh trên build `esp32cam` (BENCH_TEST_MODE=1) ra đủ 5 symbol). Env `esp32cam` chính (BENCH_TEST_MODE=1) cũng build SUCCESS — Flash 23.2%, RAM 14.9%.
- [ ] Ghi liên tục 8 tiếng trên **thẻ SD đã xoá sạch** (bước 0), dung lượng SD tiêu thụ khớp ước tính. **Kích thước JPEG đã đo thật: ~14.5KB/frame** (không phải 35KB giả định) — tính lại: 14.5KB × fps thật đo trên đêm sạch × 3600s × 8h. fps đo trong buổi bring-up (0.45-0.65fps) KHÔNG dùng làm số chính thức — nghi ngờ bị chậm do thư mục cũ tích luỹ quá nhiều file (chưa xác nhận), cần đo lại trên thư mục sạch
- [ ] Không có frame bị hỏng/corrupt trong 1 đêm test (spot-check ngẫu nhiên ≥20 file)
- [ ] VL53L0X cho khoảng cách hợp lý khi có người / không người / rời giường — **hiện tại luôn timeout/dropout**, cần chuỗi hiệu chuẩn ST đầy đủ mới đo được số thật (xem vl53l0x.h TODO); model_id đã xác nhận đúng (0xEE), chỉ đo khoảng cách chưa hoạt động
- [ ] Rotation 30 đêm hoạt động đúng khi giả lập — cần tạo tay ≥31 thư mục `YYYYMMDD` trên thẻ SD (rút thẻ ra đọc bằng máy tính, không làm được từ phiên làm việc này)
- [ ] `docs/sensor-characterization.md` có mục node camera với số liệu thật, không phải số ước tính
- [ ] Không phát hiện WiFi streaming ngoài ý muốn trong luồng ghi chính thức (runtime — khác với symbol-absence ở trên, cần phần cứng thật)

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Ảnh quá tối trong pod ban đêm, vô dụng cho training pose sau này | Chấp nhận là giới hạn đã biết (không có IR illuminator). Ghi rõ vào characterization; nếu Phase 05 sau này cần ảnh tối rõ, đó là lý do camera Phase 05 có IR riêng — không mở rộng scope node này |
| Nhiễu điện/cơ khí giữa 6 cụm cùng lắp trên rig | Test tuần tự từng cụm bật/tắt để cô lập nguồn nhiễu nếu phát hiện bất thường |
| Thẻ SD đầy giữa đêm nếu ước tính dung lượng sai | Log cảnh báo khi dung lượng còn <10%, dừng ghi an toàn thay vì crash |
