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
    try {
      final code = await _storage.read(key: _kLocaleKey);
      if (mounted && code != null) state = Locale(code);
    } catch (_) {
      // storage unavailable; fall back to system locale
    }
  }

  Future<void> setLocale(Locale locale) async {
    try {
      await _storage.write(key: _kLocaleKey, value: locale.languageCode);
    } catch (_) {}
    if (mounted) state = locale;
  }

  Future<void> clearLocale() async {
    try {
      await _storage.delete(key: _kLocaleKey);
    } catch (_) {}
    if (mounted) state = null;
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>(
  (ref) => LocaleNotifier(const FlutterSecureStorage()),
);
