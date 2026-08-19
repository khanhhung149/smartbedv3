// vo-hop-sleeppad.scad — Vỏ hộp cho node sleep-pad: ESP32-S3-CAM + 1 cổng USB-A cố định.
// In 2 mảnh: base (sàn + 4 vách) và lid (nắp bắt 4 vít M3 ren đồng).
//
// CÔNG DỤNG: hộp ngồi dưới sàn/gầm giường, đầu USB-A nhận cáp 4 dây của tấm LSM-800-T,
// đầu USB-C ra nguồn/nạp cho S3. Cáp ra HAI ĐẦU ĐỐI DIỆN nên không chồng dây.
//
// ⚠️ CỔNG USB-A TRÊN HỘP NÀY KHÔNG PHẢI USB. Nó là UART 115200 8N1 + 5V, đấu qua khối
// breakout USB-A → 4 chân. Cắm chuột/USB thường vào đây thì không cháy nhưng cũng không chạy;
// cắm hộp này vào cổng USB của máy tính thì TX của hai bên đối đầu nhau. Vì vậy nắp có khắc
// chữ cảnh báo (label_on).
//
// VẬT LIỆU: PETG, thành 3mm, FDM. KHÔNG in resin: 4 lỗ vít dùng ren đồng ép nóng (heat-set),
// mà ren đồng chỉ ép được vào nhựa NHIỆT DẺO — resin là nhựa nhiệt rắn, không chảy lại được,
// ép vào chỉ nứt. Resin cũng giòn, mà hộp này nằm dưới sàn nơi dễ bị đá phải.
//
// === NGUỒN SỐ ĐO ===
// Khối s3_* chép NGUYÊN VĂN từ vo-hop-modular.scad (voice-node) — đã in ướm thật 31/07,
// KHÔNG đo lại. Đó là bo GOOUUU ESP32-S3-CAM (N16R8): 65 × 26.5, CHỈ 2 lỗ vít và cả hai
// nằm ở đầu USB-C. Đừng thay bằng số tra mạng cho "ESP32-S3-N16R8" (bản generic 67×31, 4 lỗ).
// Khối usba_* là số user cho 03/08: 32 × 16 × 20 mm. Bao hình thì chắc, còn NỘI THẤT của
// khối (socket nằm cao bao nhiêu trong 20mm đó) thì CHƯA ĐO — xem usba_axis_z.
//
// === KÍCH THƯỚC NGOÀI: 46 × 113.9 × 28 mm ===
// Bề rộng 46 chứ không phải 37 như ước ban đầu: 37 = bo 26.5 + 2 vách 3 + khe, tức đã QUÊN
// 4 trụ góc Ø8. Trụ ăn vào lòng hộp nên bo không thể chạy sát vách. Cách gỡ đã áp dụng ở đây
// là VÙI TRỤ VÀO GÓC VÁCH (post_off = post_d/2, tâm trụ cách mặt NGOÀI đúng bán kính) thay vì
// để trụ đứng rời trong lòng như bản voice-node (post_in = 3.5). Vùi được vì phần trụ nằm
// trong vùng vách vốn đã là nhựa đặc; chỉ 5mm mỗi bên thò vào lòng thay vì 7.5mm.
// Vùi sâu hơn nữa thì thành quanh lỗ ren đồng Ø4.2 mỏng dưới 1.9mm và tuột ren — 1.9 là con
// số voice-node đang chạy, giữ nguyên làm giới hạn.
//
// === TẠI SAO NỐI TIẾP CHỨ KHÔNG SONG SONG ===
// Xếp khối USB-A NẰM CẠNH bo S3 thì hộp còn ~75 × 50 × 28 (nhỏ hơn ~30% thể tích). Không chọn
// vì hai lý do: (1) cáp tấm pad và cáp nguồn sẽ ra cùng một đầu, chỗ đặt hộp dưới gầm giường
// thành ra phải chừa dây cả hai bên một phía; (2) bo rộng 26.5 + khối rộng 16 = 42.5 mà lòng
// hộp chỉ 40 — muốn song song phải nới lòng lên 44, tức bề rộng ngoài 50, hộp thành gần vuông
// và khó nhét vào khe hẹp. Nếu sau này ưu tiên ngắn hơn dài hơn thì đổi được, nhưng phải viết
// lại toàn bộ phần toạ độ y — đừng sửa nửa vời.

part = "assembly";   // "base" | "lid" | "assembly" | "exploded" | "layout"
                     // | "test-usba" | "test-s3" | "test-s3-truoc"

/* ================= ESP32-S3-CAM (chép từ vo-hop-modular.scad) ================= */
s3_w = 26.5;  s3_l = 65;          // PCB (rộng × dài)
s3_pcb_t = 1.6;
// Chân GPIO thò xuống dưới đáy PCB. Suy ra TỪ LẦN ƯỚM BẢN IN THẬT 31/07: trụ 8mm thì chân
// "vừa chạm" sàn. Đừng suy từ tổng chiều cao bo — phép suy đó đã sai một lần.
s3_pin_drop = 8;
s3_stand = s3_pin_drop + 2;       // = 10, chừa 2mm hở dưới chân
// VỊ TRÍ hai hàng chân. Trước 04/08 những số này KHÔNG tồn tại — ghosts() chỉ có tấm PCB
// phẳng, nên checker mù hoàn toàn với chân header. Hậu quả: 2 trụ đỡ đâm thẳng hàng chân IO
// mà 205 phép kiểm vẫn báo đạt, chỉ lòi ra khi user ướm bo thật.
// Đo 04/08: mép dài bo → tâm hàng chân 1-2mm. Lấy 2.0 là đầu XẤU của dải: sai về phía này thì
// trụ đâm chân, sai về phía kia chỉ mất chút cánh tay đòn.
s3_pin_row_d = 2.0;
s3_pin_row_w = 2.5;               // bề rộng vùng cấm quanh tâm hàng chân (chân + pad + sai số đo)
// Đo 04/08: chân cuối cách mép đầu USB-C 12-13mm. Đây là thứ cứu 2 trụ VÍT — chúng phủ y
// 102.4→110.4, hở 5mm so chân cuối ở y≈96.9.
s3_pin_to_end = 12.5;
s3_usb_out = 1;                   // cổng USB-C thò ra khỏi mép PCB
s3_usb_gap = 0.5;                 // hở giữa mặt cổng và mặt TRONG vách sau
// ⚠️ s3_usb_pitch 12.5 là số SUY từ hình học (cổng USB-C rộng 8.94, hai cổng đối xứng qua tâm
// bo 26.5), CHƯA đo bằng thước. Xem chú thích gốc trong vo-hop-modular.scad.
s3_usb_pitch = 12.5;              // tâm-tâm 2 cổng USB-C (TTL và OTG)
s3_usb_w = 10;                    // bề rộng thân cổng + dung sai
// 1 -> 2 (03/08), KHÁC bản voice-node. Công thức dưới đây cộng theo THÂN CỔNG (8.94), nên với
// clear=1 thì nửa cửa tính từ tâm một cổng ra đúng 6.00mm — mà cục nhựa phích USB-C rộng ~12
// cần đúng 6.00mm. Hở BẰNG 0 ở cạnh ngoài, cả hai cổng (script đo ra 0.00). Nominal 0 trên bản
// in FDM là âm thật: chân voi + đùn dư luôn ăn bớt lỗ. Voice-node thoát vì mặt face của nó in
// NẰM nên lỗ xuyên theo Z sắc nét; hộp này in vách sau ĐỨNG, lỗ phải bắc cầu, dung sai xấu hơn.
// clear=2 cho cửa 26.5, hở 1.0mm quanh cục nhựa, vẫn còn 1.75mm tới 2 trụ góc sau.
// Muốn về đúng bản voice-node thì đổi lại 1 — nhưng đo phích trước.
s3_usb_plug_clear = 2;            // hở thêm mỗi bên cho vỏ NHỰA của phích
// MỘT cửa trùm CẢ HAI cổng, không phải 2 lỗ riêng. Lý do (đo trên bản in thật 31/07): vỏ kim
// loại của phích USB-C chỉ chìa ~6.5mm khỏi cục nhựa, nên nếu chỉ khoét vừa thân cổng thì cục
// nhựa chặn ở mặt vách và phích chui vào cổng chưa tới 6.5mm — KHÔNG cắm tới nơi. Phải khoét
// đủ rộng để cục nhựa lọt hẳn vào. Mà cục nhựa rộng ~12mm trong khi tâm-tâm 2 cổng chỉ 12.5
// ⇒ hai lỗ riêng chỉ còn vách 0.5mm ở giữa, sợi nhựa đó gãy khi in hoặc khi cắm.
s3_usb_open_w = s3_usb_pitch + s3_usb_w + 2*s3_usb_plug_clear;  // = 24.5
s3_usb_open_h = 8;                // cao hơn thân cổng (3.26) để nuốt cả vỏ nhựa phích
// ⚠️ pitch 23 là DANH NGHĨA. User từng ước 26mm nhưng bất khả trên bo rộng 26.5 (lỗ M2.5 phải
// cách mép >= 2.5mm ⇒ tối đa ~21.5); 26 nhiều khả năng là đo mép-ngoài-tới-mép-ngoài.
s3_hole_pitch = 23;
s3_hole_tol = 0.5;                // nửa chiều dài phần kéo dài của RÃNH lỗ mồi
s3_hole_to_end = 3;               // tâm lỗ vít cách mép ĐẦU USB-C của PCB
m25_pilot = 2.1;                  // lỗ mồi vít TỰ REN M2.5 — khoét to hơn là vít quay tít
                                  // không bám; muốn dung sai thì nới ĐƯỜNG KÍNH TRỤ.

