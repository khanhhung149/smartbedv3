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

## Services

- `postgres` — TimescaleDB (PostgreSQL 16 + timescaledb extension). Schema auto-loaded from `postgres/init.sql`.
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
└── scripts/
    └── setup-mosquitto-passwords.sh   generate mosquitto passwords file for prod
```

## Secrets — never commit

`.gitignore` excludes `.env.dev`, `.env.prod`, `secrets/`, `mosquitto/passwords`. Double-check before `git add`.
# CI/CD smoke test marker — 2026-05-05 01:48
