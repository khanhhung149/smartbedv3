// vo-hop-sleeppad-c3.scad — Vỏ hộp cho node sleep-pad: ESP32-C3 Super Mini + 1 cổng USB-A cố định.
// THAY THẾ vo-hop-sleeppad.scad (thiết kế cho ESP32-S3-CAM) — firmware sleep-pad-node đã đổi
// sang C3 Super Mini (nologo_esp32c3_super_mini) từ 24/08. File S3 GIỮ NGUYÊN làm tài liệu lịch
// sử, không xoá. In 2 mảnh: base (sàn + 4 vách) và lid (nắp, khớp bấm — không vít).
//
// CÔNG DỤNG: hộp ngồi dưới sàn/gầm giường, đầu USB-A nhận cáp 4 dây của tấm LSM-800-T, đầu
// USB-C ra nguồn/nạp cho C3. Cáp ra HAI ĐẦU ĐỐI DIỆN nên không chồng dây — GIỮ NGUYÊN lý do gốc
// của bản S3 dù C3 hẹp hơn nhiều nên bố cục song song giờ đã vừa (xem plan
// 260904-0811-thiet-ke-vo-hop-sensor-c3-va-voice-radar): lý do ergonomic (2 đầu dây ra 2 phía
// khi đặt dưới gầm giường) độc lập với bề rộng board — quyết định 04/09, không đổi bố cục.
//
// ⚠️ CỔNG USB-A TRÊN HỘP NÀY KHÔNG PHẢI USB. Nó là UART 115200 8N1 + 5V, đấu qua khối breakout
// USB-A → 4 chân (VCC/GND/D+/D- dùng lại làm UART, xem firmware/sleep-pad-node/include/config.h).
// Cắm chuột/USB thường vào đây thì không cháy nhưng cũng không chạy. Nắp khắc chữ cảnh báo.
//
// VẬT LIỆU: PETG, thành 3mm, FDM. KHÔNG in resin — lý do giống bản S3 (ren đồng ép nóng cần
// nhựa nhiệt dẻo, resin giòn và nằm dưới sàn dễ bị đá phải).
//
// === NGUỒN SỐ ĐO ===
// Khối usba_* CHÉP NGUYÊN VĂN từ vo-hop-sleeppad.scad — linh kiện không đổi, không đo lại.
//
// Khối c3_* — ĐO TAY THẬT 04/09 (không dùng số web 22.5×18mm làm số cuối, đúng bài học đã ghi
// 2 lần trong bản S3 về việc tin số liệu mạng):
//   c3_l = 23.5mm — đo TỪ MÉP CỔNG USB-C (mốc đo, không phải mép board đối diện).
//   c3_w = 18mm.
//   c3_pcb_t = 1.6mm — CHƯA đo tay riêng, dùng số PCB tiêu chuẩn (board mỏng kiểu này hầu hết
//     1.6mm) — chấp nhận theo quyết định 04/09, sửa lại nếu ướm thử lệch.
//   c3_comp_h = 3.5mm — linh kiện cao nhất (chip/nút) — ƯỚC TÍNH, CHƯA ĐO — quyết định 04/09
//     chấp nhận tạm, PHẢI xác nhận bằng miếng ướm (xem test_c3()) trước khi in cả hộp.
//   USB-C ở GIỮA cạnh ngắn (18mm) — xác nhận bằng mắt 04/09, không phải số đo panme.
//   KHÔNG có lỗ vít (board kiểu breadboard trần) — xác nhận 04/09.
//   KHÔNG cần lỗ nút RESET/BOOT trên vỏ — nạp firmware qua USB-C là đủ, quyết định 04/09.
//
// === ĐỊNH VỊ C3: POCKET 4 CẠNH + DÁN, KHÔNG VÍT ===
// Khác hẳn cách bản S3 giữ board (2 trụ vít + 2 trụ đỡ + gờ dẫn hướng chỉ 2 cạnh dài), vì C3
// không có lỗ vít nào. Dùng gờ dẫn hướng bao đủ 4 cạnh (kiểu "định vị + dán" — cùng triết lý đã
// áp dụng cho module radar LD2410C trong vo-hop-modular.scad, module đó cũng không có lỗ vít).
// Thêm 1 cặp gờ chặn nhấc (+z) trên 2 cạnh dài vì không có vít giữ theo phương đứng.

