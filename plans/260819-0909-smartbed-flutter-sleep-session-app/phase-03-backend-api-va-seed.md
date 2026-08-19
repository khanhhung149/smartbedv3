---
phase: 3
title: "Backend — API /sessions + /timeline, seed script, hợp đồng API"
status: completed
priority: P1
dependencies: [2]
repo: sleep_pad_AI + smartbedv3
---

# Phase 03: Backend — API `/sessions` + `/timeline`, seed script, hợp đồng API

## Overview
Mở 3 endpoint cho app, viết script bơm một đêm dữ liệu mẫu, và viết file hợp đồng API ở `smartbedv3/docs/` — thứ duy nhất giữ 2 repo không trôi khỏi nhau.

## Requirements
- Functional: `/timeline` là endpoint **duy nhất** app cần để vẽ màn hình chi tiết.
- Functional: gộp/bucket làm ở SQL (`time_bucket`), **không** ở client.
- Non-functional: 3 endpoint đều qua `get_current_user_id` + `user_can_access_device` như `data/router.py` đang làm.
- Non-functional: response có chỗ để thêm cột presence/env sau này mà app không phải sửa.

## Architecture

```
GET /sessions?device_id=<id>&from=<iso>&to=<iso>&limit=30
    → [{ id, device_id, started_at, ended_at, duration_s,
          hr_avg, hr_min, hr_max, rr_avg,
          movement_total, snore_total, resp_disorder_total,
          sit_up_count, wake_count }]

GET /sessions/{id}
    → cùng shape, 1 phần tử

GET /sessions/{id}/timeline?bucket=1m
    → { session_id, bucket, points: [
          { t, hr, rr, movement, snore, resp_disorder, bed_state } ] }
```

