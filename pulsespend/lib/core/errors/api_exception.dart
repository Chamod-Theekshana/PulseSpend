/// Normalized exception thrown by repositories whenever a backend call fails.
/// The backend consistently returns `{ message: string }` on errors
/// (see errorHandler.ts / every controller's res.status(x).json({ message })),
/// so this is the single shape the UI layer needs to handle.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isRateLimited => statusCode == 429;
  bool get isNetworkError => statusCode == null;

  @override
  String toString() => message;
}
