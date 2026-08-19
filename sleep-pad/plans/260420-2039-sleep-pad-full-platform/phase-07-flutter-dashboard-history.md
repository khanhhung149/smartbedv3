---
phase: 07
status: completed
priority: high
effort: large
sub_project: flutter
blockedBy: [phase-06]
---

# Phase 07: Flutter App — Home Dashboard & History Charts

## Overview

Home screen with realtime data via WebSocket (heart rate, respiration rate, status badge, SDATA/PDATA). History screen with day/week/month tabs and fl_chart line charts.

## Requirements

- WebSocket client connecting to `ws://{host}/ws/{device_id}?token={jwt}`
- Home screen: realtime HR, RR, status badge, SDATA, PDATA — updates every second
- Auto-reconnect WebSocket on disconnect
- History screen: 3 tabs (Day/Week/Month), line chart per metric (HR, RR, resp_disorder)
- fl_chart LineChart with smooth curves, dark theme styling
- Loading/empty states

## Home Screen Design

```
┌─────────────────────────────────┐
│  SleepPad  [device name]  [●online]│
├─────────────────────────────────┤
│  STATUS: SLEEP                  │
│  ┌──────────┐  ┌──────────┐    │
│  │  ❤️  68  │  │  🌬  14  │    │
│  │  Heart   │  │  Resp    │    │
│  │  Rate    │  │  Rate    │    │
│  └──────────┘  └──────────┘    │
│  SDATA: 12    PDATA: 8         │
│                                 │
│  [Last update: 0.5s ago]        │
└─────────────────────────────────┘
```

## History Screen Design

```
┌─────────────────────────────────┐
│  [Day] [Week] [Month]           │
├─────────────────────────────────┤
│  Heart Rate                     │
│  ╭────────────────────────╮    │
│  │  fl_chart LineChart    │    │
│  ╰────────────────────────╯    │
│  Respiration Rate               │
│  ╭────────────────────────╮    │
│  │  fl_chart LineChart    │    │
│  ╰────────────────────────╯    │
│  Resp. Disorder Events          │
│  ╭────────────────────────╮    │
│  │  fl_chart BarChart     │    │
│  ╰────────────────────────╯    │
└─────────────────────────────────┘
```

## App Structure (additions)

```
lib/features/
├── home/
│   ├── home-screen.dart           ← scaffold, WS connection lifecycle
│   ├── realtime-data-card.dart    ← HR + RR big cards
│   ├── status-badge.dart          ← color-coded status pill
│   └── realtime-provider.dart     ← Riverpod: WS stream → SecData state
├── history/
│   ├── history-screen.dart        ← DefaultTabController (Day/Week/Month)
│   ├── history-chart-panel.dart   ← 3 charts per tab
│   ├── history-repository.dart    ← GET /data/{id}/history?range=...
│   └── history-provider.dart      ← Riverpod: async fetch per tab
└── shared/
    └── widgets/
        ├── metric-card.dart        ← reusable big-number card
        └── sleep-line-chart.dart   ← fl_chart wrapper with dark theme
```

## WebSocket Provider

```dart
// realtime-provider.dart
final realtimeProvider = StreamProvider.family<SecData, String>((ref, deviceId) async* {
  final token = await ref.read(authStorageProvider).read();
  final uri = Uri.parse('ws://$host/ws/$deviceId?token=$token');
  final channel = WebSocketChannel.connect(uri);
  await for (final msg in channel.stream) {
    yield SecData.fromJson(jsonDecode(msg));
  }
});
```

Auto-reconnect: wrap in retry loop with 2s delay on error.

## fl_chart Configuration

```dart
// sleep-line-chart.dart
LineChart(
  LineChartData(
    backgroundColor: Colors.transparent,
    gridData: FlGridData(show: true, drawVerticalLine: false),
    titlesData: FlTitlesData(
      bottomTitles: AxisTitles(sideTitles: SideTitles(
        showTitles: true,
        getTitlesWidget: (value, _) => timeLabel(value, range),
      )),
      leftTitles: AxisTitles(...),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    ),
    lineBarsData: [
      LineChartBarData(
        spots: dataPoints,
        isCurved: true,
        color: Colors.tealAccent,
        barWidth: 2,
        dotData: FlDotData(show: false),
        belowBarData: BarAreaData(show: true, color: Colors.tealAccent.withOpacity(0.1)),
      )
    ],
  ),
)
```

## Status Badge Colors

```dart
const statusColors = {
  0x01: Colors.red,       // GET_OUT_OF_BED
  0x02: Colors.orange,    // MOVEMENT
  0x03: Colors.orange,    // SIT_UP
  0x04: Colors.green,     // SLEEP
  0x05: Colors.yellow,    // WAKE_UP
  0x06: Colors.red,       // HEAVY_OBJECT
  0x07: Colors.purple,    // SNORE
  0x08: Colors.deepOrange,// WEAK_BREATHING
};
```

## Related Files

- Create: `lib/features/home/home-screen.dart`
- Create: `lib/features/home/realtime-data-card.dart`
- Create: `lib/features/home/status-badge.dart`
- Create: `lib/features/home/realtime-provider.dart`
- Create: `lib/features/history/history-screen.dart`
- Create: `lib/features/history/history-chart-panel.dart`
- Create: `lib/features/history/history-repository.dart`
- Create: `lib/features/history/history-provider.dart`
- Create: `lib/shared/widgets/metric-card.dart`
- Create: `lib/shared/widgets/sleep-line-chart.dart`
- Modify: `lib/app.dart` — add home + history routes

## Implementation Steps

1. Write `shared/widgets/metric-card.dart` — reusable big-number display
2. Write `shared/widgets/sleep-line-chart.dart` — fl_chart wrapper
3. Write `home/realtime-provider.dart` — WebSocket StreamProvider
4. Write `home/status-badge.dart`
5. Write `home/realtime-data-card.dart`
6. Write `home/home-screen.dart` — wire provider to cards
7. Write `history/history-repository.dart` — Dio call to /data/history
8. Write `history/history-provider.dart` — FutureProvider per range
9. Write `history/history-chart-panel.dart` — 3 charts (HR, RR, resp_disorder)
10. Write `history/history-screen.dart` — TabController + panels
11. Update `app.dart` — register /home and /history routes
12. Test: verify WS data flows to UI, chart renders correctly

## Todo

- [x] metric-card.dart widget
- [x] sleep-line-chart.dart (fl_chart wrapper)
- [x] realtime-provider.dart (WebSocket stream)
- [x] home-screen.dart with all cards
- [x] history-repository.dart
- [x] history-provider.dart (FutureProvider)
- [x] history-chart-panel.dart (3 charts)
- [x] history-screen.dart (tabs)
- [x] Wire routes in app.dart
- [x] UI test on device

## Success Criteria

- Home screen updates HR/RR every second from WebSocket
- Status badge shows correct color per status code
- History Day tab: 288 data points (5-min buckets × 24h), renders chart
- History Week tab: 168 data points (1h buckets × 7 days)
- History Month tab: 240 data points (3h buckets × 30 days)
- Empty state shown when no data available

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| WS disconnect on app background | Reconnect on foreground resume via AppLifecycleListener |
| fl_chart rendering 300+ points slowly | Downsample on backend if needed; fl_chart handles 500+ fine in practice |
| JWT expiry during WS session | Detect 401 on reconnect → redirect to login |
