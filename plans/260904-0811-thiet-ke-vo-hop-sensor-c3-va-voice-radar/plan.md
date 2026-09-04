---
status: in-progress
priority: P3
scope: project
blockedBy: []
blocks: []
---

# Thiết kế lại 2 vỏ hộp: sleep-pad (C3) + voice-node/radar-node chung

## Bối cảnh
Xem đầy đủ: `plans/reports/brainstorm-260902-1552-thiet-ke-lai-vo-hop-sleeppad-c3-mini-report.md` (đã cập nhật 04/09, gồm cả Vỏ A và Vỏ B).

- **Vỏ A**: `vo-hop-sleeppad.scad` (S3-CAM) → viết mới `vo-hop-sleeppad-c3.scad` (C3 Super Mini) — firmware đã đổi sang C3 từ 24/08, cơ khí chưa theo kịp.
- **Vỏ B**: **ĐẢO NGƯỢC LẦN 2 (04/09, cùng ngày)** — quay lại dùng `vo-hop-voice-radar.scad` làm bản chính thức. Lần đảo ngược đầu (xem `phase-02`/`phase-03`) dựa trên nhận định "modular.scad đã có 2 board độc lập, chỉ cần sửa cửa USB-C" — đúng về mặt kỹ thuật, nhưng user quyết định (trực tiếp, phiên 04/09 buổi chiều) **tiếp tục theo hướng đã làm trong session vừa rồi** (`vo-hop-voice-radar.scad`, 2 mảnh khớp bấm không vít, đã CGAL sạch) thay vì quay lại bản 3 mảnh `vo-hop-modular.scad` (base+face rời+vít M3). Lý do: muốn vỏ **nhỏ gọn, đẹp, có vân trang trí chi tiết** giống `vo-hop-sleeppad-c3.scad` — kiểu dáng này hợp `vo-hop-voice-radar.scad` (đã là 2 mảnh khớp bấm) hơn `vo-hop-modular.scad` (3 mảnh, vít). `phase-03` (sửa cửa USB-C modular.scad) do đó dừng lại — xem `phase-04`.
- **Sửa nhận định sai trong `phase-02`**: ghi chú "mic chưa được thêm vào `vo-hop-voice-radar.scad`" là SAI — đọc lại code (`module lid()`) xác nhận cụm mic (bệ đỡ boss, hốc `mic_pocket_d`, khe thoát dây) **đã có sẵn** từ commit `528efe8`. Cái thật sự còn thiếu, đúng như success criteria gốc của phase-02, là **chỉ dấu chiều lắp** — cụ thể là gì (khoá cơ khí hay khắc dấu ngoài) phụ thuộc đặc điểm vật lý thật của board mic, xem 2 phương án ở `phase-04`, chưa chốt cứng.

## Mục tiêu (Definition of Done)
- [x] `vo-hop-sleeppad-c3.scad` render được (`part="assembly"`), qua hết checker AABB + CGAL volume.
- [x] `vo-hop-voice-radar.scad` render được (`part="assembly"`), qua CGAL — **VÀ LÀ BẢN CHÍNH THỨC** (đảo ngược lần 2, xem trên).
- [x] `vo-hop-voice-radar.scad`: code vân trang trí (4 vách) + chỉ dấu chiều mic — xong, qua CGAL + code-review.
- [x] `base()+lid()` sản xuất đã xuất (`vo-hop-voice-radar-base.stl`, `-lid.stl`) — user quyết định bỏ qua bước in ướm test, tin vào số đo đã verify khớp `vo-hop-modular.scad` (xem `phase-04`). Chờ user in thật + báo kết quả lắp ráp.
- [ ] ~~Vỏ B: `face()` của `vo-hop-modular.scad`...~~ — DỪNG, xem đảo ngược lần 2. `vo-hop-modular.scad` giữ nguyên làm tài liệu lịch sử.
- [ ] Không sửa đè `vo-hop-sleeppad.scad`/`vo-hop-modular.scad` — giữ nguyên làm tài liệu lịch sử.

