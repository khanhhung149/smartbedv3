import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'constants.dart';

// Wrapper around flutter_secure_storage for JWT read/write/delete.
// Uses Android Keystore + iOS Keychain under the hood.
class AuthStorage {
  AuthStorage() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final FlutterSecureStorage _storage;

  Future<String?> readToken() async {
    return _storage.read(key: AppConstants.jwtStorageKey);
  }

  Future<void> writeToken(String token) async {
    await _storage.write(key: AppConstants.jwtStorageKey, value: token);
  }

  Future<void> deleteToken() async {
    await _storage.delete(key: AppConstants.jwtStorageKey);
  }

  Future<bool> hasToken() async {
    final token = await readToken();
    return token != null && token.isNotEmpty;
  }
}
