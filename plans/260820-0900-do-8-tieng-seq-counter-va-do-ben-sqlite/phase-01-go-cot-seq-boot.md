---
phase: 1
title: "Go — cột seq/boot xuyên suốt từ MQTT tới SQLite"
status: completed
priority: P1
dependencies: []
---

# Phase 01: Go — cột `seq`/`boot`

## Overview
Thêm hai trường `seq` và `boot` vào contract `home/room/sample`, đi hết đường từ parse JSON tới cột SQLite, giữ tương thích ngược với firmware chưa cập nhật.

## Requirements

**Chức năng**
- `events.Sample` nhận `seq`, `boot` từ JSON; vắng mặt ⇒ `nil`, không phải `0`.
- `store.Sample` mang hai trường tương ứng; `AppendSample` ghi `NULL` khi `nil`.
- `SamplesBetween` đọc lại đúng, kể cả dòng cũ có `NULL`.
- Migration thêm cột vào DB **đã tồn tại** — `CREATE TABLE IF NOT EXISTS` không làm việc này.

**Phi chức năng**
- Không đổi chữ ký `Open`, `AppendSample`, `SamplesBetween`.
- Không phá test hiện có trong `store_test.go`.

## Architecture

```
MQTT JSON ──► events.Sample{Seq *uint32, Boot *uint32}
                     │ (main.go recordSample)
                     ▼
              store.Sample{Seq *int64, Boot *int64}
                     │
                     ▼
        samples(seq INTEGER NULL, boot INTEGER NULL)
```

Dùng con trỏ chứ không dùng giá trị: `NULL` (firmware cũ) phải phân biệt được với `0` (mẫu đầu tiên sau boot). `sql.NullInt64` cũng được nhưng con trỏ khớp `encoding/json` sẵn — vắng trường ⇒ `nil`, không cần cờ phụ.

Migration idempotent:
```go
// PRAGMA table_info trả về danh sách cột hiện có; chỉ ALTER cột nào thiếu.
// Không dùng "ALTER ... rồi nuốt lỗi" — nuốt lỗi sẽ giấu cả lỗi thật.
rows, _ := db.Query(`PRAGMA table_info(samples)`)
// ... gom tên cột vào set, ALTER TABLE samples ADD COLUMN seq INTEGER nếu thiếu
```

## Related Code Files
- Modify: `cloud/presence-ac/internal/events/events.go` — 2 trường vào `Sample`
- Modify: `cloud/presence-ac/internal/store/store.go` — 2 trường, migration, INSERT, SELECT
- Modify: `cloud/presence-ac/cmd/server/main.go` — `recordSample` chuyển tiếp 2 trường
- Modify: `cloud/presence-ac/internal/store/store_test.go` — test mới
- Check: `cloud/presence-ac/cmd/seed-csv/main.go` — CSV không có 2 cột này, để `nil`
  <!-- Updated: Validation Session 1 - không thêm cờ --fake-seq; truy vấn phân tích nghiệm thu bằng dữ liệu bench thật ở Phase 06 -->

## Implementation Steps

### 1. Test trước (RED)

Trong `store_test.go`:
- `TestAppendSampleRoundTripsSeqAndBoot` — ghi mẫu có `Seq=7, Boot=2`, đọc lại bằng `SamplesBetween`, so khớp.
- `TestAppendSampleKeepsNilSeqDistinctFromZero` — ghi hai mẫu: một `Seq=nil`, một `Seq=0`. Đọc lại phải phân biệt được. **Đây là test đắt giá nhất của phase**; nếu dùng kiểu giá trị thay vì con trỏ thì test này đỏ.
- `TestMigrationAddsColumnsToExistingDb` — tạo DB bằng schema cũ (không có 2 cột), gọi `Open` lần nữa, `AppendSample` có `Seq` phải thành công.
- `TestOpenTwiceIsIdempotent` — gọi `Open` hai lần trên cùng file, không lỗi "duplicate column name".

Trong package `events`, test unmarshal:
- payload đủ trường ⇒ `Seq` non-nil, đúng giá trị.
- payload firmware cũ (không có `seq`/`boot`) ⇒ cả hai `nil`, các trường còn lại không đổi.

Chạy: `cd cloud/presence-ac && go test ./internal/store/ ./internal/events/ -count=1` → phải **đỏ**.

### 2. Implement (GREEN)
1. `events.Sample`: thêm `Seq *uint32 \`json:"seq"\`` và `Boot *uint32 \`json:"boot"\`` kèm comment giải thích vì sao là con trỏ.
2. `store.Sample`: thêm `Seq *int64`, `Boot *int64`.
3. `store.Open`: sau khối `CREATE TABLE IF NOT EXISTS`, chạy migration đọc `PRAGMA table_info(samples)` rồi `ALTER TABLE` cột nào thiếu. Cột mới cũng có trong `CREATE TABLE` để DB mới không cần migration.
4. `AppendSample`: 2 placeholder mới.
5. `SamplesBetween`: `Scan` vào con trỏ.
6. `main.go recordSample`: chuyển tiếp (chuyển `*uint32` → `*int64`).

### 3. Xanh lại
`go vet ./... && go test ./... -count=1` — toàn bộ package, không chỉ hai package đã đổi.

## Success Criteria
- [ ] 6 test mới xanh
- [ ] `go test ./... -count=1` xanh toàn bộ 6 package
- [ ] `NULL` phân biệt được với `0` khi đọc lại
- [ ] `Open` gọi hai lần trên DB cũ không lỗi
- [ ] `cmd/seed-csv` build và chạy được không sửa (hoặc sửa tối thiểu để compile), ghi `NULL` cho `seq`/`boot` — **không** thêm cờ giả lập

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Con trỏ trong struct làm call site panic khi deref | Chỉ deref sau khi kiểm `nil`; test bao cả nhánh `nil` |
| Migration chạy trên DB đang có 11 triệu dòng | `ALTER TABLE ADD COLUMN` của SQLite là thao tác metadata, không rewrite bảng |
| `store.Sample` và `events.Sample` trùng lặp (đã có sẵn) | Không gộp đợt này — comment `store.go:170` nói rõ tách là cố ý để store không phụ thuộc `events`. Không đảo quyết định cũ |