/* --- Gờ dẫn hướng bo S3 (03/08) --- */
// Vì sao thêm: trước đó bo chỉ có 4 trụ ĐỠ, nên toàn bộ định vị NGANG treo vào đúng 2 con vít
// — mà s3_hole_pitch=23 lại chính là số script đang cảnh báo (tâm lỗ cách mép bo 1.75mm, lỗ
// M2.5 cần >= 2.5mm). Pitch sai thì vít không vào, và khi đó bo KHÔNG còn gì giữ ngang.
// Gờ dẫn hướng bám theo BỀ RỘNG bo 26.5 — số đo tay trên board thật 30/07, đáng tin hơn hẳn
// pitch — nên định vị ngang không còn phụ thuộc vào việc vít có vào hay không.
s3_guide_clear = 0.5;             // hở mỗi bên giữa mép bo và mặt trong gờ -> khe 27.5
s3_guide_t = 2;                   // bề dày mỗi gờ
s3_guide_over = 3;                // gờ cao hơn nóc PCB bấy nhiêu -> còn dẫn hướng suốt hành trình
// CHIA 4 ĐOẠN NGẮN thay vì 2 dải chạy suốt 65mm. Hai điểm chặn mỗi bên, đặt xa nhau, đã khoá
// xoay đủ; mà diện tích ma sát nhỏ thì sai số in không cộng dồn dọc 65mm để kẹp cứng lấy bo.
// Đây đúng là kiểu hỏng đã dính ở khay S2 bản trước: gờ quây dài, bo không hạ xuống hết.
s3_guide_seg = 12;                // chiều dài mỗi đoạn gờ
s3_guide_in = 2;                  // đoạn gờ lùi vào bấy nhiêu so với 2 đầu bo

/* --- Gờ chặn nhấc bo S3, treo dưới nắp (03/08) --- */
// 2 vít chỉ ở đầu USB-C nên đầu kia của bo dài 65 vẫn nhấc lên được — trước đó phải dán băng
// keo. Gờ này khoá nốt phương +z, bỏ được băng keo.
//
// ĐÈ LÊN 2 MÉP DÀI, KHÔNG bắc ngang giữa bo. Bản nháp đầu cho một gờ rộng 20mm bắc ngang mép
// trước — sai, vì bo S3-CAM có connector camera và nhiều khả năng nó nằm đúng đầu không-USB-C,
// tức đúng chỗ định đè. Dải mép PCB rộng ~3mm thì gần như chắc chắn là vùng keep-out trên mọi
// bo; mặt giữa bo thì không có gì đảm bảo.
//
// Là gờ CHẶN chứ không phải gờ KẸP: đáy gờ cách nóc PCB s3_hold_gap, bo vẫn nhấc được đúng
// khe đó rồi chạm. Kẹp cứng thì sai số in cộng vào là cong bo.
s3_hold_on = true;                // tắt bằng false nếu ướm thấy đụng linh kiện mặt trên
s3_hold_w = 3.25;                 // bề rộng mỗi gờ theo x, tính từ mép bo vào
s3_hold_l = 8;                    // chiều dài theo y
s3_hold_gap = 0.5;                // hở giữa đáy gờ và nóc PCB

