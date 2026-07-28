// vo-hop-modular.scad — Vỏ hộp XẾP LỚP MODULAR cho esp32-presence-ac (v3).
// Triết lý: "định vị + dán", KHÔNG ngàm khít. In 3 bộ phận RỜI.
//   base — đế: sàn + 3 vách (sau + 2 hông) + RÃNH TRƯỢT mặt trước; giữ WROOM/S2/IR; 4 trụ góc.
//   face — mặt trước THẢ TỪ TRÊN XUỐNG rãnh, KHÔNG vít; nắp đè giữ.
//   lid  — nắp: cửa sổ radar (mỏng, radar ngửa dưới nắp) + lỗ mic (mic ngửa) + 4 vít ren đồng.
// Vật liệu: PETG thành 3mm. Bố cục theo số đo thật 24/07.
//
// === v3 (28/07): SỬA VA CHẠM — v2 KHÔNG lắp được ===
//   Kiểm bằng CGAL (intersection) trên chính file này:
//     base ∩ face = 196 mặt, phủ trọn x0..82 · y0..3 · z0..33  -> face đè lên 2 hông + gờ trước
//     base ∩ lid  = 1512 mặt, z29.5..33 tại 4 góc              -> gờ tụt nắp đâm vào 4 trụ
//   Sửa:
//   1) Face TỤT VÀO 2mm, thả từ trên xuống rãnh chữ U (2 gờ hông + gờ đáy chặn phía trước,
//      trụ góc + gờ chặn sàn đỡ phía sau, nắp đè phía trên). BỎ HẲN vít ngang.
//      Lý do bỏ vít: trụ in đứng nên đường lớp nằm ngang, vít bắt ngang là lực TÁCH LỚP —
//      hướng yếu nhất của FDM. Rãnh trượt chuyển toàn bộ tải sang lực cắt dọc theo lớp.
//   2) Trụ góc Ø6 -> Ø8, lỗ Ø4.2 ÉP REN ĐỒNG M3 (heat-set insert) thay ren thẳng vào nhựa.
//      Ø6 + lỗ mồi 2.5 chỉ còn 1.75mm thành -> tuột ren sau vài lần tháo nắp.
//   3) Gờ tụt nắp khoét tránh 4 trụ.
//   4) Trụ TRƯỚC lùi sâu hơn (post_in_f) để chừa chỗ cho face tụt; WROOM dịch phải 2mm,
//      S2 dịch trái 2mm để tránh trụ Ø8 mới.
//
// === SỐ ĐO THẬT (24/07) ===
//   WROOM 50×30, KHÔNG lỗ vít, TỰA TRÊN HÀNG PIN chĩa xuống (dupont cắm dưới) -> đỡ mép, chừa hốc dưới
//   S2 Mini 37×25, có 2 lỗ vít cách tâm ~18.5mm -> bắt vít
//   Radar LD2410C 20×15, RỜI, mặt NGỬA LÊN -> dưới nắp, cửa sổ mỏng trên nắp
//   Mic tròn Ø10 đa hướng, NGỬA LÊN -> lỗ trên nắp
//   IR module 31(dài, gồm LED)×20 -> nằm mặt trước, LED xuyên lỗ ra ngoài
//   KHÔNG dùng tụ.

part = "assembly";   // "base" | "face" | "lid" | "assembly" | "layout"

/* ---------- Linh kiện (mm) ---------- */
wroom_w = 30;  wroom_l = 50;      // WROOM (rộng×dài)
wroom_pcb_h = 13;                 // mặt đáy PCB cao trên sàn trong = chừa pin+dupont thò xuống
usb_ctr_pcb = 3;                  // tâm USB-C trên đáy PCB (chip-up)
pin_pitch    = 2.54;              // bước chân
pin_row_gap  = 25.4;              // khoảng cách NGANG giữa 2 hàng pin WROOM (tâm-tâm)
pin_field_len = 18 * pin_pitch;   // 45.72 — 2 pin chốt đầu & cuối cách nhau 18 bước
pin_hole_d   = 1.4;               // lỗ cắm pin (pin vuông 0.64mm; 1.4 = pin xỏ lọt, giữ khít)
s2_w = 25;  s2_l = 37;  s2_pitch = 18.5;   // S2 + khoảng cách 2 lỗ vít
s2_stand = 6;                     // trụ đỡ S2 — 6mm vì radar hàn thẳng vào S2, mối hàn cao
radar_w = 15;  radar_l = 20;      // radar (ngửa dưới nắp)

