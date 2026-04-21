---
phase: 04
status: completed
priority: high
effort: medium
sub_project: backend
blockedBy: [phase-03]
---

# Phase 04: Backend Alert Engine + Family Sharing

## Overview

Background alert engine checks thresholds every 60s and sends FCM push to owner + all shared accounts. Family sharing API allows inviting by email, accepting invites, and revoking access.

## Requirements

- Alert engine: background task, runs every 60s per active device
- Thresholds: HR high/low, RR high/low, resp_disorder count (all configurable per user)
- FCM push to device owner + all accepted shares for that device
- Sharing: invite by email, accept invite, list shared devices, revoke
- Alert history stored in `alerts` table

## App Structure

```
backend/app/
├── alerts/
│   ├── router.py       ← GET/PUT /alerts/{device_id}/thresholds, GET /alerts/{device_id}/history
│   ├── models.py       ← ThresholdUpdate, AlertOut
│   ├── service.py      ← DB queries for thresholds + alert history
│   └── engine.py       ← background task: check thresholds, fire FCM
├── sharing/
│   ├── router.py       ← POST /share/invite, GET /share/my-devices, DELETE /share/{id}
│   ├── models.py       ← ShareInvite, ShareOut
│   └── service.py      ← DB queries for shares
└── fcm.py              ← Firebase Admin SDK wrapper (send_push)
```

## Alert Engine Logic

```python
# alerts/engine.py
async def run_alert_engine():
    while True:
        await asyncio.sleep(60)
        devices = await get_active_devices()   # last_seen < 2 min
        for device_id in devices:
            await check_device_alerts(device_id)

async def check_device_alerts(device_id: str):
    # Query last 1 minute of min_data
    rows = await get_last_minute_data(device_id)
    if not rows:
        return
    # Get all thresholds: owner + shared users
    thresholds = await get_all_thresholds(device_id)
    for t in thresholds:
        violations = detect_violations(rows, t)
        for v in violations:
            await send_alert(device_id, t.user_id, v)
            await log_alert(device_id, v)

def detect_violations(rows, threshold) -> list[Violation]:
    avg_hr = mean(r.heart_rate for r in rows)
    avg_rr = mean(r.resp_rate for r in rows)
    total_resp_disorder = sum(r.resp_disorder for r in rows)
    violations = []
    if avg_hr > threshold.hr_high: violations.append(...)
    if avg_hr < threshold.hr_low: violations.append(...)
    # etc.
    return violations
```

## FCM Integration

```python
# fcm.py
import firebase_admin
from firebase_admin import messaging

def init_fcm(credentials_path: str):
    cred = firebase_admin.credentials.Certificate(credentials_path)
    firebase_admin.initialize_app(cred)

async def send_push(fcm_token: str, title: str, body: str):
    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        token=fcm_token,
    )
    messaging.send(message)
```

FCM credentials JSON path from env var `FCM_CREDENTIALS_PATH`.

## API Contracts

### GET /alerts/{device_id}/thresholds
```json
{ "hr_high": 120, "hr_low": 40, "rr_high": 30.0, "rr_low": 5.0, "resp_disorder_count": 5 }
```

### PUT /alerts/{device_id}/thresholds
```json
// Request
{ "hr_high": 110, "hr_low": 45 }
// Response 200 — updated thresholds
```

### GET /alerts/{device_id}/history
```json
[{ "id": "uuid", "metric": "hr_high", "value": 125, "threshold": 120, "triggered_at": "..." }]
```

### POST /share/invite
```json
// Request
{ "device_id": "CNU2000001", "email": "family@example.com" }
// Response 201
{ "share_id": "uuid", "status": "pending" }
```

### GET /share/my-devices
```json
[{ "device_id": "CNU2000001", "owner_email": "...", "share_id": "uuid" }]
```

### POST /share/{id}/accept
```json
{ "accepted": true }
```

### DELETE /share/{id}
```json
{ "deleted": true }
```

## Related Files

- Create: `backend/app/alerts/engine.py`
- Create: `backend/app/alerts/router.py`
- Create: `backend/app/alerts/models.py`
- Create: `backend/app/alerts/service.py`
- Create: `backend/app/sharing/router.py`
- Create: `backend/app/sharing/models.py`
- Create: `backend/app/sharing/service.py`
- Create: `backend/app/fcm.py`
- Modify: `backend/app/main.py` — start alert engine in lifespan

## Implementation Steps

1. Write `fcm.py` — init Firebase, `send_push` function
2. Write `alerts/service.py` — threshold CRUD, alert log queries
3. Write `alerts/engine.py` — 60s loop, threshold check, FCM dispatch
4. Write `alerts/models.py` + `alerts/router.py`
5. Write `sharing/service.py` — invite, accept, list, delete queries
6. Write `sharing/models.py` + `sharing/router.py`
7. Update `main.py` — start alert engine alongside MQTT subscriber
8. Test: insert min_data row exceeding threshold → alert logged → FCM called

## Todo

- [x] fcm.py (Firebase Admin init + send_push)
- [x] alerts/service.py
- [x] alerts/engine.py (background 60s loop)
- [x] alerts/router.py + models.py
- [x] sharing/service.py
- [x] sharing/router.py + models.py
- [x] Wire engine into main.py lifespan
- [x] Test threshold trigger end-to-end

## Success Criteria

- PUT threshold → GET returns updated values
- Insert min_data row with HR=130 (above 120 threshold) → alert row in DB within 60s
- FCM send_push called with correct token
- Share invite → accept → GET /share/my-devices shows device
- DELETE /share/{id} → device no longer visible

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| FCM token stale/expired | Log FCM error, skip silently; token refreshed on next app login |
| Alert engine crashes | Wrap in try/except, log error, continue loop |
| Duplicate alerts every 60s | Track last alert time per device+metric in Redis; suppress if same alert fired < 5 min ago |

## Security

- Only device owner can modify thresholds
- Share invite acceptance requires the invited user to be authenticated
- FCM credentials file never committed to git
