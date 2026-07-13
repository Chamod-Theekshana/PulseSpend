import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/errors/api_exception.dart';
import '../core/network/dio_client.dart';
import '../core/network/socket_service.dart';
import '../core/notifications/firebase_messaging_service.dart';
import '../core/storage/secure_storage.dart';
import 'repository_providers.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final String? userId;
  final String? email;

  const AuthState({this.status = AuthStatus.unknown, this.userId, this.email});

  AuthState copyWith({AuthStatus? status, String? userId, String? email}) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      email: email ?? this.email,
    );
  }

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

/// Owns the whole session lifecycle: bootstrap from secure storage on app
/// start, sign in, signup (3-step passkey flow), logout, and reacting to a
/// forced session expiry triggered by DioClient when a refresh token dies.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    DioClient.instance.onSessionExpired = _handleSessionExpired;
    Future.microtask(_bootstrap);
    return const AuthState();
  }

  Future<void> _bootstrap() async {
    final hasSession = await SecureStorageService.instance.hasSession;
    if (!hasSession) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    // Backfill the multi-account registry for sessions created before the
    // account-switcher feature existed.
    await SecureStorageService.instance.ensureActiveRegistered();
    final userId = await SecureStorageService.instance.userId;
    final email = await SecureStorageService.instance.userEmail;
    state = AuthState(status: AuthStatus.authenticated, userId: userId, email: email);
    await SocketService.instance.connect();
    await _registerPushToken();
  }

  void _handleSessionExpired() {
    SocketService.instance.disconnect();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Registers this device's FCM token for the now-signed-in user so pushes can
  /// be delivered. No-ops when Firebase isn't configured (see the messaging
  /// service) — never throws.
  Future<void> _registerPushToken() async {
    await FirebaseMessagingService.instance.registerWithBackend();
  }

  Future<void> signIn({required String email, required String password}) async {
    final result = await ref.read(authRepositoryProvider).signIn(email: email, password: password);
    state = AuthState(status: AuthStatus.authenticated, userId: result.userId, email: result.email);
    await SocketService.instance.connect();
    await _registerPushToken();
  }

  Future<void> sendPasskey(String email) {
    return ref.read(authRepositoryProvider).sendPasskey(email);
  }

  Future<String> verifyPasskey({required String email, required String passkey}) {
    return ref.read(authRepositoryProvider).verifyPasskey(email: email, passkey: passkey);
  }

  Future<void> completeSignup({
    required String email,
    required String password,
    required String signupToken,
  }) async {
    // Pass the FCM token at signup so the backend can register it and deliver
    // the Welcome push immediately (see setPassword in signupController.ts).
    final fcmToken = await FirebaseMessagingService.instance.getToken();
    final result = await ref.read(authRepositoryProvider).setPassword(
          email: email,
          password: password,
          signupToken: signupToken,
          fcmToken: fcmToken,
        );
    state = AuthState(status: AuthStatus.authenticated, userId: result.userId, email: result.email);
    await SocketService.instance.connect();
    await _registerPushToken();
  }

  Future<void> logout() async {
    final currentId = state.userId ?? await SecureStorageService.instance.userId;
    SocketService.instance.disconnect();
    await ref.read(authRepositoryProvider).logout();
    if (currentId != null) {
      await SecureStorageService.instance.removeAccount(currentId);
    }
    // If the user has another signed-in account, fall through to it instead of
    // bouncing all the way out to the sign-in screen.
    final next = await SecureStorageService.instance.firstAccount();
    if (next != null) {
      await SecureStorageService.instance.switchTo(next.userId);
      state = AuthState(status: AuthStatus.authenticated, userId: next.userId, email: next.email);
      await SocketService.instance.connect();
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// Permanently deletes the active account server-side (after re-confirming
  /// the password), then forgets it locally — falling through to another
  /// signed-in account if one exists, otherwise signing out completely.
  Future<void> deleteAccount(String password) async {
    final userId = state.userId ?? await SecureStorageService.instance.userId;
    if (userId == null) throw const ApiException('Not authenticated');
    await ref.read(profileRepositoryProvider).deleteAccount(userId, password: password);
    await removeAccount(userId);
  }

  /// All accounts signed into on this device.
  Future<List<StoredAccount>> listAccounts() =>
      SecureStorageService.instance.listAccounts();

  /// Switches the active session to an already signed-in account (no re-login).
  Future<void> switchAccount(String userId) async {
    if (userId == state.userId) return;
    final acc = await SecureStorageService.instance.switchTo(userId);
    if (acc == null) return;
    SocketService.instance.disconnect();
    state = AuthState(status: AuthStatus.authenticated, userId: acc.userId, email: acc.email);
    await SocketService.instance.connect();
    await _registerPushToken();
  }

  /// Forgets an account. If it was the active one, switches to another (or
  /// signs out entirely when none remain).
  Future<void> removeAccount(String userId) async {
    await SecureStorageService.instance.removeAccount(userId);
    if (userId != state.userId) return;
    SocketService.instance.disconnect();
    final next = await SecureStorageService.instance.firstAccount();
    if (next != null) {
      await SecureStorageService.instance.switchTo(next.userId);
      state = AuthState(status: AuthStatus.authenticated, userId: next.userId, email: next.email);
      await SocketService.instance.connect();
    } else {
      await SecureStorageService.instance.clear();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Convenience: throws if read before a userId exists. Screens behind the
/// authenticated shell can safely use this without null-checking everywhere.
final currentUserIdProvider = Provider<String>((ref) {
  final id = ref.watch(authControllerProvider).userId;
  if (id == null) throw const ApiException('Not authenticated');
  return id;
});