// Mic INMP441 bo TRÒN Ø10 (chip MEMS chữ nhật nằm TRÊN bo — bo mới là thứ lọt vào hốc).
// CỬA ĐÁY: lỗ thu âm nằm ở mặt IN CHỮ (L/R WS SCK SD VDD GND), KHÔNG phải mặt có chip.
// => Lắp mặt IN CHỮ NGỬA LÊN áp vào trần hốc, chip chúc xuống khoang. Lắp ngược thì mic
// nghe tiếng trong hộp, bịt kín càng kỹ càng tệ.
// Dây đã hàn thẳng vào pad ở CÙNG mặt in chữ => mối hàn kênh bo lên, không tì phẳng được.
// Vì vậy hốc sâu dư và có rãnh thoát dây; phần bù trừ giao cho lớp đệm MỀM (xốp), không
// giao cho nhựa in — xốp mới ép quanh được cục hàn.
mic_dia   = 10;                   // đường kính bo mic
mic_liner = 1.5;                  // bề dày lớp đệm quanh mic (xốp 2 mặt, hoặc ống TPU sau này)
mic_shelf = 1.5;                  // nhựa còn lại giữa mic và trần nắp — mặt tì để bịt kín cổng âm
mic_boss_h = 7.5;                 // bệ đỡ mic thò xuống dưới nắp
ir_w = 20;  ir_l = 31;            // module IR
ir_axis_h = 7;                    // tâm LED IR cao trên sàn trong (module nằm trên 2 gờ ~3mm)

/* ---------- Khung ---------- */
inner_w = 76;  inner_l = 82;  deck_h = 30;
wall = 3;  floor_t = 3;  lid_t = 3;
post_d = 8;                   // trụ góc Ø8: đủ thịt để ép ren đồng M3 (thành còn ~1.9mm)
post_in = 3.5;                // trụ lùi vào theo X, và theo Y ở phía SAU
post_in_f = 6;                // trụ TRƯỚC lùi sâu hơn — mặt trước trụ phải nằm sau lưng face
m3_free = 3.4;  m2_pilot = 1.7;
m3_insert = 4.2;              // lỗ chờ ép ren đồng M3 (heat-set insert, ép bằng mỏ hàn ~230°C)
insert_deep = 6;              // chiều sâu lỗ chờ

/* ---------- Rãnh trượt mặt trước ---------- */
face_t     = 3;     // dày tấm face
face_inset = 2;     // face tụt vào so mặt ngoài = bề dày gờ chặn phía trước
face_gap   = 0.4;   // khe lắp tổng (dung sai FDM ~0.2/mặt)
rail_w     = 3;     // gờ chặn ăn vào trong bao nhiêu theo X
stop_t     = 2;     // gờ chặn sàn phía SAU lưng face

$fn = 48;

out_w = inner_w + 2*wall;
out_l = inner_l + 2*wall;
mic_pocket_d = mic_dia + 2*mic_liner + 0.4;   // 13.4 — chừa chỗ cho lớp đệm quanh bo mic
usb_slot_z = wroom_pcb_h + usb_ctr_pcb;   // tâm khe USB trên sàn trong (~16)
face_back  = face_inset + face_t;         // mặt sau của face (y) = 5

/* ---------- Vị trí linh kiện (gốc = mép trong; sửa để nhích) ---------- */
// y của WROOM/IR phải LÙI SAU lưng face (y=face_back=5), nếu không board đâm vào tấm face.
// WROOM lùi thêm vì 4 trụ socket thò ra trước mép board 0.36mm (pin field hụt 2.14, trụ Ø5 lồi 2.5).
wroom_x = wall + 9;      wroom_y = wall + 3.5;  // WROOM front-TRÁI (x12..42, y6.5) — trụ socket cách face 1.1mm
ir_x    = wall + 45;     ir_y    = wall + 2.5;  // IR front-PHẢI (x48..68, y5.5) — LED sát face để bắn thẳng qua lỗ
s2_x    = wall + 41;     s2_y    = wall + 42;   // S2 sau-PHẢI (x44..69) — dịch trái 2mm tránh trụ Ø8
radar_cx = wall + 22;    radar_cy = wall + 64;  // radar trên NẮP, vùng trống sau-trái
mic_cx   = wall + 40;    mic_cy   = wall + 15;  // mic trên NẮP, giữa-trước

/* ================= tiện ích ================= */
// Tâm 4 trụ góc. Cặp TRƯỚC lùi sâu hơn (post_in_f) để chừa rãnh face.
module corner_centers() {
    for (x = [wall + post_in, wall + inner_w - post_in])
        for (y = [wall + post_in_f, wall + inner_l - post_in])
            translate([x, y, 0]) children();
}

