---
phase: 1
title: "Apnea events trong MorningReport (Go)"
status: completed
priority: P1
dependencies: []
---

# Phase 1: Apnea events trong MorningReport

## Overview
Mở rộng `PGStore.MorningReport` (đã có, `cloud/presence-ac/internal/sessions/pgstore.go`) thêm phát hiện apnea signal v0 bằng OR-fusion 2 tín hiệu từ `sec_data`, không thêm query DB mới.

## Requirements
- Functional: response `GET /api/sessions/morning-report` có thêm:
  ```json
  "apnea_events": [{"start_s": 304, "end_s": 315, "duration_s": 11, "confidence": "supported"}],
  "apnea_count": 1
  ```
  Điều kiện trigger (OR):
  - A: `status==8` liên tục ≥10s.
  - B: `heart_rate>0 AND resp_rate==0` liên tục ≥10s, KHÔNG tính nếu run bắt đầu trong vòng 25s sau lần cuối `status` là 2 (MOVEMENT) hoặc 3 (SIT_UP).
  - confidence = "supported" nếu `sdata` trung bình trong run < 70% median(sdata) của 60s trước run.start, ngược lại "weak".
- Non-functional: `disclaimer` cập nhật: `"Tóm tắt giấc ngủ, không phải chẩn đoán y tế. apnea_events là tín hiệu tham khảo dựa trên resp_rate/status, không phải AHI y tế, chưa qua kiểm chứng lâm sàng."`

## Architecture
Sửa trong cùng vòng loop hiện có của `MorningReport` (đọc 1 lượt `sec_data` theo `time`):
- Query SELECT thêm 2 cột: `status`, `sdata` (đã có sẵn trong bảng, chỉ thêm vào SELECT).
- Track thêm trong loop: `lastMovementOrSitUpTs` (thời điểm gần nhất status∈{2,3}), 2 run-tracker riêng cho tín hiệu A và B (start time, đang chạy hay không).
- Khi 1 run kết thúc (status/điều kiện đổi) và đủ ≥10s → thêm vào `apnea_events`. Dedupe: nếu run A và run B overlap bất kỳ (dù chỉ 1s) → gộp thành 1 event, lấy `min(start)`/`max(end)` của cả 2 (KISS, không cần ngưỡng % overlap).
- `sdata` baseline: giữ 1 deque/slice các `(time, sdata)` trong 60s gần nhất để tính median khi cần (không cần query lại DB).

## Related Code Files
- Modify: `cloud/presence-ac/internal/sessions/pgstore.go` (mở rộng `MorningReport`, struct `MorningReport` thêm field)
- Modify: `cloud/presence-ac/internal/api/sessions_handlers.go` (thêm field vào response map ở `getMorningReport`)

## Implementation Steps
1. Đọc lại `MorningReport` hiện tại (vừa code trong plan trước, đã deploy) — không giả định lại từ trí nhớ.
2. Sửa SQL SELECT thêm `status, sdata`.
3. Viết logic run-tracking cho A/B + dedupe + confidence (dùng median trên slice Go, không cần thư viện thêm).
4. Cập nhật struct `MorningReport` + response JSON trong handler.
5. Build: `cd cloud/presence-ac && go build ./... && go test ./...`.
6. Deploy Jetson (`docker compose build backend && docker compose up -d backend`), test bằng dữ liệu đêm 25/08 đã có:
   ```
   curl "http://192.168.1.125:8080/api/sessions/morning-report?device_id=CNU190440C&from=2026-08-25T00:00:00Z&to=2026-08-26T00:00:00Z"
   ```
7. Kiểm tra `apnea_events` có hợp lý không (không tràn lan do resp_rate=0 lúc mới nằm) — nếu tràn lan, xem lại điều kiện loại trừ 25s sau MOVEMENT/SIT_UP.

## Success Criteria
- [x] `go build`/`go test` pass.
- [x] Response có `apnea_events` (mảng rỗng nếu không có, không phải `null`), `apnea_count`, `disclaimer` mới — verify thật: `{"apnea_count":0,"apnea_events":[],...}`.
- [x] Test trên dữ liệu đêm 25/08: `apnea_count=0`, không báo giả tràn lan (chỉ ~12 phút on-bed thật, hợp lý). Các field cũ (`on_bed_seconds`, `off_bed_transitions`, `snore_count`, `avg_heart_rate`, `avg_resp_rate`) không đổi so với lần verify trước — không regression.

## Risk Assessment
- Risk: dữ liệu đêm 25/08 quá ngắn (~12 phút on-bed thật) để đánh giá đầy đủ ngưỡng — chấp nhận, đây chỉ là smoke test, tinh chỉnh thật ở Phase 2 (test qua đêm).
- Risk: dedupe A/B sai có thể đếm trùng 1 sự kiện thành 2 — viết test case tay (giả lập input) nếu logic phức tạp hơn dự kiến khi code thật.
