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
// WROOM đã bỏ hoàn toàn (board chết 29/07, thay bằng ESP32-S3 bên dưới). Face cũng in lại nên
// không còn gì phải giữ toạ độ theo WROOM nữa — mọi biến wroom_* đã xoá.

// S2 Mini. Chiều dài 34.3 là số DANH NGHĨA và còn ngờ: datasheet ghi 16 chân/hàng, tức dãy
// chân 15×2.54 = 38.1mm — DÀI HƠN cả bo 34.3mm, không thể đúng cùng lúc. Nhưng vị trí 2 lỗ
// vít neo trực tiếp vào cổng USB-C (s2_hole_to_usb) nên chiều dài bo không ảnh hưởng khay.
s2_w = 25.4;  s2_l = 34.3;        // S2 Mini (rộng×dài, danh nghĩa)
s2_pitch = 20;                    // tâm-tâm 2 lỗ vít (xác nhận 28/07)
// Lỗ mồi khoét thành RÃNH dài ±0.5mm theo x. Pitch 20 đo bằng chấm giấy + thước kẻ nên còn
// sai số cỡ đó; rãnh nuốt hết mà bề RỘNG vẫn 1.7 nên ren M2 vẫn cắn đủ vào 2 thành dọc.
s2_pitch_tol = 0.5;               // nửa chiều dài phần nới thêm của rãnh
s2_hole_to_usb = 30;              // tâm lỗ vít -> ĐẦU cổng USB-C — mốc neo thật sự của khay S2
s2_usb_gap = 1;                   // hở giữa đầu cổng và mặt trong vách sau
// GIỮ NGUYÊN 6mm: chiều cao cổng USB-C so với khe ở vách sau phụ thuộc đúng con số này,
// và khe đã được nghiệm thu là khớp khi in ướm 28/07. Đổi là lệch cổng.
s2_stand = 6;                     // trụ đỡ S2
// HLK-LD2410C — số 15×20×1.6 dùng suốt từ 24/07 là SAI. Datasheet + 2 nguồn độc lập đều cho
// 22 × 16 × 3mm, pitch 2.54, chân TX RX OUT GND VCC (khớp silkscreen trên ảnh module thật).
// Hốc cũ 15.4×20.4 KHÔNG lọt nổi bo 16×22 — thiếu 0.6mm ngang và 1.6mm dọc.
//
// ⚠️ Con số 15×18×3 "cm" trong mô tả bán hàng là KÍCH THƯỚC GÓI HÀNG (phong bì xốp 150×180×30mm),
// không phải module. Đừng lấy nhầm.
radar_w = 16;  radar_l = 22;      // radar (ngửa dưới nắp), rộng×dài
radar_t = 3;                      // bề dày cả cụm bo + linh kiện, KHÔNG tính chân header
// LD2410C bản trần KHÔNG có lỗ vít nào (user xác nhận 31/07) nên không bắt vít được — chỉ định vị
// bằng hốc rồi dán. Đừng đề xuất trụ vít cho module này.
//
// CHIỀU LẮP (ảnh module thật 31/07): ăng-ten ở MỘT mặt, hàng 5 pin chĩa ra mặt ĐỐI DIỆN.
// Lắp ĂNG-TEN NGỬA LÊN NẮP, chân tự động thõng xuống khoang. KHÔNG cắt pin, KHÔNG khoét lỗ trên
// nắp — xem ghi chú radar_hdr_h bên dưới.
//
// Muốn giữ hoàn toàn bằng cơ khí thay băng keo thì thứ giải đúng là TẤM CHẶN bắt vít ép bo từ dưới
// lên — chặn đúng phương duy nhất hốc bỏ sót (rơi ra vuông góc). Dưới hốc còn 14.4mm tới bo S3.
radar_fit = 0.4;                  // khe lắp tổng của hốc (dung sai FDM ~0.2/mặt)
radar_rim = 1;                    // gờ chặn quanh cửa sổ để bo không trồi lên
// ĐÃ BỎ hướng khoét lỗ cho hàng pin xỏ lên nắp (từng làm rãnh 2×14, rồi 5 lỗ Ø1.6 bước 2.54).
//
// Lý do dứt điểm, xác nhận bằng ảnh module thật 31/07: ăng-ten và hàng pin nằm HAI MẶT ĐỐI NHAU.
// Muốn sóng xuyên màng thì ăng-ten phải ngửa lên nắp, khi đó chân TỰ ĐỘNG chĩa xuống khoang —
// không có gì hướng lên nắp để mà xỏ. Lắp ngược lại (chân lên nắp) thì cắm vừa khít nhưng ăng-ten
// quay vào lòng hộp, bắn sóng vào bo S3 và vách nhựa: radar mù mà nhìn bề ngoài vẫn "vừa khít".
// Đây là kiểu lỗi không lộ ra khi lắp, chỉ lộ khi radar không báo người.
//
// Bỏ được luôn cái giá đi kèm: trước phải thu hẹp cửa sổ màng để lấy chỗ khoan, mất ~15% khẩu độ.
// Giờ cửa sổ trở lại đối xứng, lấy lại trọn khẩu độ.
radar_hdr_h = 8.5;                // bao hình cục header + chân thõng xuống DƯỚI mặt bo

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
// Gờ đỡ IR dày và cao hơn bản trước (2->3, 3->5) theo yêu cầu 31/07: gờ 2mm mảnh quá, và nâng
// module lên giúp LED bắn thẳng hơn qua lỗ face.
ir_rib_t = 3;                     // bề dày mỗi gờ
ir_rib_h = 5;                     // chiều cao gờ = mặt đáy module trên sàn trong
// Tâm LED nằm 4mm trên mặt đáy module (đo từ bản v3: gờ 3 -> tâm 7). Buộc phải suy ra từ
// ir_rib_h, nếu ghi số chết thì nâng gờ mà quên sửa là lỗ trên face lệch xuống đúng bằng
// phần nâng.
ir_axis_h = ir_rib_h + 4;         // tâm LED IR cao trên sàn trong

