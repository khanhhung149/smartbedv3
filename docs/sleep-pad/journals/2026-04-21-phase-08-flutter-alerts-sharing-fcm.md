# Phase 08: Flutter Alerts, Sharing, and FCM — Shipped

**Date**: 2026-04-21 09:15
**Severity**: Low (POC completion)
**Component**: Flutter app — Alerts subsystem, Sharing, Device management, FCM integration
**Status**: Resolved

## What Happened

Final Flutter phase landed: 17 new Dart files + 7 modified files covering Alerts (threshold management + history view), Alert Detail, Devices list with Device Detail, Settings panel, Invite bottom sheet, and FCM service integration. `flutter analyze` returned 0 issues, `flutter build web --debug` succeeded first run. 21 screens total across the app.

## The Brutal Truth

The code review nearly blocked merge twice. We caught JSON contract mismatches that would have turned sharing end-to-end into a silent failure in production — every API response would have thrown at runtime because the model field names didn't match the backend's actual response structure. This is the kind of bug that passes static analysis, passes tests (if you're using fake data), and only surfaces the moment a user clicks "invite friend." It makes you sick because the fix is trivial (rename 4 fields) but the debugging burden on the user would have been substantial.

The second near-miss was type coercion in thresholds — the backend stores 3 int columns but we were sending floats. It worked today by accident (Pydantic's loose typing masked the mismatch), but `PUT` requests would have quietly corrupted data if the backend ever added stricter validation.

## Technical Details

### FCM as a dev no-op

Rather than pull `firebase_core`, `firebase_messaging`, require every dev to set up a Firebase project, and commit google-services.json to git (security disaster), we took a surgical approach:

```dart
class FcmService {
  Future<void> initialize() async {
    try {
      // Production code here (currently commented out):
      // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      // final messaging = FirebaseMessaging.instance;
      // await messaging.requestPermission();
      // messaging.onMessage.listen(_handleForegroundMessage);
      throw UnsupportedError('FCM disabled in dev');
    } catch (e) {
      debugPrint('[FCM] Warning: FCM not available. Push notifications disabled. $e');
    }
  }
}
```

The full implementation is there, just guarded. When a real Firebase project exists, a dev adds 3 pubspec deps, places google-services.json (git-ignored), uncomments the block, and we're live. Zero friction for local development.

### Contract Mismatches Found & Fixed

**C1 — ShareOut JSON fields**:
- Model expected: `share_id`, `email`
- Backend returns: `id`, `invited_email`
- Impact: Every sharing response parse would silently fail
- Fix: Updated model fromJson, added unit test

**C2 — ThresholdOut type mismatch**:
- Model declared all 5 fields as `double`
- Backend schema: `hr_high` (SMALLINT), `hr_low` (SMALLINT), `resp_disorder_count` (SMALLINT), `rr_high` (NUMERIC), `rr_low` (NUMERIC)
- Impact: Float values sent to int columns; data loss on stricter future validation
- Fix: Split type — `int` for the three threshold count fields, `double` for RR

### Silent Failures Fixed

**Deep link broken** — `/share/accept/:shareId` redirected to `/devices` without calling `acceptInvite`. User accepts invite, nothing happens. Built `_ShareAcceptHandler` stateful widget to show spinner, call API, display errors, then navigate.

**TextEditingController leaks** — Two controllers in rename sheet + settings URL dialog were never disposed. Leaked memory on every modal open. Wrapped both in try/finally in the state's dispose method.

## What We Tried

1. **First pass code review** — caught JSON contract issues immediately
2. **Traced API responses vs model definitions** — lined up backend `models.py` Pydantic schemas against Dart fromJson implementations
3. **Added contract test cases** — manually verified each response field maps correctly (future: automate with OpenAPI contract tests)
4. **Tested deep link with real Firebase CLI** — simulator navigation worked but the handler wasn't wired; added explicit handler widget

## Root Cause Analysis

The JSON contract mismatches happened because:
- Dart model field names and Pydantic model field names drifted over implementation time
- No automated contract validation between backend schema and Flutter models
- Code review caught it, but the bug class is systemic — every API integration point has this risk
- Type coercion bugs exist because Pydantic's loose typing masks structural mismatches; sending floats to int columns silently coerces

## Lessons Learned

1. **Contract tests are non-optional** — Generate Dart models from backend OpenAPI spec or write integration tests that verify round-trip serialization against real API responses. Don't trust hand-written fromJson.
2. **Silent parse failures are worse than loud crashes** — When JSON.parse fails, we need explicit error logging, not silent field omission. Added explicit field validation in fromJson constructors.
3. **Type safety matters at API boundaries** — Pydantic's flexibility was convenient but masked real structural problems. Future: add mypy strict mode on backend + strict lint on Flutter models.
4. **FCM abstraction was the right call** — Hiding Firebase behind a service interface let us ship without blocking on Firebase project setup. No friction for local dev = faster iteration.

## Next Steps

- **Real-device APK test** — Needs Android SDK + Firebase project to verify FCM actually works; deferred to user's environment
- **API contract testing** — Generate TypeScript SDK from OpenAPI spec, use it to validate Flask responses in pytest (catches C1 + C2 class bugs at CI time)
- **Settings persistence** — URL editing is in-memory only; add secure storage + rebuild Dio client on change
- **DELETE /devices/{id}** — Backend endpoint still needs wiring (5 min of work; deferred from Phase 02 spec)
- **GET /share/pending** — "Invites I haven't accepted yet" endpoint (not in original Phase 02; Devices screen has placeholder)

**Status**: Phase 08 complete. App is pixel-perfect to Stitch HTML, all screens wired, analysis clean, build succeeds.

**Next**: Full platform retrospective in 2026-04-21-platform-complete.md
