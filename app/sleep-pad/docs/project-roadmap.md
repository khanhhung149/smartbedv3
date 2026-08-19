# Sleep Pad Flutter App — Project Roadmap

**Last Updated:** 2026-05-03

## Project Overview

Sleep Pad is a Flutter-based health monitoring mobile application that enables users to monitor sleep metrics without requiring wearable devices. The app communicates with IoT hardware via BLE provisioning, manages device invitations, tracks historical sleep data, and generates alerts based on configurable thresholds.

## Development Phases

### Phase 1: Core Architecture & Multi-Flavor Setup ✅ COMPLETED
**Status:** Complete  
**Completion Date:** 2026-04-29

**Deliverables:**
- Multi-flavor environment configuration (dev, staging, prod)
- Flutter project structure and widget architecture
- Repository pattern abstraction layer
- Git worktree workflow documentation

**Key Commits:**
- `9130031` – Multi-flavor env, widget split, repository abstraction
- `502f972` – Bundle auto-memory + import guide

### Phase 2: Authentication & User Management ✅ COMPLETED
**Status:** Complete

**Deliverables:**
- Login/register flows with email verification
- Password recovery & reset flows
- JWT token persistence via `flutter_secure_storage`
- Auth provider integration with Riverpod

**Screens:**
- `LoginScreen`, `RegisterScreen`, `VerifyEmailScreen`
- `ForgotPasswordScreen`, `ResetPasswordScreen`
- `OnboardingScreen` with sleep tracking intro slides

### Phase 3: Device Management & BLE Provisioning ✅ COMPLETED
**Status:** Complete

**Deliverables:**
- BLE device scanning & connection
- WiFi credential provisioning workflow
- Device pairing & provisioning success confirmation
- Device detail screen with metrics display
- Device deletion capability
- Pending invite management (accept/reject)

**Screens:**
- `BleScanScreen`, `BleProvisionWifiScreen`, `BleProvisionPairingScreen`
- `BleProvisionSuccessScreen`, `DeviceDetailScreen`
- Device-related widgets in `MainShell` tab navigation

### Phase 4: Data Visualization & History ✅ COMPLETED
**Status:** Complete

**Deliverables:**
- Historical sleep data retrieval and display
- Time-series visualization (fl_chart integration)
- Alert history with filtering and detail views
- Responsive layout for mobile screens

**Screens:**
- `HistoryScreen` with sleep data charts
- `AlertsScreen` with alert list
- `AlertDetailScreen` with metric breakdown

### Phase 5: Settings, Sharing & Localization ✅ COMPLETED
**Status:** Complete  
**Completion Date:** 2026-05-03

**Deliverables:**
- User profile & account management
- Settings screen with appearance (theme, locale) options
- Multi-language support (English + Vietnamese)
- Device sharing & family invite system
- Language switching UI in Settings

**Implementation Details:**
- 65+ translation keys across all screens
- ARB-based localization with intl package
- Riverpod-backed locale provider with persistent storage
- Locale-aware date formatting (`DateFormat.MMMd()`)
- Language switcher bottom sheet in Settings

**Screens:**
- `SettingsScreen` with language/appearance controls
- `InviteFamilySheet` for device sharing
- All auth, device, history, and alert screens translated

**Localizations Delivered:**
- English (en) — primary language
- Vietnamese (vi) — secondary language
- Covers onboarding, auth, devices, alerts, history, settings

---

## Technical Stack

| Layer | Technology |
|-------|-----------|
| **UI Framework** | Flutter (Dart 3.x) |
| **State Management** | Riverpod |
| **Navigation** | GoRouter |
| **Networking** | Dio HTTP client |
| **Persistent Storage** | flutter_secure_storage, SharedPreferences |
| **BLE Communication** | flutter_blue_plus |
| **Authentication** | JWT (persisted token) |
| **Localization** | intl, flutter_localizations, ARB |
| **Charts/Visualization** | fl_chart |
| **WebSocket** | web_socket_channel (real-time alerts) |
| **Permissions** | permission_handler |
| **Icon System** | material_symbols_icons, Material Icons |
| **Fonts** | google_fonts |

---

## File Structure