// === ESP32-S3-CAM thay WROOM (31/07) — voice-node ===
// WROOM-32 chết hẳn 29/07, voice-node chuyển sang GOOUUU ESP32-S3-CAM (module N16R8).
// Số đo TAY trên chính board 30/07. KHÔNG dùng số tra mạng cho "ESP32-S3-N16R8": bản generic
// là 67×31 với 4 lỗ ở 4 góc, board này 65×26.5 và CHỈ 2 lỗ, cả hai ở đầu USB-C.
s3_w = 26.5;  s3_l = 65;          // PCB (rộng×dài)
// s3_h là số user đo bằng thước, nhưng KHÔNG khớp với thực tế lắp (xem s3_pin_drop) nên KHÔNG
// dùng cho hình học nào — giữ lại chỉ để đối chiếu.
s3_h = 10;                        // đỉnh cổng USB-C -> đáy chân GPIO (số đo, còn ngờ)
s3_pcb_t = 1.6;
// Chân GPIO thò xuống dưới mặt đáy PCB. Suy ra TỪ LẦN ƯỚM BẢN IN THẬT 31/07: với trụ cao 8mm
// thì chân "vừa chạm" sàn ⇒ chân dài xấp xỉ đúng 8mm.
//
// Con số này BÁC BỎ phép suy cũ "chân tối đa = s3_h - s3_pcb_t - 3.16 = 5.24mm". Cộng ngược:
// 8 + 1.6 + 3.16 = 12.76mm, không phải 10mm như s3_h ghi ⇒ s3_h đo sai hoặc đo thứ khác.
// Bài học: đừng suy chiều cao chân từ tổng chiều cao bo, hãy ướm rồi đo.
s3_pin_drop = 8;
// Trụ = chiều dài chân + khe hở. 2mm khe là đủ: chân "vừa chạm" ở trụ 8mm nên 10mm cho hở thật
// 2mm, không cần nâng nhiều hơn (nâng thừa chỉ đẩy bo lên cao vô ích và làm trụ mảnh hơn).
// Viết dạng công thức để đo lại chân là trụ tự theo.
// Nâng trụ tự kéo 2 lỗ USB-C trên face lên theo, vì s3_usb_z cũng suy ra từ biến này.
s3_stand = s3_pin_drop + 2;       // = 10
s3_usb_out = 1;                   // cổng thò ra khỏi mép PCB
s3_usb_gap = 0.5;                 // hở giữa mặt cổng và mặt TRONG của face — để càng sát càng tốt:
                                  // phích USB-C chỉ cắm sâu ~6.5mm mà face đã dày 3mm
