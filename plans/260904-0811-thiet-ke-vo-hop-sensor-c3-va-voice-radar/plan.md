---
status: pending
priority: P3
scope: project
blockedBy: []
blocks: []
---

# Thiết kế lại 2 vỏ hộp: sleep-pad (C3) + voice-node/radar-node chung

## Bối cảnh
Xem đầy đủ: `plans/reports/brainstorm-260902-1552-thiet-ke-lai-vo-hop-sleeppad-c3-mini-report.md` (đã cập nhật 04/09, gồm cả Vỏ A và Vỏ B).

- **Vỏ A**: `vo-hop-sleeppad.scad` (S3-CAM) → viết mới `vo-hop-sleeppad-c3.scad` (C3 Super Mini) — firmware đã đổi sang C3 từ 24/08, cơ khí chưa theo kịp.
- **Vỏ B**: `vo-hop-modular.scad` (1 board S2 gộp radar+mic+IR, đã lỗi thời) → viết mới `vo-hop-voice-radar.scad` (2 board độc lập: voice-node S3-CAM + radar-node S2 Mini, 2 khoang điện riêng trong 1 vỏ chung).

## Mục tiêu (Definition of Done)
- [ ] `vo-hop-sleeppad-c3.scad` render được (`part="assembly"`), qua hết checker AABB + CGAL volume (giống mức độ nghiêm ngặt của bản S3).
- [ ] `vo-hop-voice-radar.scad` render được, 2 khoang điện tách biệt (không khối nào bắc cầu giữa 2 khoang), qua checker.
- [ ] Cả 2 file đều xuất STL test-print (miếng ướm từng phần) trước khi in toàn bộ, giống quy trình `test_usba()`/`test_s3()` của bản cũ.
- [ ] Không sửa đè `vo-hop-sleeppad.scad`/`vo-hop-modular.scad` — giữ nguyên làm tài liệu lịch sử.

## Ngoài phạm vi
- Không đổi vật liệu (PETG/FDM), không đổi cơ chế khớp bấm (snap-fit, không vít).
- Không thiết kế lại `vo-so.scad` (vỏ sò, đường TAOSG cũ, không dùng).
- Không đổi kiến trúc điện (2-board-độc-lập, chốt 18/08).

## Kiến trúc chung
Cả 2 file dùng lại đúng khung tham số + module (`corner_centers`, `bo_goc_dung`, `van_hong`, `go_bam`/`ranh_bam`, `khac_bay`) từ `vo-hop-sleeppad.scad` — chỉ thay khối linh kiện chính (`s3_*` → `c3_*` cho Vỏ A; thêm vách ngăn 2 khoang cho Vỏ B).

## Phases
1. `phase-01-vo-a-sleeppad-c3.md` — đo thật C3 Super Mini, viết SCAD, kiểm.
2. `phase-02-vo-b-voice-radar-chung.md` — viết SCAD (tái dùng số đo S3-CAM/radar cũ), kiểm.

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