## Ngoài phạm vi
- Không đổi vật liệu (PETG/FDM), không đổi cơ chế khớp bấm (snap-fit, không vít).
- Không thiết kế lại `vo-so.scad` (vỏ sò, đường TAOSG cũ, không dùng).
- Không đổi kiến trúc điện (2-board-độc-lập, chốt 18/08).

## Kiến trúc chung
Cả 2 file dùng lại đúng khung tham số + module (`corner_centers`, `bo_goc_dung`, `go_bam`/`ranh_bam`, `khac_bay`) từ `vo-hop-sleeppad.scad` — chỉ thay khối linh kiện chính (`s3_*` → `c3_*` cho Vỏ A; thêm vách ngăn 2 khoang cho Vỏ B). Vân trang trí (`van_hong` ở bản C3) được port sang Vỏ B với tên module khác (`van_truoc_sau`, xem `phase-04`) vì hướng khắc đổi từ vách hông sang vách trước/sau — cùng kỹ thuật cắt V-groove, khác trục.

## Phases
1. `phase-01-vo-a-sleeppad-c3.md` — đo thật C3 Super Mini, viết SCAD, kiểm. **completed.**
2. `phase-02-vo-b-voice-radar-chung.md` — viết SCAD mới cho Vỏ B (`vo-hop-voice-radar.scad`). **completed** — cơ khí 2 khoang + mic đã có sẵn trong code (nhận định "mic thiếu" trong ghi chú gốc là sai, xem sửa ở trên). Được **phục hồi làm bản chính thức** bởi đảo ngược lần 2.
3. `phase-03-sua-cua-usbc-s3-ban-cu.md` — quay lại `vo-hop-modular.scad`, verify/sửa cửa USB-C S3. **superseded 04/09 (đảo ngược lần 2)** — không dùng `vo-hop-modular.scad` làm bản chính thức nữa, xem phase-04.
4. `phase-04-van-trang-tri-mic-huong-in-that.md` — vân trang trí **cả 4 vách** (trước/sau + hông) + dấu khắc chiều mic trên `vo-hop-voice-radar.scad`. **completed**: code+CGAL+code-review xong; user quyết định bỏ qua ướm test (số đo linh kiện đã verify khớp 100% `vo-hop-modular.scad` trừ USB-C-S3 đã cải thiện sẵn) — `base()+lid()` sản xuất đã xuất, chờ user in thật.

## Rủi ro
- Số đo C3 Super Mini web (22.5×18mm) chưa xác nhận thật — Phase 1 bắt đầu bằng đo tay, không parametrize trước.
- Vị trí mic/IR trên board S3-CAM (dùng cho voice-node) có thể khác dự tính ban đầu trong `vo-hop-modular.scad` (board đổi mục đích từ camera sang mic+IR) — Phase 2 cần xác nhận lại trước khi định vị cửa.
- 2 khoang điện trong Vỏ B phải test kỹ bằng CGAL volume rằng vách ngăn thật sự kín (0 khe hở) — vi phạm nguyên tắc "không share nguồn" nếu vách ngăn có khe.

## Validation Log

### Quyết định (2026-09-04)
1. **Nếu số đo C3 lệch nhiều so ước tính web** (kể cả rộng hơn khối USB-A 16mm): vẫn giữ bố cục nối tiếp — lý do ergonomic (2 đầu dây ra 2 phía) độc lập với kích thước C3, không đổi bố cục chỉ vì số đo lệch ước tính.
2. **Nếu vị trí mic/IR trên board S3-CAM thật khác giả định** `vo-hop-modular.scad`: cứ điều chỉnh thiết kế cho vừa, không dừng lại hỏi — trừ khi không thể vừa về mặt vật lý (lúc đó mới cần quyết định lại).

### Verification Results
- Tier: Light (2 phase)
- Verified: số đo S3-CAM (65×26.5mm, 2 lỗ vít đầu USB-C) và radar LD2410C (16×22×3mm, không lỗ vít) trong `vo-hop-modular.scad` khớp đúng mô tả plan. Hazard "LD2410 Module Placement" (≥5mm, chập điện 5V) verify đúng nguyên văn `system-wiring.md`. Failed: 0.