// ĐẦU USB-C QUAY RA FACE. Làm được vì user chốt 31/07 IN LẠI CẢ FACE — khe cũ rộng 12mm của
// WROOM không đủ cho hai cổng, giờ khoét lại thành 2 lỗ đúng vị trí 2 cổng S3.
// ⚠️ HAI SỐ DƯỚI ĐÂY LÀ ƯỚC, CHƯA ĐO BẰNG THƯỚC. Đo lại trước khi in face.
// 12.5 suy từ hình học: cổng USB-C tiêu chuẩn rộng 8.94mm, hai cổng đối xứng qua tâm bo rộng
// 26.5 thì mỗi bên còn ~2.5mm mép và ~3.6mm khe giữa — vừa khít và hợp lý.
s3_usb_pitch = 12.5;              // tâm-tâm 2 cổng USB-C (TTL trái, OTG phải)
s3_usb_w = 10;                    // bề rộng thân cổng + dung sai (8.94 + dung sai)
s3_usb_h = 5.5;                   // chiều cao thân cổng + dung sai (3.26 + dung sai)
// MỘT cửa thông cả bề dày face, trùm CẢ HAI cổng — không phải 2 lỗ vừa khít thân cổng.
//
// Lý do (đo trên bản in thật 31/07): mặt cổng nằm ở y=5.5, mặt ngoài face ở y=2 ⇒ cách 3.5mm.
// Vỏ kim loại của phích chỉ chìa ~6.5mm khỏi cục nhựa, nên khi cục nhựa chạm mặt face thì đầu vỏ
// mới tới y=8.5, tức chui vào cổng đúng 3.0mm trong khi cần ~6.5mm mới ăn khớp — THIẾU 3.5mm.
// Phích không cắm tới nơi.
//
// Không dời bo ra sát face được: bo do 2 trụ vít trong BASE định vị, dời bo là phải in lại base.
// Khoét bậc cũng không đủ: hạ 2mm chừa 1mm nhựa vẫn thiếu 1.5mm, mà chừa 0.5mm thì vách vỡ.
// Chỉ còn cách khoét THÔNG để cục nhựa của phích lọt vào tới sát cổng ⇒ ăn đủ 6.5mm.
//
// Buộc phải gộp 2 lỗ làm 1: cục nhựa phích rộng ~12mm mà tâm-tâm 2 cổng chỉ 12.5mm ⇒ hai lỗ riêng
// chừa vách 0.5mm ở giữa, sợi nhựa đó gãy khi in hoặc khi cắm.
s3_usb_plug_clear = 1;            // hở thêm mỗi bên cho vỏ nhựa của phích
s3_usb_open_w = s3_usb_pitch + s3_usb_w + 2*s3_usb_plug_clear;  // = 24.5
s3_usb_open_h = 8;                // cao hơn thân cổng để nuốt cả vỏ nhựa phích
// 2 lỗ vít M2.5 ở đầu USB-C. Pitch CHƯA ĐO CHẮC: user ước 26mm nhưng bất khả trên bo rộng
// 26.5 (lỗ M2.5 phải cách mép >=2.5mm => tối đa ~21.5); 26 nhiều khả năng là đo mép-ngoài-tới-
// mép-ngoài. Giữ 23 làm danh nghĩa.
s3_hole_pitch = 23;
// Rãnh ±2 -> ±0.5 (31/07): user ướm thấy lỗ mồi rộng hơn hẳn lỗ TRÒN trên bo nên vít có độ rơ.
// ±0.5 là đúng con số khay S2 đang chạy tốt — rãnh còn 2.1×3.1mm, gần như tròn, vít tự ren vẫn
// cắn đủ hai thành dọc mà vẫn nuốt được sai số nhỏ. Không làm tròn hẳn vì pitch vẫn là số đoán:
// lỗ tròn đặt sai 1mm là vít không vào, phải in lại cả base.
s3_hole_tol   = 0.5;              // nửa chiều dài phần kéo dài của rãnh
s3_hole_to_end = 3;               // tâm lỗ vít cách mép ĐẦU USB-C của PCB

/* ---------- Khung ---------- */
// inner_l 82 -> 85 (28/07): đuôi WROOM chạm mặt trong của face khi in ướm. Dài thêm 3mm,
// WROOM lùi 2mm — không lùi đủ 3 vì lùi càng xa thì phích USB-C càng phải thọc sâu, mà độ
// sâu cắm của phích chỉ ~6.5mm (3mm dày face + phần hở).
inner_w = 76;  inner_l = 85;  deck_h = 30;
wall = 3;  floor_t = 3;  lid_t = 3;
// 1.5 -> 0.8 (31/07). Tổn hao qua tấm điện môi mỏng chủ yếu do PHẢN XẠ, không phải hấp thụ:
//   |T|² = 1 / (1 + ((εr−1)²/4εr)·sin²(βt))
// Bước sóng 24GHz trong không khí 12.5mm; PETG có εr ≈ 2.6-3.0 nên trong nhựa còn ~7.5mm.
//   t=1.5mm -> βt=72°  -> |T|²≈0.79 -> −1.0 dB một chiều, −2.0 dB KHỨ HỒI (radar đi và về)
//   t=0.8mm -> βt=38.6° -> |T|²≈0.90 -> −0.46 dB một chiều, −0.9 dB khứ hồi
// Tầm radar tỷ lệ công suất mũ ¼ nên −2 dB làm tầm giảm ~11%. Mỏng còn 0.8 lấy lại hơn nửa.
//
// KHÔNG khoét hở hẳn dù được trọn 2 dB: ăng-ten patch 24GHz rất nhạy với vật lạ áp sát mặt, mà
// hộp dán sát dàn lạnh nơi có gió + hơi ẩm thổi ra liên tục. Bụi bám lâu ngày làm lệch cộng
// hưởng, tệ hơn 2 dB. Đổi 2 dB lấy một thứ xuống cấp dần theo thời gian là lỗ vốn.
//
// Cũng KHÔNG đuổi theo màng nửa bước sóng (~3.7mm, phản xạ triệt tiêu hoàn toàn): εr của PETG in
// 3D không biết chính xác nên lệch một chút là hỏng hiệu ứng, mà nắp chỉ dày 3mm cũng không đủ chỗ.
//
// In dễ: nắp in úp mặt trên xuống bàn nên màng là 4 lớp đầu nằm trực tiếp trên mặt bàn.
radar_mem_t = 0.8;            // nhựa chừa lại trên cửa sổ radar để sóng 24GHz xuyên qua
post_d = 8;                   // trụ góc Ø8: đủ thịt để ép ren đồng M3 (thành còn ~1.9mm)
post_in = 3.5;                // trụ lùi vào theo X, và theo Y ở phía SAU
post_in_f = 6;                // trụ TRƯỚC lùi sâu hơn — mặt trước trụ phải nằm sau lưng face
m25_pilot = 2.1;              // lỗ mồi vít TỰ REN M2.5 (cùng nguyên tắc với m2_pilot dưới đây)
m3_free = 3.4;  m2_pilot = 1.7;   // 1.7 = lỗ mồi vít TỰ REN M2 (ren ngoài Ø2.0). Khoét to hơn
                                 // là vít quay tít không bám — muốn dung sai thì nới ĐƯỜNG
                                 // KÍNH TRỤ, không nới lỗ mồi.
