import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps [FlutterSecureStorage] for everything related to auth persistence.
/// Access + refresh tokens live here, never in shared_preferences or memory-only,
/// so a killed app can silently resume the session via the refresh token.
class SecureStorageService {
  SecureStorageService._internal();
  static final SecureStorageService instance = SecureStorageService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kAccessToken = 'pulsespend_access_token';
  static const _kRefreshToken = 'pulsespend_refresh_token';
  static const _kUserId = 'pulsespend_user_id';
  static const _kUserEmail = 'pulsespend_user_email';

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String email,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccessToken, value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
      _storage.write(key: _kUserId, value: userId),
      _storage.write(key: _kUserEmail, value: email),
    ]);
  }

  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccessToken, value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
    ]);
  }

  Future<String?> get accessToken => _storage.read(key: _kAccessToken);
  Future<String?> get refreshToken => _storage.read(key: _kRefreshToken);
  Future<String?> get userId => _storage.read(key: _kUserId);
  Future<String?> get userEmail => _storage.read(key: _kUserEmail);

  Future<bool> get hasSession async => (await accessToken) != null;

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
      _storage.delete(key: _kUserId),
      _storage.delete(key: _kUserEmail),
    ]);
  }
}
