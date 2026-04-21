# Phase 06 Wave 1 — Flutter Scaffold + Auth + Onboarding

## Files Created (19 Dart files)

```
flutter_app/lib/
  main.dart
  app.dart                                     GoRouter + ProviderScope + home stub
  core/
    app_colors.dart                            all 40 Stitch color tokens as Dart constants
    app_theme.dart                             ThemeData + AppTextSize + AppFontWeight + AppRadius
    api_client.dart                            Dio + JWT Bearer interceptor
    auth_storage.dart                          flutter_secure_storage wrapper
    constants.dart                             API base URL + BLE UUIDs
  shared/
    providers/auth_provider.dart               Riverpod AuthNotifier + initialAuthProvider
    widgets/
      app_bottom_nav.dart                      canonical 5-tab nav (Wave 2 ready)
      primary_button.dart                      gradient CTA, isLoading state
      stitch_text_field.dart                   surface-container input, eye toggle, error text
      loading_overlay.dart                     translucent spinner overlay
  features/
    onboarding/
      onboarding_screen.dart                   PageView + pagination dots + CTA overlay
      onboarding_sleep_slide.dart              slide 1 — "Monitor sleep, without wearables"
      onboarding_alerts_slide.dart             slide 2 — "Know if something's off"
      onboarding_sharing_slide.dart            slide 3 — "Share peace of mind"
    auth/
      auth_repository.dart                     POST /auth/login + /auth/register, error mapping
      login_screen.dart                        branding + fields + footer link
      register_screen.dart                     header + 3 fields + auto-login after register
```

## Screens Implemented + Pixel-Correctness Notes

| Screen | Fidelity |
|--------|----------|
| onboarding_sleep_monitoring | Colors, typography, gradient fade from `#0B0F14` all match HTML. Illustration is placeholder icon (no external image URL usable at build time). |
| onboarding_alerts | Glow dot on slide 2 matches `rgba(94,231,223,0.6)` shadow spec. Illustration placeholder. |
| onboarding_sharing | Active dot is w-8 gradient pill matching HTML. Illustration placeholder. |
| login | Exact bg `#101419`, `text-3xl font-medium` greeting, gradient button, `rounded` (16px default) inputs, monitoring icon, footer forgot-password link. |
| register | `bg-surface-container-lowest`, `vital_signs` icon weight 600, `rounded-[20px]` inputs (BorderRadius.circular(20)), 3 fields, auto-login flow. |

## Build Output

```
flutter analyze   → No issues found (0 errors, 0 warnings, 0 infos)
flutter pub get   → 49 packages resolved
flutter build web --debug → Built build/web  (19.8s)
```

`flutter build apk --debug` — blocked: No Android SDK on this machine (ANDROID_HOME unset).
`flutter build macos --debug` — blocked: Xcode 26 beta plug-in crash (`IDESimulatorFoundation` dyld symbol not found — environment issue, not code).

Web build succeeds as compilation verification. `flutter analyze` confirms zero Dart errors.

## Deviations from Stitch Design

1. **Illustration images**: Stitch HTML references Google AIDA CDN URLs (`lh3.googleusercontent.com/aida/...`). These are ephemeral/non-distributable. Slides use placeholder `Icon` widgets. Wave 2 or asset-prep phase should replace with real assets.
2. **Backdrop blur on bottom nav**: Uses `BackdropFilter(ImageFilter.blur)` — correct Flutter equivalent of `backdrop-blur-3xl`. Requires `ClipRRect` wrapper; works on all platforms including Android.
3. **Xcode/Android SDK**: Build verification via `flutter build web` instead of `flutter build apk`. `flutter analyze` confirms Dart compilation is error-free.

## Unresolved Questions for Wave 2

1. Android SDK not present on dev machine — Wave 2 owner should verify APK build after installing SDK.
2. Illustration assets: need final assets committed to `flutter_app/assets/` before any screenshot testing.
3. Xcode 26 beta plug-in crash (`xcodebuild -runFirstLaunch` needed) — iOS/macOS builds blocked until environment is fixed.
4. `flutter_secure_storage_web` uses `dart:html` — if web target is ever a priority, swap for `shared_preferences` on web.

---

Status: DONE_WITH_CONCERNS
Summary: All 19 Wave 1 files created, flutter analyze clean (0 issues), web build succeeds. APK build unverifiable — no Android SDK on this machine; Xcode 26 beta plug-in crash blocks macOS build too.
Concerns: (1) No Android SDK → APK build not verified locally. (2) Illustration images are placeholders — Stitch CDN URLs not distributable. Both are environment/asset issues, not code issues.
