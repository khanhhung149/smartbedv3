---
phase: 2
title: "Vỏ B — voice-node + radar-node chung (2 khoang độc lập)"
status: superseded
priority: P2
dependencies: []
---

# Phase 2: Vỏ B — voice-node + radar-node chung

## ⚠️ QUYẾT ĐỊNH ĐẢO NGƯỢC 04/09 — ĐỌC TRƯỚC KHI DÙNG PHASE NÀY
Toàn bộ overview/architecture dưới đây dựa trên 1 nhận định SAI: cho rằng `vo-hop-modular.scad`
"dồn radar+mic+IR lên 1 board S2 duy nhất, đã lỗi thời". **Đọc lại code thật, đây là sai** —
`vo-hop-modular.scad` **đã có S3-CAM và S2 Mini là 2 board tách biệt, mỗi board 1 cổng USB-C
riêng** từ 31/07 (S3 qua tấm face — 2 cổng TTL/OTG, S2 qua vách sau — 1 cổng). Nguyên tắc
"2 board độc lập, không share nguồn" đã có sẵn trong bản cũ, không cần viết lại.

**Vấn đề thật duy nhất trong bản cũ** (tự bản đó ghi chú): cửa USB-C của S3 trên tấm `face()`
(`s3_usb_pitch=12.5`, `s3_usb_open_w=24.5`) là **số ƯỚC, CHƯA ĐO BẰNG THƯỚC, CHƯA IN ƯỚM**.

**Quyết định mới (04/09)**: quay lại dùng `vo-hop-modular.scad`, chỉ thêm miếng ướm test riêng
cho cửa USB-C của `face()` để verify/sửa số đo đó. **KHÔNG dùng `vo-hop-voice-radar.scad`** nữa
làm bản chính thức — file đó vẫn giữ lại làm tham khảo (đã build+verify CGAL sạch, nhưng chưa in
ướm thật lần nào, khác `vo-hop-modular.scad` đã in ướm phần lớn). Xem chi tiết ở
`phase-03-sua-cua-usbc-s3-ban-cu.md`.

---

## Overview (nội dung gốc — ĐÃ LỖI THỜI, giữ lại tham khảo)
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
- [x] 2 khoang điện tách biệt hoàn toàn — verify CGAL thật: `probe("vach-ngan-kin") ∩ base()` rỗng (vách kín, không khe hở).
- [x] Radar đặt cách mọi cổng USB-C ≥5mm — verify thật qua `echo()`: **49mm**, dư rất nhiều so ngưỡng tối thiểu.
- [x] Checker CGAL pass: `assembly`/`base`/`lid`/`test-s3`/`test-s2`/`test-radar` đều `Simple: yes`.
- [x] `base() ∩ ghost_*()` cho cả 4 linh kiện (S3, IR, S2, radar) đều rỗng sau khi verify — 2 facet ban đầu xác nhận là chạm biên vô hại (board tựa đúng đỉnh trụ đỡ), không phải va chạm thật (co ghost 0.1mm → rỗng hoàn toàn).
- [x] STL test-print xuất được cho cả 3 miếng ướm (test-s3, test-s2, test-radar), 2-manifold.
- [ ] Cửa mic có chỉ dấu chiều lắp — **CHƯA LÀM**, mic chưa được thêm vào thiết kế này (xem Ghi chú bổ sung).

## Ghi chú bổ sung (không có trong dự tính ban đầu)
- **Mic CHƯA được thêm vào `vo-hop-voice-radar.scad`** — phiên làm việc 04/09 tập trung xử lý lỗi hình học nghiêm trọng hơn (xem dưới) và hết ngân sách thời gian trước khi kịp thêm cụm mic (hốc dưới nắp, giống cách `vo-hop-modular.scad` làm). Đây là việc còn thiếu thật, không phải quên ghi — cần làm ở lượt sau.
- **Phát hiện lỗi CGAL quan trọng, áp dụng cho MỌI file .scad trong thư mục dùng trụ tiếp tuyến**: cylinder tiếp tuyến TUYỆT ĐỐI (chạm khít 0mm dư) với mặt phẳng vách làm `union()` ra `Simple: no` (không phải manifold hợp lệ) dù render nhìn vẫn đúng. Tái hiện tối giản: `cube([3,20,10]) + cylinder(d=8)` tiếp tuyến tại mép XA của cube → lỗi; lệch dù chỉ 0.01mm → hết lỗi. Sửa bằng cách cho trụ LẤN thêm `post_ov=0.15mm` vào vách thay vì tiếp tuyến khít — xem comment đầy đủ trong file. **Đáng chú ý: `vo-hop-sleeppad-c3.scad` (Phase 1) KHÔNG dính lỗi này** vì trụ ở đó tiếp tuyến đúng tại mép NGOÀI cùng (x=0), trùng với góc thật của khối hộp — chỉ tiếp tuyến tại mép XA (giữa 2 mặt song song của 1 vách) mới lỗi. Nếu sau này sửa `vo-hop-sleeppad-c3.scad` mà thêm trụ kiểu tương tự, cần áp dụng cùng cách sửa.
- **Bố cục IR+S3 đổi khác dự tính ban đầu**: bản đầu định "IR chồng vùng trước, lệch 1 bên" trong khoang hẹp — kiểm CGAL phát hiện đây là va chạm thật (IR đè lên vùng board S3 và cả 2 đè lên trụ góc). Sửa: **IR và S3 xếp CẠNH NHAU theo trục X** (không chồng), khoang A rộng ra `65.5mm` (từ dự tính 34.5mm ban đầu) để đủ chỗ. Khoang B cũng rộng ra `41.4mm` (từ 33.4mm) vì margin trụ góc ban đầu tính thiếu.

## Risk Assessment
- Risk: vị trí mic/IR trên board thật khác giả định trong `vo-hop-modular.scad` (rủi ro đã nêu ở Bước 1) — nếu sai, phải đo lại thay vì tin file cũ. IR đã verify không va chạm ở vị trí giả định, nhưng CHƯA đối chiếu với board thật.
- Risk: 5mm là ngưỡng tối thiểu ghi trong hazard cho lỗi chập điện đã từng xảy ra thật — thiết kế hiện tại đã đạt 49mm, dư rất nhiều, không phải rủi ro nữa.
- **Việc còn lại trước khi in**: thêm cụm mic (chưa làm), rồi mới in test-print + ướm thật.