/* ================= Khối breakout USB-A (số user 03/08) ================= */
usba_l = 32;                      // dọc TRỤC CẮM: socket một đầu, cầu đấu 4 chân đầu kia
usba_w = 16;
usba_h = 20;
usba_fit = 0.4;                   // khe lắp tổng (dung sai FDM ~0.2/mặt)
// Chiều cao TÂM socket so với ĐÁY khối. Suy đoán ban đầu: bo nằm ngang ở đáy khối, socket cao
// ~6.5 ngồi trên bo 1.6 ⇒ tâm ≈ 4.9. User xác nhận bằng mắt 04/08: socket nằm sát đáy, tâm
// trong khoảng 4-6 ⇒ giữ 5. Vẫn chưa đo bằng thước nên còn ±1; cửa tự bám theo biến này.
//
// Chính số này giải thích vì sao cửa USB-A thấp hơn cửa USB-C 7.23mm — hỏi 04/08. Không phải
// lỗi: tâm USB-C = sàn 3 + ĐẾ KÊ 10 + PCB 1.6 + nửa thân 1.63. Bỏ đế kê ra thì USB-A còn CAO
// HƠN 1.77mm. Toàn bộ chênh lệch đến từ s3_stand, mà đế kê đó bắt buộc vì chân header thò
// xuống 7-9mm (user xác nhận 04/08). Hai cửa ở hai vách đối diện, không cần bằng nhau.
//
// KHOẢNG DÙNG ĐƯỢC: 5 .. 12 — trong dải này cửa căn ĐÚNG TÂM socket, hở đều 1.5mm trên/dưới.
//   < 5  : đáy cửa chạm chặn usba_floor_min nên không tụt theo trục được nữa, hở đáy giảm dần
//          còn (usba_axis_z − 3.5). Tới 3.5 là hở BẰNG 0, phích cạ đáy cửa. Cách gỡ: giảm
//          usba_floor_min (sàn dưới cửa mỏng đi), hoặc kê khối lên bệ và nới deck_h theo.
//   > 12 : vách phía trên cửa mỏng dần, mà chính vách đó giữ khối không tuột ra khi rút phích.
usba_axis_z = 5;
// ⚠️ CHƯA ĐO — bao hình CỤC NHỰA của phích USB-A trên cáp tấm pad (18 × 9 × 20 là phích dân
// dụng phổ thông). Cửa phải nuốt được cục nhựa, KHÔNG chỉ vỏ kim loại 12.2 × 4.5: vách dày
// 3mm mà USB-A ăn khớp cần ~12mm chiều sâu cắm, chặn cục nhựa ở mặt vách là mất đứt 3mm —
// đúng lỗi "phích không cắm tới nơi" đã dính với USB-C ở voice-node.
// Đo phích THẬT rồi sửa 3 số này; cửa tự bám theo. Cửa càng nhỏ, vách giữ khối càng nhiều.
usba_plug_w = 18;  usba_plug_h = 9;  usba_plug_len = 20;
usba_plug_clear = 1.5;            // hở mỗi bên quanh cục nhựa
// ⚠️ CHƯA ĐO — cục nhựa phích USB-C. KHÔNG dùng để suy ra cửa USB-C: cửa đó lấy nguyên công
// thức đã nghiệm thu của voice-node (xem s3_usb_open_w). Số này chỉ để script ĐO xem cửa có
// nuốt nổi phích không rồi báo con số hở ra.
usbc_plug_w = 12;  usbc_plug_h = 7;  usbc_plug_len = 20;
usba_rib_t = 2.5;                 // bề dày mỗi gờ hông định vị khối
// Gờ CỐ Ý thấp hơn khối (16 < 20): đủ cao để chặn khối xoay khi ngoáy phích, mà vẫn chừa 4mm
// trên để kẹp tay nhấc khối ra lúc tháo.
usba_rib_h = 16;
usba_stop_t = 3;                  // bề dày vách chặn phía sau khối
usba_wire_w = 10;                 // bề rộng rãnh thoát 4 dây trên NÓC vách chặn
usba_wire_z = 11;                 // rãnh bắt đầu từ độ cao này (so sàn trong) trở lên
usba_hold_gap = 0.5;              // hở giữa gờ đè dưới nắp và nóc khối
usba_floor_min = 2;               // bề dày sàn TỐI THIỂU còn lại dưới cửa USB-A (xem usba_open_z0)
wire_gap = 6;                     // khoảng trống giữa vách chặn và mép trước bo S3 để dây quặt

/* ================= Khung ================= */
inner_w = 40;                     // xem tính toán bề rộng ở đầu file
wall = 3;  floor_t = 3;  lid_t = 3;
// deck_h phải nuốt được khối USB-A cao 20 (+ hở cho gờ đè). Bo S3 thấp hơn nhiều:
// đáy PCB ở 10, nóc PCB 11.6, nóc cổng USB-C ~14.9 — khối USB-A mới là thứ quyết chiều cao.
deck_h = 22;
post_d = 8;                       // trụ góc Ø8: đủ thịt ép ren đồng M3 (thành còn ~1.9mm)
// Tâm trụ cách mặt NGOÀI đúng bán kính ⇒ trụ tiếp tuyến mặt ngoài, phần thân nằm gọn trong
// vùng vách. Đây là chỗ lấy lại 5mm bề rộng so với cách đặt trụ rời trong lòng.
post_off = post_d/2;
m3_free = 3.4;                    // lỗ thông vít M3 trên nắp
m3_insert = 4.2;                  // lỗ chờ ép ren đồng M3 (mỏ hàn ~230°C)
insert_deep = 6;
lid_lip_h = 4;                    // chiều cao gờ tụt định vị dưới nắp
// 1.5 chứ không phải 2: đây vừa là gờ định vị vừa là LÒ XO của khớp bấm, mà lực lò xo tỉ lệ
// bề dày MŨ BA. Bản 2mm tính ra cần 13-36 kgf để đậy — phải kẹp ê-tô, không đậy bằng tay được.
// Mỏng đi 25% là lực giảm 58%. Snap-fit nhựa ép công nghiệp dùng 0.5-1mm; 2mm là bề dày của
// một chi tiết ĐỊNH VỊ, không phải của một lò xo. Định vị vẫn đủ vì độ cứng TRONG MẶT PHẲNG
// của dải 1.5 × 12.5 × 107mm là rất lớn — chỉ phương uốn ngang mới mềm, và đó là phương cần mềm.
lip_w = 1.5;                      // bề dày gờ tụt
lip_gap = 0.4;                    // khe giữa gờ tụt và mặt trong vách

/* ================= Khớp bấm thay cho vít ================= */
// Bật lại vít bằng một dòng nếu gờ bấm in ra lỏng/chặt quá. 4 trụ góc KHÔNG bỏ được dù bỏ vít:
// chúng định nghĩa bán kính bo góc (goc_r = post_off) và làm cứng 4 góc — mà vách cứng chính
// là điều kiện để MÔI võng chứ không phải VÁCH võng.
vit_on = false;
// Môi 2 cạnh hông kéo sâu ra. Cùng với lip_w, đây là hai biến chi phối lực bấm:
//   lực lò xo   F = 3·E·I·y / L³   với I = b·t³/12
//   biến dạng   ε ≈ 3·t·y / (2·L²)        (t = bề dày môi, y = độ võng, L = cánh tay đòn)
// Nắp in ÚP nên môi mọc lên thành vây đứng, các lớp xếp DỌC theo cánh tay đòn — bẻ ngang là
// kéo ngang thớ lớp, phương yếu nhất của FDM. Nên phải giữ ε thấp, mà L² ở mẫu số.
// Sâu 12.5 để cánh tay đòn tới gờ đúng 10mm sau khi trừ bam_tu_dau.
lip_h_ben = 12.5;
// Cạnh SAU giữ nguyên lid_lip_h = 4 và KHÔNG có gờ bấm: nóc cổng USB-C ở z=17.86 nên môi sau
// sâu quá 6mm là đâm vào cổng. Hai cạnh hông dài 107mm, thừa sức giữ một mình.
bam_cao = 0.7;                    // gờ bấm nhô khỏi mặt ngoài môi; lấn 0.3 quá khe lip_gap 0.4
bam_dai = 10;                     // chiều dài mỗi đoạn gờ
// 2 đoạn mỗi cạnh (4 tổng), không phải 3. Lực cộng TUYẾN TÍNH theo số gờ nên 6 đoạn vừa thừa
// giữ vừa nặng tay. Hai vị trí này nằm ngoài vùng khoét vượt vách chặn khay (y 34.9→38.9).
bam_ys = [25, 89];
// Hai má gờ KHÁC góc nhau. Bản đầu để cả hai 45° nên cắm và giữ nặng NHƯ NHAU — vô lý, ta muốn
// dễ vào khó ra. Hạ má vào xuống 30° giảm lực cắm gần một nửa mà không đụng lực giữ.
// ⚠️ Má GIỮ không được dốc quá 45°: nắp in ÚP nên chính má đó là mặt hẫng khi in. Bất đối xứng
// chỉ in được theo đúng chiều này — làm ngược lại là không in nổi.
bam_vao_deg = 30;
bam_giu_deg = 45;
// Khấc bẩy mở ở vách TRƯỚC, ngay dưới mạch ghép. Hộp bấm mà không có chỗ móc tay thì lần nào
// mở cũng cạy hỏng mép. Cạnh trước vốn không có môi nên đó là chỗ bẩy tự nhiên.
bay_w = 15;  bay_d = 1.5;  bay_h = 3;

