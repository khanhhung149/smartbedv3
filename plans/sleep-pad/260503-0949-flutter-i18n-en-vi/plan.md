---
id: 260503-0949-flutter-i18n-en-vi
title: "Flutter i18n: English + Vietnamese"
status: pending
priority: P2
createdAt: "2026-05-03T09:49:00"
phases:
  - phase-01-setup-i18n-infrastructure.md
  - phase-02-arb-translation-files.md
  - phase-03-replace-hardcoded-strings.md
  - phase-04-language-switcher-and-persistence.md
---

# Flutter i18n: English + Vietnamese

Add multi-language support (EN + VI) to the Flutter SleepPad app using the official Flutter localization stack (`flutter_localizations` + `intl` + ARB + `flutter gen-l10n`).

## Phases

| # | Phase | Status | Effort |
|---|-------|--------|--------|
| 1 | [Setup i18n Infrastructure](phase-01-setup-i18n-infrastructure.md) | pending | ~1h |
| 2 | [ARB Translation Files](phase-02-arb-translation-files.md) | pending | ~1h |
| 3 | [Replace Hardcoded Strings](phase-03-replace-hardcoded-strings.md) | pending | ~2h |
| 4 | [Language Switcher & Persistence](phase-04-language-switcher-and-persistence.md) | pending | ~1h |

## Key Dependencies

- Phase 1 must complete before Phase 2 (gen-l10n must run first to validate ARB keys)
- Phase 2 must complete before Phase 3 (generated `AppLocalizations` class needed for string references)
- Phase 4 can start after Phase 1 (localeProvider is independent of ARB content)

## Scope

- ~55 unique user-facing strings across 9 feature areas
- No backend changes required
- Language persisted via `flutter_secure_storage` (already in pubspec)
- Switcher added to existing Settings screen Appearance section