/* ================= ĐẾ ================= */
module base() {
    difference() {
        union() {
            cube([out_w, out_l, floor_t]);                                   // sàn
            translate([0, out_l - wall, 0]) cube([out_w, wall, floor_t + deck_h]); // vách sau
            cube([wall, out_l, floor_t + deck_h]);                            // hông trái
            translate([out_w - wall, 0, 0]) cube([wall, out_l, floor_t + deck_h]); // hông phải

            // --- RÃNH TRƯỢT FACE: chữ U mở lên trên ---
            // 2 gờ hông chặn phía TRƯỚC, chạy hết chiều cao -> face không đổ ra ngoài.
            for (x = [wall, out_w - wall - rail_w])
                translate([x, 0, floor_t]) cube([rail_w, face_inset, deck_h]);
            // gờ đáy chặn phía TRƯỚC -> face không tụt xuống quá, cũng không đổ ra
            translate([wall, 0, floor_t]) cube([inner_w, face_inset, 3]);
            // gờ chặn SÀN phía SAU lưng face -> face không bị đẩy vào trong
            translate([wall, face_back, floor_t]) cube([inner_w, stop_t, 3]);

            // 4 trụ góc bắt nắp
            translate([0,0,floor_t]) corner_centers() cylinder(d = post_d, h = deck_h);

            // WROOM: 4 trụ SOCKET cao 13mm — đỉnh có LỖ để CẮM 4 pin góc của WROOM vào.
            // Board tựa vành trụ, 4 pin góc xỏ xuống lỗ -> giữ chặt, không xê, KHÔNG cần keo.
            // (pin ~11mm chui hết vào lỗ sâu ~11.5mm; các pin trong còn lại + dupont thả hốc giữa)
            translate([0,0,floor_t]) difference() {
                for (dx=[-pin_row_gap/2, pin_row_gap/2]) for (dy=[-pin_field_len/2, pin_field_len/2])
                    translate([wroom_x+wroom_w/2+dx, wroom_y+wroom_l/2+dy, 0]) cylinder(d=5, h=wroom_pcb_h);
                for (dx=[-pin_row_gap/2, pin_row_gap/2]) for (dy=[-pin_field_len/2, pin_field_len/2])
                    translate([wroom_x+wroom_w/2+dx, wroom_y+wroom_l/2+dy, wroom_pcb_h-11.5])
                        cylinder(d=pin_hole_d, h=12);
            }
            // S2: 2 trụ vít M2 (pitch 18.5) + gờ định vị
            translate([0,0,floor_t]) {
                for (dx=[-s2_pitch/2, s2_pitch/2])   // 2 lỗ CÙNG HÀNG NGANG, cách 18.5mm
                    translate([s2_x + s2_w/2 + dx, s2_y + s2_l/2, 0]) cylinder(d=5, h=s2_stand);
                translate([s2_x-1.5, s2_y, 0]) cube([1.5, s2_l, 4]);          // gờ hông
                translate([s2_x-1.5, s2_y+s2_l, 0]) cube([s2_w+3, 1.5, 4]);   // gờ sau
            }
            // IR: 2 gờ đỡ module (LED chĩa ra face) — 2mm cho cứng, 1.5mm chỉ ~4 đường in
            translate([0,0,floor_t])
                for (dx=[0, ir_w]) translate([ir_x+dx-1, ir_y+5, 0]) cube([2, ir_l-8, 3]);
        }
        // lỗ ÉP REN ĐỒNG M3 trong 4 trụ góc (từ trên) — không phải lỗ mồi tự ren
        translate([0,0,floor_t+deck_h-insert_deep]) corner_centers()
            cylinder(d=m3_insert, h=insert_deep+2);
        // lỗ tự-ren M2 cho S2 (từ trên xuống trụ)
        translate([0,0,floor_t+s2_stand-5]) for (dx=[-s2_pitch/2, s2_pitch/2])
            translate([s2_x+s2_w/2+dx, s2_y+s2_l/2, 0]) cylinder(d=m2_pilot, h=7);
        // khe USB-C S2 ở VÁCH SAU (nguồn vào — Topo A: sạc cắm S2). Hạ xuống cho khớp cổng.
        translate([s2_x+s2_w/2-6, out_l-wall-1, floor_t + s2_stand - 1])
            cube([12, wall+2, 9]);
        // (v3 bỏ "rãnh luồn dây lên nắp" 10×8 xuyên vách sau: radar và mic đều treo dưới nắp,
        //  board của chúng nằm trong đế -> dây chạy trọn trong khoang, không có gì cần chui ra.
        //  Rãnh đó chỉ còn là lỗ hở đón bụi.)
    }
}