### Whole-Plan Consistency Sweep
- Đã đọc lại plan.md + 2 phase file — nhất quán, không còn câu "nhiễu điện từ" sai (đã sửa cả report gốc). Không mâu thuẫn còn lại.

### Quyết định đảo ngược lần 2 (2026-09-04, buổi chiều)
1. **File chính thức cho Vỏ B**: `vo-hop-voice-radar.scad` (không phải `vo-hop-modular.scad`). User quyết định trực tiếp, ưu tiên kiểu dáng 2 mảnh khớp bấm không vít + vân trang trí trên `vo-hop-voice-radar.scad`, chấp nhận việc file này chưa in ướm thật lần nào (khác `vo-hop-modular.scad` đã in ướm phần lớn) — bù lại bằng cách bắt buộc in ướm thật 3 miếng TRƯỚC khi in `base()+lid()` đầy đủ (xem phase-04).
2. **Không bắt vít**: đã đúng hiện trạng code (`vit_on = false`, khớp bấm) — không phải việc mới, chỉ xác nhận giữ nguyên.
3. **Vân trang trí**: port `van_hong()` từ `vo-hop-sleeppad-c3.scad`, nhưng đổi hướng khắc từ vách hông (bản C3) sang vách trước/sau (voice-radar, vì đây là 2 mặt dài nhất — `out_w≈115.9mm > out_l≈87mm`, ngược tỉ lệ với C3). 3 mức Z `[9,16,23]` thay vì 2 mức của C3 (deck_h=30 cao hơn deck_h=22 của C3). Né toạ độ X của cửa USB-C-S3 + lỗ IR (vách trước) và cửa USB-C-S2 (vách sau) — không khắc xuyên qua.
4. **Cụm mic**: đã có bệ đỡ + hốc trong code — việc thật còn thiếu là **chỉ dấu chiều lắp**. Board tròn Ø10 nên khoá cơ khí (nếu board có đặc điểm bất đối xứng) hay khắc dấu ngoài + hướng dẫn lắp ráp (nếu board đối xứng hoàn toàn) — chỉ chốt sau khi đo board thật, xem `phase-04` mục "Chỉ dấu chiều lắp mic".

### Verification Results (lần 2)
- Tier: Light — verify bằng đọc code trực tiếp (không cần agent).
- Verified: `out_w=115.9`, `out_l=87`, `deck_h=30` tính từ tham số thật trong `vo-hop-voice-radar.scad` khớp đúng số user nêu. Cửa USB-C-S3 (vách trước, X∈[34.85,59.35]), lỗ IR (vách trước, X∈[17.6,24.1]), cửa USB-C-S2 (vách sau, X∈[86.2,98.2]) — toạ độ tính trực tiếp từ code, dùng làm vùng né cho phase-04. Mic đã có bệ đỡ+hốc trong `module lid()` (dòng 300-322) — ghi chú "mic chưa thêm" trong phase-02 gốc là sai. Failed: 0.

### Whole-Plan Consistency Sweep (lần 2)
- Đã đọc lại toàn bộ `plan.md` + `phase-01`..`phase-04` sau khi thêm phase-04. Sửa 2 chỗ còn nói cứng "gờ/vát định hướng" cho chỉ dấu mic (không khớp 2-phương-án thật trong phase-04) → đổi thành "chưa chốt cứng, xem phase-04". Sửa "Kiến trúc chung" — `van_hong` chỉ đúng tên ở bản C3, bản voice-radar dùng `van_truoc_sau` (trục khác). Không còn mâu thuẫn nào giữa trạng thái phase (`completed`/`superseded`/`pending`) và nội dung mô tả tương ứng. `phase-03` giữ nguyên nội dung gốc làm lịch sử, chỉ thêm banner supersede ở đầu — không xoá.

