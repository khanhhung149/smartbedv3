// ============================================================================
// VỎ SÒ 150×100 — hộp cho ESP32 WROOM + S2 Mini + radar (UART) + mic + IR.
// KHÔNG còn PIR: LD2410 đọc qua UART (moving/stationary + cự ly + năng lượng) đủ
// thay vai trò phát hiện người, radar lo hết. Mic dời lên NẮP (dây I2S đi thẳng đứng).
//
// Kết cấu 2 nửa như sò thật:
//   - ĐÁY  = khay phẳng viền vỏ sò (mảnh vỏ phẳng của sò), cao 16mm,
//            chứa toàn bộ board + lỗ USB-C/IR trên thành đứng (dễ in, dễ cắm).
//   - NẮP  = vòm gân (mảnh vỏ cong), mang lỗ mic d5 ở đỉnh — giữ mặt đẹp nguyên vẹn.
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
WALL_NAP = 4.0;                   // độ hạ ruột nắp theo phương đứng (xem nap())
NA = 360; NT = 26; T0 = 0.06;

// ---- Hình học vỏ sò (giữ nguyên từ bản đã duyệt) ----
function rib(a) = 0.5 + 0.5 * cos(a / (goc/n) * 180);
function r_at(a) = R + bien * rib(a);
// Mặt vòm TRƠN — chỉ phần vòm, không có gân nổi.
function shell_z_base(a, t, H) =
    let (d = min(t, 1 - t, 1 - abs(a) / (goc/2)))
    H * pow(sin(min(1, d * 2.6) * 90), 0.75);
// Mặt ngoài thật = vòm trơn + gân nổi.
function shell_z(a, t, H) =
    shell_z_base(a, t, H)
    + gan * rib(a) * t * min(1, (1 - abs(a)/(goc/2)) / 0.10)
                       * min(1, (1 - t) / 0.04);

// Lưới tam giác dùng chung cho vỏ ngoài và khối khoét ruột — cùng số điểm,
// cùng cách nối, chỉ khác toạ độ. Mặt 4 đỉnh trên mặt cong KHÔNG phẳng → CGAL
// boolean vỡ (đã dính: difference() nuốt luôn khối khoét). Chia hết thành tam giác.
function shell_faces() =
    let (W = NA + 1, B = (NT+1)*W,
         quads = concat(
            [ for (j=[0:NT-1], i=[0:NA-1]) [j*W+i, j*W+i+1, (j+1)*W+i+1, (j+1)*W+i] ],
            [ for (j=[0:NT-1], i=[0:NA-1]) [B+j*W+i, B+(j+1)*W+i, B+(j+1)*W+i+1, B+j*W+i+1] ],
            [ for (i=[0:NA-1]) [NT*W+i, NT*W+i+1, B+NT*W+i+1, B+NT*W+i] ],
            [ for (i=[0:NA-1]) [i+1, i, B+i, B+i+1] ],
            [ for (j=[0:NT-1]) [j*W, (j+1)*W, B+(j+1)*W, B+j*W] ],
            [ for (j=[0:NT-1]) [(j+1)*W+NA, j*W+NA, B+j*W+NA, B+(j+1)*W+NA] ]))
    [ for (q = quads, tri = [[q[0],q[1],q[2]], [q[0],q[2],q[3]]]) tri ];

// Ruột nắp = chính vỏ ngoài HẠ XUỐNG theo phương thẳng đứng. Cách này không bao
// giờ tự cắt (dịch đứng một mặt height-field vẫn là height-field), khác hẳn mặt
// song song theo pháp tuyến: gân vỏ có bán kính cong ~1.2mm và hàm min() tạo nếp
// gấp sắc, lùi vào sâu hơn là CGAL vỡ. Đổi lại độ dày vuông góc bằng
// WALL_NAP·cos(độ dốc) — mỏng dần ở sườn dốc, nên WALL_NAP đặt dư ra.
// Vùng nào vỏ thấp hơn WALL_NAP (viền và hai mép chéo) thì ruột tụt xuống dưới
// z=0 và không cắt gì → dải quanh chu vi để đặc.

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
    polyhedron(points = pts, faces = shell_faces(), convexity = 12);
}