```
lib/
├── main.dart                                    # Entry point (delegates to flavor main)
├── main/
│   ├── main_dev.dart                           # Dev flavor entry
│   ├── main_staging.dart                       # Staging flavor entry
│   └── main_prod.dart                          # Production flavor entry
├── app.dart                                     # SleepPadApp + GoRouter config
├── core/
│   ├── app_theme.dart                          # Theme definition
│   ├── app_colors.dart                         # Color palette
│   └── constants.dart                          # App-wide constants
├── l10n/                                        # Localization
│   ├── app_en.arb                              # English translations
│   ├── app_vi.arb                              # Vietnamese translations
│   ├── l10n.yaml                               # intl config
│   └── app_localizations.dart                  # Generated delegates
├── shared/
│   ├── providers/
│   │   ├── auth_provider.dart                  # Auth state (JWT, login, logout)
│   │   ├── locale_provider.dart                # Locale state (language switching)
│   │   └── [other providers]
│   └── widgets/
│       ├── main_shell.dart                     # Tab navigation shell
│       └── [shared components]
├── features/
│   ├── onboarding/
│   │   ├── onboarding_screen.dart
│   │   └── onboarding_sleep_slide.dart
│   ├── auth/
│   │   ├── login_screen.dart
│   │   ├── register_screen.dart
│   │   ├── verify_email_screen.dart
│   │   ├── forgot_password_screen.dart
│   │   └── reset_password_screen.dart
│   ├── devices/
│   │   ├── ble_scan_screen.dart
│   │   ├── ble_provision_wifi_screen.dart
│   │   ├── ble_provision_pairing_screen.dart
│   │   ├── ble_provision_success_screen.dart
│   │   ├── device_detail_screen.dart
│   │   ├── providers/
│   │   │   └── provisioning_provider.dart
│   │   └── widgets/
│   │       ├── devices_my_section.dart
│   │       ├── devices_pending_invites_section.dart
│   │       └── device_detail_info_card.dart
│   ├── history/
│   │   ├── history_screen.dart
│   │   └── widgets/
│   │       └── [history-specific components]
│   ├── alerts/
│   │   ├── alerts_screen.dart
│   │   ├── alerts_app_bar.dart
│   │   ├── alert_detail_screen.dart
│   │   ├── models/
│   │   │   └── alert_out.dart
│   │   └── [alert-specific components]
│   └── settings/
│       ├── settings_screen.dart
│       └── widgets/
│           └── [settings-specific components]
└── [data layer — repositories, models, API clients]
```

---

## Completed Features Summary

| Feature | Status | Integrated | Notes |
|---------|--------|-----------|-------|
| Multi-flavor env (dev/staging/prod) | ✅ | Yes | Configured in `main/` |
| JWT authentication | ✅ | Yes | flutter_secure_storage backed |
| Email verification | ✅ | Yes | Part of register flow |
| Password reset | ✅ | Yes | Forgot + reset screens |
| BLE device scanning | ✅ | Yes | flutter_blue_plus |
| WiFi provisioning | ✅ | Yes | Credentials → device via BLE |
| Device pairing | ✅ | Yes | Confirmation flow |
| Device deletion | ✅ | Yes | Available in device detail |
| Pending device invites | ✅ | Yes | Accept/reject workflow |
| Sleep history visualization | ✅ | Yes | fl_chart integration |
| Alert management | ✅ | Yes | History + detail views |
| Theme customization | ✅ | Yes | Dark theme, extensible |
| **Multi-language (EN + VI)** | ✅ | Yes | Full app translated, 65+ keys |
| Language switching UI | ✅ | Yes | Settings → Appearance section |
| Locale persistence | ✅ | Yes | flutter_secure_storage |
| Locale-aware formatting | ✅ | Yes | DateFormat.MMMd() + relative time |

---

## Known Limitations & Future Enhancements

### Current Limitations
- Single-device focus per session (multi-device support planned)
- Theme limited to dark mode (light mode planned for Phase 6)
- Device sharing via deep links (email invitations planned)
- Basic push notifications (advanced filtering planned)

### Planned Enhancements
- Light mode support
- Advanced alert customization per metric
- Device firmware update mechanism
- Export sleep data (CSV/PDF)
- Social sharing of sleep achievements
- Wearable integration (Apple Watch, Fitbit, etc.)

---

## CI/CD & Quality Assurance

### Testing
- `flutter analyze` — zero issues
- Unit tests for state management (Riverpod providers)
- Widget tests for key screens
- Integration tests for BLE provisioning flow

### Build Targets
- Android: `flutter build apk -t lib/main/main_prod.dart`
- iOS: `flutter build ios -t lib/main/main_prod.dart`
- Dev flavor for hot reload testing
- Staging flavor for beta testing

### Version Management
- Current version: 1.0.0+1 (pubspec.yaml)
- Semantic versioning: MAJOR.MINOR.PATCH+BUILD

---

## Dependencies

### Core
- `flutter`, `flutter_localizations` — framework
- `flutter_riverpod: ^2.5.1` — state management
- `go_router: ^14.2.0` — navigation
- `dio: ^5.7.0` — HTTP client

### Localization
- `intl: ^0.20.2` — internationalization
- `flutter_localizations: sdk` — Flutter i18n delegates

### Storage & Security
- `flutter_secure_storage: ^9.2.2` — secure token storage
- Built-in SharedPreferences for non-sensitive data

### Hardware & Permissions
- `flutter_blue_plus: ^1.32.0` — BLE communication
- `permission_handler: ^11.3.1` — runtime permissions

### UI & Design
- `google_fonts: ^6.2.1` — custom fonts
- `material_symbols_icons: ^4.2.1070` — icon library
- `fl_chart: ^0.69.0` — charting library

### Real-time Communication
- `web_socket_channel: ^2.4.5` — WebSocket support

### Development
- `flutter_lints: ^3.0.0` — lint rules
- `flutter_test: sdk` — testing framework

---

## Contact & Support

**Project Lead:** Patrick Nguyen (patrick@chtlab.io)  
**Repository:** Sleep-Tech-AI/sleeppad-ai  
**Main Branch:** `main`

**Reporting Issues:**
1. Check existing GitHub issues
2. Create new issue with reproduction steps
3. Tag with appropriate label (bug, enhancement, documentation)

---

## Changelog

See `/docs/project-changelog.md` for detailed commit history and feature release notes.
