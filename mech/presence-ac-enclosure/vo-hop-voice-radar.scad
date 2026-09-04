// vo-hop-voice-radar.scad — Vỏ hộp CHUNG cho voice-node (ESP32-S3-CAM + mic + IR) và
// radar-node (S2 Mini + LD2410C) — 2 khoang điện ĐỘC LẬP trong 1 vỏ nhựa, mỗi khoang 1 cổng
// nguồn USB-C riêng (Michael 13/07: không share nguồn giữa các board).
//
// THAY THẾ vo-hop-modular.scad (thiết kế cũ dồn cả radar+mic+IR lên 1 board S2 duy nhất —
// đã lỗi thời từ khi docs/presence-ac/system-wiring.md 18/08 xác nhận kiến trúc 2-board-độc-lập
// thật: voice-node ESP32-S3-CAM và radar-node S2 Mini tách biệt hoàn toàn). File cũ GIỮ NGUYÊN
// làm tài liệu lịch sử, không xoá.
//
// KHÁC BIỆT CẤU TRÚC so với bản cũ: bản cũ 3 mảnh (base + face rời trượt rãnh + lid vít M3).
// Bản này 2 mảnh (base + lid khớp bấm, giống vo-hop-sleeppad-c3.scad) — quyết định 04/09.
// Cửa USB-C/IR khoét THẲNG vào vách base, không còn tấm face rời.
//
// SỐ ĐO LINH KIỆN: TÁI DÙNG NGUYÊN VĂN từ vo-hop-modular.scad (đã đo tay thật 24/07-31/07,
// không đo lại — xác nhận 04/09 board S3-CAM và radar LD2410C không đổi). Vị trí mic/IR trên
// board S3-CAM cũng giữ nguyên theo bản cũ — xác nhận 04/09.
//
// VẬT LIỆU: PETG, thành 3mm, FDM. Không in resin (lý do giống các file khác trong thư mục).

part = "assembly";   // "base" | "lid" | "assembly" | "layout" | "test-s3" | "test-s2" | "test-radar"

/* ================= S3-CAM (voice-node) — chép nguyên văn vo-hop-modular.scad ================= */
s3_w = 26.5;  s3_l = 65;
s3_pcb_t = 1.6;
s3_pin_drop = 8;
s3_stand = s3_pin_drop + 2;        // = 10
s3_usb_out = 1;
s3_usb_gap = 0.5;
s3_usb_pitch = 12.5;               // tâm-tâm 2 cổng USB-C (TTL trái, OTG phải)
s3_usb_w = 10;
s3_usb_plug_clear = 2;             // dùng số đã nghiệm thu ở vo-hop-sleeppad.scad (2, không phải
                                    // 1 như bản modular gốc — 1 từng gây thiếu hở, xem file đó)
s3_usb_open_w = s3_usb_pitch + s3_usb_w + 2*s3_usb_plug_clear;   // = 24.5
s3_usb_open_h = 8;
s3_hole_pitch = 23;
s3_hole_tol = 0.5;
s3_hole_to_end = 3;
m25_pilot = 2.1;

/* ================= IR module — chép nguyên văn ================= */
ir_w = 20;  ir_l = 31;
ir_rib_t = 3;
ir_rib_h = 5;
ir_axis_h = ir_rib_h + 4;

/* ================= Mic INMP441 — chép nguyên văn ================= */
mic_dia = 10;
mic_liner = 1.5;
mic_shelf = 1.5;
mic_boss_h = 7.5;

/* ================= S2 Mini (radar-node) — chép nguyên văn ================= */
s2_w = 25.4;  s2_l = 34.3;
s2_pitch = 20;
s2_pitch_tol = 0.5;
s2_hole_to_usb = 30;
s2_usb_gap = 1;
s2_stand = 6;

/* ================= Radar LD2410C — chép nguyên văn ================= */
radar_w = 16;  radar_l = 22;
radar_t = 3;
radar_fit = 0.4;
radar_rim = 1;
radar_hdr_h = 8.5;
radar_mem_t = 0.8;                 // nhựa chừa trên cửa sổ radar cho sóng 24GHz xuyên
radar_wire_w  = 14;
radar_wire_sh = 6;
radar_wire_h  = 1.5;

