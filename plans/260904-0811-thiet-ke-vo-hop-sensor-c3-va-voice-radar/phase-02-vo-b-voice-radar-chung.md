---
phase: 2
title: "Vỏ B — voice-node + radar-node chung (2 khoang độc lập)"
status: pending
priority: P2
dependencies: []
---

# Phase 2: Vỏ B — voice-node + radar-node chung

## Overview
Viết `mech/presence-ac-enclosure/vo-hop-voice-radar.scad` thay `vo-hop-modular.scad` (thiết kế cũ gộp 1 board S2, đã lỗi thời) — 2 khoang điện độc lập (voice-node S3-CAM, radar-node S2+LD2410C) trong 1 vỏ chung, 1 nắp snap-fit.

## Requirements
- Functional: 2 khoang tách biệt vật lý, mỗi khoang 1 cổng nguồn USB-C riêng, không khối/dây nào bắc cầu giữa 2 khoang. Cửa mic có chỉ dấu chiều lắp. Radar đặt cách xa cổng USB-C (cả của chính nó lẫn của khoang voice-node nếu 2 khoang kề sát).
- Non-functional: qua checker AABB + CGAL volume, đặc biệt kiểm vách ngăn 2 khoang kín hoàn toàn (thể tích giao giữa 2 khoang = 0, không khe hở).

## Architecture
Xem `plan.md` mục "Kiến trúc chung". Cấu trúc:
```
[Khoang voice-node]  |  [Vách ngăn]  |  [Khoang radar-node]
  S3-CAM (65×26.5,        đặc, không     S2 Mini + LD2410C
  2 lỗ vít — tái          khe hở         (16×22×3, hốc+dán,
  dùng số cũ)                            tái dùng số cũ)
  cửa mic Ø10 (có                        cửa sổ radar mỏng
  chỉ dấu chiều)
  cửa IR LED 31×20
  cổng USB-C riêng                       cổng USB-C riêng
```
1 nắp chung trùm cả 2 khoang, khớp bấm kiểu Vỏ A (không vít).

## Related Code Files
- Create: `mech/presence-ac-enclosure/vo-hop-voice-radar.scad`
- Create: `mech/presence-ac-enclosure/kiem_va_cham_vo_hop_voice_radar.py` (dựa theo mẫu Phase 1, thêm kiểm tra riêng cho vách ngăn kín)

## Implementation Steps
1. Xác nhận lại vị trí thật của mic + IR module trên board S3-CAM dùng cho voice-node (board đổi mục đích từ camera sang mic+IR — vị trí lắp linh kiện ngoài PCB có thể khác giả định gốc trong `vo-hop-modular.scad`).
2. Copy khối `s3_*` từ `vo-hop-modular.scad` (đã đo, không đổi số) cho khoang voice-node.
3. Copy khối radar LD2410C từ `vo-hop-modular.scad` (16×22×3mm, hốc+dán, không lỗ vít) cho khoang radar-node.
4. Thiết kế vách ngăn đặc giữa 2 khoang — không khoét gì xuyên qua, kiểm bằng CGAL volume rằng 2 khoang không thông nhau.
5. Thiết kế cửa mic có gờ/vát định hướng — chỉ lắp được đúng 1 chiều (khớp hazard "Mic Orientation" đã ghi nhận).
6. Đặt module radar cách bất kỳ cổng USB-C nào **≥5mm** — đúng số trong hazard thật (`system-wiring.md` mục "LD2410 Module Placement Away From USB-C Port": hàn/đặt quá gần từng gây **chập điện với rail 5V**, không phải nhiễu điện từ).
7. 1 nắp chung, khớp bấm (`vit_on=false`) kiểu Vỏ A.
8. Copy + sửa checker Python, thêm kiểm tra vách ngăn kín.
9. Chạy CGAL volume check, xuất STL test-print.
10. Render `part="assembly"`, kiểm bằng mắt.

## Success Criteria
- [ ] 2 khoang điện tách biệt hoàn toàn — CGAL volume xác nhận vách ngăn kín (0 khe hở).
- [ ] Cửa mic không lắp được sai chiều (kiểm bằng hình học, ví dụ lỗ định hướng không đối xứng).
- [ ] Radar đặt cách mọi cổng USB-C ≥5mm (đúng số hazard thật, không phải ước lượng).
- [ ] Checker AABB + CGAL volume pass.
- [ ] STL test-print xuất được, 2-manifold.

## Risk Assessment
- Risk: vị trí mic/IR trên board thật khác giả định trong `vo-hop-modular.scad` (rủi ro đã nêu ở Bước 1) — nếu sai, phải đo lại thay vì tin file cũ.
- Risk: 5mm là ngưỡng tối thiểu ghi trong hazard cho lỗi chập điện đã từng xảy ra thật — không phải ngưỡng "an toàn tuyệt đối", nên thiết kế nới rộng hơn 5mm nếu bố cục cho phép.
