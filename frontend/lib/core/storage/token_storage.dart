import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Обёртка над FlutterSecureStorage для хранения JWT-токенов.
/// Хранит отдельно токен ученика и токен администратора.
class TokenStorage {
  static const _studentKey = 'student_token';
  static const _adminKey = 'admin_token';

  final FlutterSecureStorage _storage;

  const TokenStorage(this._storage);

  // --- Ученик ---

  Future<void> saveStudentToken(String token) =>
      _storage.write(key: _studentKey, value: token);

  Future<String?> readStudentToken() => _storage.read(key: _studentKey);

  Future<void> deleteStudentToken() => _storage.delete(key: _studentKey);

  // --- Администратор ---

  Future<void> saveAdminToken(String token) =>
      _storage.write(key: _adminKey, value: token);

  Future<String?> readAdminToken() => _storage.read(key: _adminKey);

  Future<void> deleteAdminToken() => _storage.delete(key: _adminKey);
}

/// Провайдер хранилища токенов (singleton).
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  return TokenStorage(secureStorage);
});
