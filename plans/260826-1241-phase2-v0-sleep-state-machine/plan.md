---
status: pending
priority: P2
scope: project
blockedBy: []
blocks: []
---

# Phase 2 v0: Báo cáo giấc ngủ từ dữ liệu đang chạy (không AHI)

## Bối cảnh
Michael: làm LD2410C trước, cái gì chạy được thì ship. Không chờ LD2510B/piezo/SpO2.
Dữ liệu thật đang có: radar presence (LD2410C, `sessions`), sec_data (status/HR/RR mỗi giây — luôn hoạt động), snore_event (voice-node, `room_snore_events`). Dữ liệu KHÔNG có: min_data (0x20 monitor mode hỏng trên phần cứng này, đã xác nhận thật) → không tính được AHI/apnea thật.

**Sửa giả định kiến trúc ban đầu (phát hiện qua verify code, không phải giả định nữa):**
`presence-ac` (Go) và sleeppad KHÔNG phải 2 hệ tách biệt cần cầu nối HTTP. `presence-ac` đọc trực tiếp cùng 1 Postgres/TimescaleDB (`sleeptech`) chứa `sec_data`, `min_data`, `sessions`, `room_snore_events` — bằng chứng: `cloud/presence-ac/internal/sessions/pgstore.go:353` (`GetLatestSec` đọc bảng `sec_data`), `pgstore.go:153` (`GetTimeline` JOIN `sec_data`+`min_data`+snore trong Go), `cloud/presence-ac/internal/snore/store.go:35` (`snore.Open(pg.DB())` — dùng chung connection Postgres, không phải SQLite riêng). `.env` Jetson trỏ `POSTGRES_URL` vào port sleeppad-postgres expose ra host (5433).

→ Không cần sửa `cloud/sleeppad/app/ai/*` (Python, dead code, để nguyên không đụng). Chỉ cần **1 endpoint Go mới trong presence-ac**, tái dùng đúng pattern của `GetTimeline`.

## Mục tiêu (Definition of Done)
- [ ] 1 API Go mới (`GET /api/sessions/morning-report`) trả "báo cáo buổi sáng" cho 1 device_id + khoảng thời gian: tổng thời gian on-bed, số lần off-bed, HR/RR trung bình, số snore event (đo cả phòng).
- [ ] KHÔNG tính AHI/apnea — response có field `"disclaimer"` nói rõ đây là tóm tắt, không phải chẩn đoán y tế.
- [ ] Test qua 1 đêm thật, số liệu khớp cảm nhận thực tế (sanity check bằng tay).

## Ngoài phạm vi (Out of scope)
- AHI, apnea detection, min_data-based features.
- Piezo pad riêng (status 0/1/2/4 của sec_data đã đủ phân biệt on-bed/off-bed/movement cho v0).
- LD2510B multi-person, SpO2.
- Sửa `cloud/sleeppad/app/ai/*` (Python) — để nguyên, không dùng trong v0 này.
- UI đẹp — trả JSON là đủ, Flutter hiển thị để sau.

## Kiến trúc
```
presence-ac (Go) — 1 service, 1 Postgres (sleeptech, dùng chung với sleeppad)
  GET /api/sessions/morning-report?device_id=&from=&to=   (endpoint MỚI)
    → PGStore.MorningReport(deviceID, from, to) (hàm MỚI trong pgstore.go)
        - query sec_data theo range, tính bằng Go loop: on-bed time (IsOnBed(hr,rr)), off-bed transitions,
          AVG(heart_rate) FILTER hr>0, AVG(resp_rate) FILTER rr>0
    → snore.Store.CountBetween(from, to) (hàm MỚI, room_snore_events KHÔNG có cột device_id — đo cả phòng)
```
Không dùng bảng `sleep_sessions`/`ListSessions` (ghi bởi 1 service Python khác chưa đọc trong phiên này) để tránh phụ thuộc vào ngữ nghĩa chưa xác nhận.

## Phases
1. `phase-01-morning-report-endpoint.md` — thêm hàm query + handler + route trong presence-ac (Go).
2. `phase-02-test-qua-dem-that.md` — chạy thật 1 đêm, đối chiếu số liệu.

## Rủi ro
- `IsOnBed(hr, rr)` (pgstore.go:141) là rule đang dùng cho `bed_state` ở `GetTimeline` — phải đọc đúng logic hiện tại trước khi viết aggregate mới, không suy đoán.
- Timezone: mọi nơi trong presence-ac dùng UTC (`time.Now().UTC()`) — endpoint mới nhận `from/to` cũng phải là UTC, ghi rõ trong response hoặc doc để tránh nhầm giờ khi test qua đêm (đã từng nhầm 1 lần trong session: hỏi "05:21:28 là mấy giờ" tưởng là giờ local).

## Validation Log

### Câu hỏi & quyết định (2026-08-26)
1. **Gap dữ liệu khi tính off-bed transitions**: chấp nhận sai số nhỏ cho v0, KHÔNG thêm logic phát hiện gap (YAGNI — sửa sau nếu test thật cho thấy vấn đề lớn).
2. **Auth cho endpoint mới**: không auth, giống các endpoint `/sessions*` hiện có (nội bộ Jetson, không expose internet).
3. **Response shape cho radar_sessions**: chỉ đếm số phiên + tổng duration_s, KHÔNG lặp lại danh sách chi tiết từng phiên (đã có sẵn ở `/sessions/{id}/timeline`, DRY).

### Verification Results
- Tier: Standard (2 phase)
- Claims checked: ~12 (pgstore.go functions, snore/store.go, router.go routes, main.go wiring, sleeppad docker-compose port mapping)
- Verified: 12 | Failed: 0 | Unverified: 0
- Phát hiện quan trọng khi verify: kiến trúc ban đầu (2 service tách biệt, cần HTTP bridge) SAI — presence-ac và sleeppad dùng chung 1 Postgres (`sleeptech`). Đã viết lại toàn bộ plan (bỏ Phase Python/bridge, còn 2 phase thay vì 3) trước khi hỏi user.

### Whole-Plan Consistency Sweep
- Đã đọc lại `plan.md` + cả 2 phase file sau khi sửa kiến trúc — không còn nhắc tới `sleeppad/app/ai/*`, `/internal/session-summary`, hay device_id mapping (các khái niệm đã bị loại bỏ). Endpoint, tham số (`from`/`to` thay vì `date`), số phase (2) nhất quán giữa plan.md và 2 phase file.
- Không còn mâu thuẫn chưa giải quyết.
