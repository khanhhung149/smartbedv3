# Phase 04: Alert Engine + FCM + Family Sharing

**Date**: 2026-04-21 14:35
**Severity**: Medium
**Component**: Alert Engine, FCM Integration, Family Sharing API
**Status**: Complete

## What Shipped

Backend platform milestone complete. Alert engine (60s loop) + FCM push notifications + family sharing API. 9 endpoints + 1 background task, all integration-tested.

## The Technical Reality

Three architectural decisions held up under review. First: **per-user thresholds**, not per-device. Alice sets `hr_high=100`, Bob sets `hr_high=120`. Same device, same sensor reading at avg=131 triggers two distinct alert rows. No clobbering. Verified and shipping.

Second: **auto-seed defaults on pair + share-accept**. Zero config required. Owners and shared users inherit default thresholds immediately; PUT endpoint tunes from there. YAGNI—no "disabled alerts" flag. Users set `hr_high=999` if they want silence.

Third: **Redis dedup** via SET NX EX 300—5-minute suppression window per (device, user, metric). Catch the same breach twice in 60s? Only one alert row. Redis down? Fail-open; alert fires anyway.

## The Painful Parts

Review caught two critical lifecycle bugs that would've burned us in production:

1. **Re-inviting accepted share** was naively UPSERT-ing `shared_with_id`—silent revocation. Added `WHERE accepted = FALSE` guard on conflict. Now re-invites no-op correctly.

2. **Revoking share** left orphan `alert_thresholds` rows. Engine kept firing alerts (and FCM pushes) for revoked family members months later. Wrapped revoke in transaction to clean up thresholds first.

FCM blocking call wrapping: `messaging.send()` is HTTPS-blocking (50-200ms per push). Wrapped in `asyncio.to_thread`—event loop doesn't stall anymore. Dev mode gracefully no-ops: stub `{}` credentials file (len <100) silences all FCM calls.

## What's Deferred

Alert engine does O(N·M) min_data scans (one per threshold row instead of grouping by device). Fine at <100 devices. Grouping optimization deferred to scaling phase.

Sharing access unified across data layer: `user_can_access_device` now LEFT JOINs `device_shares`. Owner OR accepted share passes. Applied to `/data/*`, `/alerts/*`, device status, WebSocket.

**Next:** Phase 05 (ESP32 BLE + MQTT client rewrite).