part = "assembly";   // "base" | "lid" | "assembly" | "exploded" | "layout" | "test-usba" | "test-c3"

/* ================= ESP32-C3 Super Mini (đo tay thật 04/09) ================= */
c3_l = 23.5;  c3_w = 18;          // PCB (dài × rộng) — dài đo từ mép cổng USB-C
c3_pcb_t = 1.6;                    // CHƯA đo riêng — số PCB tiêu chuẩn, xem ghi chú đầu file
c3_comp_h = 3.5;                   // linh kiện cao nhất — ƯỚC TÍNH, xem ghi chú đầu file
c3_stand = 2;                      // trụ/gờ đỡ dưới board — board không có chân header thò
                                    // xuống (hàn dây trực tiếp GPIO, không qua header), nên chỉ
                                    // cần hở tối thiểu tránh solder mask/pad chạm sàn.
c3_usb_w = 9;                      // bề rộng thân cổng USB-C + dung sai (thân danh nghĩa ~8.94,
                                    // xem cách tính s3_usb_w cũ trong vo-hop-sleeppad.scad)
c3_usb_plug_clear = 2;             // hở thêm mỗi bên cho vỏ NHỰA của phích — CHƯA đo cục nhựa
                                    // thật, dùng lại giá trị đã nghiệm thu ở bản S3.
c3_usb_open_w = c3_usb_w + 2*c3_usb_plug_clear;   // = 13
c3_usb_open_h = 8;                 // cao hơn thân cổng để nuốt cả vỏ nhựa phích (giữ số bản S3)
c3_usb_out = 0.5;                  // cổng USB-C thò ra khỏi mép PCB — ƯỚC TÍNH nhỏ, C3 supermini
                                    // thường hàn sát mép, khác S3-CAM (1mm) — xác nhận khi ướm.
c3_usb_gap = 0.5;                  // hở giữa mặt cổng và mặt TRONG vách sau (giữ số bản S3)

/* --- Gờ dẫn hướng bao 4 cạnh (thay 2 cạnh + lỗ vít của bản S3) --- */
c3_guide_clear = 0.5;              // hở mỗi bên giữa mép board và mặt trong gờ
c3_guide_t = 2;                    // bề dày mỗi gờ
c3_guide_over = 3;                 // gờ cao hơn nóc PCB bấy nhiêu — còn dẫn hướng suốt hành trình
c3_guide_seg = 6;                  // chiều dài mỗi đoạn gờ hông (ngắn hơn bản S3 vì board ngắn)
c3_guide_in = 1.5;                 // đoạn gờ lùi vào so 2 đầu board

/* --- Gờ chặn nhấc, treo dưới nắp (thay vít, khoá phương +z) --- */
c3_hold_on = true;
c3_hold_w = 2.5;                   // bề rộng mỗi gờ theo x, tính từ mép board vào
c3_hold_l = 5;                     // chiều dài theo y
c3_hold_gap = 0.5;                 // hở giữa đáy gờ và nóc PCB

/* ================= Khối breakout USB-A (chép nguyên văn vo-hop-sleeppad.scad) ================= */
usba_l = 32;
usba_w = 16;
usba_h = 20;
usba_fit = 0.4;
usba_axis_z = 5;
usba_plug_w = 18;  usba_plug_h = 9;  usba_plug_len = 20;
usba_plug_clear = 1.5;
usba_rib_t = 2.5;
usba_rib_h = 16;
usba_stop_t = 3;
usba_wire_w = 10;
usba_wire_z = 11;
usba_hold_gap = 0.5;
usba_floor_min = 2;
wire_gap = 6;                      // khoảng trống giữa vách chặn USB-A và mép trước board C3

