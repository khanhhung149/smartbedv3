# Sleep Pad Platform — Backend

FastAPI + TimescaleDB + Mosquitto MQTT + Redis + Firebase FCM, orchestrated with Docker Compose.

## Environments

Two fully isolated environments with **different domains, different env files, different configs**:

| Env | Access | Config | Auth |
|-----|--------|--------|------|
| **dev** (local LAN) | `http://<LAN-IP>:8000` + `mqtt://<LAN-IP>:1883` | `.env.dev` + `docker-compose.dev.yml` | MQTT anonymous |
| **prod** (VPS + cloudflared) | `https://api.{DOMAIN}` + `wss://mqtt.{DOMAIN}` | `.env.prod` + `docker-compose.prod.yml` | MQTT password file |

## Quick start — DEV

```bash
cp .env.dev.example  .env.dev
# edit .env.dev: set API_DOMAIN=http://<your-lan-ip>:8000

docker compose -f docker-compose.yml -f docker-compose.dev.yml --env-file .env.dev up -d
curl http://localhost:8000/health
```

## Quick start — PROD

```bash
cp .env.prod.example .env.prod
# edit .env.prod: set API_DOMAIN, MQTT_DOMAIN, POSTGRES_PASSWORD, JWT_SECRET,
#                 MQTT_USERNAME, MQTT_PASSWORD, CLOUDFLARED_TUNNEL_TOKEN

# Generate mosquitto password file (REQUIRED before first prod boot)
./scripts/setup-mosquitto-passwords.sh

# Configure Cloudflare Tunnel routes in Zero Trust dashboard:
#   api.{DOMAIN}  → http://fastapi:8000
#   mqtt.{DOMAIN} → http://mosquitto:9001

docker compose -f docker-compose.yml -f docker-compose.prod.yml --env-file .env.prod up -d
```

## Applying schema changes

`postgres/init.sql` is mounted into `/docker-entrypoint-initdb.d`, which Postgres
runs **only when the data volume is empty**. A database that already holds data
never sees a new schema file that way — that is how `postgres/smart_watch_data.sql`
ended up with no way to reach a running database.

Use the script instead. Every statement in every schema file is `IF NOT EXISTS`,
so it is safe to re-run:

```bash
cd backend
set -a && source .env.dev && set +a
bash scripts/apply-schema.sh
```

It applies, in order: `init.sql` → `smart_watch_data.sql` → `sleep_sessions.sql` → `samples.sql`.
**Add every new schema file to the loop in that script**, not just to `postgres/`.

Target container defaults to `sleeppad-postgres`; override with `POSTGRES_CONTAINER`.

## Phase 01 — canonical samples + dashboard

- **Bảng `samples`** (`postgres/samples.sql`): dòng chuẩn đúng 9 cột CSV take-home
  (`t, presence, hr_bpm, resp_amplitude, motion, weight_kg, spo2, temp_c, humidity`)
  + kênh raw của pad (status, sdata, pdata, movement, snore_count, resp_disorder, pthd,
  body_temp) + nhiệt độ/độ ẩm môi trường + cờ `uart_ok`. `t` = epoch do **MCU** gắn
  (payload `ts`), không phải server now(). Subscriber ghép kênh 1/phút + /temp vào mẫu
  sec qua cache per-device để không mất kênh nào.
- **Retention:** `add_retention_policy('samples', INTERVAL '30 days')` — giữ 30 đêm;
  chunk cũ hơn 1 ngày được nén. Quét tự động bởi TimescaleDB.
- **Dashboard local:** `/dashboard/` — realtime 2 phút + xem lại một đêm
  (`?device=CNU...&token=<JWT>` hoặc nhập trên trang). Trang gọi
  `GET /data/{device_id}/samples?from=&to=` (JWT trong Authorization header, cửa sổ ≤ 48h).

```bash
# ví dụ — lấy 1 giờ mẫu gần nhất
curl -H "Authorization: Bearer $JWT" \
  'http://localhost:8000/data/CNUXXXXXXXX/samples?from=2026-08-18T12:00:00Z&to=2026-08-18T13:00:00Z'
```

## Services

- `postgres` — TimescaleDB (PostgreSQL 16 + timescaledb extension). Schema from `postgres/*.sql` — see *Applying schema changes* above.
- `redis` — Pub/sub for realtime WebSocket fan-out + online status cache.
- `mosquitto` — MQTT broker. Dev: anon TCP 1883 + WS 9001. Prod: auth WS 9001 (TLS via cloudflared).
- `fastapi` — Application server + MQTT subscriber + alert engine. Port 8000.
- `cloudflared` (prod only) — Cloudflare Tunnel; no ports exposed on VPS.

## Files

```
backend/
├── docker-compose.yml           base services (postgres, redis, mosquitto, fastapi)
├── docker-compose.dev.yml       dev override (LAN ports, hot reload)
├── docker-compose.prod.yml      prod override (cloudflared tunnel, no ports)
├── .env.dev.example             dev env template
├── .env.prod.example            prod env template
├── app/                         FastAPI application
├── mosquitto/
│   ├── mosquitto-dev.conf       anonymous TCP+WS
│   ├── mosquitto-prod.conf      auth WS
│   └── passwords.example        example passwords file layout
├── postgres/init.sql            schema + TimescaleDB hypertables
├── postgres/sleep_sessions.sql  sleep_sessions table + sec/min received_at
├── postgres/samples.sql         canonical samples (CSV schema) + retention 30 ngày
├── app/static/dashboard.html    dashboard local web (realtime + xem lại một đêm)
├── scripts/apply-schema.sh      apply every postgres/*.sql to a running DB
└── scripts/
    └── setup-mosquitto-passwords.sh   generate mosquitto passwords file for prod
```

## Secrets — never commit

`.gitignore` excludes `.env.dev`, `.env.prod`, `secrets/`, `mosquitto/passwords`. Double-check before `git add`.
# CI/CD smoke test marker — 2026-05-05 01:48