label_on = false;
label_size = 4;
label_deep = 0.6;                 // chiều sâu khắc chìm

/* ================= Vân trang trí (thuần thẩm mỹ) ================= */
// CHỈ trên 2 mặt hông dài. KHÔNG làm trên 2 vách đầu: rãnh sẽ cắt ngang cửa USB và làm mỏng
// vách ngay quanh cổng — chỗ chịu lực cắm rút. KHÔNG làm trên nắp: mặt trên nắp là LỚP ĐẦU
// tì vào bàn in nên vân lồi bị bẹp, còn vân lõm thì phải bắc cầu trên đúng mặt nhìn thấy.
//
// Đã cân nhắc và LOẠI Fuzzy Skin của slicer: "external perimeter" trong slicer là vòng ngoài
// của MỌI bề mặt hở ra không khí, kể cả mặt TRONG lòng hộp. Bật nó lên là nhám luôn khe gờ
// dẫn hướng (0.5mm/bên), môi nắp (0.4), lòng khay (0.2) và cửa USB-C (0.5) — không có chế độ
// nào tách được "ngoài hộp" khỏi "trong hộp". Khoét trong CAD thì đặt đúng chỗ mình chọn và
// chạy lại được đủ bộ kiểm để chứng minh không đụng khe nào.
van_on = true;                    // tắt bằng false nếu muốn mặt hông trơn
van_sau = 0.8;                    // sâu rãnh — vách hông 3mm nên còn 2.2mm
van_zs = [8, 13, 18];             // cao độ TÂM 3 rãnh so đáy NGOÀI
van_lo = 0.5;                     // lấn ra ngoài mặt vách, để lệnh cắt chắc chắn thủng bề mặt

// Bo 4 CẠNH ĐỨNG. Bán kính lấy đúng post_off nên cung tròn TRÙNG KHÍT mặt trụ góc vốn đã nằm
// sẵn trong đó — trụ Ø8 tiếp tuyến hai mặt ngoài (xem post_off). Hai mặt đồng tâm ⇒ bề dày từ
// mặt ngoài tới lỗ ren đồng vẫn nguyên 1.9mm, KHÔNG mất thịt ở chỗ ép ren. Lớn hơn post_off
// là bắt đầu ăn vào trụ, nên đây là trần.
//
// Chỉ bo cạnh ĐỨNG. Hộp in sàn xuống bàn nên cạnh đứng có mọi lớp giống hệt nhau — bo tròn
// không sinh mặt hẫng nào, chi phí in bằng 0 (còn nhỉnh hơn chút vì cung ngắn hơn hai cạnh
// vuông). Cạnh NGANG thì ngược hẳn, và cả ba cạnh ngang ở đây đều KHÔNG được bo:
//   đáy hộp      — phải phẳng tuyệt đối để bám bàn in
//   mạch ghép    — mặt tì của nắp, bo là hở
//   mặt trên nắp — nắp in úp nên đó là LỚP ĐẦU TIÊN; bo thì lớp đầu bé lại rồi loe ra, vượt
//                  45° ngay đoạn đầu, mà PETG trên PEI nhẵn đang cần nhiều diện tích bám
goc_bo = true;
goc_r = post_off;                 // = 4

$fn = 48;

/* ================= Toạ độ suy ra ================= */
out_w = inner_w + 2*wall;                    // = 46
box_cx = out_w/2;                            // = 23, tâm theo x của CẢ bo S3 lẫn khối USB-A

// --- chuỗi y: dựng TỪ MẶT TRƯỚC ra sau, mỗi mốc bám mốc trước ---
usba_y     = wall;                           // = 3, mặt trước khối tì vào mặt trong vách trước
usba_back  = usba_y + usba_l + usba_fit;     // = 35.4, mặt sau khay
s3_y       = usba_back + usba_stop_t + wire_gap;   // = 44.4, mép TRƯỚC bo S3
s3_y_rear  = s3_y + s3_l;                    // = 109.4, mép ĐẦU USB-C của bo
out_l      = s3_y_rear + s3_usb_out + s3_usb_gap + wall;   // = 113.9
inner_l    = out_l - 2*wall;                 // = 107.9

s3_x       = box_cx - s3_w/2;                // = 9.75
s3_hole_y  = s3_y_rear - s3_hole_to_end;     // = 106.4, tâm 2 lỗ vít
// 2 trụ ĐỠ (không vít) chống bo dài 65 bị võng/kênh ở đầu tự do. Bo CHỈ có 2 lỗ và cả hai ở
// đầu USB-C, nên đầu này không bắt vít được — giữ bằng băng keo 2 mặt, đúng triết lý
// "định vị + dán" của vo-hop-modular.scad.
//
// ⚠️ Bản trước để 20 với lý lẽ "đặt gần mép bo, nơi chắc chắn không có linh kiện mặt dưới".
// Lý lẽ đó SAI: nó đúng với linh kiện DÁN, nhưng ngược hoàn toàn với CHÂN HEADER — mà chân
// header nằm đúng ở mép. User ướm bo thật 04/08: bề ngang vừa, 2 lỗ vít vừa, nhưng 2 trụ Ø7
// này ĐÂM ĐÚNG hàng chân IO ⇒ bo kênh lên, không tụt xuống hết.
// Kéo về 10: trụ ở x 18 và 28, phủ 14.5→21.5 và 24.5→31.5 — nằm gọn trong dải GIỮA hai hàng
// chân, dải duy nhất trên bo không có chân xuyên lỗ.
s3_prop_pitch = 10;
s3_prop_y  = s3_y + 5;                       // = 49.4
// Tâm thân cổng USB-C so đáy NGOÀI hộp: đáy PCB (floor_t + s3_stand) + PCB 1.6 + nửa thân
// cổng 3.26/2. ⚠️ Trong vo-hop-modular.scad dòng tương ứng có chú thích đuôi "= 14.23" — con
// số đó ĐÃ CŨ (ứng với s3_stand = 8); với s3_stand = 10 biểu thức cho 16.23. Đừng chép số.
s3_usb_z   = floor_t + s3_stand + s3_pcb_t + 3.26/2;       // = 16.23

// Cửa USB-A suy TỪ CỤC NHỰA PHÍCH, không ghi số chết: đo lại phích là cửa tự theo.
usba_open_w = usba_plug_w + 2*usba_plug_clear;   // = 21
usba_open_h = usba_plug_h + 2*usba_plug_clear;   // = 12