/* ================= Khung ================= */
// inner_w do C3 (18mm) quyết định, không phải khối USB-A (16mm) — C3 rộng hơn 2mm.
// PHẢI chừa đủ để mép board KHÔNG chạm vùng trụ góc (post_d=8, tangent mặt ngoài — post_off=4):
// điều kiện box_cx + c3_w/2 <= out_w - post_d, verify bằng CGAL (base ∩ ghosts phải RỖNG) —
// lần đầu tính inner_w=27 (out_w=33) THIẾU đúng 0.5mm, trụ góc sau-phải đụng mép board (bắt
// được qua kiểm CGAL thật 04/09, không phải suy đoán). +6 (thay +4) cho dư khoảng 1.5mm an toàn.
inner_w = c3_w + 2*(c3_guide_clear + c3_guide_t) + 6;   // = 18 + 2*2.5 + 6 = 29
wall = 3;  floor_t = 3;  lid_t = 3;
deck_h = 22;                       // vẫn do khối USB-A (cao 20) quyết định — C3 thấp hơn nhiều
post_d = 8;
post_off = post_d/2;
m3_free = 3.4;
m3_insert = 4.2;
insert_deep = 6;
lid_lip_h = 4;
lip_w = 1.5;
lip_gap = 0.4;

/* ================= Khớp bấm thay cho vít (giữ nguyên tham số bản S3) ================= */
vit_on = false;
lip_h_ben = 9;                     // NGẮN HƠN bản S3 (12.5) vì hộp ngắn hơn nhiều — cánh tay đòn
                                    // môi phải tính lại theo out_l mới, không copy số cũ nguyên
                                    // xi (xem cảnh báo trong vo-hop-sleeppad.scad về F=3EI·y/L³).
bam_cao = 0.7;
bam_dai = 10;
bam_vao_deg = 30;
bam_giu_deg = 45;
bay_w = 15;  bay_d = 1.5;  bay_h = 3;

label_on = false;
label_size = 4;
label_deep = 0.6;

/* ================= Vân trang trí ================= */
van_on = true;
van_sau = 0.8;
van_zs = [10, 16];                 // 2 mức thay vì 3 — hộp thấp/ngắn hơn bản S3
van_lo = 0.5;

goc_bo = true;
goc_r = post_off;

$fn = 48;

/* ================= Toạ độ suy ra ================= */
out_w = inner_w + 2*wall;                    // = 33
box_cx = out_w/2;                            // = 16.5

usba_y     = wall;                                    // = 3
usba_back  = usba_y + usba_l + usba_fit;              // = 35.4
c3_y       = usba_back + usba_stop_t + wire_gap;       // = 44.4
c3_y_rear  = c3_y + c3_l;                              // = 67.9
out_l      = c3_y_rear + c3_usb_out + c3_usb_gap + wall;   // = 71.9
inner_l    = out_l - 2*wall;

c3_x       = box_cx - c3_w/2;                          // = 7.5

usba_open_w = usba_plug_w + 2*usba_plug_clear;   // = 21
usba_open_h = usba_plug_h + 2*usba_plug_clear;   // = 12
usba_x0    = box_cx - (usba_w + usba_fit)/2;
usba_x1    = usba_x0 + usba_w + usba_fit;
usba_pocket_l = usba_l + usba_fit;
usba_open_z0  = max(usba_floor_min, floor_t + usba_axis_z - usba_open_h/2);
usba_hold_h   = deck_h - usba_h - usba_hold_gap;

// Tâm thân cổng USB-C so đáy NGOÀI hộp: đáy PCB (floor_t + c3_stand) + PCB + nửa thân cổng.
c3_usb_z = floor_t + c3_stand + c3_pcb_t + 3.26/2;