lid_lip_h = 4;                // chiều cao gờ tụt định vị dưới nắp
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
face_back  = face_inset + face_t;         // mặt sau của face (y) = 5

/* ---------- Vị trí linh kiện (gốc = mép trong; sửa để nhích) ---------- */
// y của WROOM/IR phải LÙI SAU lưng face (y=face_back=5), nếu không board đâm vào tấm face.
// WROOM lùi thêm vì 4 trụ socket thò ra trước mép board 0.36mm (pin field hụt 2.14, trụ Ø5 lồi 2.5).
// x chọn sao cho TÂM BO giữ nguyên khi sửa bề rộng, nhờ vậy 2 khe USB-C đang khớp không
// phải đụng tới: tâm WROOM x=27, tâm S2 x=56.5.
ir_x    = wall + 45;        ir_y    = wall + 2.5;  // IR front-PHẢI (x48..68) — LED sát face
s2_x    = 56.5 - s2_w/2;                           // S2 sau-PHẢI (x43.8..69.2)

// S3 ở CỘT TRÁI (chỗ WROOM cũ), tâm x=27. Bo dài 65 thay vì 51.5 nhưng vẫn thừa chỗ: cột trái
// trống từ y=6.5 (sau lưng face) tới y=88 (mặt trong vách sau) = 81.5mm. S2 KHÔNG cản vì nằm ở
// cột x khác (43.8..69.2), không nối tiếp theo y — đây là chỗ dễ kết luận nhầm "65mm không vừa".
s3_x = 27 - s3_w/2;                                // x 13.75..40.25
s3_y = face_back + s3_usb_gap + s3_usb_out;        // = 6.5, mép ĐẦU USB-C của PCB
s3_hole_y = s3_y + s3_hole_to_end;                 // = 9.5, tâm 2 lỗ vít
// Tâm thân cổng USB-C so với đáy ngoài base: đáy PCB (floor_t+s3_stand) + PCB 1.6 + nửa thân
// cổng 3.26/2. Lỗ trên face bám theo số này, không ghi số chết.
s3_usb_z = floor_t + s3_stand + s3_pcb_t + 3.26/2; // = 14.23

// Tâm 2 lỗ vít S2 neo NGƯỢC từ vách sau ra, qua cổng USB-C — không neo theo mép bo, vì
// chiều dài bo còn chưa chắc. Bản trước đặt trụ ở giữa bo (y=63.5) nên lệch 8.5mm, vặn
// không vào; đó là lỗi "2 lỗ không vừa" khi in ướm.
s2_hole_y = out_l - wall - s2_usb_gap - s2_hole_to_usb;   // = 55
s2_y      = out_l - wall - s2_usb_gap - 1 - s2_l;         // mép trước bo; 1 = phần cổng thò khỏi PCB
radar_cx = wall + 22;    radar_cy = wall + 64;  // radar trên NẮP, vùng trống sau-trái
// Cửa sổ ĐỐI XỨNG trong hốc, hẹp hơn mỗi bên đúng radar_rim để chừa gờ chặn.
radar_win_x0 = radar_cx - radar_w/2 + radar_rim;                           // = 18
radar_win_x1 = radar_cx + radar_w/2 - radar_rim;                           // = 32
radar_pocket_x0 = radar_cx - (radar_w + radar_fit)/2;                      // = 16.8, mép −x hốc

