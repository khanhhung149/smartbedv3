# Phase 07 Implementation Report — Flutter Home Dashboard & History Charts

## Files Created (+ lines)

| File | Lines |
|------|-------|
| `lib/features/data/models/realtime_data.dart` | 46 |
| `lib/features/data/models/history_response.dart` | 57 |
| `lib/features/data/data_repository.dart` | 53 |
| `lib/features/data/providers/selected_device_provider.dart` | 45 |
| `lib/features/data/providers/realtime_provider.dart` | 61 |
| `lib/features/data/providers/history_provider.dart` | 15 |
| `lib/features/home/home_screen.dart` | 429 |
| `lib/features/home/home_secondary_metrics.dart` | 121 |
| `lib/features/home/device_selector_sheet.dart` | 204 |
| `lib/features/history/history_screen.dart` | 385 |
| `lib/features/history/history_summary_strip.dart` | 163 |
| `lib/features/history/history_chart_panel.dart` | 331 |
| `lib/shared/widgets/metric_card.dart` | 144 |
| `lib/shared/widgets/sparkline.dart` | 60 |
| `lib/shared/widgets/sleep_line_chart.dart` | 194 |
| `lib/shared/widgets/status_badge.dart` | 169 |

## Files Modified

| File | Change |
|------|--------|
| `lib/app.dart` | Replaced `_HomeStub`, added `/home` → `HomeScreen`, added `/history` → `HistoryScreen` |
| `lib/core/constants.dart` | Added `wsBaseUrl` getter + `lastDeviceIdKey` constant |
| `pubspec.yaml` | Added `fl_chart: ^0.69.0`, `web_socket_channel: ^2.4.5` |

## Pixel-Correctness Notes

- **Colors**: All hex values match HTML verbatim. HR accent = `#5EE7DF` (primaryContainer), RR accent = `#B490F5` (lavender from RR SVG stroke — not in AppColors; added inline as `const Color(0xFFB490F5)`). No new AppColors entries needed since lavender is only used in RR chart/sparkline contexts.
- **App bar**: Translucent BackdropFilter blur matches `backdrop-blur-2xl`, `bg-[#101419]/70`. Device selector chip matches `bg-[#1a2e2f]`, `border-[#234241]`, `rounded-full` exactly.
- **Status hero**: Icon circle size 64×64, glow boxShadow, gradient overlay — matches HTML layout.
- **Metric cards**: 60sp font-black, 60px number, 18sp unit, sparkline at bottom with 70% opacity — matches HTML bento cards.
- **Secondary tiles**: `rounded-[20px]` → `BorderRadius.circular(20)`, p-5 → padding 20 — exact match.
- **Tab bar**: `border-b-2 border-primary-container` active indicator, `text-[#8B96A5]` inactive — matches HTML segmented nav.
- **Bottom nav**: Reuses `AppBottomNav` unchanged; Home index=0, History index=1.

## Deviations from Stitch HTML

1. **Sleep disturbances bar chart**: HTML shows stacked Movement + Snore + Resp bars. Backend `/history` only returns `resp_disorder` per point — Movement and Snore aggregates not available. Single-series coral bar chart used; legend updated to show Resp only. Tracked for Phase 08 / backend enhancement.
2. **Summary strip trend badges**: HTML shows `↑2%` / `↓1%` trend badges. Backend doesn't return previous-period delta — badges omitted until backend adds that field. `trendText: null` parameter available for when backend adds it.
3. **Home screen grid layout**: HTML uses `grid-cols-1 md:grid-cols-2` — Flutter uses `LayoutBuilder` breakpoint at 480px for same responsive behavior.
4. **Sparkline**: HTML shows a custom SVG heartbeat waveform. fl_chart `LineChart` with `isCurved: true` used as closest match.

## WebSocket Lifecycle Design

- `realtimeProvider` is a `StreamProvider.family<RealtimeData, deviceId>`.
- `_connectWithRetry` runs an infinite loop with exponential backoff (1s → 2s → 4s, max 30s).
- Channel is closed in the `finally` block on each iteration — no socket leaks.
- Provider disposal (when widget unmounts or device changes) cancels the stream automatically via Riverpod's `ref.onDispose` semantics on `StreamProvider`.
- Ping frames `{"type":"ping"}` are filtered with `continue` inside the `await for` loop.
- JWT is read from `authProvider` state first; falls back to `AuthStorage.readToken()` if state is null (cold start).
- Offline banner shown when `streamAsync is AsyncError`.

## fl_chart Configuration

| Chart | Type | Config |
|-------|------|--------|
| HR sparkline | `LineChart` | `isCurved: true`, color `#5EE7DF`, `belowBarData` gradient 15% opacity, no axes, no dots |
| RR sparkline | `LineChart` | Same config, color `#D4BBFF` (secondary) |
| History HR | `LineChart` | `isCurved: true`, gradient fill 30%→0%, left+bottom axis labels, touch tooltip |
| History RR | `LineChart` | Same, color `#B490F5` |
| Sleep disturbances | `BarChart` | Single rod per group, coral `#FF7F50`, rounded top corners, dynamic bar width by point count |

## Build Output

```
flutter analyze  → No issues found!
flutter build web --debug → ✓ Built build/web
```

WASM dry-run warnings are pre-existing from `flutter_secure_storage_web` (Phase 06 dep), not Phase 07 code.

---

Status: DONE_WITH_CONCERNS
Summary: All Phase 07 screens implemented — Home realtime dashboard with WS stream + History charts with fl_chart. `flutter analyze` clean, `flutter build web --debug` succeeds.
Concerns: (1) Disturbance bar chart uses single series (resp_disorder only) — backend doesn't expose Movement/Snore aggregates per history bucket. (2) Trend percentage badges omitted from summary strip — backend doesn't return previous-period delta. Both are backend gaps, not Flutter gaps.