z_pcb_noc = floor_t + c3_stand + c3_pcb_t;
c3_guide_x0 = box_cx - c3_w/2 - c3_guide_clear;
c3_guide_x1 = box_cx + c3_w/2 + c3_guide_clear;
c3_guide_h  = c3_stand + c3_pcb_t + c3_guide_over;
c3_guide_ys = [c3_y + c3_guide_in, c3_y_rear - c3_guide_in - c3_guide_seg];
c3_hold_h  = (floor_t + deck_h) - (z_pcb_noc + c3_hold_gap);

// Gờ chặn NGANG 2 đầu (thay lỗ vít): board không có lỗ, cần chặn cả phương y (rút phích USB-C
// và cắm cáp UART đều tạo lực dọc trục y) — gờ chặn tì vào 2 mép ngắn của board.
c3_stop_front_y = c3_y;             // vách/gờ tì mép trước board (giáp khối USB-A)
c3_stop_back_h  = c3_guide_h;        // gờ chặn sau cao bằng gờ dẫn hướng

van_nho = van_sau + van_lo;
van_y0 = post_d + 1;
van_y1 = out_l - post_d - 1;

z_nap_duoi = floor_t + deck_h;
lip_sau_nhat = max(lid_lip_h, lip_h_ben);
bam_tu_dau = (bam_cao + van_lo)/tan(bam_vao_deg) + 0.4;
bam_z = z_nap_duoi - lip_h_ben + bam_tu_dau;
ranh_sau = bam_cao - lip_gap;
bam_rong = 2*bam_cao;
// 2 vị trí gờ bấm, cách đều trong khoảng hông dài — hộp ngắn hơn bản S3 nên chỉ cần 2 (bản S3
// dùng 2 vị trí [25,89] trên chiều dài 107.9; ở đây chiều dài hông chỉ ~65.9, tính tỉ lệ tương tự).
bam_ys = [out_l * 0.25, out_l * 0.85];
bam_y0 = post_d;
bam_y1 = out_l - post_d;

/* ================= tiện ích (giữ nguyên bản S3) ================= */
module corner_centers() {
    for (x = [post_off, out_w - post_off])
        for (y = [post_off, out_l - post_off])
            translate([x, y, 0]) children();
}

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

module bo_goc_dung(z0, z1) {
    for (g = [[0, 0, 1, 1], [out_w, 0, -1, 1], [0, out_l, 1, -1], [out_w, out_l, -1, -1]])
        translate([g[0], g[1], z0])
            scale([g[2], g[3], 1])
                linear_extrude(z1 - z0)
                    difference() {
                        square(goc_r);
                        translate([goc_r, goc_r]) circle(r = goc_r);
                    }
}

module ranh_bam() {
    for (w = [[wall, -1], [out_w - wall, 1]])
        translate([w[0], bam_y0, bam_z])
            rotate([-90, 0, 0])
                linear_extrude(bam_y1 - bam_y0)
                    polygon([[-w[1]*van_lo, -(ranh_sau + van_lo)/tan(bam_giu_deg)],
                             [ w[1]*ranh_sau, 0                                  ],
                             [-w[1]*van_lo,  (ranh_sau + van_lo)/tan(bam_vao_deg)]]);
}

module go_bam() {
    for (y = bam_ys)
        for (m = [[wall + lip_gap, -1], [out_w - wall - lip_gap, 1]])
            translate([m[0], y - bam_dai/2, bam_z - z_nap_duoi])
                rotate([-90, 0, 0])
                    linear_extrude(bam_dai)
                        polygon([[-m[1]*van_lo, -(bam_cao + van_lo)/tan(bam_giu_deg)],
                                 [ m[1]*bam_cao, 0                                  ],
                                 [-m[1]*van_lo,  (bam_cao + van_lo)/tan(bam_vao_deg)]]);
}

