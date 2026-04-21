# Full Platform Architecture: Designing for Scale After POC Validation

**Date**: 2026-04-20
**Severity**: Medium
**Component**: System Architecture, DevOps, Platform Design
**Status**: Planned (Phase 1 Ready)

## What Happened

Approved and documented a complete IoT platform architecture spanning ESP32 firmware, FastAPI backend, Flutter mobile app, and infrastructure. Moved from single-device POC to multi-tenant system with realtime data ingestion, time-series storage, push notifications, and family sharing. Created 8-phase implementation plan with clear dependencies and success criteria.

## The Brutal Truth

This was necessary but terrifying. The POC proved the sleep pad data *could* be captured; now we're committing to an architecture that must handle scale (multiple devices per user, family sharing, push notifications, historical analysis). 

The hard part wasn't picking technologies—it was making irreversible choices about data flow, authentication, and infrastructure. Once we go MQTT-centric with TimescaleDB, swapping it out is a rewrite. Once Flutter owns BLE provisioning, every ESP32 firmware update is tight-coupled to app deployments. These aren't mistakes we can iterate away.

The relief: we validated the POC first. We're not betting the farm on untested hardware. We know the pad works, the UART protocol is stable, and users want this. That makes the architecture bets feel justified rather than reckless.

## Technical Details

**Backend Stack (FastAPI + PostgreSQL/TimescaleDB + MQTT + Redis + Firebase)**

- **FastAPI**: Async HTTP framework, built-in OpenAPI docs, Pydantic validation. Choice justified by: WebSocket support, async I/O for background tasks (alert processing), and tight integration with FastAPI-Users for auth.
- **PostgreSQL + TimescaleDB**: Relational data (users, devices, families) + time-series data (respiration samples). TimescaleDB hypertables compress time-series 10-20x vs vanilla Postgres. Rejected InfluxDB (separate database, operational overhead); rejected MongoDB (poor time-series querying).
- **Mosquitto MQTT**: Lightweight pub/sub for device → backend pipeline. Rejected Kafka (overkill for device count), accepted MQTT complexity because it scales better than HTTP polling for mobile-to-backend notifications.
- **Redis**: Alert deduplication (suppress identical alert < 5 min). Prevents FCM spam. Also caches JWT token blacklist (logout revocation).
- **Firebase Cloud Messaging**: Push notifications to Flutter. No SMS complexity, users expect mobile notifications. Tokens stored per-user, refreshed on login.

**ESP32 Firmware (BLE GATT Provisioning + MQTT)**

- **WiFiManager → BLE GATT**: Captive portal is POC convenience. Production: Flutter app communicates BLE GATT credentials service. ESP32 writes WiFi SSID/password to NVS. No hardcoded secrets in firmware. Users never see a captive portal.
- **WebSocket → MQTT**: POC dashboard talks WebSocket; production ESP32 talks MQTT to Mosquitto. Allows disconnected operation (buffering on device), reduces bandwidth (publish only on change, not polling), and enables multi-backend (future Android app, web dashboard, analytics engine all subscribe same topics).
- **PubSubClient library**: Proven Arduino MQTT client, ~10KB flash overhead. Will push us to ~82% flash utilization with BLE + MQTT + UART. Acceptable.

**Flutter Mobile App (BLE Provisioning + Realtime Dashboard + History + Alerts)**

- **BLE provisioning**: User opens app → scans for sleeppad.local BLE broadcast → user selects WiFi network + password in app → app writes to GATT credential service → ESP32 connects autonomously.
- **Realtime dashboard**: MQTT subscriptions via MQTTKit (Flutter package) for <500ms latency on LAN, ~2s on internet. Fallback to REST polling if MQTT unavailable.
- **History charts**: fl_chart for respiration trends, sleep score trends. Data fetched from backend REST API (/users/{id}/sessions) with pagination.
- **Alerts**: FCM notifications for abnormal respiration (< 8 or > 30 breaths/min), connection loss, battery low. Muted by time-of-day setting.
- **Family sharing**: Users invite family members via email → recipient joins device → shared access to alerts + history. JWT tokens scoped to device groups, not individual devices.

**Infrastructure (Docker Compose + Cloudflared Tunnel)**

- **Development**: `docker-compose.yml` with FastAPI, PostgreSQL, Mosquitto, Redis. Developers run `docker-compose up` and test locally. No cloud required.
- **Production**: Same services, TLS via cloudflared tunnel (no open ports, no nginx complexity). MQTT traffic proxied through tunnel on port 443. ESP32 connects via `mqtt://cloudflared-domain:443` with TLS.
- **Why cloudflared?** No port-forwarding setup, no DDoS risk, encrypted tunnel, DNS-01 challenge for free SSL. Rejected nginx (requires port 80/443 open, DDoS surface); rejected AWS/GCP (cost, learning curve, overkill for single user initially).

**Authentication & Security**

- **JWT tokens**: 30-day expiry (long enough for UX, short enough for leaked-token risk). Stored in Flutter secure storage (Keychain/Keystore).
- **Refresh tokens**: 90-day expiry. Stored in SQLite with encryption. Logout deletes both.
- **FCM token refresh**: Stored per-user with expiry. Backend validates FCM tokens on first use; refreshes on 401.
- **Device provisioning**: GATT credential service requires BLE pairing (implicit trust). No device key rotation initially (future work). Password reset via email OTP.

**Time-Series Data Strategy**

