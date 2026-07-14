import '../core/config/api_config.dart';
import '../core/network/dio_client.dart';
import '../core/storage/secure_storage.dart';

/// Auth flows used by this app (per the user's choice):
///  - Sign up: passkey flow -> send-passkey, verify-passkey, set-password
///  - Sign in: classic email + password (the only sign-in route the backend
///    exposes; passkey routes are signup-only, see signupRoutes.ts)
class AuthRepository {
  final _dio = DioClient.instance.dio;

  /// Step 1 of signup: backend emails a 6-digit passkey/OTP to this address.
  /// Throws ApiException('Email already registered') if the email exists.
  Future<void> sendPasskey(String email) async {
    try {
      await _dio.post(ApiConfig.sendPasskey, data: {'email': email});
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Step 2: verify the code the user typed. Returns a short-lived
  /// `signupToken` that must be passed to setPassword.
  Future<String> verifyPasskey({required String email, required String passkey}) async {
    try {
      final res = await _dio.post(
        ApiConfig.verifyPasskey,
        data: {'email': email, 'passkey': passkey},
      );
      return res.data['signupToken'] as String;
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Step 3: set the password and finish account creation. On success the
  /// backend returns tokens + user immediately (no separate sign-in needed).
  Future<({String userId, String email})> setPassword({
    required String email,
    required String password,
    required String signupToken,
    String? fcmToken,
  }) async {
    try {
      final res = await _dio.post(
        ApiConfig.setPassword,
        data: {
          'email': email,
          'password': password,
          'signupToken': signupToken,
          if (fcmToken != null) 'fcm_token': fcmToken,
        },
      );
      final data = res.data as Map<String, dynamic>;
      await SecureStorageService.instance.saveSession(
        accessToken: data['token'] as String,
        refreshToken: data['refreshToken'] as String,
        userId: data['user']['id'].toString(),
        email: data['user']['email'] as String,
      );
      return (userId: data['user']['id'].toString(), email: data['user']['email'] as String);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<({String userId, String email})> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _dio.post(ApiConfig.signIn, data: {'email': email, 'password': password});
      final data = res.data as Map<String, dynamic>;
      await SecureStorageService.instance.saveSession(
        accessToken: data['token'] as String,
        refreshToken: data['refreshToken'] as String,
        userId: data['user']['id'].toString(),
        email: data['user']['email'] as String,
      );
      return (userId: data['user']['id'].toString(), email: data['user']['email'] as String);
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  // ── Password reset (see passwordResetController.ts) ──────────────────────

  /// Sends a reset passkey to [email]. The backend responds identically whether
  /// or not the address is registered (no account probing).
  Future<void> sendResetOTP(String email) async {
    try {
      await _dio.post(ApiConfig.resetSend, data: {'email': email});
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Verifies the reset passkey; returns a short-lived `resetToken`.
  Future<String> verifyResetOTP({required String email, required String passkey}) async {
    try {
      final res = await _dio.post(
        ApiConfig.resetVerify,
        data: {'email': email, 'passkey': passkey},
      );
      return res.data['resetToken'] as String;
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  /// Sets the new password. Old sessions are revoked server-side; the user
  /// signs in fresh afterwards.
  Future<void> completeReset({
    required String email,
    required String password,
    required String resetToken,
  }) async {
    try {
      await _dio.post(
        ApiConfig.resetComplete,
        data: {'email': email, 'password': password, 'resetToken': resetToken},
      );
    } catch (e) {
      throw DioClient.toApiException(e);
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post(ApiConfig.logout);
    } catch (_) {
      // Best-effort — clear local session regardless of server response.
    } finally {
      await SecureStorageService.instance.clear();
    }
  }
}
