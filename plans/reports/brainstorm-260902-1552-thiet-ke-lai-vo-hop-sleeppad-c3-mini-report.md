---
title: Thiết kế lại vỏ hộp sleep-pad-node từ ESP32-S3-CAM sang ESP32-C3 Super Mini
date: 2026-09-02
updated: 2026-09-04
type: brainstorm
---

# Thiết kế lại vỏ hộp sleep-pad: S3-CAM → C3 Super Mini

> **Cập nhật 04/09:** mở rộng phạm vi sang cả vỏ hộp voice-node+radar-node — xem mục "Vỏ B" bên dưới. Vỏ A (sleep-pad) giữ nguyên quyết định 02/09, không đổi.

## Vấn đề
`mech/presence-ac-enclosure/vo-hop-sleeppad.scad` thiết kế cho ESP32-S3-CAM (GOOUUU N16R8, 65×26.5mm) — nhưng firmware `sleep-pad-node` đã chuyển hẳn sang **ESP32-C3 Super Mini** (`nologo_esp32c3_super_mini`) từ 24/08, chạy thật ổn định (build/flash verify nhiều lần, xem `plans/260824-1109-dong-bo-sleep-pad-node-esp-idf/`). Vỏ hộp cơ khí chưa theo kịp thay đổi hardware này.

## Scout — bằng chứng từ code (không suy đoán)
- `platformio.ini`: `[env:c3supermini]`, `board = nologo_esp32c3_super_mini`.
- `config.h`: UART pad nối trực tiếp GPIO5(RX)/GPIO6(TX) của C3, comment "D+/D- → IO5/IO6" — khớp cáp pad vẫn là đầu cắm USB-A 4 dây (VCC/GND/D+/D-), giờ đấu thẳng vào C3 thay vì qua board S3 trung gian.
- Kích thước C3 Super Mini: **~22.5 × 18mm** (nguồn web, CHƯA đo thật — file SCAD này từng sai 2 lần vì tin số liệu mạng thay vì đo tay thật, ví dụ ESP32-S3-N16R8 generic 67×31/4-lỗ vs bo GOOUUU thật 65×26.5/2-lỗ).

## Quyết định (đã chốt qua AskUserQuestion)
1. **C3 Super Mini không có lỗ vít** (kiểu breadboard trần) → định vị bằng gờ dẫn hướng (pocket) + dán, giống triết lý đã áp dụng cho module radar LD2410C trong `vo-hop-modular.scad` (module đó cũng không có lỗ vít).
2. **Khối USB-A breakout (32×16×20mm) giữ nguyên** — cáp pad vẫn cắm qua đó, không hàn dây trực tiếp.
3. **Bố cục nối tiếp (không song song)** — giữ nguyên lý do gốc của bản S3 vẫn còn đúng: 2 đầu dây (cáp pad + cáp nguồn) ra 2 đầu đối diện hộp, không chồng dây khi đặt dưới gầm giường. Lý do "song song không đủ rộng" của bản S3 không còn áp dụng (C3 hẹp hơn nhiều) nhưng không đổi bố cục vì lý do ergonomic vẫn đứng.
4. **File mới**, không sửa đè: `mech/presence-ac-enclosure/vo-hop-sleeppad-c3.scad`. Giữ `vo-hop-sleeppad.scad` (bản S3) nguyên vẹn làm tài liệu lịch sử.

## Ước tính kích thước (chưa chốt, cần đo thật trước khi parametrize)
- Chiều dài hộp: ~113.9mm (bản S3) → ước **~70-75mm** (C3 ~22.5mm thay cho S3 65mm, khối USB-A 32mm + khe hở không đổi).
- Chiều rộng: ~46mm (bản S3, driven bởi bo rộng 26.5) → có thể co nhẹ vì C3 chỉ rộng 18mm, nhưng cần xem lại tương quan với khối USB-A (16mm) + 4 trụ góc.
- Chiều cao: không đổi (~28mm) — vẫn do khối USB-A (20mm) quyết định, C3 thấp hơn nhiều nên không phải yếu tố giới hạn.

## Việc phải làm trước khi viết SCAD thật
Đo tay thật board C3 Super Mini (không tin số web):
- Kích thước ngoài PCB (dài × rộng), bề dày.
- Vị trí + kích thước cổng USB-C (cần lỗ trên vách nếu muốn nạp lại firmware không tháo hộp).
- Vùng cấm anten (không đặt kim loại/thành dày gần đó).
- Chiều cao linh kiện cao nhất (thường là chip ESP32-C3 hoặc nút RESET/BOOT).
- Vị trí 2 nút bấm (nếu có) — có cần lỗ thao tác trên vỏ không.

