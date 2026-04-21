# Phase 07 Review — Flutter Home + History

Scope: 16 new files + 4 modified under `flutter_app/lib/`. `flutter analyze` clean, `flutter build web --debug` succeeded. Fully read: home_screen, realtime_provider, sleep_line_chart, status_badge, selected_device_provider. Spot-checked remainder.

## CRITICAL

### C1. WebSocket provider never tears down the channel on unwatch
`realtime_provider.dart:14-48` — `_connectWithRetry` is an infinite `while(true)` loop. When a StreamProvider.family entry becomes unwatched (user logs out, nav pops, device switches), Riverpod cancels the subscription, which stops iteration, but the **currently-open `channel.sink.close()` only runs if an inner throw unwinds**. In the `yield`-consumer-cancelled path, the `await for` is abandoned mid-stream without the `finally` running reliably against the same channel, and the outer `while(true)` keeps burning backoff timers even after dispose because there's no `ref.onDispose` registered. Verify by watching network tab when switching devices — expect leaked WS connections + ghost reconnect loops. Fix: wrap the generator in `ref.onDispose(() => channel?.sink.close())` and make the loop exit when a cancellation token flips.

### C2. Stale JWT on reconnect (logout race)
`realtime_provider.dart:52-61` — token is read once at provider-build time and then `_connectWithRetry` reuses it forever across reconnects. If the user logs out and re-logs in as a different account, the WS keeps reconnecting with the old token (until the whole provider is re-subscribed). On 401 close, the code treats it as a transient error and retries indefinitely with the stale token. Fix: on disconnect, `ref.read(authProvider)` again before reconnect; on WS close code 1008/4401, `ref.invalidateSelf()` or surface auth error instead of looping.

### C3. Backoff does not actually reset after a successful connect
`realtime_provider.dart:19-47` — `delaySeconds = 1` is reset only on the "stream ended cleanly" path (line 35). If the stream ends via a thrown `WebSocketChannelException` mid-session after hours of connection, the previously-increased `delaySeconds` (up to 30) still applies on the next retry cycle because the reset line is skipped by the catch. Fix: reset `delaySeconds = 1` inside the successful-first-frame path (e.g., on first yielded frame), not on clean-exit.

### C4. `setState` during build via `streamAsync.whenData` post-frame callback
`home_screen.dart:175-182` — every rebuild schedules a `addPostFrameCallback` that calls `setState`, which triggers another rebuild, which schedules another callback. Combined with a 1 Hz WS stream this is fine, but whenever Riverpod rebuilds for any unrelated reason (e.g., a parent provider change), the callback fires with the last cached `data` and mutates `_hrHistory`/`_rrHistory` again — the sparkline will accumulate duplicate points. Fix: use `ref.listen(realtimeProvider(...), (prev, next) { next.whenData(...) })` in `initState`/build and drop `whenData` from the build method. This is the canonical Riverpod pattern for side-effects on stream events.

## HIGH

### H1. Sparkline buffer survives across device switches
`home_screen.dart:31-44` — `_hrHistory`/`_rrHistory` live on `_HomeScreenState`, not keyed by `deviceId`. When the user switches devices via the bottom sheet, `selectedDeviceProvider` emits and `_HomeContent` rebuilds with a new `deviceId`, but the buffers are untouched and will now visually splice readings from device A into device B's sparkline until 60 s pass. Fix: reset both lists when `device.deviceId` changes (e.g., didUpdateWidget guard on `_HomeContent` or move buffers into a StateNotifier keyed by deviceId).

### H2. Status-hero subtitle shows "Signal lost" even on first frame before WS ever connects
`home_screen.dart:184,206-208` — `isConnected = streamAsync is! AsyncError` is true during `AsyncLoading`, so the initial subtitle is correctly "active". But `statusCode` is null initially → renders `_defaultStatus` ("No Signal") with subtitle "Device active & monitoring". The two mismatched phrases read oddly. Minor but visible on every cold start. Fix: gate subtitle on `_latest != null`.

