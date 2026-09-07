---
phase: 2
title: "Go — độ bền ghi SQLite ở 10Hz"
status: completed
priority: P1
dependencies: [1]
---

# Phase 02: Go — độ bền ghi SQLite

## Overview
Bỏ nút thắt fsync trong đường ghi mẫu: bật WAL, hạ `synchronous` xuống `NORMAL`, và giãn câu cắt trần từ mỗi-mẫu xuống định kỳ.

## Requirements

**Chức năng**
- `Open` trả về DB ở chế độ WAL, `synchronous=NORMAL`, có `busy_timeout`.
- `AppendSample` không còn chạy `DELETE` cắt trần sau mỗi insert.
- Trần `maxSamples` **vẫn** được giữ — không bỏ, chỉ giãn.

**Phi chức năng**
- `Open` giữ nguyên chữ ký `Open(path string) (*Store, error)`.
- Test không được chèn 11 triệu dòng.

## Architecture

Hiện tại (`store.go:191`), mỗi mẫu tốn **hai** transaction có fsync:

```
INSERT  → txn 1 (fsync)
DELETE ... WHERE id <= (SELECT MAX(id)) - 11000000  → txn 2 (fsync)
```

Ở 10Hz là 20 txn/giây, ~576.000 txn qua 8 tiếng. Câu `DELETE` gần như luôn xoá 0 dòng — nó chỉ có tác dụng khi DB đã vượt 11 triệu mẫu, tức sau ~30 đêm.

Sau khi sửa:

```
INSERT → txn 1 (WAL, synchronous=NORMAL — không fsync mỗi commit)
mỗi trimInterval mẫu: DELETE cắt trần → txn 2
```

DSN pragma (modernc.org/sqlite nhận `_pragma=` trên query string):

```go
dsn := path + "?_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)&_pragma=busy_timeout(5000)"
```

`synchronous=NORMAL` + WAL: mất tối đa các transaction chưa checkpoint khi **máy mất điện đột ngột**; process crash không mất gì. Đánh đổi chấp nhận được — đây là dữ liệu đo xu hướng, và mất điện giữa đêm thì đêm đo hỏng dù cấu hình nào.

Ngưỡng thành field để test hạ được:

```go
type Store struct {
    db           *sql.DB
    mu           sync.Mutex
    maxSamples   int64 // mặc định 11_000_000
    trimInterval int64 // mặc định 10_000
    sinceTrim    int64
}
```

## Related Code Files
- Modify: `cloud/presence-ac/internal/store/store.go` — DSN, struct field, `AppendSample`
- Modify: `cloud/presence-ac/internal/store/store_test.go` — test mới

## Implementation Steps

### 1. Test trước (RED)
- `TestOpenEnablesWAL` — `SELECT journal_mode FROM pragma_journal_mode` trả `wal`.
- `TestOpenSetsSynchronousNormal` — `PRAGMA synchronous` trả `1`.
- `TestAppendSampleEnforcesCapAfterTrimInterval` — đặt `maxSamples=50`, `trimInterval=10`, chèn 200 mẫu, kiểm số dòng không vượt `maxSamples + trimInterval`. Test này giữ cho việc giãn không biến thành bỏ.
- `TestAppendSampleDoesNotTrimEveryInsert` — đặt `trimInterval=100`, `maxSamples=1`, chèn 10 mẫu, kiểm vẫn còn đủ 10 dòng (chưa tới kỳ cắt) — chứng minh câu DELETE thật sự đã giãn.

Chạy `go test ./internal/store/ -count=1` → **đỏ**.

### 2. Implement (GREEN)
1. `Open`: dựng DSN có 3 pragma. Giữ `db.SetMaxOpenConns(1)`.
2. Sau khi mở, xác nhận WAL bật thật (query `pragma_journal_mode`); không bật được thì **trả lỗi kèm đường dẫn** — im lặng chạy tiếp ở chế độ chậm là kiểu hỏng khó tìm nhất.
3. `Store`: thêm `maxSamples`, `trimInterval`, `sinceTrim`; `Open` đặt mặc định.
4. `AppendSample`: bỏ câu DELETE khỏi đường nóng, tăng `sinceTrim`, tới ngưỡng thì chạy DELETE rồi reset.
5. Test đặt ngưỡng qua hàm không export trong cùng package (`store_test.go` đã ở `package store`).

### 3. Xanh lại
`go vet ./... && go test ./... -count=1`

### 4. Đo thật (không phải test)
Chèn 36.000 mẫu (1 giờ ở 10Hz), đo thời gian trước/sau. Ghi số vào `reports/`. Nếu không nhanh hơn rõ rệt thì giả định về fsync là sai và phải nói ra, không lặng lẽ giữ thay đổi.

## Success Criteria
- [ ] `PRAGMA journal_mode` = `wal`, `PRAGMA synchronous` = `1`
- [ ] Trần `maxSamples` vẫn được giữ sau khi giãn
- [ ] Chứng minh được câu DELETE không còn chạy mỗi insert
- [ ] `go test ./... -count=1` xanh toàn bộ
- [ ] Có số đo trước/sau cho 36.000 mẫu

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| WAL không bật được trên filesystem của volume | `Open` kiểm và trả lỗi rõ ràng thay vì chạy tiếp im lặng |
| WAL sinh file `-wal`/`-shm` cạnh DB | Volume `home-data` là thư mục riêng; ghi rõ trong runbook để không ai copy mỗi file `.db` |
| `synchronous=NORMAL` mất mẫu khi cúp điện | Nêu trong runbook; mất điện giữa đêm hỏng đêm đo dù cấu hình nào |
| Giãn cắt trần làm DB vượt trần tạm thời | Vượt tối đa `trimInterval` = 10.000 dòng, không đáng kể so với 11 triệu |
