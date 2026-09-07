# [Report] Vỏ hộp cơ khí voice-node/radar-node + sleep-pad-node — sẵn sàng bàn giao anh Khanh dựng khung

**Ngày báo cáo:** 2026-09-05
**Người nhận:** Michael
**Loại báo cáo:** Milestone Checkpoint (Gate Check)
**Context:** Chốt thiết kế + in thử 2 vỏ hộp nhựa (voice-node+radar-node chung, sleep-pad-node) trước khi bàn giao anh Khanh dựng khung cơ khí — nối tiếp report `260821-1745-san-sang-dung-khung-phase-04-report.md`.

---

## 1. Executive Summary

Đã hoàn thiện thiết kế OpenSCAD + verify hình học (CGAL) + in thật 2 vỏ hộp nhựa PETG cho voice-node/radar-node và sleep-pad-node. Cả 2 đã in bản sản xuất (base+lid) và **lắp vừa hardware thật** qua nhiều vòng đo-in-chỉnh dựa trên phản hồi cầm tay thực tế (không chỉ dựa vào số đo lý thuyết). Sẵn sàng chuyển kích thước cuối cho anh Khanh dựng khung + ngàm gắn.

## 2. Vỏ hộp voice-node + radar-node (`vo-hop-voice-radar.scad`)

- **Kích thước ngoài:** 115.9 × 87 × 36mm.
- **Kiến trúc:** 2 khoang điện độc lập trong 1 vỏ (voice-node ESP32-S3-CAM+mic+IR, radar-node S2 Mini+LD2410C), mỗi khoang 1 cổng USB-C riêng — đúng nguyên tắc "không share nguồn" đã chốt 13/07. Khớp bấm 2 mảnh, không vít.
- **Hoàn thiện thêm trong đợt này:** vân trang trí khắc cả 4 vách (thẩm mỹ), dấu khắc chỉ hướng lắp mic (khớp hazard "Mic Orientation" trong `docs/presence-ac/system-wiring.md`).
- [x] CGAL verify sạch (base/lid/vách ngăn kín/không va chạm hardware) — qua cả code-review độc lập.
- [x] Đã in base+lid, lắp hardware thật.

## 3. Vỏ hộp sleep-pad-node (`vo-hop-sleeppad-c3.scad`)

- **Kích thước ngoài:** 35.0 × 74.4 × 28.0mm.
- **Kiến trúc:** ESP32-C3 Super Mini + khối USB-A breakout, khớp bấm 2 mảnh, không vít.
- **Đã qua 3 vòng in ướm + chỉnh theo phản hồi cầm tay thật** (không phải chỉnh 1 lần là xong):
  1. Khe thoát dây điện đặt quá cao, cản dây → hạ xuống sát sàn (2-3mm).
  2. Thanh chắn 2 bên khối USB-A bó sát → nới rộng lần 1.
  3. Vẫn chưa đủ hở → nới rộng lần 2, tách riêng biến hở-bề-rộng khỏi biến chiều-dài-vỏ để tránh vỏ bị dài thêm ngoài ý muốn.
- [x] `test-c3` (khay giữ board C3) in thật, khớp đúng.
- [x] Bản `base` sản xuất đầy đủ đã in thật — **user xác nhận "vừa vặn"** (05/09).

## 4. Hành động tiếp theo (Next Steps)

- Bàn giao 2 file STL sản xuất (`vo-hop-voice-radar-{base,lid}.stl`, `mech/presence-ac-enclosure/stl/{base,lid}.stl` của sleep-pad) + kích thước ngoài ở trên cho anh Khanh để tính khung/ngàm gắn.
- Liên hệ anh Khanh bắt đầu dựng khung cơ khí.

## Câu hỏi mở
Không có.
