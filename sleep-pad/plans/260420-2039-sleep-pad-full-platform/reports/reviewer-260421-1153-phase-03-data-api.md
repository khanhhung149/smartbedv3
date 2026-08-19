# Phase 03 Code Review — MQTT + Data API + WS

Scope: 6 files, 477 LOC. All files under 200 LOC rule.

## Overall

Solid, tight implementation. Validation strict, SQL parameterized, lifespan clean with `AsyncExitStack`, reconnect backoff correct. Ships.

## CRITICAL

None.

## HIGH

**H1. Spoofed/unpaired device_id creates orphan rows in hypertables.**
`sec_data`/`min_data` have no FK to `devices`. Subscriber inserts any `device_id` found in topic, even if not paired. In dev (anon MQTT) any ESP32 can fill tables with arbitrary IDs. Pair-ownership does gate readers (safe), but storage cost + later noise is unbounded.
Fix: in `_handle_message`, short-circuit if `device_id` not in `devices` table. Cache membership in Redis (TTL 60s) to avoid per-message SELECT. `_mark_online`'s `UPDATE devices WHERE id=$2` silently no-ops today — make that an existence check instead.

**H2. ESP32-provided `ts` used as authoritative time.**
`to_timestamptz(p.ts)` trusts device clock. ESP32 with skew or before NTP sync writes wrong buckets; `time_bucket` then misplaces rows. Also: a device can send past/future ts and poison history.
Fix: use `now()` as `time` column; keep `p.ts` only as a second column (`device_ts`) for dedup/ordering if needed. Matches TimescaleDB convention (server-assigned time).

**H3. `_handle_message` runs sequentially per connection.**
`async for msg ... await _handle_message(...)` — one slow insert blocks next message. At 1 Hz sec frames per device × N devices, latency adds up on a single broker connection.
Fix: wrap in `asyncio.create_task` with a bounded semaphore (e.g. 32) or dispatch to a queue worker. Best-effort telemetry — drop on overflow is acceptable.

## SUGGESTIONS

- **S1. `_RANGE_PARAMS` f-string — safe today but fragile.** Lines 46–57 in `data/service.py`. Add an `assert range_key in _RANGE_PARAMS` at function entry and a comment pinning the constraint. Future dev won't realize the enum is load-bearing.
- **S2. WS pubsub close.** `pubsub.aclose()` in `finally` is correct for `redis-py ≥5`. OK. Concurrent WS per device: each opens its own pubsub — N subscribers for N connections. Fine at POC scale; consider a shared broadcaster if > ~100 clients/device.
- **S3. WS heartbeat.** `{"type":"ping"}` shares JSON envelope with data messages (which have no `type` field). Client must distinguish. Cheap fix: wrap all messages in `{"type":"data", "payload": {...}}`. Do now — cheaper than migrating clients later.
- **S4. Lifespan shutdown race.** In-flight insert when `task.cancel()` fires: asyncpg raises `CancelledError` mid-query, transaction rolls back. Acceptable for telemetry. No fix needed, but worth a one-liner comment in `_stop_mqtt`.
- **S5. `dict(asyncpg.Record)` → Pydantic.** Works: Record is mapping-like, `RealtimeData`/`HistoryPoint` use native types. `time_bucket` returns `timestamptz` → `datetime` ✓. `AVG(...)::real` → float ✓. No issue.
- **S6. `/status` LWT trusts payload string.** Unauthenticated in dev — a malicious publisher can force `offline` for any device and break the online indicator. Prod MQTT ACLs gate this; document it.
- **S7. `import redis_client.get_redis_from_request` unused in `router.py`.** Remove.
- **S8. Parser swallows all `ValidationError`s silently.** Add `logger.debug` so malformed payloads are traceable during firmware development.

## Unresolved Questions

- Decide H2 (server `now()` vs device `ts`) before Phase 04 alert engine — alert triggers depend on ordering semantics.
- Is H1 enforcement cheap enough via cached membership check, or move to broker-side ACL (mosquitto_auth)? Latter is prod-only.

**Status:** DONE_WITH_CONCERNS
**Summary:** Phase 03 ships cleanly; 3 HIGH items (orphan rows, device-ts trust, sequential msg handling) should be addressed before Phase 04 alerts layer on top.
**Concerns/Blockers:** H1–H3 are correctness/scalability — recommend fix before alert engine. None are blocking for current end-to-end POC verification.