/* ================= Khung: 2 khoang + vách ngăn ================= */
// KHOANG A (voice-node): S3 (26.5) VÀ IR (20) nằm CẠNH NHAU (không xếp chồng — cả hai đều cần
// ra vách trước, S3 qua cổng USB-C, IR qua lỗ LED, nên không thể xếp nối tiếp theo Y như dự tính
// ban đầu). KHOANG B (radar-node): chỉ S2 (25.4).
//
// ⚠️ SỬA SAU KHI KIỂM CGAL THẬT 04/09: bản đầu `comp_a_inner_w = s3_w+8 = 34.5` và
// `comp_b_inner_w = s2_w+8 = 33.4` ĐỀU THIẾU — `base() ∩ ghosts()` phát hiện cả 3 (S3: 68 facet,
// IR: 82 facet, S2: 32 facet) đụng trụ góc hoặc đụng nhau THẬT (không phải chạm biên vô hại kiểu
// đã gặp ở vo-hop-sleeppad-c3.scad). Nguyên nhân: "+8" không đủ cho CẢ HAI trụ góc (mỗi trụ Ø8
// cần ~7.85mm từ mép khoang mới không đụng board), và IR+S3 bị đặt trùng vùng X. Công thức đúng:
// mỗi bên cần post_off - post_ov + post_d/2 ≈ 7.85mm margin, tức "+16" tối thiểu cho 1 board.
//
// Vách ngăn ĐẶC, không khoét gì xuyên qua — verify CGAL xác nhận (xem plan 260904-0811, rủi ro
// "vách ngăn phải kín, không được có khe hở").
wall = 3;  floor_t = 3;  lid_t = 3;
part_wall_t = 3;                   // bề dày vách ngăn giữa 2 khoang — bằng bề dày vách ngoài
comp_a_inner_w = ir_w + 3 + s3_w + 16;   // = 20+3+26.5+16 = 65.5 — IR + khe 3mm + S3 + margin trụ
comp_b_inner_w = s2_w + 16;              // = 41.4
deck_h = 30;                       // giữ nguyên bản cũ — đủ cao cho radar treo dưới nắp + S2 stand
post_d = 8;
post_off = post_d/2;
// post_ov: trụ LẤN thêm bấy nhiêu vào vách so với tiếp tuyến tuyệt đối — xem giải thích đầy đủ
// tại định nghĩa corner_centers_a()/corner_centers_b() bên dưới. Đặt sớm vì comp_a_safe_margin
// cần dùng biến này để tính vị trí IR/S3.
post_ov = 0.15;
m3_free = 3.4;                     // không dùng (vit_on=false) — giữ lại nếu cần bật vít sau
lid_lip_h = 4;
lip_w = 1.5;
lip_gap = 0.4;

/* ================= Khớp bấm (giữ tham số đã nghiệm thu ở vo-hop-sleeppad-c3.scad) ================= */
vit_on = false;
bam_cao = 0.7;
bam_dai = 10;
bam_vao_deg = 30;
bam_giu_deg = 45;
bay_w = 15;  bay_d = 1.5;  bay_h = 3;

$fn = 48;

/* ================= Toạ độ suy ra ================= */
// Bố cục theo TRỤC X: [vách ngoài][Khoang A - voice-node][vách ngăn][Khoang B - radar-node][vách ngoài]
comp_a_x0 = wall;
comp_a_x1 = comp_a_x0 + comp_a_inner_w;
part_x0   = comp_a_x1;
part_x1   = part_x0 + part_wall_t;
comp_b_x0 = part_x1;
comp_b_x1 = comp_b_x0 + comp_b_inner_w;
out_w = comp_b_x1 + wall;                                  // tổng bề rộng

// Chiều dài (Y) do board dài nhất quyết định — S3 (65mm) là board dài nhất trong cả 2 khoang.
// Giữ margin trước/sau giống bản cũ (mép trước cho IR+USB-C, mép sau cho đầu tự do bo).
out_l = wall + 6 + s3_l + 10 + wall;                        // ước: 3+6+65+10+3 = 87mm — có margin
                                                              // dư cho gờ dẫn hướng + cửa USB-C

box_b_cx = (comp_b_x0 + comp_b_x1)/2;

/* --- Khoang A: voice-node (S3 + mic + IR) — IR và S3 XẾP CẠNH NHAU theo X, cả hai đều ra
   vách TRƯỚC (S3 qua cổng USB-C, IR qua lỗ LED) --- */