// Khối đặc mặt trên là vòm TRƠN (không gân). Dùng làm ruột khoét nắp: hạ xuống
// WALL_NAP thì chỗ có gân vỏ dày thêm cả chiều cao gân, và SƯỜN GÂN không còn tạo
// điểm mỏng — bản bám theo cả gân trước đây tụt còn 0.76mm ở sườn dốc. Cấu trúc y
// hệt shell_solid (đáy z=0) nên difference() ổn định; chỉ khác z mặt trên là trơn.
module shell_solid_smooth(H) {
    pts = concat(
        [ for (j = [0:NT], i = [0:NA])
            let (a = -goc/2 + goc*i/NA, t = T0 + (1-T0)*j/NT, r = r_at(a)*t)
            [r*sin(a), r*cos(a), max(shell_z_base(a, t, H), 0.4)] ],
        [ for (j = [0:NT], i = [0:NA])
            let (a = -goc/2 + goc*i/NA, t = T0 + (1-T0)*j/NT, r = r_at(a)*t)
            [r*sin(a), r*cos(a), 0] ]);
    polyhedron(points = pts, faces = shell_faces(), convexity = 12);
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
            // Tab chốt mép trước — lệch 14° khỏi giữa để không đè lên khe USB-C.
            // Khối đặc suốt từ mặt bàn (z=0) lên ngang vành (z=16): tab treo lơ
            // lửng ở z=11 thì lớp nhựa đầu tiên nhả vào không khí, võng và yếu
            // đúng chỗ bắt vít. Đặc từ đáy lên thì in thẳng, không cần support.
            rotate([0, 0, -14]) translate([-6, 99, 0]) cube([12, 9, H_DAY]);
            // Khung định vị CHỈ cho WROOM (cần thẳng hàng khe USB-C).
            // Cụm S2+radar đã HÀN LIỀN thành một khối cứng → không ép vào khung
            // được, chừa trống nửa trái khay: dán keo, radar áp sát thành nào
            // cũng xuyên được (thành 2mm, sóng 24GHz qua tốt).
            // Mic INMP441 nhỏ (14×13): dán keo ngay sau lỗ mic.
            translate([0, 68.5, FLOOR]) fence(30, 57.5);            // WROOM, USB quay ra trước
        }
        // lỗ chốt bản lề (xuyên cả 2 lug theo trục x)
        translate([0, 15, 22]) rotate([0, 90, 0]) cylinder(d = 3.4, h = 40, center = true, $fn = 24);
        // lỗ vít/đinh tab chốt trước (cùng góc 14° với tab)
        rotate([0, 0, -14]) translate([0, 103.5, -1]) cylinder(d = 3.4, h = 20, $fn = 24);
        // Khe USB-C cấp nguồn vào WROOM. Khe đo theo VỎ NHỰA đầu cáp chứ không
        // theo đầu kim loại 8.4×2.6: đầu kim loại chỉ dài 6.5mm mà phải cắm sâu
        // ~6mm vào ổ → vỏ nhựa bắt buộc chui qua thành 2-3mm mới với tới board.
        translate([-6, 96, 4]) cube([12, 12, 8]);
        // lỗ mic (INMP441 nằm ngay sau thành)
        wall_hole(-20, 8, 4);
        // Lỗ LED IR (chĩa ra, dí sát mắt nhận dàn lạnh). 6.5mm chứ không phải
        // 5.5: LED "5mm" có gờ vành ở chân rộng ~5.9mm, và lỗ in ra hụt thêm
        // 0.2-0.4mm so với thiết kế — 5.5 chặn đúng cái gờ, không nhét lọt.
        wall_hole(15, 9, 6.5);
    }
}

// ---------------------------------------------------------------- NẮP (vòm)
module nap() {
    difference() {
        union() {
            difference() {
                shell_solid(H_NAP);
                translate([0, 0, -WALL_NAP]) shell_solid_smooth(H_NAP);
            }
            // Lug bản lề giữa (lọt khe 2 lug đáy, hở 0.4mm mỗi bên). Dựng thành
            // CỘT cao rồi cắt bằng chính vỏ ngoài: mặt dưới vòm ở chỗ này nằm tận
            // z≈33, nên lug cao cố định tới z=28 như trước là một khối lập phương
            // rời hẳn, lơ lửng trong lòng nắp — nắp in ra coi như không có bản lề.
            // Cắt theo shell_solid đảm bảo lug vừa dính chắc vào vòm vừa không thò
            // ra khỏi mặt ngoài.
            intersection() {
                translate([-5, 10, 3]) cube([10, 10, 60]);
                shell_solid(H_NAP);
            }
            // tab chốt mép trước (đè lên tab đáy khi đóng), cùng góc 14°
            rotate([0, 0, -14]) translate([-6, 96, 0]) cube([12, 13, 4]);
        }
        // lỗ chốt bản lề — khi đóng nắp (nắp +16), z=6 thẳng hàng lỗ lug đáy z=22
        translate([0, 15, 6]) rotate([0, 90, 0]) cylinder(d = 3.4, h = 20, center = true, $fn = 24);
        // lỗ vít tab chốt (thẳng hàng lỗ tab đáy khi đóng)
        rotate([0, 0, -14]) translate([0, 103.5, -1]) cylinder(d = 3.4, h = 8, $fn = 24);
        // Lỗ mic trên đỉnh vòm: mic INMP441 dán trong nắp, dây I2S đi thẳng đứng
        // xuống WROOM. d5 đủ cho cổng thu âm + luồn dây; mic áp mặt cổng vào lỗ, bôi
        // keo vòng quanh mép, KHÔNG để keo bịt cổng. (Trước là lỗ PIR d23.5 — đã bỏ
        // PIR khỏi hệ thống, radar UART lo hết việc phát hiện người.)
        translate([0, 60, 15]) cylinder(d = 5, h = 60, $fn = 32);
    }
}

// ---------------------------------------------------------------- XUẤT
if (part == "day") day();
if (part == "nap") nap();
if (part == "all") { day(); translate([0, 0, H_DAY]) nap(); }
