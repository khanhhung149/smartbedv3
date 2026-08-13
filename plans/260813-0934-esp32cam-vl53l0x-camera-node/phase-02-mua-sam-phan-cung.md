---
phase: 2
title: "Mua sắm phần cứng"
status: pending
priority: P1
dependencies: [1]
---

# Phase 2: Mua sắm phần cứng

## Overview

Chốt danh sách linh kiện thật, có giá, ra tổng chi phí — đúng nguyên tắc Phase 00 ("BOM có giá trước khi mua").

## Requirements

- Functional: đủ linh kiện để lắp và chạy node camera thứ 6 độc lập trên bench rig.
- Non-functional: nguồn riêng cho node (không lấy từ laptop/Jetson) — quy tắc phần cứng chuẩn dự án (H-20).

## Architecture

Không đổi kiến trúc. Đây là bước mua sắm thuần tuý.

## Related Code Files

- Không có file code. Output là danh sách mua hàng — có thể ghi tạm vào phần "Việc phải làm" của phase-01 gốc (`plans/260713-1019-smartbed-v3-mvp/phase-01-*.md`) nếu Hưng muốn track chung với BOM v3, hoặc giữ riêng ở đây. Không tạo file BOM riêng mới (repo chưa có `docs/bom.md` chính thức — theo `tien-do-phase-00` report, BOM có giá vẫn đang chờ Michael ở cấp toàn dự án).

## Implementation Steps

1. Mua **ESP32-CAM (AI-Thinker, OV2640)** — bo mạch phổ biến, giá tham khảo rẻ, có sẵn khe microSD tích hợp.
2. Mua **VL53L0X breakout** (I2C, mặc định địa chỉ `0x29`) — xác nhận breakout có sẵn pull-up I2C hoặc tự thêm 4.7kΩ nếu bus chưa có.
3. Mua **thẻ microSD 256GB, class 10/U3 trở lên**. Lý do dung lượng: SVGA 800×600 @ ~5fps × 8h/đêm ≈ 5GB/đêm, giữ rotating 30 đêm ≈ 150GB ổn định — 256GB để dư margin ghi/xoá liên tục không đầy sát nút.
4. Mua **nguồn 5V/2A riêng** cho ESP32-CAM (không dùng chung nguồn laptop/Jetson) — camera + ghi SD kéo dòng đỉnh cao hơn ESP32 thường lúc chụp+ghi đồng thời.
5. Format thẻ SD **exFAT** trước khi lắp (FAT32 giới hạn 4GB/file và thường bị Windows giới hạn format ở ~32GB — không đủ cho 256GB).
6. Ghi lại giá thật + nhà cung cấp vào bảng dưới, cộng tổng.

### Bảng mua sắm (điền giá thật khi mua)

| Linh kiện | Số lượng | Giá tham khảo | Nhà cung cấp | Ghi chú |
|---|---|---|---|---|
| ESP32-CAM (AI-Thinker, OV2640) | 1 | — | — | — |
| VL53L0X breakout | 1 | — | — | Địa chỉ mặc định `0x29` |
| MicroSD 256GB Class10/U3 | 1 | — | — | Format exFAT |
| Nguồn 5V/2A riêng | 1 | — | — | Không dùng chung laptop/Jetson |
| **Tổng** | | | | |

## Success Criteria

- [ ] Đủ 4 hạng mục trong tay (ESP32-CAM, VL53L0X, thẻ SD 256GB đã format exFAT, nguồn riêng)
- [ ] Bảng giá đã điền đầy đủ, tổng chi phí biết trước

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| VL53L0X breakout khác hãng có địa chỉ I2C mặc định khác `0x29` | Kiểm tra datasheet trước khi mua; hầu hết clone giữ `0x29` theo chip gốc ST |
| Thẻ SD tốc độ ghi không đủ cho SVGA @5fps liên tục | Chọn tối thiểu U3 (ghi tuần tự ≥30MB/s), dư rất nhiều so với nhu cầu thật (~175KB/s ở 5fps×35KB) |
