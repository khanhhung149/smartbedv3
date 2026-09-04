---
phase: 3
title: "Sửa/verify cửa USB-C S3 trong vo-hop-modular.scad (bản cũ)"
status: superseded
priority: P1
dependencies: []
---

# Phase 3: Sửa cửa USB-C S3 trong bản cũ

## ⚠️ SUPERSEDED (04/09, đảo ngược lần 2) — KHÔNG LÀM PHASE NÀY
User quyết định trực tiếp quay lại `vo-hop-voice-radar.scad` làm bản chính thức (xem `plan.md`
mục "Quyết định đảo ngược lần 2" + `phase-04-van-trang-tri-mic-huong-in-that.md`). `vo-hop-modular.scad`
không còn là đường đi sản xuất — phase này giữ lại làm lịch sử, chỉ cân nhắc lại nếu sau này
`vo-hop-voice-radar.scad` gặp vấn đề không sửa được (chưa xảy ra, chưa có lý do quay lại).

## Overview (nội dung gốc — ĐÃ SUPERSEDED, giữ tham khảo)
Đảo ngược quyết định Phase 2 (04/09) — quay lại dùng `vo-hop-modular.scad` làm vỏ chính cho voice-node+radar-node (đã có 2 board độc lập, mỗi board 1 nguồn riêng, đã in ướm phần lớn). Chỉ còn 1 việc thật: verify/sửa cửa USB-C của S3 trên tấm `face()` — số hiện tại (`s3_usb_pitch=12.5`, `s3_usb_open_w=24.5`) là ước tính, chưa đo tay, chưa in ướm (tự file ghi chú rõ).

## Requirements
- Functional: cửa USB-C trên `face()` đủ rộng/đúng vị trí để phích USB-C cắm được hết cỡ vào cả 2 cổng của S3-CAM (TTL và OTG).
- Non-functional: verify bằng miếng ướm in thật (giống cách `test_s2()`/`test_s3()` đã có cho base — nhưng đó là test khay ĐỠ board, không phải test CỬA trên face; face chưa có miếng ướm riêng).

## Architecture
`face()` hiện in nằm ngang (`face_print()`, xoay úp mặt ngoài xuống bàn) — không cắt trực tiếp từ `face()` như base được vì face vốn đã là 1 tấm mỏng độc lập, không cần "miếng ướm" cắt nhỏ ra — **in nguyên cả face_print() đã đủ nhỏ/nhanh** để test, không cần thêm module cắt riêng.

## Related Code Files
- Modify: `mech/presence-ac-enclosure/vo-hop-modular.scad` (sửa `s3_usb_pitch`/`s3_usb_open_w` sau khi đo, hoặc giữ nguyên nếu đo thấy đúng)

## Implementation Steps
1. Đo tay thật cục nhựa phích USB-C (bề rộng, không phải chỉ vỏ kim loại) — bản cũ đã ghi chú cách đo cho bản sleeppad (`usbc_plug_w=12`), có thể dùng lại số đó nếu cùng loại phích USB-C tiêu chuẩn.
2. In `face_print()` (đã có sẵn module, không cần thêm gì): `openscad -D 'part="face-print"' -o face-test.stl vo-hop-modular.scad`.
3. Cắm thử cả 2 đầu USB-C (TTL, OTG) của S3-CAM thật qua tấm face vừa in — kiểm cắm hết cỡ (~6.5mm sâu) không bị cấn.
4. Nếu không vừa: đo lại theo đúng bài học đã ghi trong file (`s3_usb_pitch`, `s3_usb_open_w`), sửa, in lại `face_print()` cho tới khi vừa — KHÔNG cần in lại cả `base()`/`lid()` vì chỉ face đổi.
5. Sau khi face vừa: render `assembly()` đầy đủ lần cuối, kiểm bằng mắt.

## Success Criteria
- [ ] Cả 2 đầu USB-C S3 (TTL, OTG) cắm hết cỡ qua face in thật, không cấn.
- [ ] `s3_usb_pitch`/`s3_usb_open_w` trong file đã là số đo tay thật (không còn ghi "ƯỚC, CHƯA ĐO").

## Risk Assessment
- Risk: nếu pitch sai nhiều, có thể phải khoét lại cả vị trí 2 lỗ vít neo bo S3 (đang neo theo `s3_hole_pitch=23`, số này CŨNG chưa đo chắc theo comment file) — kiểm luôn trong lúc đo, đỡ phải quay lại 2 lần.
