---
phase: 4
title: "Flutter Home widget test + build smoke"
status: pending
priority: P2
dependencies: []
---

# Phase 4: Home widget test + build smoke

## Overview

Home là màn bị viết lại nhiều nhất trong Phase 3 của plan gốc mà chưa có test nào.
Thêm widget test 4 trạng thái + chạy `flutter test` và build smoke.

Độc lập với Phase 1–3 (không cần backend), chạy song song được.

## Requirements

**Functional** — Home render đúng với 4 trạng thái:
- Chỉ có pad (watch = null)
- Chỉ có watch (pad = null)
- Có cả hai
- Pad offline (`pad.online == false`)

**Non-functional**
- Test không gọi mạng (WS thật, Google Fonts)
- `flutter analyze lib` giữ nguyên No issues

## Architecture

### Override provider

`userRealtimeProvider` là `StreamProvider<CombinedRealtimeData>` (không phải `.family`)
→ override thẳng bằng stream dựng sẵn:

```dart
ProviderScope(
  overrides: [
    devicesListProvider.overrideWith((ref) async => [fakePad, fakeWatch]),
    userRealtimeProvider.overrideWith((ref) => Stream.value(combined)),
  ],
  child: const MaterialApp(home: HomeScreen()),
)
```

`HomeScreen` có guard `devicesListProvider` — devices rỗng thì render
`HomeNoDeviceView` chứ không phải `HomeContent`. **Bắt buộc override cả hai provider**,
nếu không test sẽ assert nhầm màn empty state.

### l10n bắt buộc

`HomeContent` import `app_localizations.dart`. `MaterialApp` trong test phải có
`localizationsDelegates: AppLocalizations.localizationsDelegates` +
`supportedLocales`, nếu không `AppLocalizations.of(context)!` sẽ null → crash.

### Google Fonts và mạng

`home_screen.dart` và các widget con dùng `GoogleFonts.inter(...)`. Trong widget test,
`google_fonts` cố tải font qua HTTP và log lỗi (có thể fail tuỳ cấu hình). Đặt ở
`setUpAll`:

```dart
GoogleFonts.config.allowRuntimeFetching = false;
```

### Test khẳng định gì

Widget test ở đây khoá **cấu trúc**, không khoá pixel. Assert theo giá trị hiển thị
(`find.text('72')`) và sự hiện diện widget (`find.byType(HomeWatchMetrics)`), không
dùng golden file — golden dễ vỡ và đang không có baseline.

## Related Code Files

**Create**
- `flutter_app/test/home_screen_test.dart`

**Read only**
- `flutter_app/lib/features/home/home_screen.dart`
- `flutter_app/lib/features/home/home_content.dart`
- `flutter_app/lib/features/home/home_device_status_row.dart`
- `flutter_app/lib/features/home/home_watch_metrics.dart`
- `flutter_app/lib/features/data/providers/user_realtime_provider.dart`
- `flutter_app/lib/features/devices/providers/devices_list_provider.dart`
- `flutter_app/test/combined_realtime_data_test.dart` (mẫu có sẵn)

**Không sửa** file `lib/` nào.

## Implementation Steps

1. Helper dựng `CombinedRealtimeData` cho từng trạng thái (tái dùng shape JSON từ
   `combined_realtime_data_test.dart` đã có)
2. Helper `pumpHome(...)` bọc `ProviderScope` + `MaterialApp` + l10n delegates
3. `test_home_pad_only` — pad có `hr:72, rr:15`, watch null → hiện HR/RR, không hiện
   section watch
4. `test_home_watch_only` — pad null, watch có `spo2:98, steps:4521` → hiện metric watch,
   pad hiện trạng thái rỗng
5. `test_home_both` — cả hai → hiện đủ
6. `test_home_pad_offline` — `pad.online == false` → status row hiện trạng thái offline
7. Chạy `flutter analyze lib` và `flutter test`
8. Build smoke: `flutter build apk --debug` (hoặc `flutter build ios --simulator --no-codesign`
   nếu làm trên macOS). Trên WSL thì Android là lựa chọn khả thi.

## Success Criteria

- [ ] 4 widget test pass
- [ ] `flutter test` toàn bộ xanh (gồm 4 test model có sẵn)
- [ ] `flutter analyze lib` → No issues
- [ ] Build smoke thành công
- [ ] Không sửa file nào trong `lib/`

## Risk Assessment

| Rủi ro | Giảm thiểu |
|---|---|
| Google Fonts gọi mạng làm test chậm/fail | `GoogleFonts.config.allowRuntimeFetching = false` trong `setUpAll` |
| Quên override `devicesListProvider` → test assert vào empty state | Assert `find.byType(HomeContent)` ngay đầu mỗi test |
| Layout overflow trong test surface mặc định (800×600) | Đặt `tester.view.physicalSize` cỡ điện thoại, reset ở `tearDown` |
| `HomeContent` là `ConsumerStatefulWidget` với `ref.listen` — cần pump thêm | `await tester.pumpAndSettle()` sau khi stream emit |
| Build smoke trên WSL thiếu Android SDK | Nếu thiếu, ghi rõ là bị chặn thay vì bỏ qua im lặng; iOS build cần macOS |
