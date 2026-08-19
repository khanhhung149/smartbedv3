# Phase 07: Flutter Home + History Charts — WebSocket Lifecycle Nearly Shipped Broken

**Date**: 2026-04-21 15:30
**Severity**: High (caught at review, not production)
**Component**: Flutter UI (home_screen, history_charts, realtime_provider)
**Status**: Resolved

## What Shipped

Realtime dashboard + 7-day history with interactive charts. 16 new Dart files + 4 modified. Pixel-matched `sleep_pad_home_final_sync` + `sleep_history_synced` from Stitch. fl_chart for charts, web_socket_channel for realtime. Build: `flutter analyze` 0 issues, `flutter build web --debug` SUCCESS.

## The Brutal Truth

A single fullstack agent completed the entire phase in ~7 minutes of background compute — lean context, clean first pass. But the code review caught four clustered WebSocket bugs that would have shipped silent and broken. The frustration: none of them leave obvious error traces. They're state-machine gotchas that only surface after user session lifecycle patterns (logout, device switch, re-login) that QA doesn't exercise in 30 seconds of smoke testing. A user switches devices, the app silently leaks channels and ghosted reconnects with stale JWT until eventual socket close. Gone unnoticed for days in a POC.

## Technical Details

**Caught bugs in `realtime_provider.dart` + `home_screen.dart`:**

1. **No `ref.onDispose` teardown** → channel never closed on logout/device switch → infinite reconnect loop with dead socket
2. **JWT read once at build** → stale token persisted across re-login → 1008 socket close only triggered blind retry, never fetched fresh token
3. **Backoff delay reset inside try block** → long-lived connection errors eventually used inflated delay (30s+) from previous attempt
4. **`streamAsync.whenData` + `addPostFrameCallback` in build** → any unrelated rebuild cached the frame callback → 60-point sparkline buffers accumulated duplicates

Fix: cancellation flag + `ref.onDispose`, JWT re-read at every reconnect, backoff reset on first successful frame, `ref.listen` pattern instead of post-frame setState. ~20 minutes.

## Root Cause

Lifecycle management in Riverpod async providers is non-obvious. Stale-token retry loops look "correct" (reconnect on error) without enforcing token freshness. Post-frame callbacks nested inside build are a footgun for accumulation. Code review (not developer intuition) caught all four.

## Lessons

- **WebSocket + auth = defensive programming zone.** Token refresh and cleanup patterns must be explicit and tested.
- **Sparkline state shouldn't live in parent** — keying with `ValueKey(deviceId)` resets automatically. `didUpdateWidget` is a smell.
- **Backend limitations are OK at POC stage.** Disturbance chart (stacked bars, missing `/data/history` schema) and trend badges (no delta field) are flagged, not blocking.

## Next Steps

Phase 08 (Alerts + Sharing + FCM + Settings — last phase).
