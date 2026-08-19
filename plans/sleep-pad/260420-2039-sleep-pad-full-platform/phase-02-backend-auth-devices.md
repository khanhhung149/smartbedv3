---
phase: 02
status: completed
priority: critical
effort: medium
sub_project: backend
blockedBy: [phase-01]
---

# Phase 02: Backend Auth & Device Pairing

## Overview

FastAPI application with JWT authentication and device pairing. ESP32 calls `/devices/pair` after connecting to MQTT. Flutter app uses `/auth/*` endpoints.

## Requirements

- JWT-based auth (register, login, /auth/me)
- Device pairing endpoint called by ESP32 after MQTT connect
- List devices owned by user
- Device status (online/offline via MQTT LWT)

## App Structure

```
backend/app/
├── main.py               ← FastAPI app factory, router inclusion
├── config.py             ← Settings from env vars (pydantic BaseSettings)
├── database.py           ← asyncpg connection pool
├── auth/
│   ├── router.py         ← /auth/register, /auth/login, /auth/me
│   ├── models.py         ← Pydantic schemas (UserCreate, UserLogin, UserOut, Token)
│   └── service.py        ← password hashing, JWT create/verify
├── devices/
│   ├── router.py         ← /devices/pair, /devices/mine, /devices/{id}/status
│   ├── models.py         ← Pydantic schemas (DevicePair, DeviceOut)
│   └── service.py        ← DB queries
└── dependencies.py       ← get_current_user dependency
```

## API Contracts

### POST /auth/register
```json
// Request
{ "email": "user@example.com", "password": "secret" }
// Response 201
{ "id": "uuid", "email": "user@example.com" }
```

### POST /auth/login
```json
// Request
{ "email": "user@example.com", "password": "secret" }
// Response 200
{ "access_token": "jwt...", "token_type": "bearer" }
```

### GET /auth/me  (Bearer token required)
```json
{ "id": "uuid", "email": "user@example.com" }
```

### POST /devices/pair  (Bearer token required)
```json
// Request — sent by ESP32 after MQTT connect
{ "device_id": "CNU2000001", "name": "Bedroom Pad" }
// Response 200
{ "device_id": "CNU2000001", "paired": true }
```

### GET /devices/mine  (Bearer token required)
```json
[{ "device_id": "CNU2000001", "name": "Bedroom Pad", "online": true, "last_seen": "..." }]
```

### GET /devices/{id}/status  (Bearer token required)
```json
{ "device_id": "CNU2000001", "online": true, "last_seen": "..." }
```

## JWT Implementation

```python
# auth/service.py
SECRET_KEY = settings.jwt_secret  # from env
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE = timedelta(days=30)

def create_access_token(user_id: str) -> str: ...
def verify_token(token: str) -> str: ...  # returns user_id
```

## Device Online Status

Online/offline tracked via Redis:
- MQTT LWT sets `sleeppad/{device_id}/status` → `"offline"` on disconnect
- MQTT subscriber (Phase 03) sets Redis key `device:{id}:online` = `1` with TTL 70s
- `/devices/mine` checks Redis for each device

## Related Files

- Create: `backend/app/config.py`
- Create: `backend/app/database.py`
- Create: `backend/app/dependencies.py`
- Create: `backend/app/auth/router.py`
- Create: `backend/app/auth/models.py`
- Create: `backend/app/auth/service.py`
- Create: `backend/app/devices/router.py`
- Create: `backend/app/devices/models.py`
- Create: `backend/app/devices/service.py`
- Modify: `backend/app/main.py`

## Implementation Steps

1. Write `config.py` — BaseSettings pulling from .env
2. Write `database.py` — asyncpg pool init/close lifespan
3. Write `auth/models.py` — Pydantic schemas
4. Write `auth/service.py` — bcrypt password hash, JWT sign/verify
5. Write `auth/router.py` — register, login, me endpoints
6. Write `dependencies.py` — `get_current_user` from Bearer token
7. Write `devices/models.py`
8. Write `devices/service.py` — pair_device, get_user_devices DB queries
9. Write `devices/router.py`
10. Update `main.py` — include routers, lifespan for DB pool
11. Test with httpie/curl: register → login → pair device → list devices

## Todo

- [x] config.py (BaseSettings)
- [x] database.py (asyncpg pool)
- [x] auth module (models, service, router)
- [x] dependencies.py (get_current_user)
- [x] devices module (models, service, router)
- [x] Update main.py
- [x] Integration test: full register→login→pair flow

## Success Criteria

- `POST /auth/register` creates user, returns 201
- `POST /auth/login` returns JWT
- `GET /auth/me` with valid token returns user
- `POST /devices/pair` with valid token stores device in DB
- `GET /devices/mine` returns paired devices

## Security

- Passwords hashed with bcrypt (passlib[bcrypt])
- JWT signed with secret from env (never hardcoded)
- All device endpoints require valid JWT
- SQL via parameterized asyncpg queries (no string interpolation)
