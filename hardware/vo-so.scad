// ============================================================================
// VỎ SÒ 150×100 — hộp cho ESP32 WROOM + S2 Mini + radar + mic + IR (+PIR sau).
//
// Kết cấu 2 nửa như sò thật:
//   - ĐÁY  = khay phẳng viền vỏ sò (mảnh vỏ phẳng của sò), cao 16mm,
//            chứa toàn bộ board + mọi lỗ chức năng trên thành đứng (dễ in, dễ cắm).
//   - NẮP  = vòm gân (mảnh vỏ cong), chỉ mang lỗ PIR — giữ mặt đẹp nguyên vẹn.
//   - BẢN LỀ chốt 3mm ở đỉnh quạt (khớp sò thật), TAB CHỐT ở mép trước:
//     xuyên đinh/vít M3/dây rút là đóng chặt.
//
// Trục toạ độ: đỉnh quạt (bản lề) ở gốc, mép cung hướng +y. Đơn vị mm.
// ============================================================================

part = "all";           // "day" | "nap" | "all" (all = lắp ráp để xem)

// ---- Tham số vỏ (đã duyệt hình dáng, đừng đổi tuỳ tiện) ----
R    = 100;  goc = 97;  n = 13;  bien = 3;
H_NAP = 44;  gan = 7;            // vòm nắp + độ nổi gân
H_DAY = 16;                       // khay đáy
WALL  = 2.0; FLOOR = 2.0;
NA = 360; NT = 26; T0 = 0.06;

// ---- Hình học vỏ sò (giữ nguyên từ bản đã duyệt) ----
function rib(a) = 0.5 + 0.5 * cos(a / (goc/n) * 180);
function r_at(a) = R + bien * rib(a);
function shell_z(a, t, H) =
    let (d = min(t, 1 - t, 1 - abs(a) / (goc/2)),
         vom = H * pow(sin(min(1, d * 2.6) * 90), 0.75),
         gan_z = gan * rib(a) * t * min(1, (1 - abs(a)/(goc/2)) / 0.10)
                              * min(1, (1 - t) / 0.04))
    vom + gan_z;

module shell_solid(H) {
    pts = concat(
        // mặt trên tối thiểu 0.4mm: tại mép/cạnh bên shell_z=0 trùng mặt đáy
        // → tam giác diện tích 0 → mesh hở; 0.4mm cũng là cạnh in được tối thiểu
        [ for (j = [0:NT], i = [0:NA])
            let (a = -goc/2 + goc*i/NA, t = T0 + (1-T0)*j/NT, r = r_at(a)*t)
            [r*sin(a), r*cos(a), max(shell_z(a, t, H), 0.4)] ],
        [ for (j = [0:NT], i = [0:NA])
            let (a = -goc/2 + goc*i/NA, t = T0 + (1-T0)*j/NT, r = r_at(a)*t)
            [r*sin(a), r*cos(a), 0] ]);
    W = NA + 1;  B = (NT+1)*W;
    // Mặt 4 đỉnh trên mặt cong KHÔNG phẳng → CGAL boolean vỡ (đã dính:
    // difference() nuốt luôn khối khoét thành union rác). Chia hết thành tam giác.
    quads = concat(
        [ for (j=[0:NT-1], i=[0:NA-1]) [j*W+i, j*W+i+1, (j+1)*W+i+1, (j+1)*W+i] ],
        [ for (j=[0:NT-1], i=[0:NA-1]) [B+j*W+i, B+(j+1)*W+i, B+(j+1)*W+i+1, B+j*W+i+1] ],
        [ for (i=[0:NA-1]) [NT*W+i, NT*W+i+1, B+NT*W+i+1, B+NT*W+i] ],
        [ for (i=[0:NA-1]) [i+1, i, B+i, B+i+1] ],
        [ for (j=[0:NT-1]) [j*W, (j+1)*W, B+(j+1)*W, B+j*W] ],
        [ for (j=[0:NT-1]) [(j+1)*W+NA, j*W+NA, B+j*W+NA, B+(j+1)*W+NA] ]);
    faces = [ for (q = quads, tri = [[q[0],q[1],q[2]], [q[0],q[2],q[3]]]) tri ];
    polyhedron(points = pts, faces = faces, convexity = 12);
}

// Viền vỏ sò 2D (mặt bằng của khay đáy) — quạt kín từ gốc ra mép lượn sóng.
module outline_2d() {
    polygon(concat([[0, 0]],
        [ for (i = [0:NA]) let (a = -goc/2 + goc*i/NA, r = r_at(a))
            [r*sin(a), r*cos(a)] ]));
}

// Khung định vị board: viền 1.2mm, cao 4mm, hở 1mm quanh board — board đặt vào
// rồi dán băng keo 2 mặt/keo nến. KHÔNG làm ngàm khít: kích thước board thật
// (chân hàn, dây) không đo chính xác được, ngàm khít sai 1mm là in lại cả hộp.
module fence(bw, bd) {
    linear_extrude(4) difference() {
        square([bw + 2 + 2.4, bd + 2 + 2.4], center = true);
        square([bw + 2, bd + 2], center = true);
    }
}

