---
phase: 2
title: "Backend — máy trạng thái dựng phiên ngủ"
status: completed
priority: P1
dependencies: [1]
repo: sleep_pad_AI
---

# Phase 02: Backend — máy trạng thái dựng phiên ngủ

## Overview
Module `sessions/` với máy trạng thái đọc `sec_data` → sinh/đóng dòng `sleep_sessions`, chạy nền trong `lifespan`. Đây là pha chứa **toàn bộ** logic nghiệp vụ của plan.

## Requirements
- Functional: từ chuỗi `sec_data` một đêm, sinh đúng số phiên với `started_at`/`ended_at` theo luật 30 giây / 30 phút.
- Functional: tóm tắt loại bỏ `hr = 0` và `rr = 0` khi tính trung bình.
- Functional: chạy lại builder trên cùng dữ liệu **không** tạo phiên trùng (idempotent).
- Non-functional: ngưỡng nằm trong config, không hardcode.
- Non-functional: logic thuần hàm, test được **không cần DB**.

## Architecture

Theo đúng khuôn `alerts/` đã chạy thật (`alerts/engine.py` + `service.py` + `models.py` + `router.py`).

```
backend/app/sessions/
  __init__.py
  models.py     # pydantic: SessionOut, SessionSummary, TimelinePoint
  rules.py      # HÀM THUẦN: máy trạng thái. Không đụng DB. Đây là chỗ test
  service.py    # truy vấn DB: đọc sec_data/min_data, ghi sleep_sessions
  builder.py    # task nền, khuôn run_alert_engine(pool, rds, stop)
  router.py     # Phase 03
```

**Máy trạng thái** (`rules.py`) — nguồn: PDF Legact tr.2 và tr.4 §2.4.1:

```python
# Ngưỡng — config, không hardcode ở call site
SESSION_OPEN_SECONDS  = 30      # tr.2: "in bed for 30 consecutive seconds"
SESSION_CLOSE_SECONDS = 1800    # tr.2: "leaves the bed for 30 minutes"
SESSION_MAX_MINUTES   = 1440    # tr.2: "maximum length of a single recording"

def is_on_bed(hr: int | None, rr: float | None) -> bool:
    """tr.4 §2.4.1: hr/rr = 0 khi rời giường HOẶC khi không tính được.
    Không có mã status nào nghĩa là 'đang nằm trên giường' — không dùng status ở đây."""
    return (hr or 0) > 0 or (rr or 0) > 0
```

Trạng thái: `IDLE` → (on_bed ≥ 30s) → `IN_SESSION` → (off_bed ≥ 30 phút **hoặc** đủ 1440 phút) → `IDLE`.
`ended_at` = thời điểm **bắt đầu** đoạn off_bed, không phải lúc đủ 30 phút.
Khoảng trống dữ liệu (gap) tính như off_bed.

**Tóm tắt** — SQL, cột `time` làm trục (xem Validation Session 2 / F-04: `time` đã là giờ ingest; `COALESCE` phá chunk exclusion):
```sql
SELECT AVG(heart_rate)::real FILTER (WHERE heart_rate > 0) AS hr_avg,
       MIN(heart_rate)       FILTER (WHERE heart_rate > 0) AS hr_min,
       MAX(heart_rate)       FILTER (WHERE heart_rate > 0) AS hr_max,
       AVG(resp_rate)::real  FILTER (WHERE resp_rate  > 0) AS rr_avg,
       SUM(movement), SUM(snore_count), SUM(resp_disorder)
FROM min_data
WHERE device_id = $1 AND time >= $2 AND time < $3
```
`sit_up_count` = số giây có `status = 0x03`; `wake_count` = số giây có `status = 0x05` (từ `sec_data`).

**Idempotent:** ghi bằng `INSERT ... ON CONFLICT (device_id, started_at) DO UPDATE` — tận dụng UNIQUE của Phase 01.

**Task nền:** `run_session_builder(pool, rds, stop)`, tick 60s, khuôn giống `run_alert_engine`; wire vào `main.py` `lifespan` cạnh `alerts_task`.

## Related Code Files
- Create: `sleep_pad_AI/backend/app/sessions/{__init__,models,rules,service,builder}.py`
- Create: `sleep_pad_AI/backend/requirements-dev.txt` — **chỉ** `pytest`
- Create: `sleep_pad_AI/backend/tests/test_session_rules.py`
- Modify: `sleep_pad_AI/backend/app/main.py` — thêm `sessions_task` vào `lifespan` (cạnh `alerts_task`, dòng ~55) **và vào danh sách của `_stop_tasks` (dòng ~63)**
- Modify: `sleep_pad_AI/backend/app/config.py` — thêm 3 ngưỡng vào `Settings`