// Vùng an toàn tránh trụ góc: mỗi bên chừa post_off - post_ov + post_d/2 ≈ 7.85mm từ mép khoang
// (xem giải thích ở comp_a_inner_w). IR bên TRÁI, S3 bên PHẢI, cách nhau khe 3mm.
comp_a_safe_margin = post_off - post_ov + post_d/2;   // ≈ 7.85
ir_x = comp_a_x0 + comp_a_safe_margin;
ir_y = wall + 2.5;
s3_x = ir_x + ir_w + 3;                                     // = ir_x + 23, khe 3mm với IR
s3_y = wall + s3_usb_gap + s3_usb_out;                      // mép ĐẦU USB-C của PCB, sát vách trước
s3_hole_y = s3_y + s3_hole_to_end;
s3_usb_z = floor_t + s3_stand + s3_pcb_t + 3.26/2;
box_a_cx = s3_x + s3_w/2;   // dùng cho vị trí 2 lỗ vít S3 + cửa USB-C (canh theo TÂM S3, không
                             // phải tâm khoang, vì khoang giờ không đối xứng quanh S3 nữa)

// Mic: dưới nắp, khoang A, đặt về phía SAU (xa vùng USB-C/IR) để không chồng khoét cửa.
mic_cx = box_a_cx;
mic_cy = out_l - wall - 20;
mic_pocket_d = mic_dia + 2*mic_liner + 0.4;

/* --- Khoang B: radar-node (S2 + LD2410C) --- */
// S2: USB-C ra vách SAU (y lớn) — đối xứng với voice-node để 2 đầu dây ra 2 phía, giữ tinh
// thần "không chồng dây" của các file khác trong thư mục.
s2_x = box_b_cx - s2_w/2;
s2_hole_y = out_l - wall - s2_usb_gap - s2_hole_to_usb;
s2_y = out_l - wall - s2_usb_gap - 1 - s2_l;

// Radar: treo dưới nắp, khoang B, đặt về phía TRƯỚC của khoang (xa cổng USB-C của S2 ở vách
// sau) — thoả hazard "LD2410 cách USB-C ≥5mm" (system-wiring.md mục "LD2410 Module Placement").
radar_cx = box_b_cx;
radar_cy = wall + 20;
radar_win_x0 = radar_cx - radar_w/2 + radar_rim;
radar_win_x1 = radar_cx + radar_w/2 - radar_rim;
radar_pocket_x0 = radar_cx - (radar_w + radar_fit)/2;
// Khoảng cách radar (mép xa nhất, y = radar_cy+radar_l/2) tới cổng USB-C S2 (mặt cổng ở
// khoảng y = out_l-wall-s2_usb_gap): PHẢI ≥5mm, verify bằng số trong echo() khi render.
radar_to_usbc_gap = (out_l - wall - s2_usb_gap) - (radar_cy + radar_l/2);
echo(str("Khoảng cách radar tới USB-C (yêu cầu >=5mm): ", radar_to_usbc_gap, "mm"));

/* ================= tiện ích ================= */
// (post_ov định nghĩa sớm hơn ở phần Khung — xem giải thích đầy đủ ở đó. Dùng lại tại đây cho
// corner_centers_a()/corner_centers_b(): trụ PHẢI LẤN vào vách, không được tiếp tuyến khít tuyệt
// đối, nếu không union() ra Simple:no dù render nhìn vẫn đúng — kiểm CGAL thật 04/09 bắt được.)

module corner_centers_a() {
    for (x = [comp_a_x0 + post_off - post_ov, comp_a_x1 - post_off + post_ov])
        for (y = [post_off, out_l - post_off])
            translate([x, y, 0]) children();
}
module corner_centers_b() {
    for (x = [comp_b_x0 + post_off - post_ov, comp_b_x1 - post_off + post_ov])
        for (y = [post_off, out_l - post_off])
            translate([x, y, 0]) children();
}

module bo_goc_dung(z0, z1) {
    for (g = [[0, 0, 1, 1], [out_w, 0, -1, 1], [0, out_l, 1, -1], [out_w, out_l, -1, -1]])
        translate([g[0], g[1], z0])
            scale([g[2], g[3], 1])
                linear_extrude(z1 - z0)
                    difference() {
                        square(post_off);
                        translate([post_off, post_off]) circle(r = post_off);
                    }
}

