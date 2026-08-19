---
phase: 03
status: completed
priority: critical
effort: large
sub_project: backend
blockedBy: [phase-02]
---

# Phase 03: Backend Data API (MQTT Subscriber + History + Realtime WebSocket)

## Overview

MQTT subscriber that ingests 0x85/0x86 frames into TimescaleDB, REST history API (day/week/month), and WebSocket endpoint streaming realtime data to Flutter app.

## Requirements

- Background MQTT subscriber (aiomqtt) subscribes to `sleeppad/+/sec` and `sleeppad/+/min`
- Parse JSON from ESP32, insert into `sec_data` / `min_data` TimescaleDB tables
- Redis pub/sub: subscriber publishes to `realtime:{device_id}` channel
- WebSocket `/ws/{device_id}`: streams from Redis channel to Flutter client
- REST GET `/data/{device_id}/realtime` — latest sec_data row
- REST GET `/data/{device_id}/history?range=day|week|month` — aggregated min_data

## MQTT Message Format (sent by ESP32)

```json
// Topic: sleeppad/CNU2000001/sec
{
  "device_id": "CNU2000001",
  "ts": 1713600000,
  "status": 4,
  "heart_rate": 68,
  "resp_rate": 14.5,
  "sdata": 12,
  "pdata": 8
}

// Topic: sleeppad/CNU2000001/min
{
  "device_id": "CNU2000001",
  "ts": 1713600060,
  "status": 4,
  "heart_rate": 68,
  "resp_rate": 14.0,
  "movement": 2,
  "snore_count": 0,
  "resp_disorder": 0,
  "pthd": 5,
  "temp": 36.5
}
```

## App Structure

```
backend/app/
├── mqtt/
│   ├── subscriber.py     ← aiomqtt client, subscribes, inserts to DB, publishes to Redis
│   └── parser.py         ← validate/parse incoming JSON payloads
├── data/
│   ├── router.py         ← /data/{device_id}/realtime, /data/{device_id}/history, /ws/{device_id}
│   ├── models.py         ← Pydantic schemas (HistoryPoint, RealtimeData)
│   └── service.py        ← TimescaleDB history queries
└── redis_client.py       ← shared Redis connection (redis.asyncio)
```

## History Query Logic

```sql
-- day: last 24h, group by 5 min
SELECT
  time_bucket('5 minutes', time) AS bucket,
  AVG(heart_rate) AS hr,
  AVG(resp_rate) AS rr,
  MAX(resp_disorder) AS resp_disorder
FROM min_data
WHERE device_id = $1 AND time > now() - interval '1 day'
GROUP BY bucket ORDER BY bucket;

-- week: last 7 days, group by 1 hour
-- month: last 30 days, group by 3 hours
```

## WebSocket Flow

```
Flutter connects → WS /ws/{device_id}
  ↓ verify JWT (query param ?token=...)
  ↓ subscribe to Redis channel realtime:{device_id}
  ↓ loop: receive message → forward to WS client
  ↓ on disconnect: unsubscribe Redis
```

## Related Files

- Create: `backend/app/mqtt/subscriber.py`
- Create: `backend/app/mqtt/parser.py`
- Create: `backend/app/data/router.py`
- Create: `backend/app/data/models.py`
- Create: `backend/app/data/service.py`
- Create: `backend/app/redis_client.py`
- Modify: `backend/app/main.py` — start MQTT subscriber as background task in lifespan

## Implementation Steps

1. Write `redis_client.py` — async Redis pool (redis.asyncio)
2. Write `mqtt/parser.py` — validate incoming MQTT JSON
3. Write `mqtt/subscriber.py`:
   - Connect to Mosquitto via aiomqtt
   - Subscribe `sleeppad/+/sec` and `sleeppad/+/min`
   - On message: parse → insert asyncpg → publish to Redis channel
   - Update `device:{id}:online` Redis key TTL 70s
4. Write `data/service.py` — time_bucket queries for day/week/month
5. Write `data/models.py` — response schemas
6. Write `data/router.py`:
   - GET `/data/{id}/realtime` → latest row from sec_data
   - GET `/data/{id}/history` → time_bucket query
   - WS `/ws/{id}` → JWT verify → Redis subscribe loop
7. Update `main.py` — start MQTT subscriber in lifespan
8. Integration test: publish MQTT message → verify DB insert → verify WS receives it

## Todo

- [x] redis_client.py
- [x] mqtt/parser.py
- [x] mqtt/subscriber.py (DB insert + Redis publish)
- [x] data/service.py (time_bucket queries)
- [x] data/router.py (realtime + history + WebSocket)
- [x] Wire MQTT subscriber into main.py lifespan
- [x] Integration test end-to-end

## Success Criteria

- Publish to `sleeppad/test/sec` → row appears in `sec_data` table
- GET `/data/test/realtime` → returns latest reading
- GET `/data/test/history?range=day` → returns bucketed time series
- WS `/ws/test?token=...` receives messages within 1s of MQTT publish

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| aiomqtt reconnect on broker restart | Wrap subscriber in retry loop with exponential backoff |
| Redis channel backpressure | WS send is async; drop old if client slow (non-critical realtime data) |
| TimescaleDB week/month query latency | Use `time_bucket` with indexes — verified fast at design time |
| JWT in WS URL (query param) | Acceptable for WebSocket (no custom headers in browser WS); use short-lived tokens if security concern |