## Ngoài phạm vi (Vỏ A)
- Không đổi khối USB-A (giữ nguyên số đo bản S3).
- Không đổi vật liệu/phương pháp in (PETG, FDM, snap-fit).

---

# Vỏ B — voice-node + radar-node chung (thay `vo-hop-modular.scad`)

## Vấn đề
`vo-hop-modular.scad` (28/07-04/08) thiết kế cho **1 board S2 Mini duy nhất** làm hết (radar+mic+IR). Nhưng `docs/presence-ac/system-wiring.md` (cập nhật 18/08, mục "What Changed from Previous Doc") xác nhận kiến trúc đã tách thành **2 board độc lập, mỗi board 1 nguồn USB-C riêng**: voice-node (ESP32-S3, mic+IR) và radar-node (S2 Mini, chỉ LD2410C). `vo-hop-modular.scad` là thiết kế cho kiến trúc cũ đã lỗi thời, không khớp hardware thật.

## Xác nhận (qua AskUserQuestion 04/09)
1. **Board voice-node thật vẫn là GOOUUU ESP32-S3-CAM** (không phải DevKitC-1 dù `system-wiring.md` ghi tên đó — cùng board đã đo trong `vo-hop-modular.scad`) → **tái dùng số đo cũ, không cần đo lại**: 65×26.5mm, 2 lỗ vít đầu USB-C.
2. **2 board đặt CHUNG 1 vị trí vật lý** (đầu giường) → làm **1 vỏ hộp chung, 2 khoang điện độc lập bên trong** (không share nguồn — đúng nguyên tắc Michael 13/07 — chỉ share vỏ nhựa).
3. **1 nắp chung, khớp bấm (snap-fit) như vỏ A** — không khoang vít, không vít, chỉ khớp đậy.
4. **File mới**: `mech/presence-ac-enclosure/vo-hop-voice-radar.scad` (tên đề xuất, thay `vo-hop-modular.scad`). Giữ file cũ nguyên vẹn làm tài liệu lịch sử.

## Cụm thiết kế (Vỏ B)
1. **Khung ngoài chung + vách ngăn giữa 2 khoang** — vách ngăn vật lý đảm bảo 2 nguồn USB-C độc lập không vô tình chạm nhau.
2. **Khoang voice-node**: đỡ S3-CAM (tái dùng số đo cũ: 65×26.5mm, 2 lỗ vít đầu USB-C) + cửa mic Ø10 + cửa IR LED (31×20mm) + cửa nguồn USB-C riêng.
   - ⚠️ **Ràng buộc bắt buộc** (hazard thật đã ghi nhận, `system-wiring.md` mục "Mic Orientation"): mic lắp SAI CHIỀU thì nghe tiếng vọng trong vỏ hộp thay vì nghe phòng. Cửa mic phải có chỉ dấu/gờ định hướng, không lắp được 2 chiều.
3. **Khoang radar-node**: đỡ S2 Mini + radar LD2410C (tái dùng số đo cũ: radar 16×22×3mm, không lỗ vít, định vị bằng hốc+dán) + cửa sổ radar mỏng + cửa nguồn USB-C riêng.
   - ⚠️ **Ràng buộc bắt buộc** (hazard thật, `system-wiring.md` mục "LD2410 Module Placement Away From USB-C Port"): module radar cách mọi cổng USB-C **≥5mm** — lý do thật là nguy cơ **chập điện với rail 5V** khi đặt/hàn quá gần (đã từng xảy ra thật, không phải nhiễu điện từ).
4. **Khớp bấm chung** (1 nắp, snap-fit, giống vỏ A — đã chốt).
5. **Bo góc + vân trang trí** — đồng bộ phong cách với vỏ A cho đẹp/nhất quán bộ 2 vỏ.

## Việc phải làm trước khi viết SCAD thật (Vỏ B)
- Không cần đo lại S3-CAM/radar LD2410C (đã có số từ `vo-hop-modular.scad`).
- Đo/xác nhận: vị trí thật của mic + IR module trên S3-CAM board thật (board đổi mục đích từ camera sang mic+IR — vị trí lắp linh kiện ngoài có thể khác bản gốc `vo-hop-modular.scad` dự tính).
- Xác định khoảng cách tối thiểu giữa khoang radar và khoang có cổng USB-C (radar hoặc voice-node) để thoả hazard "LD2410 cách xa USB-C".

## Ngoài phạm vi (Vỏ B)
- Không đổi vật liệu/phương pháp in (PETG, FDM, snap-fit).
- Không đổi kiến trúc điện 2-board-độc-lập (đã chốt 18/08, không bàn lại).