// Khớp bấm — CHÉP ĐÚNG cặp module ranh_bam()/go_bam() đã kiểm CGAL sạch ở vo-hop-sleeppad-c3.scad
// (bản nháp đầu ở đây chỉ làm 1 hông, thiếu đối xứng, gây base() không phải manifold hợp lệ —
// sửa bằng cách dùng lại đúng cặp rãnh(base)/gờ(lid) cho CẢ 2 hông, không tự chế lại).
bam_z_snap = floor_t + deck_h - 9 + 2.48;   // = bam_z công thức gốc, lip_h_ben=9 (xem lip_h_ben())
bam_ys_snap = [out_l * 0.25, out_l * 0.85];

module ranh_bam() {
    for (w = [[wall, -1], [out_w - wall, 1]])
        translate([w[0], post_d, bam_z_snap])
            rotate([-90, 0, 0])
                linear_extrude(out_l - 2*post_d)
                    polygon([[-w[1]*0.5, -(bam_cao+0.5)/tan(bam_giu_deg)],
                             [ w[1]*(bam_cao-0.4), 0                    ],
                             [-w[1]*0.5,  (bam_cao+0.5)/tan(bam_vao_deg)]]);
}

module go_bam() {
    for (y = bam_ys_snap)
        for (m = [[wall + lip_gap, -1], [out_w - wall - lip_gap, 1]])
            translate([m[0], y - bam_dai/2, bam_z_snap - (floor_t + deck_h)])
                rotate([-90, 0, 0])
                    linear_extrude(bam_dai)
                        polygon([[-m[1]*0.5, -(bam_cao+0.5)/tan(bam_giu_deg)],
                                 [ m[1]*bam_cao, 0                          ],
                                 [-m[1]*0.5,  (bam_cao+0.5)/tan(bam_vao_deg)]]);
}

module khac_bay() {
    translate([out_w/2 - bay_w/2, -1, deck_h + floor_t - bay_h])
        cube([bay_w, bay_d + 1, bay_h + 1]);
}

module base() {
    difference() {
        union() {
            cube([out_w, out_l, floor_t]);                                        // sàn
            cube([wall, out_l, floor_t + deck_h]);                                // hông trái
            translate([out_w - wall, 0, 0]) cube([wall, out_l, floor_t + deck_h]);// hông phải
            cube([out_w, wall, floor_t + deck_h]);                                // vách trước
            translate([0, out_l - wall, 0]) cube([out_w, wall, floor_t + deck_h]);// vách sau
            // VÁCH NGĂN 2 khoang — ĐẶC, chạy suốt chiều dài + chiều cao. Đây là ranh giới điện
            // độc lập, PHẢI kín (verify CGAL: 2 khoang không được thông thể tích với nhau).
            translate([part_x0, 0, 0]) cube([part_wall_t, out_l, floor_t + deck_h]);

            // 4 trụ góc mỗi khoang (8 trụ tổng — mỗi khoang có bộ trụ riêng, độc lập)
            translate([0, 0, floor_t]) corner_centers_a() cylinder(d = post_d, h = deck_h);
            translate([0, 0, floor_t]) corner_centers_b() cylinder(d = post_d, h = deck_h);

            // --- KHOANG A: đỡ S3 (2 trụ vít M2.5 đầu USB-C) ---
            translate([0, 0, floor_t])
                for (dx = [-s3_hole_pitch/2, s3_hole_pitch/2])
                    translate([box_a_cx + dx, s3_hole_y, 0]) cylinder(d = 8, h = s3_stand);
            // --- KHOANG A: gờ đỡ IR ---
            translate([0, 0, floor_t])
                for (dx = [0, ir_w])
                    translate([ir_x + dx - ir_rib_t/2, ir_y + 5, 0])
                        cube([ir_rib_t, ir_l - 8, ir_rib_h]);

            // --- KHOANG B: đỡ S2 (2 trụ vít M2, neo theo cổng USB-C) ---
            translate([0, 0, floor_t])
                for (dx = [-s2_pitch/2, s2_pitch/2])
                    translate([s2_x + s2_w/2 + dx, s2_hole_y, 0]) cylinder(d = 7, h = s2_stand);
        }

        if (!vit_on) khac_bay();

        // CỬA USB-C khoang A (voice-node) — vách TRƯỚC, trùm 2 cổng (giữ số đã nghiệm thu ở
        // vo-hop-sleeppad.scad, khác 24.5 gốc modular vì s3_usb_plug_clear đổi 1->2).
        translate([box_a_cx - s3_usb_open_w/2, -1, s3_usb_z - s3_usb_open_h/2])
            cube([s3_usb_open_w, wall + 2, s3_usb_open_h]);
        // Lỗ mồi vít M2.5 (rãnh dài theo x)
        translate([0, 0, floor_t + s3_stand - 5])
            for (dx = [-s3_hole_pitch/2, s3_hole_pitch/2])
                translate([box_a_cx + dx, s3_hole_y, 0])
                    hull() for (sx = [-s3_hole_tol, s3_hole_tol])
                        translate([sx, 0, 0]) cylinder(d = m25_pilot, h = 7);
        // Lỗ LED IR xuyên vách trước
        translate([ir_x + ir_w/2, -1, floor_t + ir_axis_h]) rotate([-90, 0, 0])
            cylinder(d = 6.5, h = wall + 2);

        // CỬA USB-C khoang B (radar-node) — vách SAU
        translate([s2_x + s2_w/2 - 6, out_l - wall - 1, floor_t + s2_stand - 1])
            cube([12, wall + 2, 9]);
        // Lỗ mồi vít M2 (rãnh dài theo x)
        translate([0, 0, floor_t + s2_stand - 5])
            for (dx = [-s2_pitch/2, s2_pitch/2])
                translate([s2_x + s2_w/2 + dx, s2_hole_y, 0])
                    hull() for (sx = [-s2_pitch_tol, s2_pitch_tol])
                        translate([sx, 0, 0]) cylinder(d = 1.7, h = 7);

        if (!vit_on) ranh_bam();

        bo_goc_dung(-1, floor_t + deck_h + 1);
    }
}

