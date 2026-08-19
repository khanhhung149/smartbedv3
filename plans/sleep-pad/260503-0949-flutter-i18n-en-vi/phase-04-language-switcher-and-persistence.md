---
phase: 4
title: "Language Switcher & Persistence"
status: pending
priority: P2
effort: "1h"
dependencies: [phase-01-setup-i18n-infrastructure.md]
---

# Phase 4: Language Switcher & Persistence

## Overview
Add a `localeProvider` (Riverpod) that persists the selected language via `flutter_secure_storage`, wire it into `MaterialApp.router`, and add a language row to the Settings screen Appearance section.

## Architecture

```
localeProvider (StateNotifierProvider<LocaleNotifier, Locale?>)
  ├── reads from flutter_secure_storage on init
  ├── writes to flutter_secure_storage on change
  └── null = system default

MaterialApp.router
  └── locale: ref.watch(localeProvider)   ← drives active locale

Settings → Appearance section
  └── _LanguageRow                        ← shows current language, opens picker modal
```

## Related Code Files
- Create: `flutter_app/lib/shared/providers/locale_provider.dart`
- Modify: `flutter_app/lib/app.dart`
- Modify: `flutter_app/lib/features/settings/settings_screen.dart`

## Implementation Steps

### Step 1: Create `locale_provider.dart`

```dart
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kLocaleKey = 'app_locale';

class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier(this._storage) : super(null) {
    _load();
  }

  final FlutterSecureStorage _storage;

  Future<void> _load() async {
    final code = await _storage.read(key: _kLocaleKey);
    if (code != null) state = Locale(code);
  }

  Future<void> setLocale(Locale locale) async {
    await _storage.write(key: _kLocaleKey, value: locale.languageCode);
    state = locale;
  }

  Future<void> clearLocale() async {
    await _storage.delete(key: _kLocaleKey);
    state = null;
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>(
  (ref) => LocaleNotifier(const FlutterSecureStorage()),
);
```

### Step 2: Wire into `app.dart`

In `AppRouter`'s `build` method, watch `localeProvider`:
```dart
final locale = ref.watch(localeProvider);
```

Add to `MaterialApp.router(...)`:
```dart
locale: locale,
localizationsDelegates: AppLocalizations.localizationsDelegates,
supportedLocales: AppLocalizations.supportedLocales,
```

### Step 3: Add `_LanguageRow` to `settings_screen.dart`

Add under the existing Appearance section (after theme toggle, before Device Connection section):

```dart
_TappableRow(
  label: l10n.language,
  trailing: Text(
    _currentLanguageLabel(context),
    style: GoogleFonts.inter(
      fontSize: AppTextSize.sm,
      color: AppColors.secondary,
    ),
  ),
  onTap: () => _showLanguagePicker(context, ref),
),
```

Helper methods to add to `_SettingsScreenState`:

```dart
String _currentLanguageLabel(BuildContext context) {
  final locale = ref.read(localeProvider);
  if (locale == null) return 'System';
  return locale.languageCode == 'vi' ? 'Tiếng Việt' : 'English';
}

void _showLanguagePicker(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _LanguagePickerSheet(
      current: ref.read(localeProvider),
      onSelect: (locale) {
        if (locale == null) {
          ref.read(localeProvider.notifier).clearLocale();
        } else {
          ref.read(localeProvider.notifier).setLocale(locale);
        }
        Navigator.pop(context);
      },
    ),
  );
}
```

`_LanguagePickerSheet` widget (add as private class at bottom of file):

```dart
class _LanguagePickerSheet extends StatelessWidget {
  const _LanguagePickerSheet({required this.current, required this.onSelect});

  final Locale? current;
  final void Function(Locale?) onSelect;

  @override
  Widget build(BuildContext context) {
    final options = [
      (null, 'System default'),
      (const Locale('en'), 'English'),
      (const Locale('vi'), 'Tiếng Việt'),
    ];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: options.map((entry) {
          final (locale, label) = entry;
          final isSelected = locale?.languageCode == current?.languageCode &&
              !(locale == null && current != null);
          return ListTile(
            title: Text(label, style: GoogleFonts.inter(color: AppColors.onSurface)),
            trailing: isSelected
                ? const Icon(Icons.check, color: AppColors.primary)
                : null,
            onTap: () => onSelect(locale),
          );
        }).toList(),
      ),
    );
  }
}
```

## Success Criteria
- [ ] Language persists across app restarts (cold start)
- [ ] Switching EN → VI updates all translated strings immediately (no restart needed)
- [ ] Settings screen Appearance section shows current language name
- [ ] "System default" option resets to device locale
- [ ] `flutter analyze` shows no errors in modified files

## Risk Assessment
- `settings_screen.dart` is close to 200-line limit — if adding `_LanguagePickerSheet` pushes it over, extract it to `flutter_app/lib/features/settings/widgets/language-picker-sheet.dart`
- `StateNotifier` is deprecated in newer Riverpod — if project upgrades to Riverpod 3.x, migrate to `Notifier`; acceptable to use `StateNotifier` for now since existing providers use it
