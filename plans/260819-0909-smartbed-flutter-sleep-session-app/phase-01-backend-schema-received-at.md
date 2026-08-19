---
phase: 1
title: "Backend — schema sleep_sessions + cột received_at"
status: completed
priority: P1
dependencies: []
repo: sleep_pad_AI
---

# Phase 01: Backend — schema `sleep_sessions` + cột `received_at`

## Overview
Thêm bảng `sleep_sessions` và cột `received_at` vào `sec_data`/`min_data`, ghi `received_at` lúc ingest. Không có logic nghiệp vụ nào ở pha này — chỉ đặt nền dữ liệu.

## Requirements
- Functional: DB mới có `sleep_sessions`; mọi bản ghi `sec_data`/`min_data` ghi từ pha này trở đi có `received_at`.
- Non-functional: **không rewrite bảng cũ**; dữ liệu cũ giữ `received_at IS NULL` và vẫn đọc được bình thường vì mọi query dùng cột `time`.
- Chỉ chạy trên dev/local. Không đụng prod `api.sleeptech.me`.

## Architecture

<!-- Updated: Validation Session 2 (F-04) — đo lại lúc thực thi. Tiền đề cũ sai. -->

Đồng hồ pad không tin được — điều đó đúng:

| Nơi | Thực tế |
|---|---|
| PDF tr.2 + tr.6 §2.9 | Đồng hồ pad = local-time đóng giả UTC, có drift, "nên hiệu chỉnh mỗi ngày" bằng `0x0B` |
| `firmware/src/mqtt-client.cpp:296` | `doc["ts"] = d.timestamp` — forward nguyên |
| `firmware/src/main.cpp` | Chỉ gửi `0x04` và `0x08`. **Chưa bao giờ gửi `0x0B`** |

**Nhưng backend đã trung hoà sẵn:** `app/mqtt/subscriber.py:108` ghi `datetime.now(tz=utc)` vào cột `time` và **vứt `ts` đi** — `ts` không được lưu ở bất kỳ đâu. `to_timestamptz()` ở `parser.py:58` có tồn tại nhưng **0 caller**.

→ Cột `time` **đã là** trục ingest. Mọi truy vấn của Phase 02/03 dùng `time`.
→ `received_at` vẫn tạo và vẫn ghi, nhưng **không query**: nó là dự phòng cho lúc sửa firmware `0x0B`, khi `time` có thể đổi nghĩa sang giờ thiết bị.

`sleep_sessions` là bảng thường (không hypertable) — một đêm một dòng, không phải time-series.

## Related Code Files
- Create: `sleep_pad_AI/backend/postgres/sleep_sessions.sql`
- Modify: `sleep_pad_AI/backend/app/mqtt/subscriber.py` — `_insert_sec` (dòng ~172), `_insert_min` (dòng ~183)
- Create: `sleep_pad_AI/backend/scripts/apply-schema.sh`
- Modify: `sleep_pad_AI/backend/README.md` — mục "Áp schema"

<!-- Updated: Validation Session 1 — F-02: repo KHÔNG có cơ chế áp file schema phụ. `docker-compose.yml:21` chỉ mount `init.sql`; `smart_watch_data.sql` không được mount và không có gì trong repo tham chiếu tới nó. Thay `\i` bằng script apply-schema.sh -->

## Implementation Steps

1. Tách branch: `git -C /mnt/d/sleep_pad_AI checkout -b feat/sleep-sessions dev/khanhhung`

2. Viết `backend/postgres/sleep_sessions.sql`:
```sql
ALTER TABLE sec_data ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ;
ALTER TABLE min_data ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS sleep_sessions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id           TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  started_at          TIMESTAMPTZ NOT NULL,
  ended_at            TIMESTAMPTZ,              -- NULL = phiên đang diễn ra
  duration_s          INTEGER,
  hr_avg              REAL, hr_min SMALLINT, hr_max SMALLINT,
  rr_avg              REAL,
  movement_total      INTEGER,
  snore_total         INTEGER,
  resp_disorder_total INTEGER,
  sit_up_count        INTEGER,
  wake_count          INTEGER,
  computed_at         TIMESTAMPTZ,
  UNIQUE (device_id, started_at)
);
CREATE INDEX IF NOT EXISTS idx_sessions_device_started
  ON sleep_sessions (device_id, started_at DESC);
```
   `UNIQUE (device_id, started_at)` để builder chạy lại không tạo phiên trùng.

3. Sửa `_insert_sec` / `_insert_min` trong `mqtt/subscriber.py`: thêm cột `received_at` vào INSERT, giá trị `datetime.now(timezone.utc)`. Không đổi chữ ký hàm nếu không cần.

4. Viết `backend/scripts/apply-schema.sh` — **vá luôn lỗ hổng đang có**: `smart_watch_data.sql` hiện không có cách nào được áp.
```bash
#!/usr/bin/env bash
# Áp schema theo thứ tự vào DB đang chạy. Idempotent — mọi câu đều IF NOT EXISTS.
# initdb.d chỉ chạy khi volume postgres rỗng, nên DB đã có dữ liệu phải dùng script này.
set -euo pipefail
for f in postgres/init.sql postgres/smart_watch_data.sql postgres/sleep_sessions.sql; do
  echo "-> $f"
  docker exec -i sleeppad-postgres psql -v ON_ERROR_STOP=1 \
    -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$f"
done
```
   Chạy từ `backend/`, không cần mount gì thêm (dùng `docker exec`, không phải initdb.d).

5. Áp lên DB dev:
```bash
cd /mnt/d/sleep_pad_AI/backend
docker compose -f docker-compose.yml -f docker-compose.dev.yml --env-file .env.dev up -d postgres
set -a && source .env.dev && set +a
bash scripts/apply-schema.sh
```

6. Ghi cách áp schema vào `backend/README.md` — nếu bỏ bước này thì người tiếp theo dựng DB sẽ lặp lại đúng vấn đề của `smart_watch_data.sql`.

## Success Criteria
- [ ] `\d sec_data` và `\d min_data` có cột `received_at`
- [ ] `\d sleep_sessions` khớp schema trên
- [ ] Bơm 1 message MQTT test → dòng mới có `received_at IS NOT NULL`
- [ ] Dòng cũ vẫn `received_at IS NULL` và **không** bị rewrite (kiểm bằng thời gian chạy ALTER < 1s)
- [ ] `bash scripts/apply-schema.sh` chạy **hai lần liên tiếp** đều thành công (idempotent)
- [ ] `backend/README.md` có mục hướng dẫn áp schema

<!-- Updated: Validation Session 1 — F-01: bỏ tiêu chí `python -m pytest`. Repo KHÔNG có pytest (requirements.txt không có, không có pytest.ini/pyproject/setup.cfg, không có file test_*.py nào). Bootstrap pytest chuyển sang Phase 02 -->

## Risk Assessment
- **ALTER trên hypertable:** thêm cột nullable ở Postgres 11+ chỉ sửa catalog, không rewrite. Nếu ALTER chạy lâu bất thường → dừng, điều tra, đừng để chạy tiếp.
- **Dùng `COALESCE(received_at, time)` trong query:** cấm. Đo bằng `EXPLAIN` trên DB dev — biểu thức này mất index range scan và phá chunk exclusion của Timescale (quét mọi chunk thay vì 1). Truy vấn trên `time`.
