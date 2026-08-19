---
phase: 01
status: completed
priority: critical
effort: medium
sub_project: backend
---

# Phase 01: Backend Infrastructure

## Overview

Scaffold the Docker-based backend infrastructure: directory layout, Docker Compose configs (base/dev/prod), PostgreSQL+TimescaleDB, Mosquitto MQTT broker, Redis. No application code yet — just services running and communicating.

## Requirements

- `docker-compose.yml` base with shared service definitions
- `docker-compose.dev.yml`: LAN direct ports, no tunnel
- `docker-compose.prod.yml`: cloudflared tunnel, VPS
- TimescaleDB hypertable + indexes designed up front (perf requirement)
- Mosquitto: TCP 1883 (dev) + WebSocket 9001 (dev) + WebSocket 443 via cloudflared (prod)
- Redis: default port 6379

## Directory Structure

```
backend/
├── docker-compose.yml
├── docker-compose.dev.yml
├── docker-compose.prod.yml
├── .env.example
├── mosquitto/
│   ├── mosquitto.conf
│   └── mosquitto-dev.conf
├── postgres/
│   └── init.sql             ← schema + TimescaleDB hypertables
├── app/
│   ├── Dockerfile
│   ├── requirements.txt
│   └── main.py              ← placeholder FastAPI app
```

## Architecture

```
docker-compose.yml (base)
├── fastapi    image: ./app, env_file: .env
├── mosquitto  image: eclipse-mosquitto:2
├── postgres   image: timescale/timescaledb:latest-pg16
└── redis      image: redis:7-alpine

docker-compose.dev.yml (extends base)
└── ports exposed: 8000, 1883, 9001, 5432, 6379

docker-compose.prod.yml (extends base)
└── cloudflared (tunnel) — no exposed ports
```

## Database Schema (init.sql)

```sql
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Users
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  fcm_token TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Devices
CREATE TABLE devices (
  id TEXT PRIMARY KEY,           -- 10-char ASCII from ESP32 e.g. CNU2000001
  owner_id UUID REFERENCES users(id),
  name TEXT,
  paired_at TIMESTAMPTZ DEFAULT now(),
  last_seen TIMESTAMPTZ
);

-- Per-second readings (0x85)
CREATE TABLE sec_data (
  time TIMESTAMPTZ NOT NULL,
  device_id TEXT NOT NULL,
  status SMALLINT,
  heart_rate SMALLINT,
  resp_rate REAL,
  sdata SMALLINT,
  pdata SMALLINT
);
SELECT create_hypertable('sec_data', 'time');
CREATE INDEX ON sec_data (device_id, time DESC);

-- Per-minute readings (0x86)
CREATE TABLE min_data (
  time TIMESTAMPTZ NOT NULL,
  device_id TEXT NOT NULL,
  status SMALLINT,
  heart_rate SMALLINT,
  resp_rate REAL,
  movement SMALLINT,
  snore_count SMALLINT,
  resp_disorder SMALLINT,
  pthd SMALLINT,
  temp REAL
);
SELECT create_hypertable('min_data', 'time');
CREATE INDEX ON min_data (device_id, time DESC);

-- Alert thresholds (per device per owner)
CREATE TABLE alert_thresholds (
  device_id TEXT REFERENCES devices(id),
  user_id UUID REFERENCES users(id),
  hr_high SMALLINT DEFAULT 120,
  hr_low SMALLINT DEFAULT 40,
  rr_high REAL DEFAULT 30,
  rr_low REAL DEFAULT 5,
  resp_disorder_count SMALLINT DEFAULT 5,
  PRIMARY KEY (device_id, user_id)
);

-- Alert history
CREATE TABLE alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id TEXT NOT NULL,
  metric TEXT NOT NULL,
  value REAL NOT NULL,
  threshold REAL NOT NULL,
  triggered_at TIMESTAMPTZ DEFAULT now()
);

-- Device sharing
CREATE TABLE device_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id TEXT REFERENCES devices(id),
  owner_id UUID REFERENCES users(id),
  shared_with_id UUID REFERENCES users(id),
  invited_email TEXT,
  accepted BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

## Mosquitto Config

```
# mosquitto.conf (dev)
listener 1883
allow_anonymous true

listener 9001
protocol websockets
allow_anonymous true
```

Prod config uses WebSocket only (cloudflared proxies 443 → 9001).

## Related Files

- Create: `backend/docker-compose.yml`
- Create: `backend/docker-compose.dev.yml`
- Create: `backend/docker-compose.prod.yml`
- Create: `backend/.env.example`
- Create: `backend/mosquitto/mosquitto.conf`
- Create: `backend/mosquitto/mosquitto-dev.conf`
- Create: `backend/postgres/init.sql`
- Create: `backend/app/Dockerfile`
- Create: `backend/app/requirements.txt`
- Create: `backend/app/main.py` (placeholder)

## Implementation Steps

1. Create `backend/` directory tree
2. Write `postgres/init.sql` with full schema + hypertables
3. Write `mosquitto/mosquitto.conf` (prod WS only) and `mosquitto-dev.conf` (TCP + WS)
4. Write `docker-compose.yml` base — services without ports
5. Write `docker-compose.dev.yml` — port mappings, dev mosquitto config
6. Write `docker-compose.prod.yml` — cloudflared service, no port exposure
7. Write `app/Dockerfile` (Python 3.12-slim, FastAPI placeholder)
8. Write `app/requirements.txt` (fastapi, uvicorn, asyncpg, redis, paho-mqtt, firebase-admin, python-jose, passlib, pydantic)
9. Write `.env.example` with all required vars
10. Run `docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d`
11. Verify: psql connects, MQTT broker accepts connections, Redis pings

## Todo

- [x] Create backend directory tree
- [x] Write init.sql schema
- [x] Write mosquitto configs
- [x] Write Docker Compose files (base + dev + prod)
- [x] Write Dockerfile + requirements.txt
- [x] Write .env.example
- [x] Boot stack: `docker compose up -d`
- [x] Verify all services healthy

## Success Criteria

- `docker compose -f docker-compose.yml -f docker-compose.dev.yml up` → all 4 services healthy
- `psql` connects to TimescaleDB, tables created, hypertables verified
- `mosquitto_pub -h localhost -p 1883 -t test/topic -m hello` succeeds
- `redis-cli ping` → PONG

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| TimescaleDB init order | Use `healthcheck` on postgres before fastapi starts |
| Mosquitto WS in prod | Test cloudflared tunnel WS upgrade header passthrough |
| .env secrets in git | Add .env to .gitignore, only commit .env.example |

## Security

- Postgres: non-root user in .env
- Mosquitto: prod should add password auth (post-MVP)
- All secrets via env vars, never hardcoded