- **Hypertables**: One hypertable per device (e.g., `respiration_samples_device_001`). Automatic partitioning by time (daily chunks). Compression kicks in after 7 days (cold data).
- **Retention policy**: 2 years of historical data. Automatic cleanup via TimescaleDB jobs. Users can export CSV before deletion.
- **Query patterns**: Aggregations (hourly avg, daily min/max) materialized in separate `session_summaries` table for fast history queries. Real-time samples queried from main hypertable.

## What We Tried

1. **Single PostgreSQL table for time-series** → Would require custom partitioning, manual vacuuming. TimescaleDB handles this; decision was clear once we researched.

2. **Kafka for device pipeline** → Overkill for 10-100 devices initially. Would require separate infrastructure, operational knowledge. MQTT + Mosquitto simpler to deploy, scale later if needed.

3. **In-app BLE library options** (flutter_blue vs flutter_reactive_ble) → Chose flutter_reactive_ble (better error handling, active maintenance). flutter_blue is deprecated.

4. **FCM vs custom SMS notifications** → FCM won (free, mobile-native, less infrastructure). SMS is fallback for critical alerts if we add it.

5. **JWT 7-day vs 30-day expiry** → Settled on 30-day. Mobile UX expects infrequent login. 7-day would trigger re-auth every week (frustrating). Mitigated by short refresh token, secure storage, and logout revocation.

6. **HTTP polling vs MQTT for ESP32→Backend** → MQTT won. Allows stateful buffering (device queues samples if offline), reduces bandwidth, enables multi-subscriber. HTTP is REST API fallback for other systems.

## Root Cause Analysis

Why this architecture? Because the POC exposed two hard truths:

1. **WiFiManager + WebServer doesn't scale.** Users don't want to type credentials into a captive portal. Every device needs provisioning, and factory defaults can't ship WiFi SSID hardcoded. BLE is the only path forward—every iOS/Android device has it.

2. **WebSocket from ESP32 to browser doesn't scale.** If the browser refreshes, device loses connection. If user has multiple tabs, duplicate streams. MQTT decouples device from client, enables offline buffering, and allows backend to re-publish data to multiple consumers (alerts engine, analytics, history API).

3. **Single-user POC becomes multi-tenant fast.** We must design for: multiple devices per user, family sharing, per-device credentials, and per-user alert settings. This complexity is *in the foundation*, not bolted on later.

The architecture choices reflect these constraints:
- BLE + MQTT replaces WiFiManager + WebSocket (scalable provisioning + decoupled data flow)
- TimescaleDB replaces simple Postgres (efficient time-series queries)
- Redis + FCM replaces in-app alerts (backend can push to offline devices)
- Cloudflared replaces open ports (security, simplicity, no DDoS surface)

## Lessons Learned

1. **POC-to-platform transition requires re-architecting, not refactoring.** The WiFiManager + WebServer approach is fundamentally unsuitable for production, even if the code is clean. Don't try to "evolve" it—replace it.

2. **Choose boring, proven technology.** FastAPI (Starlette + Pydantic), PostgreSQL, Mosquitto, Firebase—all battle-tested, well-documented, low-surprise. Rejected trendy choices (Rust backend, NoSQL, custom push service) because they add risk without commensurate benefit.

3. **Infrastructure decisions are irreversible.** Once we commit to MQTT, changing to HTTP polling requires firmware updates to thousands of devices (if we scale). Cloudflared choice locks us in unless we're willing to rewrite deployment. Make these decisions slowly, validate assumptions, then move fast.

4. **Time-series data handling *cannot* be afterthought.** Building time-series queries on vanilla Postgres is painful (slow aggregations, manual partitioning, bloated indexes). TimescaleDB adds minimal operational overhead and prevents future pain. Worth the upfront cost.

5. **Family sharing architecture is simpler with JWT scoping.** Don't build ad-hoc permission checks. Scope JWT tokens to device *groups* at auth time (claim: `device_groups: [group_1, group_2]`). Rest of backend reads claim once and knows what user can access. Avoids N+1 permission queries.

6. **Alert deduplication via Redis is non-negotiable.** Without it, a stuck sensor reading generates 100 FCM notifications. With Redis (TTL 5 min per alert hash), one notification per alert event. Users won't uninstall the app.

## Next Steps

**Immediate (Phase 1-2):**
1. Set up Docker Compose stack locally (PostgreSQL + TimescaleDB + Mosquitto + Redis).
2. Migrate ESP32 firmware: Remove WebServer, add PubSubClient + BLE GATT provisioning.
3. Implement FastAPI backend skeleton: Auth (JWT), device registration, MQTT listener.
4. Start Flutter app: BLE provisioning flow, MQTT subscription, basic dashboard.

**Subsequent (Phase 3-5):**
5. Implement history charting + family sharing in Flutter.
6. Implement alert engine in backend (Redis dedup, FCM dispatch).
7. Deploy to cloudflared tunnel (test in staging first).

**Risk mitigation:**
- Test BLE GATT provisioning on at least 3 devices (iOS, Android, before shipping firmware).
- Load-test MQTT with simulator before accepting real devices.
- Document firewall rules for cloudflared tunnel (future ops person will thank us).
- Version GATT service (future firmware may need breaking changes; versioning allows graceful fallback).

---

**Owner**: Michael  
**Plan reference**: `/Users/michaelphan/projects/sleep-pad/plans/260420-2039-sleep-pad-full-platform/`  
**8-Phase Plan**: Phase 1 (Setup), Phase 2 (ESP32 BLE+MQTT), Phase 3 (FastAPI Backend), Phase 4 (Flutter Provisioning), Phase 5 (Realtime Dashboard), Phase 6 (History + Alerts), Phase 7 (Family Sharing), Phase 8 (Testing + Deployment)