### Validate — Verification Pass (Fact Checker + Contract Verifier, tier Standard)
- Claims checked: 6 (out_w/out_l/deck_h số đo; toạ độ 3 cửa/lỗ; mic đã có sẵn trong `lid()`; `vit_on=false`; `test-radar-base-wall` tồn tại từ `882d603`; hazard "Mic Orientation" đúng nguyên văn `system-wiring.md` mục 5).
- **Thực nghiệm bổ sung (ngoài đọc code)**: dùng `openscad` CLI thật (có sẵn ở `/usr/bin/openscad`) render 3 file test cô lập để verify TOÁN HỌC HÌNH HỌC của `van_truoc_sau()` (phép quay `rotate([0,90,0])`) và hàm `van_doan_ho()` — không chỉ suy luận trên giấy:
  - Test 1: xác nhận `rotate([0,90,0])` cho đúng chiều dài dọc X, đúng offset Y/Z như polygon định nghĩa (đọc STL ASCII, đối chiếu toạ độ đỉnh tay).
  - Test 2: `van_doan_ho()` với keepout IR = cả bề rộng module (20mm) → vách trước chỉ còn 1 đoạn hở duy nhất, mất nửa trái — phát hiện vấn đề thẩm mỹ thật, đưa vào câu hỏi validate.
  - Test 3: `van_doan_ho()` với keepout IR = đường kính lỗ thật (6.5mm) → vách trước có 3 đoạn hở cân đối. `union(van_hong();van_truoc_sau())` cho CGAL `Simple: yes`.
- Verified: 6 | Failed: 0 | Unverified: 0.

### Validate — Câu hỏi & quyết định (2026-09-04, phỏng vấn validate)
1. **Vùng né lỗ IR trên vách trước**: chọn dùng đường kính lỗ LED thật (Ø6.5mm), KHÔNG dùng cả bề rộng module IR (20mm) — lý do: vân nằm trên mặt ngoài vách, module nằm sâu bên trong không chiếm diện tích mặt ngoài; dùng cả module làm mất nửa trái vách trước không có vân, lệch thẩm mỹ. Đã cập nhật `phase-04`.
2. **Chỉ dấu chiều mic**: user giao "tự tra thông số INMP441 đi" → đã tra (Digi-Key datasheet, components101, easyelecmodule — xem citation trong hội thoại) — KHÔNG tìm thấy tài liệu công khai nào cho biến thể board TRÒN Ø10 cụ thể (khác hẳn breakout 6-chân chữ nhật phổ biến). **Phát hiện quan trọng**: hazard là lỗi LẬT MẶT (flip), không phải lỗi XOAY (spin quanh Z) — 1 khoá cơ khí kiểu D-cut/keyway (phương án (a) trong bản nháp phase-04 cũ) BẢN CHẤT không ngăn được lỗi lật mặt dù đặt đúng vị trí. Quyết định: bỏ phương án (a), chốt phương án (b) — khắc dấu ngoài + comment quy trình lắp ráp trong code. Đã cập nhật `phase-04`, không còn "chưa chốt" nữa.
3. **Vân vách hông**: user chọn CÓ thêm (khác đề xuất ban đầu chỉ 2 vách trước/sau) — port verbatim `van_hong()` gốc từ bản C3 cho x=0/out_w, không cần logic né cửa vì không vách nào có cửa. Đã verify không đụng khớp bấm `ranh_bam()` (z=26.48 vs van_zs tối đa 23, hở 3.5mm). Đã cập nhật `phase-04` + đổi tên phase title.
4. **Miếng ướm test mic riêng**: user chọn KHÔNG thêm — verify hốc mic + dấu khắc ngay lúc in `lid()` đầy đủ, chấp nhận rủi ro in lại nếu sai. Đã cập nhật `phase-04` Risk Assessment.

### Whole-Plan Consistency Sweep (validate, lần 3)
- Đã đọc lại `plan.md` + toàn bộ `phase-04` sau khi áp dụng 4 quyết định validate. Xoá sạch các câu "chưa chốt", "cần đo board thật trước" còn sót từ bản nháp trước — thay bằng quyết định cuối + lý do. Đổi tên phase-04 (frontmatter `title`) và mục Phases trong `plan.md` để phản ánh đúng "4 vách" thay vì "vách trước/sau". Không còn mâu thuẫn. Verification Results: Failed 0 → đủ điều kiện chuyển sang implementation.