### H3. `sleep_line_chart.dart` X-axis labels are positional, not time-aware
`sleep_line_chart.dart:148-194` — comment on line 164 acknowledges "not time-aware here; caller passes epoch seconds as X values" but callers in `history_chart_panel.dart:79-83` pass `i.toDouble()` (array index). Week view will show "Mon/Thu/Sun" regardless of the actual `bucket` timestamps returned by the API. If the backend emits 8 points or a partial week, labels will be wrong. Fix: accept `List<DateTime> xLabels` or compute the label from `points[idx].bucket`.

### H4. `_DisturbanceBarChart` grid line at every `maxY/2` with `maxY < 4` fallback of 10 produces an odd scale
`history_chart_panel.dart:190-205` — when all `respDisorder` are 0, `maxY = 2`, then bumped to 10, giving gridlines at 0, 5. Bars render at 0 → empty plot area with "5" on Y axis looks broken. Consider showing an empty-state message when `totalDisturbances == 0`.

## SUGGESTIONS

- **File size**: home_screen 429 / history_screen 385 / history_chart_panel 331 all exceed the 200-LOC rule. Private sub-widgets are colocated, which is fine for readability, but the `_buildAppBar` function is duplicated near-verbatim between home_screen and history_screen — extract a `TranslucentAppBar` widget (DRY).
- `metric_card.dart:48` — the "subtle glow" circle at `-24, -24` will be clipped by the parent `Container`'s rounded corners implicitly only if a `ClipRRect` wraps it. Without one, it may paint outside bounds on some rasterizers. Wrap the Stack in `ClipRRect(borderRadius: 16)` to match HTML `overflow-hidden`.
- `selected_device_provider.dart:11-45` — `AsyncNotifier.build()` calls `DeviceRepository().getMyDevices()` on every auto-dispose rebuild. For a cold path this is fine, but if the provider is ever reconstructed mid-session it re-hits the API. Not a leak; flagging as a cost consideration.
- `data_repository.dart:51` — `e.response?.data?['detail']?.toString()` assumes `data` is a Map. For HTML error pages it would throw `NoSuchMethodError`. Wrap in `try/catch` or check `data is Map`.
- `home_secondary_metrics.dart:34` — displays `sdata` as a percentage but the RealtimeData comment says "raw signal amplitude (percentage displayed as-is)". Verify backend actually returns 0–100; if it returns raw ADC counts the "%" suffix will mislead.
- `history_chart_panel.dart:145-268` — consider hoisting `_xLabel` to share implementation with `sleep_line_chart._bottomLabel` (DRY).

## Positive

- Clean separation: repository / provider / screen / widget layers.
- `status_badge.dart` correctly maps all 8 ESP32 status codes with sensible colors and icons; default "No Signal" is a nice fallback.
- Error states in history_screen (error, empty, loading) are well-designed.
- fl_chart gradient fill wiring in `SleepLineChart` is correct; tooltip wired via `LineTouchData`.
- Empty-list guards in `Sparkline` (line 22) and `SleepLineChart` (line 31) prevent crashes.
- Device selector persists via secure storage with proper `aOptions`.

## Unresolved Questions

1. Does the backend WS close code on auth failure emit 1008, 4401, or 1006? Affects C2 handling.
2. Is `sdata` sent as % or raw? Phase-07 report didn't verify against phase-03 response schema.
3. Should `selectedDeviceProvider` auto-refresh when a new device is paired in the Devices tab (Phase 08)?

**Status:** DONE_WITH_CONCERNS
**Summary:** Phase 07 compiles and renders, but the WS provider has three correctness bugs (no teardown, stale token, incorrect backoff reset) that will cause resource leaks and auth confusion in production. `setState`-in-build pattern risks duplicate sparkline points. Sparkline buffer leaks across device switches. UI fidelity and error states are solid.
**Concerns/Blockers:** C1–C4 should be fixed before this ships. H1–H4 are worth addressing in a follow-up.
