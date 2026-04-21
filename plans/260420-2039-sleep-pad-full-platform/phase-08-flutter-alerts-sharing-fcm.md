---
phase: 08
status: completed
priority: high
effort: medium
sub_project: flutter
blockedBy: [phase-07]
---

# Phase 08: Flutter App — Alerts, Sharing, FCM & Settings

## Overview

Alert threshold settings screen, family sharing (invite by email, manage), Firebase FCM push notifications, and Settings screen (account, server URL, logout).

## Requirements

- Alerts screen: view/edit thresholds per metric (HR high/low, RR high/low, resp_disorder)
- Alert history list (last triggered alerts)
- Sharing screen: invite by email, list shared users, revoke access
- Accept invite flow (from deep link or in-app notification)
- FCM: register token on login, receive foreground + background push
- Settings: account info, server URL config, logout

## App Structure (additions)

```
lib/features/
├── alerts/
│   ├── alerts-screen.dart          ← tab: Thresholds | History
│   ├── threshold-form.dart         ← sliders/fields for HR, RR, resp_disorder
│   ├── alert-history-list.dart     ← list of past alert events
│   └── alerts-repository.dart      ← GET/PUT thresholds, GET history
├── sharing/
│   ├── sharing-screen.dart         ← list shared users + invite button
│   ├── invite-dialog.dart          ← email input dialog
│   └── sharing-repository.dart     ← POST invite, GET my-devices, DELETE share
├── settings/
│   └── settings-screen.dart        ← account info, server URL, logout
└── shared/
    └── services/
        └── fcm-service.dart        ← Firebase init, token upload, message handlers
```

## Alerts Screen

```
┌─────────────────────────────────┐
│  [Thresholds] [History]         │
├─────────────────────────────────┤
│  Heart Rate                     │
│  High: [──●──────] 120 bpm      │
│  Low:  [──────●──]  40 bpm      │
│                                 │
│  Respiration Rate               │
│  High: [──●──────]  30 /min     │
│  Low:  [──────●──]   5 /min     │
│                                 │
│  Resp. Disorder (per min)       │
│  Count: [────●────]   5         │
│                                 │
│         [Save Changes]          │
└─────────────────────────────────┘
```

## Sharing Screen

```
┌─────────────────────────────────┐
│  Shared With                [+] │
├─────────────────────────────────┤
│  family@example.com    [Revoke] │
│  sister@example.com    [Revoke] │
├─────────────────────────────────┤
│  Devices Shared To Me           │
│  Mom's Pad (owner@ex.com)       │
└─────────────────────────────────┘
```

## FCM Integration

```dart
// fcm-service.dart
class FcmService {
  static Future<void> init() async {
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();
    if (token != null) await _uploadToken(token);
    messaging.onTokenRefresh.listen(_uploadToken);

    // Foreground: show local notification
    FirebaseMessaging.onMessage.listen((msg) {
      // show in-app snackbar or local notification
    });
  }

  static Future<void> _uploadToken(String token) async {
    // PATCH /auth/me with { fcm_token: token }
  }
}
```

Backend needs: `PATCH /auth/fcm-token` endpoint — add to Phase 02 auth router.

## Settings Screen

```dart
// settings-screen.dart
// - Display: email address
// - Edit: Server URL (saved to secure storage, used by api-client)
// - Button: Logout (clear JWT + FCM token from storage, navigate to login)
```

## Related Files

- Create: `lib/features/alerts/alerts-screen.dart`
- Create: `lib/features/alerts/threshold-form.dart`
- Create: `lib/features/alerts/alert-history-list.dart`
- Create: `lib/features/alerts/alerts-repository.dart`
- Create: `lib/features/sharing/sharing-screen.dart`
- Create: `lib/features/sharing/invite-dialog.dart`
- Create: `lib/features/sharing/sharing-repository.dart`
- Create: `lib/features/settings/settings-screen.dart`
- Create: `lib/shared/services/fcm-service.dart`
- Modify: `lib/main.dart` — call FcmService.init()
- Modify: `lib/app.dart` — add alerts/sharing/settings routes
- Modify: `backend/app/auth/router.py` — add PATCH /auth/fcm-token endpoint

## Implementation Steps

1. Write `fcm-service.dart` — Firebase init + token upload + foreground handler
2. Add `PATCH /auth/fcm-token` to backend auth router
3. Write `alerts/alerts-repository.dart` — GET/PUT thresholds, GET history
4. Write `alerts/threshold-form.dart` — Slider widgets per metric
5. Write `alerts/alert-history-list.dart`
6. Write `alerts/alerts-screen.dart` — TabBar: Thresholds | History
7. Write `sharing/sharing-repository.dart`
8. Write `sharing/invite-dialog.dart`
9. Write `sharing/sharing-screen.dart`
10. Write `settings/settings-screen.dart`
11. Update `main.dart` — FcmService.init() after auth check
12. Update `app.dart` — wire all new routes into bottom nav
13. Add bottom navigation bar (Home / History / Alerts / Devices / Settings)
14. Test FCM: trigger alert from backend → push arrives on device

## Bottom Navigation Structure

```dart
// app.dart — StatefulShellRoute with 5 branches
destinations: [
  NavigationDestination(icon: Icons.home,        label: 'Home'),
  NavigationDestination(icon: Icons.bar_chart,   label: 'History'),
  NavigationDestination(icon: Icons.notifications, label: 'Alerts'),
  NavigationDestination(icon: Icons.devices,     label: 'Devices'),
  NavigationDestination(icon: Icons.settings,    label: 'Settings'),
]
```

## Todo

- [x] fcm-service.dart (Firebase + token upload)
- [x] Backend: PATCH /auth/fcm-token
- [x] alerts-repository.dart
- [x] threshold-form.dart (sliders)
- [x] alert-history-list.dart
- [x] alerts-screen.dart
- [x] sharing-repository.dart
- [x] invite-dialog.dart
- [x] sharing-screen.dart
- [x] settings-screen.dart
- [x] Bottom nav bar in app.dart
- [x] FCM push test end-to-end (stub, Firebase config pending)

## Success Criteria

- Threshold sliders save to backend, persist after app restart
- Alert history shows triggered alerts with timestamp + metric
- Invite email → family member opens app → sees shared device in /share/my-devices
- FCM token uploaded on login; push notification received when threshold exceeded
- Logout clears token, redirects to login

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| FCM on iOS requires APNs certificate | Register in Firebase console + Apple Developer; test on real device |
| Background FCM on Android 13+ | Request POST_NOTIFICATIONS permission at runtime |
| Deep link for share invite | Use app_links package; fallback: accept in-app via notification |

## Security

- FCM token stored in secure storage, deleted on logout
- Server URL editable in Settings — validate URL format before save
- Revoke sharing: only device owner can revoke; verified server-side