### Cook — Implementation + Code Review (2026-09-04)
- Implement xong `van_hong()`/`van_doan_ho()`/`van_truoc_sau()`/`mic_huong_khac()` trong `vo-hop-voice-radar.scad`, gọi trong `base()`/`lid()`.
- Verify thật (không chỉ render assembly): CGAL `Simple: yes` cho `base`/`lid`/`test-s3`/`test-s2`/`test-radar`/`test-radar-base-wall`; `probe("vach-ngan-kin")` rỗng; `base()∩ghosts()` giống hệt bit-for-bit bản gốc (không va chạm mới); echo đoạn hở đúng dự kiến.
- `code-reviewer` subagent độc lập review diff — 1 finding CONFIRMED (medium): keepout vân dùng literal riêng (`6.5`, `-6/+12`) thay vì tái dùng biến của cutout thật (`ir_hole_d`, S2 door) → rủi ro lệch âm thầm nếu cutout đổi số sau này mà quên sửa keepout. Đã fix: hoist `s2_usb_door_off`/`s2_usb_door_w` dùng chung cho cutout thật + probe + keepout; `ir_hole_d` dùng chung tương tự. 1 finding PLAUSIBLE (low): `van_doan_ho()` không chặn input suy biến (keepout x0>=x1) → đã thêm `assert()`. 1 finding informational: comment cũ `// = 24.5` tại `s3_usb_open_w` lệch so số thật (26.5, do `s3_usb_plug_clear` đổi từ 1→2 trước đó) — đã sửa comment, đây cũng là nguyên nhân số ví dụ trong `phase-04` (viết lúc validate) lệch ~1mm so số thật trong file (không ảnh hưởng hình học, code tự tính đúng từ biến sống).
- Re-verify sau fix: toàn bộ CGAL vẫn `Simple: yes`, echo vẫn đúng, đã xuất lại 3 STL ướm (byte-identical với trước fix — fix chỉ đổi tên biến, không đổi số).
- Đã xuất 3 STL ướm vào `mech/presence-ac-enclosure/`: `vo-hop-voice-radar-test-{s3,s2,radar}.stl`.
- **Việc còn lại KHÔNG PHẢI AI làm được**: in ướm thật 3 miếng + lắp hardware thật (S3-CAM, S2 Mini, radar LD2410C) — chờ user, xem `phase-04` mục "Bàn giao cho user". `phase-04` giữ `status: in-progress`, không đánh `completed`.

### Quyết định bỏ qua ướm test (2026-09-04, sau cook)
User quyết định trực tiếp: không cần in ướm 3 miếng test, xuất thẳng `base()+lid()` sản xuất — căn cứ đã dùng `vo-hop-modular.scad` thật nhiều lần và xác nhận toàn bộ số đo linh kiện đúng, chỉ riêng cổng USB-C-S3 là sai (không tính vít/vân — 2 điểm khác biệt có chủ đích, không phải lỗi).
**Verify trước khi chấp nhận**: `grep` so sánh toàn bộ tham số `s3_*`/`s2_*`/`ir_*`/`mic_*`/`radar_*` giữa `vo-hop-modular.scad` và `vo-hop-voice-radar.scad` — khớp 100%, TRỪ `s3_usb_plug_clear` (modular=1, voice-radar=2 — sửa chủ ý có sẵn từ trước, lấy số đã nghiệm thu ở `vo-hop-sleeppad.scad`, không phải sai sót cần sửa thêm). Không có tham số nào cần đổi.
Đã xuất `vo-hop-voice-radar-base.stl` + `vo-hop-voice-radar-lid.stl` (CGAL `Simple: yes` cả 2). `phase-04` chuyển `status: completed`. Rủi ro còn lại (chưa in ướm CHÍNH file này, dù số đo linh kiện giống modular) đã thông báo cho user, user chấp nhận.