usba_x0    = box_cx - (usba_w + usba_fit)/2; // = 14.8, mép -x của khay
usba_x1    = usba_x0 + usba_w + usba_fit;    // = 31.2, mép +x của khay
usba_pocket_l = usba_l + usba_fit;           // = 32.4
// Đáy cửa USB-A: căn ĐÚNG TÂM socket, chỉ chặn để dưới cửa còn đủ bề dày sàn.
// Trục socket ở floor_t + usba_axis_z = 8, cục nhựa phích cao 9 ⇒ mép dưới phích ở 3.5.
// Căn tâm cho đáy cửa xuống z = 2 ⇒ hở đều 1.5mm trên/dưới.
//
// Bản trước chặn ở floor_t (đáy cửa z=3) làm hở đáy chỉ còn 0.5 trong khi nóc thừa 2.5 — chỗ
// hẹp nhất cả thiết kế, mà nguyên nhân là cửa LỆCH TÂM chứ không phải thiếu chỗ.
//
// Cho cửa ăn 1mm vào sàn không thủng đáy hộp: dưới cửa vẫn còn usba_floor_min = 2mm. Cũng
// không mất chỗ giữ khối — dải giữ khối là dải TRÊN cửa, hạ cửa 1mm thì dải đó DÀY THÊM 1mm
// (10 → 11). Được cả hai chiều.
//
// ĐỪNG hạ thêm nữa: tổng hở luôn = usba_open_h − usba_plug_h = 3mm bất kể đặt cửa ở đâu, hạ
// tiếp chỉ dời chỗ hẹp từ đáy lên nóc. Muốn hở nhiều hơn thì phải nới usba_open_h.
//
// Hệ quả phụ: lệnh khoét vượt 1mm vào trong (y tới wall+1) để chắc chắn thủng, nên sàn ngay
// dưới mép TRƯỚC khối hụt một dải 21 × 1mm. Khối dài 32mm nên mất 1mm đỡ ở mép trước là
// không đáng kể — nó vẫn tì trên 31mm sàn còn lại.
usba_open_z0  = max(usba_floor_min, floor_t + usba_axis_z - usba_open_h/2);   // = 2
usba_hold_h   = deck_h - usba_h - usba_hold_gap;   // = 1.5, gờ đè dưới nắp

z_pcb_noc  = floor_t + s3_stand + s3_pcb_t;  // = 14.6, nóc PCB so đáy ngoài
// Mặt TRONG 2 gờ dẫn hướng: khe = s3_w + 2*s3_guide_clear = 27.5 cho bo 26.5.
s3_guide_x0 = box_cx - s3_w/2 - s3_guide_clear;   // = 9.25
s3_guide_x1 = box_cx + s3_w/2 + s3_guide_clear;   // = 36.75
s3_guide_h  = s3_stand + s3_pcb_t + s3_guide_over;  // = 14.6, cao trên sàn trong
// 2 đoạn mỗi bên, đặt sát 2 đầu bo nhất có thể (lùi vào s3_guide_in) để cánh tay đòn khoá
// xoay dài nhất.
s3_guide_ys = [s3_y + s3_guide_in, s3_y_rear - s3_guide_in - s3_guide_seg];  // = [46.4, 95.4]
// Gờ chặn nhấc: đáy cách nóc PCB s3_hold_gap, kéo lên tới mặt dưới nắp.
s3_hold_h  = (floor_t + deck_h) - (z_pcb_noc + s3_hold_gap);   // = 9.9

// Tiết diện rãnh vân là tam giác cân RỘNG = 2 × SÂU ⇒ hai má nghiêng đúng 45°. Vách hông in
// dựng đứng nên má TRÊN của rãnh là mặt hẫng; 45° là ngưỡng tự đỡ của FDM, không cần support.
van_nho = van_sau + van_lo;                  // = 1.3, nửa chiều cao tiết diện ở mặt ngoài cùng
// Rãnh phải DỪNG trước 4 trụ góc. Trụ Ø8 tiếp tuyến mặt ngoài (post_off = post_d/2) nên thành
// trụ tới lỗ ren đồng chỉ còn 1.9mm; khoét thêm 0.8mm ở đúng đó còn 1.1mm — mỏng cho ép ren
// nóng, mà đỉnh V lại là điểm tập trung ứng suất chĩa thẳng vào lỗ ren. Trụ trải y 0..post_d,
// chừa thêm 1mm.
van_y0 = post_d + 1;                         // = 9
van_y1 = out_l - post_d - 1;                 // = 104.9

z_nap_duoi = floor_t + deck_h;               // = 25, mặt dưới tấm nắp so đáy NGOÀI
lip_sau_nhat = max(lid_lip_h, lip_h_ben);    // = 10, dùng cho lỗ khoét tránh trụ trong nắp
// Cao độ tâm gờ bấm và rãnh vách. Bám theo mép TỰ DO của môi chứ không ghi số chết: đặt sát
// mép thì cánh tay đòn L dài nhất ⇒ biến dạng nhỏ nhất (xem lip_h_ben).
// Má vào dốc 30° nên chân tam giác gờ thò xuống (bam_cao+van_lo)/tan(30) = 2.08mm dưới đỉnh gờ.
// Đặt gờ cách MÉP TỰ DO của môi ít nhất bấy nhiêu, không thì chân gờ thò khỏi đáy môi thành
// một nêm lơ lửng chỉ dính vào môi ở mặt trên — in ra là xệ. Suy từ góc chứ không ghi số chết.
bam_tu_dau = (bam_cao + van_lo)/tan(bam_vao_deg) + 0.4;    // = 2.48
bam_z = z_nap_duoi - lip_h_ben + bam_tu_dau; // = 15.02
bam_canh_tay = z_nap_duoi - bam_z;           // = 9.98, cánh tay đòn thật của môi tới gờ
// Rãnh KHÔNG sâu bằng gờ. Gờ nhô 0.7 khỏi mặt môi, mà môi cách vách lip_gap = 0.4, nên phần
// thực sự LẤN vào vách chỉ là 0.3. Khoét rãnh sâu 0.7 thì lúc đậy xong gờ lọt thỏm trong rãnh,
// nắp nhấc tự do 0.4mm mới chạm má rãnh — thành khớp lỏng, không phải khớp bấm.
// Sâu đúng 0.3 thì hai tiết diện V khít má vào nhau ngay khi click.
ranh_sau = bam_cao - lip_gap;                // = 0.3
bam_rong = 2*bam_cao;                        // = 1.4, tiết diện tam giác cân ⇒ hai má 45° tự đỡ
// Rãnh vách dừng trước 4 trụ góc — không phải vì sợ mỏng (trụ giờ đặc, hụt 1mm² là không đáng
// kể) mà vì môi nắp bị khoét tránh trụ ở đúng đó nên chẳng có gờ nào để ăn vào.
bam_y0 = post_d;                             // = 8
bam_y1 = out_l - post_d;                     // = 105.9

// Môi hông sâu 10mm CẮT NGANG vách chặn khay (nóc ở z=19) — checker bắt được va chạm
// 2 × 3 × 4mm. Vách chặn không hạ được vì nó là thứ chặn khối USB-A khi ngoáy phích, nên
// khoét môi đúng đoạn đó. Mất 4mm môi trên 107mm, và 3 đoạn gờ bấm (y 25/57/89) đều nằm
// ngoài vùng này nên không mất điểm giữ nào.
z_noc_vach_chan = floor_t + usba_rib_h;      // = 19
lip_khe_stop = 0.5;                          // hở mỗi bên khi môi vượt vách chặn
lip_z_vuot = z_noc_vach_chan + lip_khe_stop; // = 19.5, đáy môi ở đoạn vượt (tuyệt đối)

/* ================= tiện ích ================= */
module corner_centers() {
    for (x = [post_off, out_w - post_off])
        for (y = [post_off, out_l - post_off])
            translate([x, y, 0]) children();
}

