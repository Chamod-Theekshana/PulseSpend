import 'dart:async';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../errors/api_exception.dart';
import '../storage/secure_storage.dart';

/// Callback fired when the refresh token itself is rejected — i.e. the user
/// must sign in again. Wired up to a Riverpod auth controller at app start.
typedef OnSessionExpired = void Function();

/// Singleton-ish Dio wrapper.
///
/// Handles:
/// 1. Attaching `Authorization: Bearer <token>` to every request.
/// 2. Transparently refreshing the access token on a 401 and retrying the
///    original request exactly once (access tokens expire after 15m per
///    JWT_EXPIRES_IN in the backend's jwt.ts, so this will fire often on
///    long sessions).
/// 3. Queuing concurrent requests while a refresh is in-flight, so five
///    parallel calls don't trigger five refresh attempts.
/// 4. Converting every failure into an [ApiException] with the backend's
///    `message` field, so the UI never has to know about Dio internals.
class DioClient {
  DioClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(_authInterceptor());
  }

  static final DioClient instance = DioClient._internal();

  late final Dio _dio;
  Dio get dio => _dio;

  OnSessionExpired? onSessionExpired;

  bool _isRefreshing = false;
  final List<Completer<void>> _refreshWaiters = [];

  static const int _maxTransientRetries = 1;

  /// A failure worth retrying: the request either never reached the server
  /// (connection could not be established) or the server explicitly said the
  /// condition is temporary (503). We deliberately exclude [receiveTimeout],
  /// since there the server may have already processed a mutating request.
  bool _isTransient(DioException error) {
    final status = error.response?.statusCode;
    if (status == 503) return true;
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.connectionError;
  }

  InterceptorsWrapper _authInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await SecureStorageService.instance.accessToken;
        if (token != null && !options.path.contains('/auth/signin') &&
            !options.path.contains('/auth/signup') &&
            !options.path.contains('/auth/refresh')) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (DioException error, handler) async {
        final isAuthEndpoint = error.requestOptions.path.contains('/auth/');
        final is401 = error.response?.statusCode == 401;

        if (is401 && !isAuthEndpoint) {
          try {
            await _refreshAccessToken();
            // Retry the original request with the fresh token.
            final retryResponse = await _retry(error.requestOptions);
            return handler.resolve(retryResponse);
          } catch (_) {
            await SecureStorageService.instance.clear();
            onSessionExpired?.call();
            return handler.next(error);
          }
        }

        // Transparently retry transient connectivity failures (e.g. the backend
        // briefly can't reach the database → 503, or the connection couldn't be
        // established). This smooths over the intermittent Neon connect timeouts.
        if (_isTransient(error)) {
          final attempts = (error.requestOptions.extra['retryAttempts'] as int?) ?? 0;
          if (attempts < _maxTransientRetries) {
            await Future.delayed(Duration(milliseconds: 400 * (attempts + 1)));
            try {
              final opts = error.requestOptions
                ..extra['retryAttempts'] = attempts + 1;
              final response = await _dio.fetch(opts);
              return handler.resolve(response);
            } catch (e) {
              return handler.next(e is DioException ? e : error);
            }
          }
        }
        handler.next(error);
      },
    );
  }

  /// Ensures only one refresh call is in-flight at a time. Any request that
  /// hits a 401 while a refresh is already running just waits for it.
  Future<void> _refreshAccessToken() async {
    if (_isRefreshing) {
      final completer = Completer<void>();
      _refreshWaiters.add(completer);
      return completer.future;
    }

    _isRefreshing = true;
    try {
      final refreshToken = await SecureStorageService.instance.refreshToken;
      if (refreshToken == null) throw const ApiException('No refresh token');

      final response = await Dio(BaseOptions(baseUrl: ApiConfig.baseUrl)).post(
        ApiConfig.refreshToken,
        data: {'refreshToken': refreshToken},
      );

      final newAccess = response.data['token'] as String;
      final newRefresh = response.data['refreshToken'] as String;
      await SecureStorageService.instance.updateTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
      );

      for (final waiter in _refreshWaiters) {
        waiter.complete();
      }
      _refreshWaiters.clear();
    } catch (e) {
      for (final waiter in _refreshWaiters) {
        waiter.completeError(e);
      }
      _refreshWaiters.clear();
      rethrow;
    } finally {
      _isRefreshing = false;
    }
  }

  Future<Response> _retry(RequestOptions requestOptions) async {
    final token = await SecureStorageService.instance.accessToken;
    final options = Options(
      method: requestOptions.method,
      headers: {
        ...requestOptions.headers,
        'Authorization': 'Bearer $token',
      },
    );
    return _dio.request(
      requestOptions.path,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: options,
    );
  }

  /// Converts any Dio failure into a clean [ApiException]. English fallback
  /// text stays here for logs/toString; screens should render
  /// [ApiException.localizedMessage] so the user sees their own language.
  static ApiException toApiException(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final data = error.response?.data;
      final isTimeout = error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout;
      String message;
      var hasServerMessage = false;
      if (data is Map && data['message'] != null) {
        message = data['message'].toString();
        hasServerMessage = true;
      } else if (isTimeout) {
        message = 'Connection timed out. Check your network and try again.';
      } else if (error.type == DioExceptionType.connectionError) {
        message = 'Could not reach the server. Is the backend running?';
      } else {
        message = 'Something went wrong. Please try again.';
      }
      return ApiException(
        message,
        statusCode: statusCode,
        hasServerMessage: hasServerMessage,
        kind: isTimeout ? ApiErrorKind.timeout : ApiException.kindForStatus(statusCode),
      );
    }
    if (error is ApiException) return error;
    return ApiException(error.toString());
  }
}
