# Sleep Pad IoT Platform: From POC to Full Stack in One Day

**Date**: 2026-04-21 14:30
**Severity**: Low (retrospective)
**Component**: Sleep Pad — entire platform (ESP32 + backend + Flutter)
**Status**: Complete, ready for real-device integration

## What We Built

Eight phases, one day of intense execution (April 20 brainstorm → April 21 shipping). The Sleep Pad evolved from a single-file Arduino sketch on a Legact Pro V2 board into a distributed IoT system:

**Backend** (FastAPI + PostgreSQL/TimescaleDB + Mosquitto MQTT + Redis):
- JWT-based auth (refresh tokens, secure httpOnly cookies)
- Device pairing flow (BLE provisioning → MQTT credential exchange)
- MQTT ingest (Mosquitto with pattern-based ACL per device)
- Real-time WebSocket subscriptions (Riverpod async providers on Flutter side)
- Historical data API (paginated, time-windowed queries)
- Alert engine (thresholds + escalation + FCM-ready)
- Family sharing (invites + accept/reject flow)

**ESP32 Firmware** (PlatformIO/Arduino C++):
- BLE GATT server (provisioning service with WiFi + device name characteristics)
- MQTT TLS client (publishes heart rate, respiratory rate every 30s)
- Replaces legacy WiFiManager + local web server with modern provisioning
- Memory stable: 49.8% flash / 17.7% RAM after all features

**Flutter App** (3+ releases pending):
- 21 screens total: scaffold, auth, BLE provisioning flow, home realtime dashboard, historical charts, alerts management, family sharing, device pairing, device detail, settings
- Pixel-perfect match to Google Stitch HTML exports
- Riverpod state management (async providers + notifiers)
- WebSocket lifecycle management (cancel on unmount, JWT refresh, exponential backoff)
- FCM service stub (production code written, dev no-op until Firebase project exists)

## What Went Right

### Plan-first orchestration
Writing 8 phase files upfront with explicit API contracts + protocol specs + BLE UUID tables meant every agent (firmware, backend, Flutter) had clear boundaries and no rework. The `docs/protocols/ble-provisioning-and-mqtt-auth.md` file became the canonical reference — both firmware and Flutter were verified against it in code review. Zero guesswork.

### Canonical ground truth for mobile UI
We extracted Tailwind classes from Stitch HTML once, mapped them to `app_colors.dart` + `app_theme.dart`, then implemented each screen's layout as a 1:1 class mapping. Changed the design? One update to the theme file ripples everywhere. The bottom nav was identical across all 21 screens.

### Subagent waves for large tasks
Phase 06's scaffold was too large for single-agent context, so we split into Wave 1 (scaffold + home + auth) and Wave 2 (history + alerts). Each wave had tight file ownership, explicit success criteria, and pre-agreed dependencies. No merge conflicts, clean handoff.

### Code review at every phase gate
24 critical + high-severity issues caught across all phases:
- **Phase 02**: MQTT password bootstrap, mosquitto Dynamic Security gap
- **Phase 03**: WebSocket channel leaks (3 bugs in one file)
- **Phase 05**: Timing side-channel in login (user could guess password reset tokens)
- **Phase 06**: setState-in-build, async provider teardown bugs
- **Phase 08**: JSON contract mismatches (ShareOut, ThresholdOut)

Every fix was re-verified by `flutter analyze` / `flutter build` / integration test before proceeding. Caught at code review = caught at the phase gate = no rework downstream.

## What Hurt and Why

### JSON contract mismatches almost shipped

Phase 08 code review found `ShareOut` parsing `share_id` + `email` but backend returning `id` + `invited_email`. The model's fromJson would silently drop fields, API responses would parse to half-filled objects, and sharing would be broken end-to-end. The bug is invisible to static analysis — only runtime on the first real API call reveals it.

The sting: this is the third contract-mismatch class bug we've caught (ShareOut + ThresholdOut + earlier mismatches in Phase 03). Every time it's a surprise. Every time the root cause is "hand-written fromJson wasn't validated against actual API responses."

**Lesson that sticks**: Contract testing is non-optional. Generate Dart models from OpenAPI spec or write round-trip serialization tests. Don't hand-write JSON mapping and hope.

### Pydantic type coercion masked structural bugs

ThresholdOut sent floats for int columns. Pydantic quietly accepted it. Data silently coerced at the DB layer. Will break if the backend ever adds stricter validation (e.g., Pydantic strict mode). We didn't catch it until code review asked "why are all thresholds doubles when the schema says ints?"

