import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/errors/api_exception.dart';
import '../core/network/dio_client.dart';
import '../core/network/socket_service.dart';
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
    final userId = await SecureStorageService.instance.userId;
    final email = await SecureStorageService.instance.userEmail;
    state = AuthState(status: AuthStatus.authenticated, userId: userId, email: email);
    await SocketService.instance.connect();
  }

  void _handleSessionExpired() {
    SocketService.instance.disconnect();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> signIn({required String email, required String password}) async {
    final result = await ref.read(authRepositoryProvider).signIn(email: email, password: password);
    state = AuthState(status: AuthStatus.authenticated, userId: result.userId, email: result.email);
    await SocketService.instance.connect();
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
    final result = await ref.read(authRepositoryProvider).setPassword(
          email: email,
          password: password,
          signupToken: signupToken,
        );
    state = AuthState(status: AuthStatus.authenticated, userId: result.userId, email: result.email);
    await SocketService.instance.connect();
  }

  Future<void> logout() async {
    SocketService.instance.disconnect();
    await ref.read(authRepositoryProvider).logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
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
