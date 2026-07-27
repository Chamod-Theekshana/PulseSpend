import 'package:flutter/widgets.dart';
import '../../l10n/l10n_ext.dart';

/// Broad classification of an API failure, used to pick a translated
/// user-facing message when the backend didn't provide one.
enum ApiErrorKind { network, timeout, unauthorized, validation, rateLimited, server, unknown }

/// Normalized exception thrown by repositories whenever a backend call fails.
/// The backend consistently returns `{ message: string }` on errors
/// (see errorHandler.ts / every controller's res.status(x).json({ message })),
/// so this is the single shape the UI layer needs to handle.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  /// True when [message] came from the backend's `{message}` payload (already
  /// human-written); false for client-side fallbacks (timeouts, no network).
  final bool hasServerMessage;

  final ApiErrorKind kind;

  const ApiException(
    this.message, {
    this.statusCode,
    this.hasServerMessage = false,
    ApiErrorKind? kind,
  }) : kind = kind ?? ApiErrorKind.unknown;

  /// Derives a [kind] from an HTTP status code (null = no response ⇒ network).
  static ApiErrorKind kindForStatus(int? statusCode) {
    if (statusCode == null) return ApiErrorKind.network;
    if (statusCode == 401 || statusCode == 403) return ApiErrorKind.unauthorized;
    if (statusCode == 429) return ApiErrorKind.rateLimited;
    if (statusCode >= 400 && statusCode < 500) return ApiErrorKind.validation;
    if (statusCode >= 500) return ApiErrorKind.server;
    return ApiErrorKind.unknown;
  }

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isRateLimited => statusCode == 429;
  bool get isNetworkError => statusCode == null;

  /// The message to show the user: the backend's own text when it sent one
  /// (already human-written), otherwise a translated message for [kind] in
  /// the app's locale. Raw `Exception:` strings never reach the UI.
  String localizedMessage(BuildContext context) {
    if (hasServerMessage && message.trim().isNotEmpty) return message;
    final l = context.l10n;
    return switch (kind) {
      ApiErrorKind.network => l.errNetwork,
      ApiErrorKind.timeout => l.errTimeout,
      ApiErrorKind.unauthorized => l.errUnauthorized,
      ApiErrorKind.validation => l.errValidation,
      ApiErrorKind.rateLimited => l.errRateLimited,
      ApiErrorKind.server => l.errServer,
      ApiErrorKind.unknown => l.errUnknown,
    };
  }

  @override
  String toString() => message;
}