/* ================= ĐẾ ================= */
// Rãnh vân chữ V chạy dọc 2 mặt hông. Mỗi rãnh là một lăng trụ tam giác đùn theo y.
// `rotate([-90,0,0])` đưa mặt phẳng vẽ 2D về đứng và quay trục đùn từ +z sang +y: điểm
// (x,y,z) → (x,z,−y). Tiết diện đối xứng theo y cục bộ nên phép lật dấu đó vô hại.
module van_hong() {
    for (z = van_zs)
        for (m = [[0, 1], [out_w, -1]])      // [x mặt ngoài, hướng khoét vào thân hộp]
            translate([m[0], van_y0, z])
                rotate([-90, 0, 0])
                    linear_extrude(van_y1 - van_y0)
                        polygon([[-m[1]*van_lo, -van_nho],
                                 [ m[1]*van_sau, 0      ],
                                 [-m[1]*van_lo,  van_nho]]);
}

// Khối cần BỎ ở 4 góc để bo cạnh đứng: hình vuông cạnh goc_r trừ đi cung tròn bán kính goc_r.
// Làm kiểu TRỪ vào lớp da ngoài chứ không dựng lại vỏ — cùng cách với van_hong(). Dựng lại vỏ
// thì phải đụng vào 5 khối sàn/vách vốn là thứ 136 phép kiểm đang bám vào; trừ thì không có
// đường nào phá được hình học bên trong.
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

// Rãnh chữ V trên mặt TRONG 2 vách hông, để gờ bấm của nắp click vào. Cùng tiết diện tam giác
// 45° với van_hong() nên má trên rãnh không vượt ngưỡng tự đỡ, không cần support.
module ranh_bam() {
    for (w = [[wall, -1], [out_w - wall, 1]])
        translate([w[0], bam_y0, bam_z])
            rotate([-90, 0, 0])
                linear_extrude(bam_y1 - bam_y0)
                    polygon([[-w[1]*van_lo, -(ranh_sau + van_lo)/tan(bam_giu_deg)],
                             [ w[1]*ranh_sau, 0                                  ],
                             [-w[1]*van_lo,  (ranh_sau + van_lo)/tan(bam_vao_deg)]]);
}

// Gờ bấm trên mặt NGOÀI 2 môi hông của nắp. Toạ độ ở đây là toạ độ NẮP (tấm nắp ở z 0..lid_t,
// môi thõng xuống z âm) nên phải trừ z_nap_duoi khỏi cao độ tuyệt đối.
// Đáy tam giác thụt van_lo vào trong thân môi để hợp nhất sạch, không để mặt trùng.
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

// Khấc bẩy mở ở vách TRƯỚC. Khoét từ mặt NGOÀI vào bay_d, chừa lại wall − bay_d = 1.5mm vách.
// Không sinh mặt hẫng: in từ dưới lên thì tới z này vách chỉ đột ngột MỎNG đi rồi hở lên trời.
module khac_bay() {
    translate([box_cx - bay_w/2, -1, z_nap_duoi - bay_h])
        cube([bay_w, bay_d + 1, bay_h + 1]);
}

module base() {
    difference() {
        union() {
            cube([out_w, out_l, floor_t]);                                        // sàn
            cube([wall, out_l, floor_t + deck_h]);                                // hông trái
            translate([out_w - wall, 0, 0]) cube([wall, out_l, floor_t + deck_h]);// hông phải
            cube([out_w, wall, floor_t + deck_h]);                                // vách TRƯỚC
            translate([0, out_l - wall, 0])
                cube([out_w, wall, floor_t + deck_h]);                            // vách SAU

            // 4 trụ góc bắt nắp (vùi vào góc vách — xem post_off)
            translate([0, 0, floor_t]) corner_centers() cylinder(d = post_d, h = deck_h);

            // --- KHAY USB-A ---
            // Khối bị giam đủ 6 phương mà KHÔNG cần một lỗ vít nào, nên không phụ thuộc vào
            // toạ độ lỗ vít của khối (thứ chưa đo được):
            //   ±x  : 2 gờ hông          -y : vách trước hộp   (chặn khi RÚT phích)
            //   +y  : vách chặn          -z : sàn              +z : gờ đè dưới nắp
            // Phương +y là phương chịu tải thật: cắm phích USB-A đẩy socket lùi vào cỡ 10-20N.
            // Đó là lý do vách chặn chạy SUỐT bề rộng lòng hộp và ăn vào cả hai vách hông —
            // tải đi thẳng vào vách dưới dạng lực cắt dọc theo lớp in. Làm thành 2 vấu rời
            // đứng giữa sàn thì tải thành mô-men bẻ chân vấu, tức lực TÁCH LỚP, hướng yếu nhất
            // của FDM; tính sơ đã ra ~23MPa ở chân vấu, sát ngưỡng bám lớp của PETG.
            for (x = [usba_x0 - usba_rib_t, usba_x1])
                translate([x, usba_y, floor_t])
                    cube([usba_rib_t, usba_pocket_l, usba_rib_h]);
            translate([wall, usba_back, floor_t])
                cube([inner_w, usba_stop_t, usba_rib_h]);

            // --- ĐỠ ESP32-S3 ---
            // 2 trụ vít M2.5 ở đầu USB-C (đúng 2 lỗ mà bo có).
            translate([0, 0, floor_t])
                for (dx = [-s3_hole_pitch/2, s3_hole_pitch/2])
                    translate([box_cx + dx, s3_hole_y, 0]) cylinder(d = 8, h = s3_stand);
            // 2 trụ ĐỠ đầu tự do, Ø7 không lỗ — xem s3_prop_pitch.
            translate([0, 0, floor_t])
                for (dx = [-s3_prop_pitch/2, s3_prop_pitch/2])
                    translate([box_cx + dx, s3_prop_y, 0]) cylinder(d = 7, h = s3_stand);
            // 4 đoạn gờ dẫn hướng ôm 2 cạnh dài bo — xem s3_guide_*.
            // Vài đoạn dính nhẹ vào trụ góc sau và trụ vít S3: cùng nằm trong union này nên
            // chỉ hợp nhất thành một cục nhựa, không phải va chạm.
            for (x = [s3_guide_x0 - s3_guide_t, s3_guide_x1])
                for (y = s3_guide_ys)
                    translate([x, y, floor_t]) cube([s3_guide_t, s3_guide_seg, s3_guide_h]);
        }

        // Rãnh thoát 4 dây, khoét từ NÓC vách chặn xuống. Khoét từ nóc chứ không đục lỗ giữa
        // vách: cầu đấu nằm ở nóc khối nên dây vốn đã ra ở trên cao, mà lỗ giữa vách thì phải
        // bắc cầu khi in. Phần vách dưới rãnh vẫn liền, đó mới là phần chịu lực cắm.
        translate([box_cx - usba_wire_w/2, usba_back - 1, floor_t + usba_wire_z])
            cube([usba_wire_w, usba_stop_t + 2, usba_rib_h - usba_wire_z + 1]);

        // Lỗ ÉP REN ĐỒNG M3 trong 4 trụ góc (khoét từ trên) — KHÔNG phải lỗ mồi tự ren.
        // Bỏ khi dùng khớp bấm: trụ thành ĐẶC, chắc hơn bản có lỗ.
        if (vit_on)
            translate([0, 0, floor_t + deck_h - insert_deep]) corner_centers()
                cylinder(d = m3_insert, h = insert_deep + 2);

        // KHỚP BẤM: rãnh trong 2 vách hông + khấc bẩy mở ở vách trước.
        if (!vit_on) { ranh_bam(); khac_bay(); }

        // Lỗ mồi tự-ren M2.5 trong 2 trụ S3 — RÃNH dài theo x để nuốt sai số pitch danh nghĩa.
        translate([0, 0, floor_t + s3_stand - 5])
            for (dx = [-s3_hole_pitch/2, s3_hole_pitch/2])
                translate([box_cx + dx, s3_hole_y, 0])
                    hull() for (sx = [-s3_hole_tol, s3_hole_tol])
                        translate([sx, 0, 0]) cylinder(d = m25_pilot, h = 7);

        // CỬA USB-A ở vách TRƯỚC.
        // Mép trên cửa là chỗ máy phải bắc cầu ngang 20mm khi in (hộp in sàn xuống bàn).
        // Nếu xệ: tăng quạt / giảm tốc riêng lớp bắc cầu. ĐỪNG khoét cao thêm cho dễ in —
        // phần vách phía trên cửa chính là thứ giữ khối USB-A không tuột ra.
        translate([box_cx - usba_open_w/2, -1, usba_open_z0])
            cube([usba_open_w, wall + 2, usba_open_h]);

        // CỬA USB-C ở vách SAU, trùm cả 2 cổng (xem s3_usb_open_w).
        translate([box_cx - s3_usb_open_w/2, out_l - wall - 1, s3_usb_z - s3_usb_open_h/2])
            cube([s3_usb_open_w, wall + 2, s3_usb_open_h]);

        // VÂN TRANG TRÍ 2 mặt hông — xem van_hong().
        if (van_on) van_hong();

        // BO 4 CẠNH ĐỨNG — xem bo_goc_dung(). Nắp phải bo cùng bán kính, không thì lệch mạch.
        if (goc_bo) bo_goc_dung(-1, floor_t + deck_h + 1);
    }
}