module lid() {
    difference() {
        union() {
            cube([out_w, out_l, lid_t]);
            translate([wall + lip_gap, wall + lip_gap, -lip_h_ben()])
                cube([lip_w, out_l - 2*wall - 2*lip_gap, lip_h_ben()]);
            translate([out_w - wall - lip_gap - lip_w, wall + lip_gap, -lip_h_ben()])
                cube([lip_w, out_l - 2*wall - 2*lip_gap, lip_h_ben()]);

            if (!vit_on) go_bam();

            // Bệ đỡ mic (khoang A) — hốc khoét ở difference bên dưới
            translate([mic_cx, mic_cy, -mic_boss_h])
                cylinder(d = mic_pocket_d + 4, h = mic_boss_h);
        }

        // === RADAR (khoang B): hốc + cửa sổ màng — CHÉP CƠ CHẾ ĐÃ NGHIỆM THU từ
        // vo-hop-modular.scad (đã qua 3 lần sửa lỗi thật, không thiết kế lại từ đầu).
        translate([radar_cx, radar_cy, -lid_lip_h/2])
            cube([radar_w + radar_fit, radar_l + radar_fit, lid_lip_h], center=true);
        translate([(radar_win_x0 + radar_win_x1)/2, radar_cy, (lid_t-radar_mem_t)/2])
            cube([radar_win_x1 - radar_win_x0, radar_l - 2*radar_rim, lid_t-radar_mem_t],
                 center=true);
        translate([radar_pocket_x0 - radar_wire_sh, radar_cy - radar_wire_w/2, 0])
            cube([radar_win_x0 + 1 - (radar_pocket_x0 - radar_wire_sh), radar_wire_w, radar_wire_h]);
        translate([radar_pocket_x0 - radar_wire_sh, radar_cy - radar_wire_w/2, -lid_lip_h])
            cube([radar_wire_sh + 1, radar_wire_w, lid_lip_h]);

        // Hốc mic (khoang A)
        translate([mic_cx, mic_cy, -mic_boss_h-1])
            cylinder(d = mic_pocket_d, h = mic_boss_h - mic_shelf + 1);
        translate([mic_cx - mic_pocket_d/2 - 4, mic_cy - 2, -mic_shelf - 2.5])
            cube([6, 4, 2.5]);
        translate([mic_cx, mic_cy, -mic_boss_h-2]) cylinder(d = 4, h = mic_boss_h + lid_t + 4);

        // Bo góc
        bo_goc_dung(-lip_h_ben() - 1, lid_t + 1);

        // Khoét tránh trụ góc (cả 2 khoang)
        translate([0, 0, -lip_h_ben() - 1]) corner_centers_a() cylinder(d = post_d + 0.6, h = lip_h_ben() + 1);
        translate([0, 0, -lip_h_ben() - 1]) corner_centers_b() cylinder(d = post_d + 0.6, h = lip_h_ben() + 1);
    }
}