/* ================= MẶT TRƯỚC (thả vào rãnh, không vít) ================= */
module face() {
    difference() {
        // Tấm nằm giữa 2 gờ hông, đứng trên gờ đáy. Trừ khe lắp ở mọi mặt.
        translate([wall + face_gap/2, face_inset, floor_t + face_gap/2])
            cube([inner_w - face_gap, face_t, deck_h - face_gap]);
        // khe USB-C WROOM (cao 11mm dung sai lắp tay)
        translate([wroom_x + wroom_w/2 - 6, -1, floor_t + usb_slot_z - 5.5])
            cube([12, face_t+2, 11]);
        // lỗ LED IR 6.5mm
        translate([ir_x + ir_w/2, face_back+1, floor_t + ir_axis_h]) rotate([90,0,0])
            cylinder(d=6.5, h=face_t+2);
    }
}

/* ================= NẮP ================= */
module lid() {
    difference() {
        union() {
            cube([out_w, out_l, lid_t]);
            // gờ tụt định vị — bắt đầu SAU lưng face, nếu không sẽ đè lên đầu face
            translate([wall+0.4, face_back+0.4, -4])
                cube([inner_w-0.8, out_l-wall-0.4 - (face_back+0.4), 4]);
            // cradle radar ngửa: 4 nub dưới nắp ôm module 15×20 (Ø4 — Ø3 cao 6mm quá mảnh)
            translate([0,0,-6]) for (dx=[-1, radar_w+1]) for (dy=[-1, radar_l+1])
                translate([radar_cx - radar_w/2 + dx, radar_cy - radar_l/2 + dy, 0])
                    cylinder(d=4, h=6);
            // bệ đỡ mic — khối đặc, hốc khoét ở phần difference bên dưới
            translate([mic_cx, mic_cy, -mic_boss_h])
                cylinder(d=mic_pocket_d+4, h=mic_boss_h);
        }
        // Cửa sổ radar: khoét TỪ DƯỚI, chừa 1.5mm nhựa trên mặt (24GHz xuyên tốt), vùng 17×22.
        // v2 khoét cao lid_t=3 giữa ở z=1.5 -> ăn thủng cả 3mm, thành lỗ hở trái với chú thích.
        translate([radar_cx, radar_cy, 0.75])
            cube([radar_w+2, radar_l+2, 1.5], center=true);
        // Hốc mic: khoét TỪ DƯỚI lên, chừa lại mic_shelf làm mặt tì. Sâu 6mm để chứa đủ
        // bo 1.6 + chip chúc xuống ~1.2 + cục hàn ~1 + lớp đệm — vẫn còn dư.
        translate([mic_cx, mic_cy, -mic_boss_h-1])
            cylinder(d=mic_pocket_d, h=mic_boss_h - mic_shelf + 1);
        // Rãnh thoát dây ra hông (về phía WROOM, tức −x): dây hàn ở mặt trên bo nên phải
        // đi ngang, không bẻ ngoặt 180° quanh mép bo.
        translate([mic_cx - mic_pocket_d/2 - 4, mic_cy - 2, -mic_shelf - 2.5])
            cube([6, 4, 2.5]);
        // Lỗ thu âm Ø4 xuyên nắp
        translate([mic_cx, mic_cy, -mic_boss_h-2]) cylinder(d=4, h=mic_boss_h+lid_t+4);
        // 4 lỗ thông vít M3
        translate([0,0,-5]) corner_centers() cylinder(d=m3_free, h=lid_t+10);
        // KHOÉT TRÁNH 4 TRỤ: gờ tụt chạy qua vùng trụ, không khoét là nắp kênh 3.5mm
        translate([0,0,-5]) corner_centers() cylinder(d=post_d+0.6, h=5);
    }
}

/* ================= LẮP ================= */
module assembly() {
    color("LightSteelBlue") base();
    color("Khaki") face();
    color("Silver") translate([0,0,floor_t+deck_h]) lid();
}

// Bóng mờ vị trí board (kiểm bố trí) — không xuất STL, chỉ để xem.
module ghosts() {
    color([0.2,0.6,1,0.45]) translate([wroom_x, wroom_y, floor_t+wroom_pcb_h]) cube([wroom_w, wroom_l, 1.6]);
    color([1,0.5,0.2,0.45]) translate([ir_x, ir_y, floor_t+3]) cube([ir_w, ir_l, 1.6]);
    color([0.3,1,0.3,0.45]) translate([s2_x, s2_y, floor_t+s2_stand]) cube([s2_w, s2_l, 1.6]);
}

// Xem tách rời — dễ thấy rãnh trượt và 4 trụ.
module exploded() {
    color("LightSteelBlue") base();
    color("Khaki") translate([0,-22,0]) face();
    color("Silver") translate([0,0,floor_t+deck_h+26]) lid();
}

if (part=="base") base();
else if (part=="face") face();
else if (part=="lid") lid();
else if (part=="layout") { base(); ghosts(); }
else if (part=="exploded") exploded();
else assembly();