/* ================= NẮP ================= */
module lid() {
    difference() {
        union() {
            cube([out_w, out_l, lid_t]);

            // Gờ tụt định vị hình chữ U — 3 cạnh, BỎ cạnh trước.
            // Bỏ vì khối USB-A cao 20 tì sát mặt trong vách trước, mà gờ tụt xuống tới z=21
            // (tuyệt đối) nên cạnh trước sẽ đâm thẳng vào nóc khối. Ba cạnh + 4 vít là thừa
            // đủ để định vị nắp; cạnh trước chỉ là chỗ để va chạm.
            // 2 cạnh HÔNG sâu lip_h_ben — đây là cánh tay đòn của khớp bấm, sâu để hạ biến dạng.
            translate([wall + lip_gap, wall + lip_gap, -lip_h_ben])
                cube([lip_w, inner_l - 2*lip_gap, lip_h_ben]);
            translate([out_w - wall - lip_gap - lip_w, wall + lip_gap, -lip_h_ben])
                cube([lip_w, inner_l - 2*lip_gap, lip_h_ben]);
            // Cạnh SAU chỉ lid_lip_h: nóc cổng USB-C ở z=17.86, sâu quá 6mm là đâm vào cổng.
            translate([wall + lip_gap, out_l - wall - lip_gap - lip_w, -lid_lip_h])
                cube([inner_w - 2*lip_gap, lip_w, lid_lip_h]);

            // GỜ BẤM trên mặt NGOÀI 2 môi hông, ăn vào ranh_bam() của đế.
            if (!vit_on) go_bam();

            // Gờ ĐÈ khối USB-A — khoá nốt phương +z. Chỉ cao 1.5mm vì deck_h đã đo sát khối.
            translate([usba_x0, usba_y, -usba_hold_h])
                cube([usba_w + usba_fit, usba_pocket_l, usba_hold_h]);

            // 2 gờ CHẶN NHẤC đầu tự do bo S3, đè lên 2 MÉP DÀI — xem s3_hold_*.
            if (s3_hold_on)
                for (x = [s3_x, s3_x + s3_w - s3_hold_w])
                    translate([x, s3_y, -s3_hold_h]) cube([s3_hold_w, s3_hold_l, s3_hold_h]);
        }

        // BO 4 CẠNH ĐỨNG — cùng bán kính với base, không thì mạch ghép lệch nhìn thấy rõ.
        // Gờ tụt nằm thụt vào wall+lip_gap = 3.4 nên hoàn toàn bên trong cung, không bị xén.
        if (goc_bo) bo_goc_dung(-lip_sau_nhat - 1, lid_t + 1);

        // 4 lỗ thông vít M3
        if (vit_on)
            translate([0, 0, -lip_sau_nhat - 2]) corner_centers()
                cylinder(d = m3_free, h = lid_t + lip_sau_nhat + 4);
        // KHOÉT TRÁNH VÁCH CHẶN KHAY — xem lip_z_vuot. Chỉ cần khi môi hông sâu hơn 6mm.
        if (!vit_on)
            translate([0, usba_back - lip_khe_stop, -lip_h_ben - 1])
                cube([out_w, usba_stop_t + 2*lip_khe_stop,
                      (lip_z_vuot - z_nap_duoi) - (-lip_h_ben - 1)]);

        // KHOÉT TRÁNH 4 TRỤ: gờ tụt chạy qua vùng trụ, không khoét là nắp kênh cả chiều sâu môi.
        // Giữ kể cả khi bỏ vít — trụ vẫn đứng đó vì nó định nghĩa bo góc và làm cứng 4 góc.
        translate([0, 0, -lip_sau_nhat - 1]) corner_centers()
            cylinder(d = post_d + 0.6, h = lip_sau_nhat + 1);

        // Chữ cảnh báo khắc chìm trên MẶT TRÊN, đặt về phía đầu USB-A.
        // ASCII không dấu: chữ 4mm in ra mà thêm dấu thanh thì dính bết, đọc không ra.
        // Nắp in ÚP mặt trên xuống bàn nên vùng khắc nằm ngay lớp đầu — nét sắc, không cần
        // support, và máy chỉ việc bỏ trống rồi bắc cầu ở lớp trên.
        if (label_on) {
            translate([box_cx, wall + 24, lid_t - label_deep])
                linear_extrude(label_deep + 1)
                    text("UART 5V", size = label_size, halign = "center", valign = "center");
            translate([box_cx, wall + 17, lid_t - label_deep])
                linear_extrude(label_deep + 1)
                    text("KHONG PHAI USB", size = label_size,
                         halign = "center", valign = "center");
        }
    }
}

/* ================= LẮP ================= */
module assembly() {
    color("LightSteelBlue") base();
    color("Silver") translate([0, 0, floor_t + deck_h]) lid();
}

module exploded() {
    color("LightSteelBlue") base();
    color("Silver") translate([0, 0, floor_t + deck_h + 28]) lid();
}

