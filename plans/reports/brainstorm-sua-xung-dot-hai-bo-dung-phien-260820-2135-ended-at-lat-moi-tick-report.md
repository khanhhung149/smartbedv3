---
type: brainstorm
date: 2026-08-20 21:35
slug: sua-xung-dot-hai-bo-dung-phien-ended-at-lat-moi-tick
status: mức 1 và mức 2 đã áp dụng (21/08); mức 3 đã chốt làm sau demo
branch: master
tiếp nối: brainstorm-hop-nhat-backend-260820-2127-fastapi-toan-phan-vs-hai-service-ranh-gioi-report.md
---

# Sửa xung đột hai bộ dựng phiên — có sửa được không, sửa tới đâu

## Câu hỏi

Xung đột `ended_at` lật qua lật lại giữa builder Go và builder FastAPI — có sửa được không?

## Phát hiện chính

`rules.go` và `rules.py` **giống nhau dòng-đối-dòng**: cùng biến trạng thái (`started_at`,
`pending_start`, `absent_since`), cùng thứ tự xử lý gap → occupancy → cap, cùng cách đóng phiên cuối.
Go là bản port trung thực.

**Xung đột không nằm ở luật, nằm ở chỗ gọi.**

| | Python `service.py:94` | Go `main.go:223` |
|---|---|---|
| `now` | truyền `now=now` | **thiếu** |
| Hệ quả | đóng phiên treo, ghi `ended_at` | để ngỏ, ghi `ended_at = NULL` |
| Tham số luật | đọc từ Settings (env override được) | **hardcode 30/1800/1440** |
| Cửa sổ quét lại | `LOOKBACK = 1440+60 phút` (25 giờ) | **30 ngày** |

Ba khác biệt, ba mức nghiêm trọng khác nhau:

1. **`now`** — gây dao động quan sát được: mỗi 60 giây, bên nào tick sau thì `ended_at` của phiên đang
   mở theo bên đó. App lúc thấy giờ kết thúc lúc không.
2. **Config hardcode bên Go** — lệch âm thầm. Chỉnh `SESSION_CLOSE_SECONDS` bên Python là hai bên lại
   khác luật, và lần này không có dấu hiệu cảnh báo nào.
3. **Cửa sổ 30 ngày** — mỗi phút Go kéo ~2,6 triệu dòng `sec_data` mỗi thiết bị về dựng lại. DB mới thì
   chưa thấy; chạy vài tuần là thấy.

## Ba mức sửa

### Mức 1 — thêm `Now` vào `BuildOptions` (1 dòng)

Hai bên cho cùng kết quả → upsert đè nhau vô hại. 2 phút, không đổi kiến trúc.

Chỉ vá triệu chứng số 1. Số 2 và số 3 còn nguyên.

### Mức 2 — gỡ writer bên Go, giữ đường đọc

Xóa `rules.go` + `rules_test.go`, xóa `LoadSamples`/`Summarize`/`Upsert`/`RebuildDevice`/`ActiveDeviceIDs`
trong `pgstore.go`, xóa goroutine tick trong `main.go`. Giữ nguyên `/api/sessions*` (đường đọc) để app
Flutter không phải đổi gì.

~30 phút. Hết cả ba vấn đề cùng lúc. FastAPI thành nguồn duy nhất ghi `sleep_sessions` — đúng quyết
định "dùng tech của backend gốc".

### Mức 3 — hợp nhất toàn bộ về FastAPI

~2–3 tuần. Không giải quyết thêm gì cho riêng chuyện trùng lặp này (xem báo cáo 21:27).

## Loại bỏ: Postgres advisory lock

Cho hai bên tranh quyền ghi bằng advisory lock chỉ ngăn ghi **đồng thời**, không ngăn ghi **khác nhau**.
Giải sai bài, và thêm một cơ chế phải bảo trì.

## Quyết định

**Mức 1 đêm nay, mức 2 ngày mai.** Lý do: cần chạy thử một đêm để xem hai stack sống chung thế nào; một
dòng thì không tiếc khi mức 2 xóa nó đi.

## Đã làm trong phiên này

- `cmd/server/main.go`: thêm `Now: &now` vào `BuildOptions`, kèm chú thích nêu rõ vì sao nó bắt buộc
  chứ không phải tùy chọn.
- `go build ./...` sạch; `go test ./... -count=1` xanh 8/8 package.
- Ghi chú: `internal/voice/command_test.go` bị `gofmt -l` liệt kê — có sẵn từ trước, không liên quan
  thay đổi này.

## Việc còn lại

- [x] Mức 2 (21/08): xoá `rules.go` + `rules_test.go`, xoá 156 dòng khối ghi trong `pgstore.go`
  (giữ lại `IsOnBed` vì `GetTimeline` cần cho `bed_state`), gỡ goroutine rebuild 39 dòng trong
  `main.go`. `go build`/`go vet` sạch, `go test ./... -count=1` xanh. Đã dựng lại container
  `home-backend` và xác minh `ended_at` đứng yên qua hai tick trong khi `computed_at` vẫn tiến.
- [x] Mức 3 đã chốt: chuyển toàn bộ backend sang FastAPI, làm SAU demo; lịch sử SQLite
  (event + mẫu 10 Hz) sẽ migrate sang Postgres chứ không giữ song song.

## Câu chưa trả lời

- Sau mức 2, `/api/sessions*` nên tiếp tục ở Go (proxy đọc) hay app trỏ thẳng FastAPI? Câu này quyết
  định app phải mang mấy loại credential.
- Nếu giữ Go làm proxy đọc lâu dài, có cần test contract giữa `pgstore.go` và `service.py` không? Đã lệch
  một lần (`null` vs `[]`).