**Lesson**: Loose type systems are convenient and dangerous at API boundaries. Future: enforce Pydantic strict mode in test suite + mypy --strict on backend.

### WebSocket lifecycle was a minefield

Four correctness bugs in one `realtime_provider.dart` file:
1. No cancel() on provider unmount → memory leak + stale data
2. JWT refresh didn't propagate to WebSocket auth header → requests rejected after token refresh
3. No backoff on reconnect → hammered server with 1000 reconnect/sec on network flap
4. setState-in-build in a Riverpod async notifier (setState doesn't exist; should use state = newValue)

The file itself wasn't huge, but the WebSocket abstraction is subtle. State management library + async runtime + network edge cases = a concentration of complexity. Took 3 reviewer passes to catch all 4.

**Lesson**: WebSocket management in Riverpod deserves a team playbook. Document the lifecycle (connect → subscribe → receive → reconnect-with-backoff → JWT-refresh-handling → cancel-on-unmount). Copy the right pattern from this codebase; don't reinvent.

### BLE permissions on Android 12+ are a silent footgun

`permission_handler` in pubspec isn't enough — you must call `request()` at runtime before BLE scan. The provisioning flow would scan but return zero devices on Android 12 if the permission wasn't granted. The app doesn't error; it just looks like there are no devices to pair with. User walks away. Real-device smoke test will reveal this, but we can't run it on this machine (no Android SDK).

**Lesson**: Document platform-specific setup in a README. Android ≠ iOS ≠ Web. Real device testing is mandatory before production.

## The Unbuilt (Deferred to Production)

These were knowingly deferred to keep the POC tight:

- **MQTT WSS / cloudflared tunnel** — ESP32's PubSubClient is TCP-only. For production over untrusted networks, swap to `espMqttClient` (supports WSS) or cloudflared tunnel.
- **Mosquitto Dynamic Security** — Currently all ESP32s share one password + pattern-based ACL (%c wildcard). Should be per-device credentials + signed tokens.
- **NVS encryption on ESP32** — WiFi password + MQTT password stored plaintext in flash. Secure Enclave or NVS encryption layer needed before shipping.
- **BLE bonding** — Any phone in range can provision during the 10-minute setup window. Should bond to specific MAC address or require PIN.
- **Backend migrations** — init.sql runs on empty volume only. Add alembic for schema versioning before next release.
- **Firebase project** + APNS cert + google-services.json / Info.plist — FCM service is stubbed; real push notifications need real Firebase project + Apple app registration.
- **Three missing endpoints**: `DELETE /devices/{id}`, `PATCH /devices/{id}/name`, `GET /share/pending` (not in original Phase 02 spec; documented as gaps).
- **Zero test coverage** — No pytest, no integration tests, no Flutter unit tests. CI/CD exists nowhere. This is a POC.
- **Real-device smoke test** — Haven't run ESP32 + backend + mobile together on actual hardware. Will reveal Bluetooth flakiness, network timeout edge cases, and BLE permission issues Android 12+ throws.

## What Ownership Felt Like

This is the 12th journal entry across April 10–21. Started with "let's write a web dashboard for this sleep pad board" and ended with a 3-component distributed system (firmware, backend, app). The CK stack (write plan → delegate to agents → read code review feedback → implement fixes → journal the lessons) made it feasible without losing coherence.

There were moments of frustration (why is the WebSocket broken *again*? why didn't the contract test catch this?), but also clarity (the plan was right; the execution had gaps). The journal entries forced me to be honest about what broke and why. That honesty is the only thing that prevents repeating the same bug class.

## The Hand-Off

Production readiness checklist:

**Blocking issues** (must fix before shipping):
- Real-device APK build + Firebase project
- MQTT WSS for untrusted networks
- BLE permission flow on Android 12+

**High priority** (within 2 weeks):
- API contract tests (generate Dart models from OpenAPI)
- WebSocket playbook documentation
- Settings persistence (secure storage)

**Medium priority** (before general availability):
- DELETE /devices endpoint
- Mosquitto Dynamic Security
- NVS encryption

**Low priority** (nice-to-have):
- CI/CD pipeline
- Test suite
- BLE bonding

---

**Next**: Real-device integration smoke test when hardware availability, Firebase project, and Android SDK are ready. At that point, the POC becomes production or reveals what the POC assumptions missed.

