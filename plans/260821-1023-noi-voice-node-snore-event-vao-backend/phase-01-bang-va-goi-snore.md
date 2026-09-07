---
phase: 1
title: "Bảng room_snore_events và gói internal/snore"
status: completed
priority: P1
dependencies: []
---

# Phase 01: Bảng + gói `internal/snore`

## Overview

Gói Go mới sở hữu bảng `room_snore_events`: tự tạo lược đồ lúc khởi động, một kiểu sự kiện, một hàm
ghi. Chưa nối MQTT — pha 02 làm việc đó.

## Requirements

**Chức năng**

- `Open(db *sql.DB) (*Store, error)` — nhận pool sẵn có, chạy `CREATE TABLE IF NOT EXISTS`.
- `Append(ctx, Event) error` — chèn một sự kiện.
- Kiểu `Event{T time.Time, DeviceMS *int64, Confidence float64, DurationMS int, Source string}`.

**Phi chức năng**

- **Không** thêm hàm ghi vào `sessions.PGStore` — gói đó vừa được dọn thành chỉ đọc ngày 21/08.
  Dùng lại pool qua `PGStore.DB()`.
- Không thêm dependency: `database/sql` + driver `pgx/v5/stdlib` đã có.
- Ghi lỗi không được panic, không được chặn lâu.

## Architecture

### Vì sao gói riêng chứ không nhét vào `sessions`

Ngày 21/08 đã xoá `LoadSamples`/`Summarize`/`Upsert`/`RebuildDevice`/`ActiveDeviceIDs` khỏi
`sessions/pgstore.go` để FastAPI thành nơi ghi phiên duy nhất. Gói đó hiện chỉ còn đường đọc. Thêm
một hàm ghi vào đấy là đục lại ranh giới vừa dọn, và sự kiện ngáy cũng không phải "phiên ngủ".

`PGStore.DB()` đã phơi `*sql.DB` sẵn — dùng lại pool, không mở kết nối thứ hai.

### Vì sao Go tự sở hữu DDL

`internal/store/store.go` đã tự tạo và tự migrate lược đồ SQLite của nó (`CREATE TABLE IF NOT EXISTS`
+ dò `table_info` trước khi `ALTER`). Làm y hệt cho bảng Postgres này giữ **một nơi duy nhất** cho
lược đồ và đặt nó cạnh bên ghi.

Phương án đặt DDL ở `cloud/sleeppad/postgres/` bị bác: file ở đó chỉ chạy khi khởi tạo database mới,
mà database hiện tại đã tồn tại — sẽ phải chạy tay, đúng cái bẫy `samples.sql` đã mắc ngày 20/08.

### Lược đồ

```sql
CREATE TABLE IF NOT EXISTS room_snore_events (
  id          BIGSERIAL PRIMARY KEY,
  t           TIMESTAMPTZ NOT NULL,
  device_ms   BIGINT,
  confidence  REAL        NOT NULL,
  duration_ms INTEGER     NOT NULL,
  source      TEXT        NOT NULL DEFAULT 'voice-node'
);
CREATE INDEX IF NOT EXISTS idx_room_snore_t ON room_snore_events (t DESC);
```

**Không có `device_id`.** Mic nghe căn phòng, không nghe một người. Thêm cột đó là mời người sau
join nhầm sự kiện phòng với một người cụ thể.

`device_ms` nullable: payload có thể thiếu trường, và giá trị tụt đọc là board reset.

## Related Code Files

- Create: `cloud/presence-ac/internal/snore/store.go`
- Create: `cloud/presence-ac/internal/snore/store_test.go`
- Reference (không sửa): `cloud/presence-ac/internal/store/store.go` — mẫu tự tạo lược đồ
- Reference (không sửa): `cloud/presence-ac/internal/sessions/pgstore.go:75` — `DB()` phơi pool

## Implementation Steps

1. Tạo `internal/snore/store.go` với `Event`, `Store`, `Open()`, `Append()`.
2. `Open()` chạy DDL trên. Lỗi DDL trả về cho caller quyết định — pha 02 sẽ log rồi chạy tiếp
   (quyết định 8: DB hỏng không chặn khởi động).
3. `Append()` dùng `ExecContext` với timeout ngắn (đề xuất 3 giây) để không treo callback MQTT.
4. Comment đầu gói ghi rõ: bảng này đo **căn phòng**, không đo người; nguồn là mic nên không phân
   biệt được ai ngáy; và vì sao không nằm trong `sessions`.
5. Test: dùng cùng cách `internal/store/store_test.go` đang làm nếu có Postgres test; nếu không, test
   phần thuần (validate payload → `Event`) và để phần SQL cho pha 03 nghiệm thu trên DB thật.

## Success Criteria

- [ ] `go build ./...` sạch.
- [ ] `Open()` trên database đã có → bảng và index tồn tại, chạy lại lần hai không lỗi.
- [ ] `Append()` chèn đúng một dòng; `t` giữ nguyên giá trị truyền vào (không bị đổi múi giờ).
- [ ] `DeviceMS = nil` → cột `device_ms` là NULL, không phải 0.
- [ ] `Append()` với context đã huỷ → trả lỗi trong dưới 1 giây, không treo.
- [ ] Gói `sessions` **không** có thêm method ghi nào: `grep -n "^func (s \*PGStore)" pgstore.go`
      vẫn chỉ ra `Close`, `DB`, `ListSessions`, `GetSession`, `GetTimeline`, `GetLatestSec`.

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Ghi DB chặn callback MQTT (R4) | Timeout 3 giây ở `Append()`; pha 02 nuốt lỗi thành log |
| Lược đồ lệch giữa Go và các file DDL của sleeppad | Quyết định 4: chỉ một nơi giữ lược đồ, là gói này. Ghi comment nêu rõ quyền sở hữu |
| Ai đó thêm `device_id` vào bảng cho "tiện" | Comment đầu gói giải thích vì sao không có. Nếu cần nhiều phòng thì thêm cột `room`, không phải `device_id` |
