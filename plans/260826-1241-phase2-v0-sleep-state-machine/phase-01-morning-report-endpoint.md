---
phase: 1
title: "Morning report endpoint (presence-ac, Go, 1 service)"
status: completed
priority: P1
dependencies: []
---

# Phase 1: Morning report endpoint

## Overview
Thêm 1 hàm query + 1 handler + 1 route trong `presence-ac` (Go) trả về tóm tắt giấc ngủ cho 1 device_id trong 1 khoảng thời gian, dùng lại 3 nguồn dữ liệu đã có sẵn trong cùng Postgres: `sec_data`, `sessions`, `room_snore_events`. Không sửa gì bên `cloud/sleeppad/`.

## Requirements
- Functional: `GET /api/sessions/morning-report?device_id=<id>&from=<RFC3339 UTC>&to=<RFC3339 UTC>` trả về:
  - `on_bed_seconds`: tổng thời gian on-bed (dùng `IsOnBed(hr,rr)` — pgstore.go:141 — trên từng dòng sec_data, KHÔNG dùng `status`).
  - `off_bed_transitions`: số lần chuyển từ on-bed → off-bed.
  - `avg_heart_rate`, `avg_resp_rate`: `AVG(...) FILTER (WHERE ... > 0)` giống cách `GetTimeline` đang làm (pgstore.go dòng ~196).
  - `snore_count`: `COUNT(*) FROM room_snore_events WHERE t BETWEEN $1 AND $2` — KHÔNG lọc theo device_id (bảng này cố tình không có cột device_id, xem comment `snore/store.go:1-5`: đo cả phòng, không phải 1 pad).
  - `disclaimer`: chuỗi cố định `"Tóm tắt giấc ngủ, không phải chẩn đoán y tế (không có AHI/apnea)."`
- Non-functional: `from`/`to` bắt buộc là UTC RFC3339 — 400 nếu thiếu hoặc không parse được.

**Đã bỏ khỏi scope so với bản plan trước:** không dùng `ListSessions`/bảng `sleep_sessions` — bảng đó được ghi bởi 1 service Python khác (`cloud/sleeppad/app/sessions/`, xem comment `main.go:99-102`) chưa đọc trong phiên này, ngữ nghĩa thật của nó (radar-only hay gộp cả min_data) chưa xác nhận. Để tránh phụ thuộc vào code chưa đọc, v0 tự tính on-bed time thẳng từ `sec_data` (đã verify kỹ) thay vì tin vào bảng đã build sẵn.

## Architecture
- Hàm mới `(s *PGStore) MorningReport(ctx, deviceID string, from, to time.Time) (*MorningReport, error)` trong `pgstore.go`, đặt sau `GetTimeline`. Query 1 lần: `SELECT time, heart_rate, resp_rate FROM sec_data WHERE device_id=$1 AND time>=$2 AND time<$3 ORDER BY time`, rồi tính on_bed_seconds/off_bed_transitions bằng vòng lặp Go (so hàng hiện tại với hàng trước qua `IsOnBed`, cộng dồn `Δt` khi on-bed) — KHÔNG dùng LAG() SQL (đơn giản hơn, tránh viết SQL window function không cần thiết, dữ liệu 1 đêm chỉ vài chục nghìn dòng nên loop Go đủ nhanh, YAGNI).
- Snore count: thêm `func (s *Store) CountBetween(ctx context.Context, from, to time.Time) (int, error)` trong `snore/store.go` — KHÔNG có tham số deviceID (bảng không có cột này).
- `main.go` hiện chỉ giữ biến `ss` (snore.Store) cục bộ trong scope `if pg != nil {...}` để tạo closure `recordSnore` — biến `ss` KHÔNG thoát ra ngoài block đó. Cần hoist `ss` ra biến ở scope ngoài (giống cách `pg`/`sS` đã làm) để truyền vào router.
- Route mới trong `router.go`: `r.Get("/sessions/morning-report", a.getMorningReport)` — đặt cạnh dòng 93-96 (không dùng `/{id}` vì input là device_id+time range, không phải 1 session id có sẵn).
- `API` struct (`router.go:41-47`) cần thêm field mới (ví dụ `snoreReader SnoreCounter`, interface 1 method `CountBetween`) — truyền qua `NewRouterFull`, cập nhật cả 2 wrapper `NewRouter`/`NewRouterSamples` (truyền `nil` để không phá chữ ký gọi cũ ở nơi khác nếu có).

## Related Code Files
- Modify: `cloud/presence-ac/internal/sessions/pgstore.go` (thêm `MorningReport` + struct `MorningReport` kết quả)
- Modify: `cloud/presence-ac/internal/snore/store.go` (thêm `CountBetween`)
- Modify: `cloud/presence-ac/internal/api/sessions_handlers.go` (thêm handler `getMorningReport`, interface `SnoreCounter`)
- Modify: `cloud/presence-ac/internal/api/router.go` (thêm field `snoreReader`, route, cập nhật chữ ký `NewRouterFull`/wrapper)
- Modify: `cloud/presence-ac/cmd/server/main.go` (hoist biến `ss`, truyền vào `NewRouterFull`)

## Implementation Steps
1. Grep tất cả nơi gọi `NewRouterFull`/`NewRouterSamples`/`NewRouter` (kể cả test) trước khi đổi chữ ký, để không vỡ compile chỗ khác.
2. Viết `MorningReport` trong pgstore.go (query sec_data 1 lần, tính bằng Go loop như mô tả ở Architecture).
3. Viết `CountBetween` trong snore/store.go.
4. Sửa `main.go`: hoist `ss`, truyền vào `NewRouterFull`.
5. Sửa `router.go`: thêm field, interface, route, cập nhật wrapper functions.
6. Viết handler `getMorningReport` trong sessions_handlers.go (parse device_id/from/to, gọi 2 nguồn, gộp JSON).
7. Build: `cd cloud/presence-ac && go build ./...` — sửa lỗi biên dịch trước khi deploy.
8. Deploy lên Jetson (`docker compose up -d --build backend`), test bằng `curl` với khoảng thời gian có dữ liệu thật đã biết (đêm 2026-08-25, 27→38 snore events đã verify trước đó).

## Success Criteria
- [x] `go build ./...` không lỗi, các call site cũ của `NewRouterFull`/wrapper vẫn compile (đã cập nhật `sessions_empty_test.go`, `go test ./...` pass).
- [x] `curl http://192.168.1.125:8080/api/sessions/morning-report?device_id=CNU190440C&from=2026-08-25T00:00:00Z&to=2026-08-26T00:00:00Z` trả JSON đúng field: `{"avg_heart_rate":78.1,"avg_resp_rate":14.96,"off_bed_transitions":12,"on_bed_seconds":725,"snore_count":27,"disclaimer":"..."}`.
- [x] `snore_count=27` khớp chính xác `psql SELECT COUNT(*) FROM room_snore_events WHERE t BETWEEN ...` cùng khoảng.
- [x] Response có `disclaimer`, không có field `ahi`/`apnea` nào.

## Risk Assessment
- Risk: đổi chữ ký `NewRouterFull` có thể ảnh hưởng nơi gọi khác chưa biết — Step 1 (grep trước khi sửa) là bắt buộc, không suy đoán.
- Risk: nếu có gap dữ liệu dài trong sec_data (mất kết nối), vòng loop Go coi khoảng cách lớn giữa 2 dòng là "vẫn ở trạng thái trước đó" cho tới dòng kế — chấp nhận sai số cho v0 (theo quyết định Validation Log của plan.md).