/* ================= BÓNG LINH KIỆN ================= */
// Chỉ để xem/kiểm bố trí, không xuất STL. Bao hình phải mô hình hoá ĐỦ phần nhô ra, không chỉ
// mỗi PCB — mô hình thiếu thì script kiểm sẽ xác nhận "không đè nhau" cho một vật mỏng hơn
// thực tế, đúng loại sai lầm đã để lọt 2 defect nặng ở voice-node.
module ghosts() {
    // Bo S3 + cổng USB-C nhô ra sau
    color([0.2, 0.6, 1, 0.45]) {
        translate([s3_x, s3_y, floor_t + s3_stand]) cube([s3_w, s3_l, s3_pcb_t]);
        translate([box_cx - s3_usb_pitch/2 - s3_usb_w/2, s3_y_rear,
                   floor_t + s3_stand + s3_pcb_t])
            cube([s3_usb_pitch + s3_usb_w, s3_usb_out, 3.26]);
    }
    // 2 HÀNG CHÂN GPIO thò xuống dưới bo — xem s3_pin_row_d. Có ở đây thì phép giao CGAL
    // base() ∩ ghosts() mới bắt được trụ nào đâm chân; trước 04/08 nó không thể bắt vì chân
    // chưa từng được vẽ ra.
    color([0.9, 0.75, 0.2, 0.55])
        for (dx = [s3_pin_row_d, s3_w - s3_pin_row_d])
            translate([s3_x + dx - s3_pin_row_w/2, s3_y,
                       floor_t + s3_stand - s3_pin_drop])
                cube([s3_pin_row_w, s3_l - s3_pin_to_end, s3_pin_drop]);
    // Khối USB-A
    color([1, 0.5, 0.2, 0.45])
        translate([usba_x0, usba_y, floor_t]) cube([usba_w, usba_l, usba_h]);
    // Phích USB-A ở tư thế CẮM HẾT CỠ — mặt sau cục nhựa tì đúng vào mặt trước khối, vỏ kim
    // loại thọc trọn 12mm vào socket. Phải vẽ ở tư thế cắm hết chứ không phải tư thế dừng
    // ngoài vách: vẽ dừng ngoài thì cục nhựa không chạm vách, phép giao với base() rỗng sẵn
    // và phép kiểm thành vô nghĩa — vẫn "đạt" kể cả khi cửa bé tí.
    // Cục nhựa PHẢI chui qua cửa 3mm bề dày vách; đó là toàn bộ lý do cửa rộng 20 × 12.
    color([0.6, 0.6, 0.6, 0.45]) {
        translate([box_cx - 6.1, usba_y, floor_t + usba_axis_z - 2.25])
            cube([12.2, 12, 4.5]);                                   // vỏ kim loại trong socket
        translate([box_cx - usba_plug_w/2, usba_y - usba_plug_len,
                   floor_t + usba_axis_z - usba_plug_h/2])
            cube([usba_plug_w, usba_plug_len, usba_plug_h]);         // cục nhựa, XUYÊN vách
    }
    // Phích USB-C cũng ở tư thế CẮM HẾT CỠ, trên cổng TRÁI (TTL — cổng thật sự dùng).
    // Mặt trước cục nhựa tì vào mặt ngoài cổng (y = s3_y_rear + s3_usb_out) nên nó phải chui
    // trọn qua vách sau. Vỏ kim loại nằm hẳn trong cổng nên không vẽ: nó không đụng gì tới
    // vách, mà phép kiểm ở đây hỏi đúng một câu — cửa có nuốt nổi cục nhựa không.
    color([0.6, 0.6, 0.6, 0.45])
        translate([box_cx - s3_usb_pitch/2 - usbc_plug_w/2, s3_y_rear + s3_usb_out,
                   s3_usb_z - usbc_plug_h/2])
            cube([usbc_plug_w, usbc_plug_len, usbc_plug_h]);
}

/* ================= ĐẦU DÒ KIỂM LỖ ================= */
// Khối mỏng nằm gọn TRONG lòng mỗi lỗ. Giao với mảnh phải RỖNG thì lỗ mới thật sự thông.
// Ở voice-node đã dính 3 lần lỗi "khoét hụt" (lệnh khoét không phủ hết bề dày, còn lại lớp
// nhựa mỏng) và render nhìn bằng mắt KHÔNG phân biệt được với lỗ thật.
module probe(which) {
    if (which == "usba")
        translate([box_cx - usba_open_w/2 + 1, -1, usba_open_z0 + 1])
            cube([usba_open_w - 2, wall + 2, usba_open_h - 2]);
    else if (which == "usbc")
        translate([box_cx - s3_usb_open_w/2 + 1, out_l - wall - 1,
                   s3_usb_z - s3_usb_open_h/2 + 1])
            cube([s3_usb_open_w - 2, wall + 2, s3_usb_open_h - 2]);
    else if (which == "s3-pilot")
        translate([0, 0, floor_t + s3_stand - 4])
            for (dx = [-s3_hole_pitch/2, s3_hole_pitch/2])
                translate([box_cx + dx, s3_hole_y, 0]) cylinder(d = 1.4, h = 5);
    else if (which == "usba-wire")
        translate([box_cx - usba_wire_w/2 + 1, usba_back - 1, floor_t + usba_wire_z + 1])
            cube([usba_wire_w - 2, usba_stop_t + 2, usba_rib_h - usba_wire_z]);
}

/* ================= MIẾNG ƯỚM ================= */
// Cắt riêng từng vùng để thử lắp trong ~20 phút thay vì in lại cả base. Cắt THẲNG TỪ base()
// nên hình học y hệt bản thật — không phải mô hình dựng riêng.
//
// Mặt cắt phải TRÁNH mép sẵn có: cắt trùng mép sinh mặt dày 0 và làm STL mất 2-manifold.
// y = 45.4 chọn vì tại đó base() KHÔNG có khối nào: vách chặn hết ở 38.4, còn 2 trụ đỡ S3 mãi
// 45.9 mới bắt đầu. Mặt cắt chỉ đi qua sàn và 2 vách hông — nơi nó nằm giữa lòng vật liệu.
module test_usba() {   // kèm vách trước + cửa USB-A + trọn khay để ướm khối thật
    intersection() { base(); cube([out_w, 45.4, 26]); }
}
module test_s3() {     // kèm vách sau + cửa USB-C + 2 trụ vít để ướm luôn chiều cao cổng
    intersection() {
        base();
        translate([0, s3_hole_y - 14, 0]) cube([out_w, out_l, 26]);
    }
}
// Miếng ướm KHE DẪN HƯỚNG: cắt đúng đoạn có 2 gờ trước + 2 trụ đỡ. In ~20 phút rồi thả bo
// thật vào là biết khe 27.5 có vừa không — trước khi in cả base 2h.
// Khe là số duy nhất trong thiết kế mà sai thì hỏng theo kiểu tệ nhất: bo KHÔNG hạ xuống hết,
// mà nhìn thì vẫn thấy "gần vừa". Đúng lỗi đã dính với khay S2 bản trước.
// Chỉ cần ướm MỘT đầu: 2 cặp gờ dùng chung s3_guide_x0/x1 nên vừa đầu này là vừa đầu kia.
// Cắt y 40..62: hai mặt cắt đều rơi vào chỗ trống (vách chặn hết ở 38.4, gờ trước hết ở 58.4),
// không trùng mép sẵn có nên không sinh mặt dày 0.
module test_s3_truoc() {
    intersection() { base(); translate([0, 40, 0]) cube([out_w, 22, 26]); }
}

if      (part == "base")      base();
else if (part == "lid")       lid();
else if (part == "test-usba") test_usba();
else if (part == "test-s3")   test_s3();
else if (part == "test-s3-truoc") test_s3_truoc();
else if (part == "layout")    { base(); ghosts(); }
else if (part == "exploded")  exploded();
else                          assembly();