`bed_state`: `"on_bed" | "off_bed"` — suy từ `is_on_bed` của Phase 02, **không** từ `status`.
Sự kiện trong bucket (ngồi dậy `0x03`, tỉnh `0x05`, ngáy `0x07`, thở yếu `0x08`) trả kèm ở mỗi point dưới `events: []` — không cần bảng riêng (quyết định #6 của plan).

`bucket` chỉ nhận whitelist `{"1m","5m"}` — hằng số phía server, nội suy vào SQL an toàn, đúng cách `_RANGE_PARAMS` của `data/service.py:212` đang làm.

**Chỗ để mở rộng:** mỗi point là một object; thêm `presence`/`temp`/`ac_on` sau này là **thêm khoá**, app cũ bỏ qua khoá lạ.

## Related Code Files
- Create: `sleep_pad_AI/backend/app/sessions/router.py`
- Modify: `sleep_pad_AI/backend/app/sessions/{models,service}.py` — thêm shape cho `/timeline`
- Modify: `sleep_pad_AI/backend/app/main.py` — `app.include_router(sessions_router)`
- Create: `sleep_pad_AI/backend/scripts/seed-night.py` — **chạy trong container `fastapi`**, không phải trên host
- Modify: `sleep_pad_AI/backend/docker-compose.dev.yml` — mount `./scripts:/app/scripts:ro` vào service `fastapi`
- Create: `smartbedv3/docs/sleep-session-api-contract.md`

> `smartbedv3/app/README.md` do **Phase 04** sở hữu — không sửa ở pha này.

## Implementation Steps

1. `models.py`: `SessionOut`, `TimelinePoint`, `TimelineResponse` (pydantic, khuôn `data/models.py`).

2. `router.py`: 3 endpoint, dùng `Depends(get_current_user_id)` + `user_can_access_device` (`data/service.py:17`). 404 khi device không thuộc user — copy đúng cách `data/router.py:48-60` đang làm.

3. `service.py` — truy vấn timeline:
```sql
SELECT time_bucket('1 minute', time) AS t,
       AVG(heart_rate)::real FILTER (WHERE heart_rate > 0) AS hr,
       AVG(resp_rate)::real  FILTER (WHERE resp_rate  > 0) AS rr,
       SUM(movement) AS movement,
       SUM(snore_count) AS snore,
       SUM(resp_disorder) AS resp_disorder
FROM min_data
WHERE device_id = $1 AND time >= $2 AND time < $3
GROUP BY t ORDER BY t
```
`time` chứ không phải `COALESCE(received_at, time)` — xem Validation Session 2 / F-04.
   `bed_state` + `events` lấy từ `sec_data` cùng bucket, join ở Python (một truy vấn phụ, không lồng SQL cho phức tạp).

4. `scripts/seed-night.py` — ghi **thẳng DB** qua asyncpg (không qua MQTT, quyết định #7).
   **Chạy trong container `fastapi`**: `asyncpg` và `DATABASE_URL` đã có sẵn ở đó, host không cần venv.
```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml --env-file .env.dev \
  exec fastapi python /app/scripts/seed-night.py --device-id TEST000001 --hours 8
```
   Cần thêm mount `./scripts:/app/scripts:ro` vào service `fastapi` trong `docker-compose.dev.yml`.
   Tham số:
   - `--device-id`, `--start` (ISO), `--hours` (mặc định 8)
   - Sinh `sec_data` 1 Hz + `min_data` 1 phút cho một đêm hợp lý (hr 55–70, rr 12–18, vài lần trở mình, một đợt ngáy)
   - `--gap-minutes` chèn một đoạn rời giường
   - `--zero-hr-half` để nửa sau `hr=0` — **đây là fixture cho tiêu chí nghiệm thu #2**
   - Ghi `received_at = time` cho dữ liệu seed để giống hệt đường ingest thật

5. `smartbedv3/docs/sleep-session-api-contract.md`: 3 endpoint, shape request/response, mã lỗi, phiên bản. **Luật: sửa endpoint là sửa file này trong cùng commit.** Ghi rõ backend là cầu tạm, K8s (`cloud/`) vẫn là đích theo `phase-06` của plan MVP — không đảo ngược quyết định của Michael.

6. Smoke test:
```bash
TOKEN=$(curl -s -X POST localhost:8080/auth/login -H 'Content-Type: application/json' \
  -d '{"email":"...","password":"..."}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
curl -s -H "Authorization: Bearer $TOKEN" 'localhost:8080/sessions?device_id=XXX' | python3 -m json.tool
```

## Success Criteria
- [ ] Seed một đêm 8 tiếng → `GET /sessions` trả **đúng 1 phiên**, `started_at`/`ended_at` khớp luật 30s/30phút
- [ ] Seed với `--zero-hr-half` → `hr_avg` **không** tụt so với seed không có cờ đó
- [ ] Seed với `--gap-minutes 40` → trả **2** phiên
- [ ] `GET /sessions/{id}/timeline` trả số point = số phút của phiên (±1)
- [ ] Gọi bằng token của user khác → **404**, không phải 200 rỗng
- [ ] `bucket=9m` → **422**, không phải lỗi SQL
- [ ] `smartbedv3/docs/sleep-session-api-contract.md` tồn tại và khớp response thật
- [ ] `seed-night.py` chạy được qua `docker compose exec fastapi` **không** cần cài gì trên host

<!-- Updated: Validation Session 1 — F-03: `backend/scripts/` là thư mục shell (chỉ có setup-mosquitto-passwords.sh), host không có venv Python. Seed chạy trong container fastapi -->

## Risk Assessment
- **R4 (từ plan):** hai repo trôi khỏi nhau. Giảm thiểu duy nhất là file hợp đồng — nếu bỏ qua bước 5, rủi ro này thành hiện thực trong vài tuần.
- **SQL injection qua `bucket`:** whitelist bắt buộc, không nhận chuỗi tự do từ query param.
- **Seed script chạy nhầm lên prod:** script phải in ra `DATABASE_URL` đang dùng và hỏi xác nhận nếu host không phải `localhost`.