// === CỬA THOÁT DÂY RADAR (01/08) ===
// Dây hàn thẳng vào 5 pad ở MẶT ĂNG-TEN (mặt ngửa lên nắp), KHÔNG dùng hàng pin chĩa xuống.
// Đúng bài toán của hốc mic — xem chú thích "Rãnh thoát dây ra hông" trong lid().
//
// Chỗ CHỨA thì đã có sẵn: giữa mặt bo (z=0) và trần cửa sổ (z=lid_t-radar_mem_t) là 2.2mm, đủ cho
// vảy thiếc bẹt ~1mm + dây 28-30AWG Ø~1.2mm. Thiếu duy nhất là ĐƯỜNG RA — hốc kín 4 phía, khe
// hông chỉ 0.2mm, mà gờ tụt cắm vào miệng hộp cũng chỉ hở 0.4mm quanh chu vi nên không có khe nào
// cho dây tụt xuống khoang.
//
// Gỡ bằng 2 nhát: RÃNH DÂY hạ gờ chặn trên dải có hàng pad + GIẾNG RƠI đục thủng tường hốc, hở
// đáy thẳng xuống khoang. Dây bò ngang rồi gập 90° rơi xuống, KHÔNG bẻ 180° quanh mép bo.
//
// ⚠️ RÃNH DÂY PHẢI CHỜM QUA CẢ NÓC GIẾNG, không được dừng ở mép hốc. Bản nháp đầu cho rãnh chạy
// đúng bề rộng gờ chặn (x 16.8..19) rồi để dây gập ngay tại x=16.8. Sai: dây chiếm z 0..1.2 mà ở
// x<16.8 thì z>0 là nhựa đặc, tức dây phải tụt hết 1.2mm trong vòng 0.2mm chạy ngang — gập bán
// kính 0, bất khả. Giếng có mà dây không xuống nổi, và render nhìn vẫn thấy "có rãnh, có giếng".
//
// Đổi lại rãnh chỉ sâu 1.5 thay vì 2.2: vảy thiếc nằm tại pad (x≈18.3) vốn đã ở trong vùng cửa sổ
// có sẵn 2.2mm, đoạn chạy ngang chỉ cần lọt thân dây. Nhựa nắp còn 1.5mm thay vì 0.8mm.
//
// Đặt ở cạnh dài −x (hàng 5 pad nằm dọc cạnh 22mm, xác nhận 01/08): mép trái bo S3 ở x=13.75 nên
// gần nửa giếng rơi thẳng xuống sàn trống cạnh bo. Phương +x thì dây đổ lên lưng S3.
radar_wire_w  = 14;   // bề rộng cửa thoát dọc cạnh; hàng 5 pad trải 2.54*4 + pad ≈ 12.2
radar_wire_sh = 6;    // bề rộng giếng rơi theo x, tính từ mép hốc ra ngoài
radar_wire_h  = 1.5;  // chiều sâu rãnh dây ăn vào tấm nắp (nắp còn lid_t - radar_wire_h)
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

            // ESP32-S3: 4 trụ đỡ phẳng + gờ dẫn hướng, KHÔNG bắt vít.
            //
            // Bo CÓ 2 lỗ M2.5 ở đầu USB-C nhưng khoảng tâm-tâm chưa đo được: số ước 26mm là bất
            // khả trên bo rộng 26.5 (lỗ M2.5 phải cách mép >=2.5mm nên tối đa ~21.5). Đặt trụ vít
            // sai chỗ thì vít không vào; tệ hơn, gờ/trụ đặt sai chỗ CHẶN bo không hạ xuống được —
            // đúng lỗi đã mắc với khay S2 bản trước. Trụ ĐỠ thì lệch bao nhiêu bo vẫn nằm phẳng.
            // Theo triết lý "định vị + dán" của file này: gờ lo định vị, băng keo 2 mặt lo giữ.
            //
            // Trụ TRÒN Ø8 (không kéo dài): rãnh chỉ nằm ở lỗ mồi, giống hệt khay S2. Ø8 với lỗ
            // mồi rãnh 2.1×3.1 còn ~2.45mm thành mỏng nhất — thừa sức cho vít tự ren M2.5.
            // Trụ trái có thể dính vào trụ góc trước-trái: hai khối cùng nằm trong union của
            // base nên chỉ hợp nhất thành một cục nhựa, không phải va chạm.
            translate([0,0,floor_t])
                for (dx=[-s3_hole_pitch/2, s3_hole_pitch/2])
                    translate([27+dx, s3_hole_y, 0]) cylinder(d=8, h=s3_stand);
            // S2: 2 trụ vít M2 tại y = s2_hole_y (neo theo cổng USB-C, KHÔNG theo mép bo).
            //
            // Trụ Ø7 chứ không Ø5: pitch 20mm đo bằng chấm giấy + thước kẻ nên sai số ~±0.5mm.
            // Ø7 cho vít lệch tới 1mm vẫn ăn vào thịt trụ, còn ~2.6mm thành quanh lỗ mồi.
            // Bỏ gờ quây quanh bo: 2 vít đã định vị đủ, mà chiều dài bo còn chưa chắc nên gờ
            // đặt sai chỗ chỉ tổ chặn không cho bo hạ xuống.
            translate([0,0,floor_t])
                for (dx=[-s2_pitch/2, s2_pitch/2])
                    translate([s2_x + s2_w/2 + dx, s2_hole_y, 0]) cylinder(d=7, h=s2_stand);
            // IR: 2 gờ đỡ module (LED chĩa ra face), dày ir_rib_t cao ir_rib_h
            translate([0,0,floor_t])
                for (dx=[0, ir_w])
                    translate([ir_x+dx-ir_rib_t/2, ir_y+5, 0])
                        cube([ir_rib_t, ir_l-8, ir_rib_h]);
        }
        // lỗ ÉP REN ĐỒNG M3 trong 4 trụ góc (từ trên) — không phải lỗ mồi tự ren
        translate([0,0,floor_t+deck_h-insert_deep]) corner_centers()
            cylinder(d=m3_insert, h=insert_deep+2);
        // lỗ mồi tự-ren M2 trong 2 trụ S2 — RÃNH dài theo x để nuốt sai số pitch (xem s2_pitch)
        translate([0,0,floor_t+s2_stand-5]) for (dx=[-s2_pitch/2, s2_pitch/2])
            translate([s2_x+s2_w/2+dx, s2_hole_y, 0])
                hull() for (sx=[-s2_pitch_tol, s2_pitch_tol])
                    translate([sx,0,0]) cylinder(d=m2_pilot, h=7);
        // khe USB-C S2 ở VÁCH SAU (nguồn vào — Topo A: sạc cắm S2). Hạ xuống cho khớp cổng.
        translate([s2_x+s2_w/2-6, out_l-wall-1, floor_t + s2_stand - 1])
            cube([12, wall+2, 9]);
        // lỗ mồi tự-ren M2.5 trong 2 trụ S3 — cùng rãnh dài như trụ (xem s3_hole_pitch)
        translate([0,0,floor_t+s3_stand-5]) for (dx=[-s3_hole_pitch/2, s3_hole_pitch/2])
            translate([27+dx, s3_hole_y, 0])
                hull() for (sx=[-s3_hole_tol, s3_hole_tol])
                    translate([sx,0,0]) cylinder(d=m25_pilot, h=7);
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
        // HAI lỗ USB-C của ESP32-S3 (TTL trái, OTG phải) thay khe đơn 12mm của WROOM.
        // y bắt đầu từ face_inset-1: tấm face nằm ở y 2..5, để nguyên y=-1 thì khoét hụt, chừa
        // 1mm nhựa -> hốc mù nhìn render không phát hiện được (đã dính 3 lần, xem probe()).
        translate([27 - s3_usb_open_w/2, face_inset - 1, s3_usb_z - s3_usb_open_h/2])
            cube([s3_usb_open_w, face_t+2, s3_usb_open_h]);
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
            translate([wall+0.4, face_back+0.4, -lid_lip_h])
                cube([inner_w-0.8, out_l-wall-0.4 - (face_back+0.4), lid_lip_h]);
            // bệ đỡ mic — khối đặc, hốc khoét ở phần difference bên dưới
            translate([mic_cx, mic_cy, -mic_boss_h])
                cylinder(d=mic_pocket_d+4, h=mic_boss_h);
        }
        // === RADAR: hốc xuyên gờ tụt + cửa sổ màng, thay cho 4 nub cũ (v4.1, 31/07) ===
        //
        // Lỗi của bản trước, đo được lid ∩ radar = 480mm³ = TRỌN thể tích module: lệnh khoét cửa sổ
        // chỉ ăn trong tấm nắp (z 0..1.5) mà KHÔNG xuyên gờ tụt dày lid_lip_h ngay dưới nó, nên dưới
        // cửa sổ vẫn là nhựa đặc — radar không có chỗ đặt. 4 nub cũ cũng sai: tâm đặt cách mép module
        // 1mm nhưng trụ Ø4 bán kính 2mm nên thân trụ thò VÀO trong 1mm mỗi bên, khe giữa hai trụ chỉ
        // 13mm trong khi module rộng 15mm. Cả hai lọt vì ghosts() chưa từng có radar.
        //
        // Cách mới: HỐC định vị thay vì 4 trụ. Module thả từ dưới lên, 4 vách hốc ôm trọn bề dày bo
        // nên định vị chắc hơn hẳn nub chỉ chạm ở 4 điểm; gờ 1mm quanh cửa sổ làm mặt chặn để bo
        // không trồi lên. Vẫn theo triết lý "định vị + dán": hốc lo định vị, băng keo lo giữ.
        translate([radar_cx, radar_cy, -lid_lip_h/2])
            cube([radar_w + radar_fit, radar_l + radar_fit, lid_lip_h], center=true);
        // Cửa sổ màng: HẸP HƠN hốc để chừa gờ chặn 1mm quanh mép bo. Chừa radar_mem_t nhựa trên
        // mặt cho sóng 24GHz xuyên. v2 từng khoét cao lid_t=3 đặt giữa ở z=1.5 -> ăn thủng cả 3mm.
        translate([(radar_win_x0 + radar_win_x1)/2, radar_cy, (lid_t-radar_mem_t)/2])
            cube([radar_win_x1 - radar_win_x0, radar_l - 2*radar_rim, lid_t-radar_mem_t],
                 center=true);
        // Cửa thoát dây radar — xem chú thích radar_wire_* ở phần tham số.
        // Cả hai khối CỐ Ý CHỜM 1mm vào cửa sổ / hốc: cắt đúng bằng mép sẵn có sinh mặt dày 0 và
        // làm STL mất 2-manifold (đã dính khi cắt test_s3 trùng mép gờ rãnh face).
        //
        // RÃNH DÂY: hạ gờ chặn, chạy suốt từ trong cửa sổ ra hết bề rộng giếng để dây có chỗ gập.
        translate([radar_pocket_x0 - radar_wire_sh, radar_cy - radar_wire_w/2, 0])
            cube([radar_win_x0 + 1 - (radar_pocket_x0 - radar_wire_sh), radar_wire_w, radar_wire_h]);
        // GIẾNG RƠI: thủng tường hốc + gờ tụt, hở đáy thẳng xuống khoang.
        translate([radar_pocket_x0 - radar_wire_sh, radar_cy - radar_wire_w/2, -lid_lip_h])
            cube([radar_wire_sh + 1, radar_wire_w, lid_lip_h]);
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

