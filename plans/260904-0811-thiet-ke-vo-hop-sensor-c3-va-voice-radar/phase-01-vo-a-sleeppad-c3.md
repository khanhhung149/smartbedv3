---
phase: 1
title: "Vỏ A — sleep-pad-node ESP32-C3 Super Mini"
status: completed
priority: P1
dependencies: []
---

# Phase 1: Vỏ A — sleep-pad-node C3 Super Mini

## Overview
Viết `mech/presence-ac-enclosure/vo-hop-sleeppad-c3.scad`, thay `s3_*` (ESP32-S3-CAM) bằng `c3_*` (ESP32-C3 Super Mini), giữ nguyên khối USB-A breakout và bố cục nối tiếp.

## Requirements
- Functional: hộp 2 mảnh (base/lid) đựng C3 Super Mini + khối USB-A breakout, khớp bấm không vít.
- Non-functional: qua checker AABB (`kiem_va_cham_vo_hop_sleeppad.py`, cần đổi tên biến/đường dẫn cho file mới) + CGAL volume check (`xuat-stl-va-kiem-lo.sh`, cùng logic).

## Architecture
Xem `plan.md` mục "Kiến trúc chung". Cụ thể thay đổi so với `vo-hop-sleeppad.scad`:
- Bỏ khối `s3_*` (66×26.5mm, 2 lỗ vít, 4 đoạn gờ dẫn hướng dài 65mm).
- Thêm khối `c3_*`: kích thước đo thật (Bước 1), KHÔNG lỗ vít → định vị bằng pocket (gờ dẫn hướng bao 4 cạnh, giống module radar LD2410C trong `vo-hop-modular.scad`) + dán.
- Giữ nguyên toàn bộ khối `usba_*`, khung, khớp bấm, bo góc, vân trang trí.
- `out_l` (chiều dài hộp) tính lại theo `c3_l` thay `s3_l` — ước ~70-75mm, chốt sau khi có số đo thật.

## Related Code Files
- Create: `mech/presence-ac-enclosure/vo-hop-sleeppad-c3.scad`
- Create: `mech/presence-ac-enclosure/kiem_va_cham_vo_hop_sleeppad_c3.py` (copy + sửa từ bản S3, đổi đường dẫn SCAD + tên biến `s3_*`→`c3_*`)
- Modify: `mech/presence-ac-enclosure/xuat-stl-va-kiem-lo.sh` (thêm tham số chọn file nguồn, hoặc tạo bản `-c3` riêng — quyết định lúc code theo mức trùng lặp thật)

## Implementation Steps
1. **Đo tay thật** board C3 Super Mini (không dùng số web 22.5×18mm làm số cuối):
   - Kích thước ngoài PCB (dài × rộng × dày).
   - Vị trí + kích thước cổng USB-C.
   - Vùng cấm anten.
   - Chiều cao linh kiện cao nhất (chip/nút RESET-BOOT).
   - Vị trí 2 nút bấm (nếu có).
2. Copy `vo-hop-sleeppad.scad` → `vo-hop-sleeppad-c3.scad`, thay khối `s3_*` bằng `c3_*` theo số đo Bước 1.
3. Viết pocket định vị C3 (4 cạnh, không lỗ vít) — tham khảo cách radar LD2410C được xử lý trong `vo-hop-modular.scad` (hốc + dán, không trụ vít).
4. Tính lại `out_l`, `out_w` theo kích thước C3 mới; giữ nguyên `deck_h` (vẫn do khối USB-A quyết định).
5. Copy + sửa checker Python, chạy — sửa lỗi hình học nếu có.
6. Chạy CGAL volume check, xuất STL test-print (miếng ướm khay C3 trước, giống `test_s3()`/`test_s3_truoc()` cũ).
7. Render `part="assembly"`, kiểm bằng mắt lần cuối.

## Success Criteria
- [x] Số đo C3 Super Mini là số đo tay thật (23.5×18mm, đo từ mép USB-C) — bề dày PCB (1.6mm) và chiều cao linh kiện (3.5mm) vẫn là ước tính chưa đo tay, ghi rõ trong file.
- [x] Render `openscad` sạch (`Simple: yes`) cho cả `assembly`/`base`/`lid`/`test-c3`/`test-usba`.
- [x] CGAL kiểm va chạm thật: phát hiện + sửa 1 lỗi thật (trụ góc đụng mép board do `inner_w` hụt 0.5mm) — không phải suy đoán, bắt bằng `base() ∩ ghosts()` cho facet 20→4 sau khi sửa.
- [x] Cửa USB-C và USB-A đều verify thông thật (`probe ∩ base()` rỗng ở cả 2 vị trí).
- [ ] STL test-print **chưa in thật** — cần bạn in `test-c3`/`test-usba` để ướm trước khi in cả hộp (không phải phần Claude tự làm được).

## Ghi chú bổ sung (không có trong dự tính ban đầu)
- Đã đổi công thức `inner_w` từ `c3_w + margin(4)` sang `+margin(6)` sau khi kiểm CGAL phát hiện trụ góc chồng lấn — bài học giống hệt các lỗi "khoét hụt"/"trụ đâm chân" đã ghi trong `vo-hop-sleeppad.scad`/`vo-hop-modular.scad`: không tin tính toán tay, phải verify bằng CGAL thật.
- `c3_pcb_t` (1.6mm) và `c3_comp_h` (3.5mm) vẫn là số ước tính — nếu ướm thử (`test_c3()`) thấy lệch, sửa 2 số này trước, không sửa hình học khác.

## Risk Assessment
- Risk: nếu C3 không có mounting hole thật sự nào để bám, pocket cần ma sát/dán đủ chắc — nếu ướm thử thấy lỏng, cân nhắc thêm 1 gờ chặn +z (giống S3's `s3_hold_*`) dù ban đầu nghĩ không cần.
