---
phase: 1
title: "Branch setup + test harness"
status: pending
priority: P1
dependencies: []
---

# Phase 1: Branch setup + test harness

## Overview

Đưa `feat/ws-user-combined` về local và dựng test infra backend từ đầu. Repo chưa có
bất kỳ test backend nào — đây là phần nặng nhất của cả plan.

## Requirements

**Functional**
- Branch checkout về local, plan files commit trên branch (không phải `dev/khanhhung`)
- pytest chạy được, fixture cấp Postgres(timescale) + Redis sạch cho mỗi test session
- Fixture dựng app FastAPI tối thiểu, không khởi động MQTT/alert/watch worker

**Non-functional**
- Test không đụng vào stack dev đang chạy (port riêng, container riêng)
- Teardown xoá sạch container, không để rác

## Architecture

### Vì sao không dùng lifespan thật

`backend/app/main.py` lifespan khởi động `run_subscriber` (mosquitto), `run_alert_engine`,
`run_watch_data_worker`. Test dùng full app sẽ treo/fail khi không có broker.

Fixture dựng app tối thiểu:

```python
app = FastAPI()
app.include_router(data_router)
app.state.db_pool = pool     # gán thủ công
app.state.redis = rds
```

### pythonpath

Backend import bằng tên module trần (`from data.router import ...`,
`from config import get_settings`, `from auth.service import decode_access_token`).
Không có package `app.`. pytest phải set:

```ini
[pytest]
pythonpath = backend/app
asyncio_mode = auto
```

### Settings

`Settings` bắt buộc `database_url`, `redis_url`, `jwt_secret` (không default) và
`get_settings()` có cache → env phải set **trước khi import module backend nào**.
Đặt trong `conftest.py` ở đầu file hoặc qua `pytest.ini` env, và clear cache nếu cần.

### Container

Postgres **phải** là `timescale/timescaledb:latest-pg16` — `smart_watch_data.sql` gọi
`create_hypertable()`, image postgres thường sẽ fail.

Thứ tự apply schema: `postgres/init.sql` → `postgres/smart_watch_data.sql`.

Hai lựa chọn dựng container, chọn 1:
- **(a) `testcontainers-python`** — tự quản lý lifecycle, port ngẫu nhiên, không đụng
  stack dev. Thêm 1 dep. **Khuyến nghị.**
- (b) `docker compose` riêng với project name + port khác. Không thêm dep nhưng phải tự
  viết wait-for-ready và cleanup.

## Related Code Files

**Create**
- `backend/tests/__init__.py`
- `backend/tests/conftest.py` — fixtures: container pg + redis, pool, redis client, app, client, seeded user + JWT
- `backend/pytest.ini` (hoặc thêm section vào `pyproject.toml` nếu tạo mới)
- `backend/requirements-dev.txt` — `pytest`, `pytest-asyncio`, `testcontainers[postgres,redis]` (nếu chọn (a))

**Modify**
- `plans/260603-0958-user-keyed-realtime-ws/plan.md` — Phase 5 pending → in-progress

**Read only**
- `backend/app/main.py`, `backend/app/config.py`, `backend/app/database.py`
- `backend/postgres/init.sql`, `backend/postgres/smart_watch_data.sql`

## Implementation Steps

1. `git fetch origin && git checkout -b feat/ws-user-combined origin/feat/ws-user-combined`
   Plan files + brainstorm report hiện untracked → tự động theo sang branch mới.
2. Commit plan + report trên branch này. **Không commit lên `dev/khanhhung`/`main`.**
3. Tạo `backend/requirements-dev.txt`. Cài vào venv riêng, không đụng
   `.claude/skills/.venv`.
4. Viết `pytest.ini` với `pythonpath = backend/app` + `asyncio_mode = auto`.
5. Viết `conftest.py`:
   - session fixture: khởi động container pg + redis, export `DATABASE_URL`/`REDIS_URL`/`JWT_SECRET`
   - session fixture: apply `init.sql` rồi `smart_watch_data.sql`
   - function fixture: truncate bảng giữa các test (giữ schema)
   - fixture `test_app`: FastAPI tối thiểu + `data_router` + state
   - fixture `seeded_user`: tạo user + device (`sleep_pad` và/hoặc `smart_watch`), trả JWT hợp lệ ký bằng `jwt_secret` của test
6. Viết 1 smoke test xác nhận harness sống (ví dụ query `SELECT 1` + connect WS bị từ chối khi thiếu token) rồi chạy `pytest backend/tests -v`.

## Success Criteria

- [ ] `git branch --show-current` = `feat/ws-user-combined`
- [ ] `pytest backend/tests` chạy được, smoke test pass
- [ ] Container tạo và xoá sạch sau khi chạy (`docker ps -a` không còn rác)
- [ ] Stack dev đang chạy (nếu có) không bị ảnh hưởng
- [ ] Plan + brainstorm report đã commit trên branch

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| `get_settings()` cache đọc env trước khi test set | Set env ở đầu `conftest.py` trước mọi import backend; hoặc `get_settings.cache_clear()` |
| Port trùng stack dev đang chạy | Dùng testcontainers (port ngẫu nhiên) |
| `create_hypertable` fail | Bắt buộc image timescale, không dùng `postgres:16` |
| Pull image timescale lần đầu chậm | Pull trước khi chạy test lần đầu |
| Import bare-module xung đột với package khác cùng tên (`config`, `data`) | `pythonpath` trỏ đúng `backend/app`; chạy pytest từ repo root |