/* ================= FACE Ở TƯ THẾ IN ================= */
// Xoay face nằm xuống: dày 3mm theo Z, MẶT NGOÀI ÚP XUỐNG BÀN (ăn vân tấm PEI).
//
// Để đứng như toạ độ gốc thì 2 lỗ USB-C và lỗ IR thành lỗ NGANG — mép trên phải bắc cầu và lỗ
// tròn IR sẽ xệ, đúng vào mảnh cần chính xác nhất. Nằm thì cả 3 lỗ xuyên theo Z, in sắc nét,
// không cần support.
//
// Đường lớp song song mặt tấm => yếu khi bị bẻ, nhưng face nằm trong rãnh chữ U, 3 cạnh bị ôm,
// nắp đè phía trên nên tải toàn là nén — không phải hướng yếu đó.
module face_print() {
    translate([0, floor_t + deck_h, -face_inset]) rotate([90, 0, 0]) face();
}

/* ================= LẮP ================= */
module assembly() {
    color("LightSteelBlue") base();
    color("Khaki") face();
    color("Silver") translate([0,0,floor_t+deck_h]) lid();
}

/* ================= ĐẦU DÒ KIỂM LỖ ================= */
// Khối mỏng nằm gọn TRONG lòng mỗi lỗ. Giao với mảnh phải RỖNG thì lỗ mới thật sự thông.
//
// Ba lần dính lỗi "khoét hụt" đều cùng một kiểu: lệnh khoét không phủ hết bề dày nên để lại
// một lớp nhựa mỏng, và render nhìn bằng mắt KHÔNG thấy khác gì lỗ thật.
//   - cửa sổ radar: khoét cao lid_t giữa ở z=1.5 -> lại ăn thủng cả 3mm (ngược lại, thừa)
//   - khe USB face: face đã tụt sang y 2..5 mà lệnh khoét vẫn ở y -1..4 -> chừa 1mm
//   - lỗ mồi M2:    quên hẳn lệnh khoét khi khôi phục 2 trụ
// Đầu dò lấy toạ độ từ chính các biến ở trên nên tự bám theo mọi lần sửa tham số.
module probe(which) {
    if (which=="face-usb")
        translate([27-s3_usb_open_w/2+1, face_inset-1, s3_usb_z-s3_usb_open_h/2+1])
            cube([s3_usb_open_w-2, face_t+2, s3_usb_open_h-2]);
    else if (which=="face-ir")
        translate([ir_x+ir_w/2, face_back+1, floor_t+ir_axis_h]) rotate([90,0,0])
            cylinder(d=4, h=face_t+2);
    else if (which=="base-s2-pilot")
        translate([0,0,floor_t+s2_stand-4]) for (dx=[-s2_pitch/2, s2_pitch/2])
            translate([s2_x+s2_w/2+dx, s2_hole_y, 0]) cylinder(d=1.2, h=5);
    else if (which=="base-s2-usb")
        translate([s2_x+s2_w/2-5, out_l-wall-1, floor_t+s2_stand]) cube([10, wall+2, 7]);
    else if (which=="base-s3-pilot")
        translate([0,0,floor_t+s3_stand-4]) for (dx=[-s3_hole_pitch/2, s3_hole_pitch/2])
            translate([27+dx, s3_hole_y, 0]) cylinder(d=1.4, h=5);
    else if (which=="lid-mic")
        translate([mic_cx, mic_cy, -mic_boss_h-1]) cylinder(d=3, h=mic_boss_h+lid_t+2);
    // Đường dây radar phải THÔNG từ mặt bo ra tới khoang: đoạn NGANG trong rãnh dây nối vào đoạn
    // ĐỨNG trong giếng rơi. Bắt đúng lỗi "giếng có mà dây không xuống nổi" — nóc giếng vẫn là
    // nhựa đặc thì render nhìn vẫn thấy đủ rãnh lẫn giếng, chỉ đầu dò mới phát hiện.
    else if (which=="lid-radar-day")
        union() {
            translate([radar_pocket_x0 - radar_wire_sh + 0.5, radar_cy - radar_wire_w/2 + 1, 0.3])
                cube([radar_win_x0 - radar_pocket_x0 + radar_wire_sh, radar_wire_w - 2,
                      radar_wire_h - 0.6]);
            translate([radar_pocket_x0 - radar_wire_sh + 0.5, radar_cy - radar_wire_w/2 + 1,
                       -lid_lip_h + 0.4])
                cube([radar_wire_sh, radar_wire_w - 2, lid_lip_h - 0.1]);
        }
    // NGƯỢC LẠI: vùng này phải ĐẶC (màng nhựa chừa cho radar xuyên qua).
    // Đầu dò lùi vào 0.5mm so với bề dày màng để không chạm đúng mặt cắt.
    //
    // Đo trên vùng CỬA SỔ, KHÔNG phải vùng bo. Bản trước đo cả vùng bo là hỏi sai câu: màng chỉ
    // cần nguyên ở chỗ sóng xuyên qua, còn mép bo thì không. Script tự chuẩn hoá giá trị nên đổi
    // kích thước cửa sổ hay bề dày màng không phải sửa hằng số chép tay nữa.
    else if (which=="lid-radar-mang")
        translate([(radar_win_x0 + radar_win_x1)/2, radar_cy, lid_t - radar_mem_t/2])
            cube([radar_win_x1 - radar_win_x0, radar_l - 2*radar_rim, radar_mem_t-0.5],
                 center=true);
}