// Cánh tay đòn khớp bấm — hàm thay vì hằng số vì out_l tính từ tham số board, không phải số cố định.
function lip_h_ben() = 9;

module assembly() {
    color("LightSteelBlue") base();
    color("Silver") translate([0, 0, floor_t + deck_h]) lid();
}

/* ================= BÓNG LINH KIỆN (kiểm/xem, không xuất STL) ================= */
module ghost_s3()    { translate([s3_x, s3_y, floor_t+s3_stand]) cube([s3_w, s3_l, s3_pcb_t]); }
module ghost_ir()    { translate([ir_x, ir_y, floor_t+ir_rib_h]) cube([ir_w, ir_l, 1.6]); }
module ghost_s2()    { translate([s2_x, s2_y, floor_t+s2_stand]) cube([s2_w, s2_l, 1.6]); }
module ghost_radar() {
    translate([radar_cx - radar_w/2, radar_cy - radar_l/2, floor_t+deck_h-radar_t-radar_hdr_h])
        cube([radar_w, radar_l, radar_t + radar_hdr_h]);
}
module ghosts() {
    color([0.2,0.6,1,0.45]) ghost_s3();
    color([1,0.5,0.2,0.45]) ghost_ir();
    color([0.3,1,0.3,0.45]) ghost_s2();
    color([1,0.2,0.2,0.45]) ghost_radar();
}

/* ================= ĐẦU DÒ KIỂM LỖ / VÁCH NGĂN (dùng lại nguyên tắc probe() ở vo-hop-modular.scad) ================= */
module probe(which) {
    if (which == "usbc-a")
        translate([box_a_cx - s3_usb_open_w/2 + 1, -1, s3_usb_z - s3_usb_open_h/2 + 1])
            cube([s3_usb_open_w - 2, wall + 2, s3_usb_open_h - 2]);
    else if (which == "usbc-b")
        translate([s2_x + s2_w/2 - 6 + 1, out_l - wall - 1, floor_t + s2_stand - 1 + 1])
            cube([12 - 2, wall + 2, 9 - 2]);
    else if (which == "ir-hole")
        translate([ir_x + ir_w/2, -1, floor_t + ir_axis_h]) rotate([-90, 0, 0])
            cylinder(d = 4, h = wall + 2);
    // Vách ngăn PHẢI kín: khối mỏng nằm NGAY GIỮA vách ngăn, cao gần hết deck_h. Giao với
    // NEGATIVE của base (tức: nếu vách kín, khối này phải nằm HOÀN TOÀN trong nhựa đặc — giao
    // với base() phải bằng CHÍNH khối đó, không nhỏ hơn). Kiểm bằng cách khác: giao khối này với
    // "không khí" (lấy phần THỪA ra ngoài base) — nếu vách kín, phần thừa phải RỖNG.
    else if (which == "vach-ngan-kin")
        difference() {
            translate([part_x0 + 0.5, 1, floor_t + 1])
                cube([part_wall_t - 1, out_l - 2, deck_h - 2]);
            base();
        }
}

/* ================= MIẾNG ƯỚM ================= */
module test_s3() {
    intersection() { base(); cube([out_w, s3_y + 20, 26]); }
}
module test_s2() {
    intersection() { base(); translate([0, out_l - 40, 0]) cube([out_w, 40, 26]); }
}
module test_radar() {
    // Mặt cắt x LÙI VÀO 1mm so với comp_b_x0 (mép trong vách ngăn) — cắt đúng mép sẵn có sinh
    // mặt dày 0, mất 2-manifold (bài học đã ghi trong vo-hop-modular.scad, gặp lại ở đây 04/09).
    intersection() { base(); translate([comp_b_x0 - 1, 0, 0]) cube([comp_b_inner_w + part_wall_t + 1, 40, 32]); }
}

if      (part == "base")      base();
else if (part == "lid")       lid();
else if (part == "test-s3")   test_s3();
else if (part == "test-s2")   test_s2();
else if (part == "test-radar") test_radar();
else if (part == "layout")    { base(); ghosts(); }
else                          assembly();