## Implementation Steps

0. **Bootstrap pytest** — repo hiện **không có pytest ở bất kỳ đâu**: `app/requirements.txt` không có, không có `pytest.ini`/`pyproject.toml`/`setup.cfg`, không có file `test_*.py` hay `conftest.py` nào.
   Tạo `backend/requirements-dev.txt` chỉ với `pytest`, cài vào venv/host: `pip install -r requirements-dev.txt`.
   **Không** tạo `conftest.py`, **không** tạo fixture docker — `rules.py` là hàm thuần, không cần DB. Harness đầy đủ (conftest + fixture docker) đang được dựng ở plan `260802-2203` trên branch `feat/ws-user-combined`; đừng dựng trùng và đừng đụng vào.

1. `rules.py`: `is_on_bed()`, `build_sessions(samples) -> list[SessionWindow]` — hàm thuần, nhận list `(t, hr, rr, status)`, trả list cửa sổ. Không import asyncpg.
2. `tests/test_session_rules.py`: viết **trước** `service.py`. Các case ở Success Criteria bên dưới.
3. `service.py`: đọc `sec_data` từ mốc cuối đã xử lý; gọi `build_sessions`; tính tóm tắt bằng SQL trên; upsert `sleep_sessions`.
4. `builder.py`: vòng lặp `while not stop.is_set()` + `asyncio.wait_for(stop.wait(), timeout=60)`, bắt exception và log, **không được làm sập lifespan**.
5. Wire vào `main.py`: `asyncio.create_task(run_session_builder(...), name="session-builder")` **và thêm `sessions_task` vào list truyền cho `_stop_tasks`** — task không nằm trong list đó sẽ không bị huỷ lúc shutdown.
6. `python -m pytest tests/test_session_rules.py -v`

## Success Criteria
- [ ] on_bed 29 giây rồi off → **không** sinh phiên
- [ ] on_bed 30 giây rồi off → sinh **1** phiên
- [ ] Giữa phiên off_bed 25 phút rồi on lại → vẫn là **1** phiên (chưa đủ 30 phút)
- [ ] Giữa phiên off_bed 31 phút → **2** phiên, phiên 1 `ended_at` = lúc bắt đầu off, không phải lúc đủ 30 phút
- [ ] Chuỗi 1500 phút liên tục on_bed → phiên bị cắt ở **1440** phút
- [ ] Nửa phiên có `hr = 0` → `hr_avg` bằng trung bình của nửa còn lại (không tụt)
- [ ] Gap dữ liệu 40 phút được tính như off_bed → đóng phiên
- [ ] Chạy builder 2 lần trên cùng dữ liệu → số dòng `sleep_sessions` không đổi
- [ ] Backend khởi động được, `docker compose logs fastapi` có dòng "session builder started"
- [x] `_stop_tasks` gồm `sessions_task` (`main.py:72`); không có warning "Task was destroyed but it is pending" ở bất kỳ log nào

<!-- Đo được ở Session thực thi: dưới `uvicorn --reload` (cấu hình dev), reload giết
     process con nên **không** task nào in dòng "stopped" — kể cả `alerts.engine` có sẵn.
     Tiêu chí gốc không quan sát được ở chế độ dev. Bằng chứng thay thế: task nằm trong
     list truyền cho `_stop_tasks`, và không log nào có warning task bị bỏ rơi. -->

<!-- Updated: Validation Session 1 — F-01: thêm bước 0 bootstrap pytest. Contract gap: `_stop_tasks` (main.py:63) phải gồm task mới -->

## Risk Assessment
- **R1 (từ plan):** `is_on_bed` dựa vào `hr>0 OR rr>0` là suy luận. PDF nói `0` cũng nghĩa "không tính được" → có thể cắt phiên nhầm khi cảm biến nhiễu. Ngưỡng ở config để chỉnh sau đêm đo thật. **Không** coi kết quả pha này là đã kiểm chứng.
- **Task nền làm sập app:** mọi exception trong vòng lặp phải bị bắt và log, giống `run_alert_engine`.
- **Dùng `COALESCE(received_at, time)`:** cấm — phá index range scan và chunk exclusion (đo bằng `EXPLAIN`, Validation Session 2). Grep lại toàn bộ SQL của pha này trước khi đóng: không được có `COALESCE` trên trục thời gian.