/* ================= MIẾNG ƯỚM ================= */
// Cắt riêng vùng đỡ từng board để thử lắp trong ~20 phút, thay vì in lại cả base 2h18m.
// Cắt thẳng từ base() nên hình học y hệt bản thật — không phải mô hình dựng riêng.
module test_s2() {      // kèm cả vách sau + khe USB-C để kiểm luôn chiều cao cổng
    intersection() { base(); translate([40, 46, 0]) cube([34, out_l-46, 20]); }
}
// Mặt cắt phải TRÁNH mép sẵn có, đừng trùng: cắt đúng x=6 là trùng mép phải của gờ rãnh face
// (x 3..6) -> sinh mặt dày 0 -> STL không còn 2-manifold. Cắt từ x=2 (nằm giữa lòng vách hông).
module test_s3() {      // kèm cả gờ rãnh trượt face để ướm luôn 2 trụ vít và khe lắp mặt trước
    intersection() { base(); translate([2, 0, 0]) cube([44, 26, 18]); }
}

// Bóng mờ vị trí board (kiểm bố trí) — không xuất STL, chỉ để xem.
module ghosts() {
    color([0.2,0.6,1,0.45]) translate([s3_x, s3_y, floor_t+s3_stand]) cube([s3_w, s3_l, s3_pcb_t]);
    color([1,0.5,0.2,0.45]) translate([ir_x, ir_y, floor_t+ir_rib_h]) cube([ir_w, ir_l, 1.6]);
    color([0.3,1,0.3,0.45]) translate([s2_x, s2_y, floor_t+s2_stand]) cube([s2_w, s2_l, 1.6]);
    // Radar áp NGỬA vào mặt dưới nắp, ngay dưới cửa sổ màng. Thiếu bóng này thì script kiểm
    // KHÔNG hề soi vùng radar — đúng chỗ đã lọt lỗi 4 nub đặt sai và gờ tụt nắp bịt chỗ đặt.
    // Bao hình GỒM CẢ cục header + chân thõng xuống, không chỉ mỗi PCB. Mô hình hoá thiếu phần
    // nhô ra là script kiểm xác nhận "không đè nhau" cho một vật thể mỏng hơn thực tế — đúng loại
    // sai lầm đã để lọt hai defect nặng khi ghosts() còn chưa có radar.
    // Lấy trọn diện tích bo cho phần header (bảo thủ hơn thực tế, header chỉ chạy dọc một mép).
    color([1,0.2,0.2,0.45])
        translate([radar_cx - radar_w/2, radar_cy - radar_l/2, floor_t+deck_h-radar_t-radar_hdr_h])
            cube([radar_w, radar_l, radar_t + radar_hdr_h]);
    // Bó dây radar: hàn ở MẶT ĂNG-TEN nên chạy ngang TRÊN mặt bo rồi gập xuống giếng. Không có
    // bóng này thì cửa thoát chỉ được kiểm bằng mắt trên render — mà đúng cái lỗi vừa bắt được
    // (nóc giếng còn nhựa, dây không gập xuống nổi) lại nhìn không ra trên render.
    // Cao 1.2mm = dây 28-30AWG; đây cũng chính là ràng buộc đặt lên tay hàn.
    color([1,1,0.2,0.45]) {
        translate([radar_pocket_x0 - radar_wire_sh, radar_cy - 6, floor_t+deck_h])
            cube([radar_win_x0 + 1.5 - (radar_pocket_x0 - radar_wire_sh), 12, 1.2]);
        translate([radar_pocket_x0 - radar_wire_sh + 0.5, radar_cy - 6, floor_t+deck_h-lid_lip_h])
            cube([radar_wire_sh - 1, 12, lid_lip_h + 0.2]);
    }
}

// Xem tách rời — dễ thấy rãnh trượt và 4 trụ.
module exploded() {
    color("LightSteelBlue") base();
    color("Khaki") translate([0,-22,0]) face();
    color("Silver") translate([0,0,floor_t+deck_h+26]) lid();
}

if (part=="base") base();
else if (part=="face") face();
else if (part=="face-print") face_print();   // face đã lật sẵn để in, xuất ra vo-hop-face-in-nam.stl
else if (part=="lid") lid();
else if (part=="test-s2") test_s2();
else if (part=="test-s3") test_s3();
else if (part=="layout") { base(); ghosts(); }
else if (part=="exploded") exploded();
else assembly();