// Lỗ xuyên thành đứng của khay tại góc a (0 = chính giữa mép trước), tâm cao z.
module wall_hole(a, z, d) {
    rotate([0, 0, -a]) translate([0, R - 6, z])
        rotate([-90, 0, 0]) cylinder(d = d, h = 16, $fn = 32);
}

// ---------------------------------------------------------------- ĐÁY (khay)
module day() {
    difference() {
        union() {
            // thân khay: thành 2mm, sàn 2mm
            difference() {
                linear_extrude(H_DAY) outline_2d();
                translate([0, 0, FLOOR])
                    linear_extrude(H_DAY) offset(-WALL) outline_2d();
            }
            // 2 lug bản lề sát đỉnh quạt, lỗ chốt ngang 3.4mm.
            // Trục chốt ở z=22 (6mm trên mặt vành): đủ cao để lug nắp không phải
            // thò xuống dưới vành → cả 2 nửa đều in phẳng trên bàn, không cần support lug
            for (sx = [-1, 1]) translate([sx*7.9, 15, 13.5])
                cube([5, 10, 27], center = true);
            // tab chốt mép trước — lệch 14° khỏi giữa để không đè lên khe USB-C
            rotate([0, 0, -14]) translate([-6, 99, 11]) cube([12, 9, 5]);
            // khung định vị board (đặt board xong dán keo/băng dính):
            translate([0, 68.5, FLOOR]) fence(30, 57.5);            // WROOM, USB quay ra trước
            translate([-33, 62, FLOOR]) fence(26.4, 35.3);          // S2 Mini
            rotate([0, 0, -32]) translate([0, 90, FLOOR]) fence(37, 9);    // LD2410 dựng sát thành
            // mic INMP441 nhỏ (14×13): dán keo ngay sau lỗ mic, không cần khung
        }
        // lỗ chốt bản lề (xuyên cả 2 lug theo trục x)
        translate([0, 15, 22]) rotate([0, 90, 0]) cylinder(d = 3.4, h = 40, center = true, $fn = 24);
        // lỗ vít/đinh tab chốt trước (cùng góc 14° với tab)
        rotate([0, 0, -14]) translate([0, 103.5, 8]) cylinder(d = 3.4, h = 20, $fn = 24);
        // khe USB-C cấp nguồn vào WROOM (rộng rãi cho mọi kiểu board/cáp)
        translate([-5.5, 96, 4]) cube([11, 12, 8]);
        // lỗ mic (INMP441 nằm ngay sau thành)
        wall_hole(-20, 8, 4);
        // lỗ LED IR (KY-005 chĩa ra, dí sát mắt nhận dàn lạnh)
        wall_hole(15, 9, 5.5);
    }
}

// ---------------------------------------------------------------- NẮP (vòm)
module nap() {
    difference() {
        union() {
            // vỏ vòm: khoét bằng chính vỏ thu nhỏ quanh gốc (đỉnh quạt) →
            // thành hông ~4mm, đỉnh vòm ~5mm, hở hoàn toàn phía dưới
            difference() {
                shell_solid(H_NAP);
                // ruột = chính vỏ thu 0.96/0.92 quanh gốc, hạ 2mm để hở đáy:
                // đỉnh vòm còn 44 − (0.92·44 − 2) ≈ 5.5mm, thành hông ~4mm
                translate([0, 0, -2]) scale([0.96, 0.96, 0.92]) shell_solid(H_NAP);
            }
            // lug bản lề giữa (lọt khe 2 lug đáy, hở 0.4mm mỗi bên),
            // đáy lug ở z=3 — KHÔNG thò xuống dưới mặt vành để in phẳng được
            translate([0, 15, 15.5]) cube([10, 10, 25], center = true);
            // tab chốt mép trước (đè lên tab đáy khi đóng), cùng góc 14°
            rotate([0, 0, -14]) translate([-6, 96, 0]) cube([12, 13, 4]);
        }
        // lỗ chốt bản lề — khi đóng nắp (nắp +16), z=6 thẳng hàng lỗ lug đáy z=22
        translate([0, 15, 6]) rotate([0, 90, 0]) cylinder(d = 3.4, h = 20, center = true, $fn = 24);
        // lỗ vít tab chốt (thẳng hàng lỗ tab đáy khi đóng)
        rotate([0, 0, -14]) translate([0, 103.5, -1]) cylinder(d = 3.4, h = 8, $fn = 24);
        // lỗ vòm PIR d23.5 (lắp sau — PIR cố định bằng keo nến từ trong)
        translate([0, 60, 15]) cylinder(d = 23.5, h = 60, $fn = 48);
    }
}

// ---------------------------------------------------------------- XUẤT
if (part == "day") day();
if (part == "nap") nap();
if (part == "all") { day(); translate([0, 0, H_DAY]) nap(); }
