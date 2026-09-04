---
phase: 4
title: "Vân trang trí (4 vách) + chỉ dấu chiều mic + in ướm thật trên vo-hop-voice-radar.scad"
status: in-progress
priority: P1
dependencies: [2]
---

## Trạng thái implement (2026-09-04, cook)
Code + verify hình học (bước 1-7 của Implementation Steps) đã xong, đã qua code-reviewer độc lập
(2 fix áp dụng: gộp số trùng lặp `ir_hole_d`/`s2_usb_door_off`/`s2_usb_door_w` với cutout thật thay
vì lặp lại literal riêng; thêm `assert()` chặn keepout suy biến trong `van_doan_ho()`). **Việc còn
lại (bước 8-9: in ướm thật + lắp hardware thật + in sản xuất) là hành động vật lý, KHÔNG PHẢI việc
AI làm được** — chờ user tự thực hiện, xem `## Bàn giao cho user` cuối phase file.

# Phase 4: Vân trang trí (4 vách) + chỉ dấu chiều mic + in ướm thật

## Overview
Hoàn thiện `vo-hop-voice-radar.scad` (đã phục hồi làm bản chính thức, xem `plan.md` mục "Quyết
định đảo ngược lần 2") để đạt tiêu chuẩn "nhỏ gọn, đẹp, chi tiết" giống `vo-hop-sleeppad-c3.scad`:
khắc vân trang trí trên **cả 4 vách** (trước/sau — port mới, né cửa; hông trái/phải — port verbatim
từ bản C3, không cửa nào chắn), thêm chỉ dấu chiều lắp mic (external mark, xem quyết định dưới),
verify CGAL, in ướm thật 3 miếng, rồi mới in sản xuất `base()+lid()` đầy đủ.

**Đã verify bằng OpenSCAD headless thật** (không chỉ suy luận trên giấy) trong phiên lập plan —
xem `plan.md` mục "Verification Results (lần 2, validate)": toàn bộ code mẫu trong file này đã
render thử, `Simple: yes`, toạ độ đoạn hở đã echo đối chiếu đúng số. Cook chỉ cần copy đúng logic
vào file thật, không cần tự suy diễn lại từ đầu.

## Requirements
- Functional:
  - Vân trang trí khắc **cả 4 vách**: TRƯỚC (y=0) + SAU (y=out_l) — 2 mặt dài nhất
    (`out_w≈115.9mm > out_l≈87mm`, ngược tỉ lệ bản C3) — và HÔNG TRÁI/PHẢI (x=0, x=out_w) — không
    bị cửa nào chắn nên khắc trọn `out_l` (quyết định validate: thêm cho đối xứng/chi tiết hơn,
    không chỉ 2 vách như đề xuất ban đầu).
  - Không khắc xuyên qua **lỗ IR thật** (Ø6.5mm, KHÔNG PHẢI cả bề rộng module IR 20mm — quyết định
    validate: dùng đường kính lỗ LED thật vì vân nằm trên MẶT NGOÀI vách, module IR nằm sâu bên
    trong không chiếm diện tích mặt ngoài) hay cửa USB-C-S3 (vách trước)/cửa USB-C-S2 (vách sau).
  - Mic có chỉ dấu chiều lắp — xem mục Architecture #2, đã CHỐT phương án (không còn mở).
  - Giữ khớp bấm không vít (`vit_on=false`) — ĐÃ ĐÚNG hiện trạng, không phải việc mới.
- Non-functional:
  - Sau khi thêm vân + chỉ dấu mic, `assembly()`/`base()`/`lid()`/`test-s3()`/`test-s2()`/
    `test-radar()` **và** `test-radar-base-wall()` (module đổi tên ở `882d603`, xem lịch sử) vẫn
    phải qua CGAL `Simple: yes` trong FILE THẬT — mẫu cô lập đã verify sạch, nhưng khi union vào
    `base()` thật (có trụ góc, vách ngăn, cửa khác) vẫn phải render lại, không suy diễn từ mẫu cô
    lập là đủ.
  - Vách ngăn 2 khoang vẫn phải kín (0 khe hở) sau khi thêm vân — vân chỉ chạy trên 4 vách NGOÀI,
    không chạm `part_wall_t` (X∈[68.5,71.5], nằm giữa, không phải vách ngoài) — về lý thuyết không
    giao nhau, nhưng vẫn phải verify CGAL thật.
  - Không thêm miếng ướm test riêng cho mic (quyết định validate) — verify hốc mic + chỉ dấu ngay
    lúc in `lid()` đầy đủ, chấp nhận rủi ro phải in lại `lid()` nếu sai (xem Risk Assessment).

## Architecture

### 1. Vân trang trí — 4 vách, đã verify render thật

**Vách hông (trái/phải, x=0/out_w)** — port **verbatim** module `van_hong()` gốc từ
`vo-hop-sleeppad-c3.scad` (không cửa nào chắn ở đây, không cần logic né):
```openscad
van_y0 = post_d + 1;              // né góc bo tròn, giống bản C3
van_y1 = out_l - post_d - 1;

module van_hong() {
    for (z = van_zs)
        for (m = [[0, 1], [out_w, -1]])
            translate([m[0], van_y0, z])
                rotate([-90, 0, 0])
                    linear_extrude(van_y1 - van_y0)
                        polygon([[-m[1]*van_lo, -van_nho],
                                 [ m[1]*van_sau, 0      ],
                                 [-m[1]*van_lo,  van_nho]]);
}
```
Đã kiểm không đụng khớp bấm: `ranh_bam()` cắt rãnh ngang toàn bộ hông tại `bam_z_snap≈26.48` —
`van_zs=[9,16,23]` cách xa (mức cao nhất 23, hở 3.5mm), không giao nhau.

**Vách trước/sau (y=0/out_l)** — module mới `van_truoc_sau()`, đổi trục quay `rotate([0,90,0])`
(khác `rotate([-90,0,0])` của `van_hong()` vì cần extrude dọc X thay vì Y — **đã verify bằng STL
thật**: extrude dài đúng theo X, tiết diện V-groove đúng hướng cắt vào +Y/-Y tương ứng từng vách).
Né cửa bằng hàm cắt khoảng `van_doan_ho()` — **đã echo kiểm với số thật của file**, kết quả đúng
dự kiến (xem `plan.md` phần verify):

```openscad
/* ================= Vân trang trí (port từ vo-hop-sleeppad-c3.scad, 4 vách) ================= */
van_on = true;
van_sau = 0.8;                      // giữ nguyên bản C3
van_lo  = 0.5;                      // giữ nguyên bản C3
van_zs  = [9, 16, 23];              // 3 mức thay 2 — deck_h=30 cao hơn deck_h=22 của bản C3
van_nho = van_sau + van_lo;
van_margin_goc = post_d + 1;        // né 2 góc bo tròn
van_margin_cua = 2;                 // đệm thêm quanh mỗi cửa/lỗ

ir_hole_cx = ir_x + ir_w/2;         // tâm lỗ IR thật (đã có sẵn trong file, dùng lại)
ir_hole_d  = 6.5;                   // đúng số lỗ khoét thật (base(): "Lỗ LED IR xuyên vách trước")

// Vùng né vách TRƯỚC (y=0): CHỈ lỗ IR thật (Ø6.5, không phải cả bề rộng module 20mm) + cửa USB-C-S3.
van_keepout_truoc = [
    [ir_hole_cx - ir_hole_d/2 - van_margin_cua, ir_hole_cx + ir_hole_d/2 + van_margin_cua],
    [box_a_cx - s3_usb_open_w/2 - van_margin_cua, box_a_cx + s3_usb_open_w/2 + van_margin_cua],
];
// Vùng né vách SAU (y=out_l): cửa USB-C-S2.
van_keepout_sau = [
    [s2_x + s2_w/2 - 6 - van_margin_cua, s2_x + s2_w/2 + 6 + van_margin_cua],
];

// Cắt [x0,x1] thành các đoạn HỞ (bỏ phần giao với keepout) — ĐÃ TEST với số thật, xem plan.md.
function van_doan_ho(x0, x1, keepouts, i=0) =
    i >= len(keepouts) ? [[x0, x1]] :
    (keepouts[i][1] <= x0 || keepouts[i][0] >= x1) ? van_doan_ho(x0, x1, keepouts, i+1) :
    concat(
        keepouts[i][0] > x0 ? van_doan_ho(x0, keepouts[i][0], keepouts, i+1) : [],
        keepouts[i][1] < x1 ? van_doan_ho(keepouts[i][1], x1, keepouts, i+1) : []
    );

module van_truoc_sau() {
    for (z = van_zs)
        for (w = [[0, 1, van_keepout_truoc], [out_l, -1, van_keepout_sau]])
            for (seg = van_doan_ho(van_margin_goc, out_w - van_margin_goc, w[2]))
                if (seg[1] - seg[0] > 1)   // bỏ đoạn quá ngắn (mảnh vụn do phép trừ khoảng)
                    translate([seg[0], w[0], z])
                        rotate([0, 90, 0])
                            linear_extrude(seg[1] - seg[0])
                                polygon([[-van_nho, -w[1]*van_lo],
                                         [0,          w[1]*van_sau],
                                         [ van_nho, -w[1]*van_lo]]);
}
```
**Kết quả echo đã verify với số thật của file** (dùng làm tham chiếu, KHÔNG hardcode vào code —
biến sẽ tự tính lại nếu tham số linh kiện đổi):
- Vách trước: 3 đoạn hở `[9,15.6] [26.1,32.85] [61.35,106.9]` (đoạn nhỏ 2 bên lỗ IR + đoạn lớn
  bên phải cửa USB-C-S3) — cân đối hơn hẳn phương án dùng `ir_w` (bề rộng module) làm keepout, lúc
  đó chỉ còn 1 đoạn duy nhất `[61.35,106.9]`, mất nửa trái hoàn toàn.
- Vách sau: 2 đoạn hở `[9,84.2] [100.2,106.9]` (quanh cửa USB-C-S2).
- Render thử `union(van_hong(); van_truoc_sau())` độc lập: CGAL `Simple: yes`, 22 volumes — hình
  học mẫu hợp lệ. Vẫn phải render lại trong file thật (base() có trụ góc + vách ngăn khác) trước
  khi tin.

Gọi `if (van_on) { van_hong(); van_truoc_sau(); }` trong `difference()` của `module base()` — thêm
cạnh các lệnh khoét cửa khác, TRƯỚC `bo_goc_dung()`.

### 2. Chỉ dấu chiều lắp mic — ĐÃ CHỐT: khắc dấu ngoài + hướng dẫn lắp ráp (phương án b)
Hazard thật (`docs/presence-ac/system-wiring.md` mục 5 "Mic Orientation"): mic INMP441 tròn Ø10,
lỗi lắp ngược là **ÚP SAI MẶT** (mặt hàn chân phải hướng LÊN áp trần vỏ — khớp lỗ cổng âm Ø4 xuyên
ra ngoài — mặt chip MEMS hướng XUỐNG khoang trong), KHÔNG PHẢI lỗi xoay quanh trục Z.

**Đã tra cứu public specs INMP441** (Digi-Key datasheet, components101, easyelecmodule — xem
Sources trong hội thoại lập plan): không có tài liệu công khai nào mô tả layout/độ lệch tâm của
riêng biến thể board TRÒN Ø10 (đây là biến thể AliExpress/OEM nhỏ lẻ, không phải breakout 6-chân
chữ nhật phổ biến — 2 loại khác hẳn nhau, không dùng nhầm số liệu loại kia). **Không có cơ sở xác
nhận đặc điểm bất đối xứng vật lý nào (dây hàn lệch cạnh, lỗ lệch tâm) mà không cầm board thật lên
đo** — quyết định KHÔNG bịa toạ độ notch dựa trên suy đoán.

**Thêm nữa: 1 gờ/khe xoay quanh trục Z (D-cut kiểu keyway) BẢN CHẤT KHÔNG GIẢI QUYẾT ĐƯỢC hazard
này** — hazard là lỗi LẬT MẶT (flip quanh 1 trục nằm trong mặt phẳng board), không phải lỗi XOAY
(spin quanh trục Z). Một khoá xoay dù đúng vị trí cũng không ngăn được việc lật úp/ngửa board tròn
đối xứng. Vì vậy hướng "phương án (a): khoá cơ khí bằng gờ xoay" trong bản nháp trước của phase
này **bị loại bỏ hoàn toàn**, không phải vì thiếu số đo mà vì sai bản chất vật lý — không đáng đo
board thật chỉ để làm ra 1 thứ không giải quyết được vấn đề.

**Quyết định cuối**: khắc 1 dấu tam giác nhỏ (`label_deep`-style, nông ~0.4-0.6mm) trên MẶT NGOÀI
`lid()`, sát lỗ cổng âm Ø4 (`translate([mic_cx, mic_cy, -mic_boss_h-2]) cylinder(d=4, ...)` — cửa
sổ âm hiện có trong `module lid()`), chỉ hướng lắp bằng chữ khắc ngắn (nếu không gian đủ) hoặc chỉ
1 mũi tên đơn giản. Kèm 1 dòng comment trong file .scad ghi rõ quy trình lắp ráp thật: "mặt board
có in chữ/hàn chân đặt ÚP LÊN TRẦN vỏ (khớp dấu khắc ngoài + lỗ cổng âm), mặt chip MEMS trần
xuống khoang trong". Đây là hướng dẫn quy trình, không phải khoá cơ khí — chấp nhận rủi ro con
người quên đọc, xem Risk Assessment.

## Related Code Files
- Modify: `mech/presence-ac-enclosure/vo-hop-voice-radar.scad` (thêm `van_hong()` + `van_truoc_sau()`
  gọi trong `base()`; thêm dấu khắc chiều mic + comment quy trình lắp trong `lid()`)

## Implementation Steps
1. Thêm khối tham số + `van_hong()` + `function van_doan_ho()` + `van_truoc_sau()` vào
   `vo-hop-voice-radar.scad` (copy đúng code mẫu ở mục Architecture, đã verify sẵn — không viết
   lại từ đầu), gọi cả hai trong `difference()` của `base()`.
2. Thêm dấu khắc chiều mic + comment quy trình lắp vào `module lid()` theo mục Architecture #2.
3. `echo()` lại `van_doan_ho()` cho cả vách trước/sau NGAY TRONG FILE THẬT (không chỉ tin số đã
   verify ở mẫu cô lập — biến thật trong file có thể khác nếu ai đó sửa tham số linh kiện sau
   04/09) — đối chiếu với số tham chiếu ở mục Architecture.
4. Render `openscad -D 'part="assembly"' vo-hop-voice-radar.scad` — kiểm mắt vân 4 vách + dấu mic
   không đè lên cửa/lỗ nào, không lồi ra ngoài `out_w`/`out_l`.
5. Render CGAL từng phần, đọc log tìm `Simple: yes`/`Simple: no`:
   `base`, `lid`, `test-s3`, `test-s2`, `test-radar`, `test-radar-base-wall`
   (`openscad -D 'part="<tên>"' -o <ten>.stl vo-hop-voice-radar.scad`, kiểm output/log CGAL).
   Nếu bất kỳ phần nào `Simple: no` → áp dụng bài học "trụ tiếp tuyến" (`post_ov`-style lấn nhẹ),
   chỉnh `van_margin_cua`/`van_margin_goc` nếu đó là nguồn lỗi (không bịa số mới không có căn cứ).
6. Verify vách ngăn 2 khoang vẫn kín — chạy lại `probe()`-style intersection như phase-02 đã làm.
7. Xuất STL 3 miếng ướm: `test-s3`, `test-s2`, `test-radar` (dùng `part=` tương ứng, tên file rõ
   ràng, ví dụ `test-s3-ban-in-that.stl`).
8. **In ướm thật cả 3 miếng** (khác lần trước — lần đó chỉ verify hình học CGAL, chưa cầm nhựa
   thật ướm hardware). Cắm/lắp hardware thật (S3-CAM, S2 Mini, radar LD2410C) vào từng miếng in,
   xác nhận vừa khít, không cấn.
9. Sau khi cả 3 miếng ướm OK: render + in `base()` và `lid()` đầy đủ
   (`openscad -D 'part="base"' -o base.stl ...`, tương tự cho `lid`). Khi lắp thật, kiểm mic theo
   đúng dấu khắc + comment quy trình (bước này thay cho miếng ướm test mic riêng — xem Risk).

## Success Criteria
- [x] Vân khắc đủ 4 vách (trước/sau/hông trái/hông phải), vách trước/sau né đúng lỗ IR thật
      (Ø6.5, không phải cả module 20mm)/cửa USB-C-S3/cửa USB-C-S2 — verify bằng `echo()` đoạn hở
      TRONG FILE THẬT: vách trước `[[9,15.6],[26.1,31.85],[62.35,106.9]]`, vách sau
      `[[9,84.2],[100.2,106.9]]`.
- [x] CGAL `Simple: yes` cho cả 6 phần: `base`, `lid`, `test-s3`, `test-s2`, `test-radar`,
      `test-radar-base-wall` — verify lại sau khi áp dụng fix từ code-review, vẫn `Simple: yes`.
- [x] Vách ngăn 2 khoang vẫn kín — `probe("vach-ngan-kin")` trả về rỗng hoàn toàn.
- [x] Dấu khắc chiều mic + comment quy trình lắp đã thêm vào `lid()` — `mic_huong_khac()`, cách lỗ
      cổng âm 1.5mm (verify toạ độ bởi code-reviewer độc lập).
- [x] `base() ∩ ghosts()` (va chạm hardware) đối chiếu bit-for-bit với bản gốc trước khi sửa —
      giống hệt, không có va chạm mới do vân gây ra.
- [x] 3 file STL ướm đã xuất: `vo-hop-voice-radar-test-s3.stl`, `-test-s2.stl`, `-test-radar.stl`
      trong `mech/presence-ac-enclosure/`.
- [ ] **[CHỜ USER]** 3 miếng ướm in thật, hardware thật (S3-CAM, S2 Mini, radar LD2410C) lắp vừa —
      AI không in/lắp vật lý được, đây là việc thật user phải tự làm.
- [ ] **[CHỜ USER]** `base()`+`lid()` đầy đủ chỉ in SAU KHI cả 3 miếng ướm ở trên xác nhận OK.

## Bàn giao cho user
1. In 3 file `.stl` ở `mech/presence-ac-enclosure/vo-hop-voice-radar-test-{s3,s2,radar}.stl`.
2. Lắp thử S3-CAM, S2 Mini, radar LD2410C thật vào từng miếng — xác nhận vừa khít, không cấn.
3. Báo lại kết quả (vừa hay không, sai ở đâu nếu có) — nếu vừa, phase-04 mới chuyển `completed` và
   in `base()+lid()` đầy đủ; nếu không vừa, quay lại sửa số đo tương ứng rồi lặp lại bước 1-2.

## Risk Assessment
- Risk: mẫu cô lập (`union(van_hong();van_truoc_sau())`) đã CGAL sạch, nhưng khi union vào `base()`
  thật (có trụ góc, vách ngăn, cửa khác) vẫn có thể phát sinh lỗi tiếp tuyến mới do tương tác với
  hình học khác — bài học 04/09 (chính file này) đã gặp lỗi CGAL dù nhìn render đúng mắt. Giảm
  thiểu: bắt buộc render CGAL đủ cả 6 part trong FILE THẬT, không dừng ở mẫu cô lập.
- Risk: không có miếng ướm test riêng cho hốc mic (quyết định validate) — nếu chỉ dấu/hốc mic sai
  kích thước, phải in lại toàn bộ `lid()` (lớn, tốn thời gian hơn 1 miếng test nhỏ). Đây là đánh
  đổi user đã chấp nhận, không phải bỏ sót.
- Risk: chỉ dấu chiều mic là hướng dẫn quy trình (khắc dấu ngoài), KHÔNG PHẢI khoá cơ khí — không
  ngăn được người lắp quên đọc/bỏ qua dấu khắc. Đây là giới hạn vật lý thật (board tròn đối xứng,
  hazard là lỗi lật mặt không thể khoá bằng hình dạng hốc tròn), không phải thiếu sót thiết kế.
