# Phase 03: MQTT Ingest & Realtime Delivery

**Date**: 2026-04-21 12:08
**Severity**: Completed
**Component**: Telemetry pipeline (MQTT → TimescaleDB → WebSocket)
**Status**: Resolved

## What Shipped

Full end-to-end telemetry pipeline: ESP32 → MQTT → TimescaleDB → Redis → WebSocket → Flutter. 3 REST endpoints + 1 WebSocket endpoint. Integration-tested sub-500ms latency from MQTT publish to browser delivery.

## The Critical Calls

**Server `now()` vs device timestamp:** Code reviewer caught a nasty one — letting ESP32 timestamps directly populate TimescaleDB's `time` column would let device clock skew destroy bucketing and queries. Switched to server-side `now()`. Verified by publishing `ts=1` (Unix epoch) and confirming it stored as 2026-04-21. Device timestamp silently discarded for now. If forensic replay ever matters, we add a `device_ts` column.

**Orphan publishes:** Dev MQTT is unauthenticated, so spoofing is trivial. Added paired-device check before insert — published GHOST999 to verify: 0 rows inserted. Prod layers MQTT password auth on top, but this check keeps bad data out of the database now.

**Async subscriber bottleneck:** First pass was `async for msg: await handle(msg)` — one slow insert blocks every device. Switched to `asyncio.create_task(handle)` with `Semaphore(32)` gating. Headroom for spiky load; tasks outlive the iteration loop but that's acceptable at this scale.

**WebSocket heartbeat:** Sends `{"type":"ping"}` every 30s when idle to prevent Cloudflare's connection timeout. Clients must filter by `type`.

## Deferred (Acceptable)

- Redis cache for `is_paired` query (1 per MQTT message, negligible at 1Hz per device)
- MQTT ACL per-device credentials (single password for now)
- Graceful shutdown race on in-flight inserts (rollback is fine)

Next: Phase 04 (alert engine + FCM + family sharing).