module khac_bay() {
    translate([box_cx - bay_w/2, -1, z_nap_duoi - bay_h])
        cube([bay_w, bay_d + 1, bay_h + 1]);
}

module base() {
    difference() {
        union() {
            cube([out_w, out_l, floor_t]);
            cube([wall, out_l, floor_t + deck_h]);
            translate([out_w - wall, 0, 0]) cube([wall, out_l, floor_t + deck_h]);
            cube([out_w, wall, floor_t + deck_h]);
            translate([0, out_l - wall, 0]) cube([out_w, wall, floor_t + deck_h]);

            translate([0, 0, floor_t]) corner_centers() cylinder(d = post_d, h = deck_h);

            // --- KHAY USB-A (giữ nguyên bản S3) ---
            for (x = [usba_x0 - usba_rib_t, usba_x1])
                translate([x, usba_y, floor_t])
                    cube([usba_rib_t, usba_pocket_l, usba_rib_h]);
            translate([wall, usba_back, floor_t])
                cube([inner_w, usba_stop_t, usba_rib_h]);

            // --- POCKET C3: gờ dẫn hướng 2 cạnh dài + gờ chặn 2 đầu (thay trụ vít) ---
            for (x = [c3_guide_x0 - c3_guide_t, c3_guide_x1])
                for (y = c3_guide_ys)
                    translate([x, y, floor_t]) cube([c3_guide_t, c3_guide_seg, c3_guide_h]);
            // Gờ chặn mép TRƯỚC (giáp khối USB-A) — chặn board trượt về phía USB-A khi cắm cáp.
            translate([c3_x - c3_guide_clear, c3_y - c3_guide_t, floor_t])
                cube([c3_w + 2*c3_guide_clear, c3_guide_t, c3_guide_h]);
        }

        // Rãnh thoát 4 dây USB-A (giữ nguyên bản S3)
        translate([box_cx - usba_wire_w/2, usba_back - 1, floor_t + usba_wire_z])
            cube([usba_wire_w, usba_stop_t + 2, usba_rib_h - usba_wire_z + 1]);

        if (!vit_on) { ranh_bam(); khac_bay(); }

        // CỬA USB-A ở vách TRƯỚC (giữ nguyên bản S3)
        translate([box_cx - usba_open_w/2, -1, usba_open_z0])
            cube([usba_open_w, wall + 2, usba_open_h]);

        // CỬA USB-C ở vách SAU — 1 cổng duy nhất (C3 chỉ có 1 USB-C, không 2 như S3-CAM)
        translate([box_cx - c3_usb_open_w/2, out_l - wall - 1, c3_usb_z - c3_usb_open_h/2])
            cube([c3_usb_open_w, wall + 2, c3_usb_open_h]);

        if (van_on) van_hong();
        if (goc_bo) bo_goc_dung(-1, floor_t + deck_h + 1);
    }
}

