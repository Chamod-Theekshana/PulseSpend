import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Lightweight descriptor for a stored account in the multi-account registry.
class StoredAccount {
  final String userId;
  final String email;
  const StoredAccount({required this.userId, required this.email});
}

/// Wraps [FlutterSecureStorage] for everything related to auth persistence.
/// Access + refresh tokens live here, never in shared_preferences or memory-only,
/// so a killed app can silently resume the session via the refresh token.
///
/// Supports multiple signed-in accounts: the *active* session lives under the
/// `_kAccessToken`/… keys (what [DioClient] reads), while every account the
/// user has signed into is mirrored into an `_kAccounts` JSON registry so they
/// can switch between them without re-entering credentials.
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
  static const _kAccounts = 'pulsespend_accounts';
  static const _kTheme = 'pulsespend_theme';
  static const _kBiometric = 'pulsespend_biometric_enabled';
  static const _kOnboardingSeen = 'pulsespend_onboarding_seen';

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
    await _upsertAccount(userId, email, accessToken, refreshToken);
  }

  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccessToken, value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
    ]);
    // Keep the registry copy of the active account in sync after a refresh.
    final uid = await userId;
    final mail = await userEmail;
    if (uid != null) {
      await _upsertAccount(uid, mail ?? '', accessToken, refreshToken);
    }
  }

  Future<String?> get accessToken => _storage.read(key: _kAccessToken);
  Future<String?> get refreshToken => _storage.read(key: _kRefreshToken);
  Future<String?> get userId => _storage.read(key: _kUserId);
  Future<String?> get userEmail => _storage.read(key: _kUserEmail);

  Future<bool> get hasSession async => (await accessToken) != null;

  /// Cached theme preference ('dark' | 'light'), read at startup to seed the
  /// app theme before the profile finishes loading — avoids a flash of the
  /// wrong colour. Kept in sync whenever the profile theme changes.
  Future<String?> get themePref => _storage.read(key: _kTheme);
  Future<void> setThemePref(String value) => _storage.write(key: _kTheme, value: value);

  /// Device-level app-lock preference. Stored locally (not just on the profile)
  /// so the lock gate can decide whether to challenge on launch/resume without
  /// waiting for the network profile to load.
  Future<bool> get biometricEnabled async =>
      (await _storage.read(key: _kBiometric)) == 'true';
  Future<void> setBiometricEnabled(bool value) =>
      _storage.write(key: _kBiometric, value: value ? 'true' : 'false');

  /// Whether the first-run onboarding walkthrough has been completed on this
  /// device. Device-scoped (not per account), shown once before sign-in.
  Future<bool> get onboardingSeen async =>
      (await _storage.read(key: _kOnboardingSeen)) == 'true';
  Future<void> setOnboardingSeen() =>
      _storage.write(key: _kOnboardingSeen, value: 'true');

  /// Clears the *active* session keys only. The account registry is preserved
  /// (use [removeAccount] to forget an account entirely).
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
      _storage.delete(key: _kUserId),
      _storage.delete(key: _kUserEmail),
    ]);
  }

  // ── Multi-account registry ─────────────────────────────────────────────

  Future<Map<String, dynamic>> _accountsMap() async {
    final raw = await _storage.read(key: _kAccounts);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _upsertAccount(
    String userId,
    String email,
    String accessToken,
    String refreshToken,
  ) async {
    final map = await _accountsMap();
    map[userId] = {
      'email': email,
      'access': accessToken,
      'refresh': refreshToken,
    };
    await _storage.write(key: _kAccounts, value: jsonEncode(map));
  }

  /// All accounts the user has signed into on this device.
  Future<List<StoredAccount>> listAccounts() async {
    final map = await _accountsMap();
    return map.entries
        .map((e) => StoredAccount(
              userId: e.key,
              email: (e.value is Map ? e.value['email'] : null)?.toString() ?? '',
            ))
        .toList();
  }

  /// Ensures the currently-active session is present in the registry — used at
  /// bootstrap so accounts created before multi-account support still appear.
  Future<void> ensureActiveRegistered() async {
    final uid = await userId;
    if (uid == null) return;
    final map = await _accountsMap();
    if (map.containsKey(uid)) return;
    final access = await accessToken;
    final refresh = await refreshToken;
    final mail = await userEmail;
    if (access != null && refresh != null) {
      await _upsertAccount(uid, mail ?? '', access, refresh);
    }
  }

  /// Copies a registered account's tokens into the active session keys.
  /// Returns null if the account isn't in the registry.
  Future<StoredAccount?> switchTo(String userId) async {
    final map = await _accountsMap();
    final acc = map[userId];
    if (acc is! Map) return null;
    final email = acc['email']?.toString() ?? '';
    await Future.wait([
      _storage.write(key: _kAccessToken, value: acc['access']?.toString()),
      _storage.write(key: _kRefreshToken, value: acc['refresh']?.toString()),
      _storage.write(key: _kUserId, value: userId),
      _storage.write(key: _kUserEmail, value: email),
    ]);
    return StoredAccount(userId: userId, email: email);
  }

  /// Forgets an account (removes it from the registry). Does not touch the
  /// active session keys — caller decides whether the active user changed.
  Future<void> removeAccount(String userId) async {
    final map = await _accountsMap();
    map.remove(userId);
    await _storage.write(key: _kAccounts, value: jsonEncode(map));
  }

  /// The first available account in the registry, or null if none remain.
  Future<StoredAccount?> firstAccount() async {
    final accounts = await listAccounts();
    return accounts.isEmpty ? null : accounts.first;
  }
}
