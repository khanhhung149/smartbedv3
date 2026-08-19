---
phase: 1
title: "Setup i18n Infrastructure"
status: pending
priority: P1
effort: "1h"
dependencies: []
---

# Phase 1: Setup i18n Infrastructure

## Overview
Add `flutter_localizations` and `intl` to pubspec, configure `flutter gen-l10n`, create ARB directory structure, and wire `MaterialApp.router` with localization delegates.

## Requirements
- Functional: App compiles with localization delegates wired; `AppLocalizations.of(context)` is accessible in widget tree
- Non-functional: Zero runtime warnings about missing locale delegates

## Architecture

```
flutter_app/
├── pubspec.yaml                          # add flutter_localizations + intl + generate: true
├── l10n.yaml                             # gen-l10n config
└── lib/
    └── l10n/
        ├── app_en.arb                    # English strings (source of truth)
        └── app_vi.arb                    # Vietnamese strings
```

Generated output (gitignored or committed, default `.dart_tool/`):
```
.dart_tool/flutter_gen/gen_l10n/
└── app_localizations.dart               # AppLocalizations class + delegates
```

## Related Code Files
- Modify: `flutter_app/pubspec.yaml`
- Create: `flutter_app/l10n.yaml`
- Create: `flutter_app/lib/l10n/app_en.arb` (stub — Phase 2 fills content)
- Create: `flutter_app/lib/l10n/app_vi.arb` (stub — Phase 2 fills content)
- Modify: `flutter_app/lib/app.dart` (add delegates + supportedLocales to MaterialApp.router)

## Implementation Steps

### 1. Update `pubspec.yaml`

Add under `dependencies:`:
```yaml
flutter_localizations:
  sdk: flutter
intl: ^0.19.0
```

Add `flutter:` section entry (if not present):
```yaml
flutter:
  generate: true
```

### 2. Create `l10n.yaml` at project root

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
```

### 3. Create stub ARB files

`lib/l10n/app_en.arb`:
```json
{
  "@@locale": "en"
}
```

`lib/l10n/app_vi.arb`:
```json
{
  "@@locale": "vi"
}
```

### 4. Run code generation

```bash
cd flutter_app && flutter gen-l10n
```

Verify `app_localizations.dart` is generated successfully.

### 5. Wire `app.dart`

In `MaterialApp.router(...)`, add:
```dart
localizationsDelegates: AppLocalizations.localizationsDelegates,
supportedLocales: AppLocalizations.supportedLocales,
```

Import: `import 'package:flutter_gen/gen_l10n/app_localizations.dart';`

The `locale` parameter will be wired in Phase 4 via `localeProvider`.

## Success Criteria
- [ ] `flutter pub get` succeeds
- [ ] `flutter gen-l10n` runs without errors
- [ ] `AppLocalizations.of(context)` is non-null on any screen
- [ ] App builds and launches on iOS Simulator

## Risk Assessment
- `intl` version conflict with existing packages: check `flutter pub deps` after adding — resolve with version constraint
- `generate: true` must be at the top-level `flutter:` key, not nested