module lid() {
    difference() {
        union() {
            cube([out_w, out_l, lid_t]);

            translate([wall + lip_gap, wall + lip_gap, -lip_h_ben])
                cube([lip_w, inner_l - 2*lip_gap, lip_h_ben]);
            translate([out_w - wall - lip_gap - lip_w, wall + lip_gap, -lip_h_ben])
                cube([lip_w, inner_l - 2*lip_gap, lip_h_ben]);
            translate([wall + lip_gap, out_l - wall - lip_gap - lip_w, -lid_lip_h])
                cube([inner_w - 2*lip_gap, lip_w, lid_lip_h]);

            if (!vit_on) go_bam();

            translate([usba_x0, usba_y, -usba_hold_h])
                cube([usba_w + usba_fit, usba_pocket_l, usba_hold_h]);

            // Gờ CHẶN NHẤC C3 — đè lên 2 mép dài, thay vít (board không có lỗ)
            if (c3_hold_on)
                for (x = [c3_x, c3_x + c3_w - c3_hold_w])
                    translate([x, c3_y, -c3_hold_h]) cube([c3_hold_w, c3_hold_l, c3_hold_h]);
        }

        if (goc_bo) bo_goc_dung(-lip_sau_nhat - 1, lid_t + 1);

        if (vit_on)
            translate([0, 0, -lip_sau_nhat - 2]) corner_centers()
                cylinder(d = m3_free, h = lid_t + lip_sau_nhat + 4);
        if (!vit_on)
            translate([0, usba_back - 0.5, -lip_h_ben - 1])
                cube([out_w, usba_stop_t + 1,
                      (floor_t + usba_rib_h - z_nap_duoi) - (-lip_h_ben - 1)]);

        translate([0, 0, -lip_sau_nhat - 1]) corner_centers()
            cylinder(d = post_d + 0.6, h = lip_sau_nhat + 1);

        if (label_on) {
            translate([box_cx, wall + 18, lid_t - label_deep])
                linear_extrude(label_deep + 1)
                    text("UART 5V", size = label_size, halign = "center", valign = "center");
            translate([box_cx, wall + 11, lid_t - label_deep])
                linear_extrude(label_deep + 1)
                    text("KHONG PHAI USB", size = label_size,
                         halign = "center", valign = "center");
        }
    }
}

module assembly() {
    color("LightSteelBlue") base();
    color("Silver") translate([0, 0, floor_t + deck_h]) lid();
}

module exploded() {
    color("LightSteelBlue") base();
    color("Silver") translate([0, 0, floor_t + deck_h + 28]) lid();
}

/* ================= BÓNG LINH KIỆN (để xem/kiểm, không xuất STL) ================= */
module ghosts() {
    color([0.2, 0.6, 1, 0.45])
        translate([c3_x, c3_y, floor_t + c3_stand]) cube([c3_w, c3_l, c3_pcb_t + c3_comp_h]);
    color([1, 0.5, 0.2, 0.45])
        translate([usba_x0, usba_y, floor_t]) cube([usba_w, usba_l, usba_h]);
    color([0.6, 0.6, 0.6, 0.45])
        translate([box_cx - c3_usb_w/2, c3_y_rear, c3_usb_z - c3_usb_open_h/2])
            cube([c3_usb_w, 6, c3_usb_open_h]);
}

/* ================= MIẾNG ƯỚM ================= */
module test_usba() {
    intersection() { base(); cube([out_w, 42, 26]); }
}
// === KIỂM CGAL THẬT ĐÃ CHẠY 04/09 (openscad 2021.01, không phải suy đoán) ===
//   base() ∩ ghosts(): LẦN ĐẦU inner_w=27 → 20 facet, trụ góc sau-phải đụng mép board 0.5mm
//     (bắt được thật, không phải nhìn hụt trên render). Sửa inner_w=29 → còn 4 facet, khớp mẫu
//     "mặt tiếp xúc có chủ đích" (gờ chặn trước áp sát mép board, cùng loại false-positive đã
//     ghi trong xuat-stl-va-kiem-lo.sh) — chấp nhận, không phải va chạm thật.
//   Cửa USB-C, cửa USB-A: probe ∩ base() đều RỖNG — lỗ thông thật, không "khoét hụt".
//   CHƯA in thật — miếng ướm test_c3()/test_usba() vẫn cần in trước khi in cả hộp, đúng quy
//   trình đã dùng cho bản S3 (kiểm hình học ≠ kiểm lắp ráp thật).
//
// Miếng ướm khoang C3 — CHƯA VERIFY BẰNG IN THẬT, in trước khi in cả hộp.
module test_c3() {
    intersection() { base(); translate([0, c3_y - 4, 0]) cube([out_w, c3_l + 8, 26]); }
}

if      (part == "base")      base();
else if (part == "lid")       lid();
else if (part == "test-usba") test_usba();
else if (part == "test-c3")   test_c3();
else if (part == "layout")    { base(); ghosts(); }
else if (part == "exploded")  exploded();
else                          assembly();
