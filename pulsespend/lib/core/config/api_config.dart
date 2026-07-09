/// Central place for backend connection settings and every API path.
///
/// ════════════════════════════════════════════════════════════════════
///  HOW TO RUN
/// ════════════════════════════════════════════════════════════════════
///
///  Android Emulator (default — no flag needed):
///    flutter run
///
///  Real Android / iOS Device (Wi-Fi):
///    flutter run --dart-define=USE_REAL_DEVICE=true
///
///  ⚠️  When using a real device, also update [_realDeviceIp] below
///      to your PC's current LAN IP address.
///      Run: ipconfig   → look for "IPv4 Address" under Wi-Fi adapter.
/// ════════════════════════════════════════════════════════════════════
class ApiConfig {
  ApiConfig._();

  // ── Configuration ─────────────────────────────────────────────────

  /// Set this to your PC's LAN IP when testing on a real device.
  /// e.g. '192.168.1.100'
  static const String _realDeviceIp = '10.177.81.188';

  static const int _port = 5001;

  /// Pass --dart-define=USE_REAL_DEVICE=true when running on a real device.
  static const bool _useRealDevice =
      bool.fromEnvironment('USE_REAL_DEVICE', defaultValue: false);

  /// Base URL — resolved at compile time via dart-define flag.
  ///
  ///  Emulator  →  http://10.0.2.2:5001   (Android loopback alias to host)
  ///  Real device → http://<_realDeviceIp>:5001
  static String get baseUrl =>
      _useRealDevice ? 'http://$_realDeviceIp:$_port' : 'http://10.0.2.2:$_port';

  static const String apiPrefix = '/api';

  // ── Auth ──────────────────────────────────────────────────────────
  static const String signIn = '$apiPrefix/auth/signin';
  static const String signUp = '$apiPrefix/auth/signup';
  static const String refreshToken = '$apiPrefix/auth/refresh';
  static const String logout = '$apiPrefix/auth/logout';

  // Passkey (email OTP) signup flow
  static const String sendPasskey = '$apiPrefix/auth/send-passkey';
  static const String verifyPasskey = '$apiPrefix/auth/verify-passkey';
  static const String setPassword = '$apiPrefix/auth/set-password';

  // ── Transactions ─────────────────────────────────────────────────
  static const String transactions = '$apiPrefix/transaction';
  static String transactionsByUser(String userId) => '$apiPrefix/transaction/$userId';
  static String transactionSummary(String userId) => '$apiPrefix/transaction/summary/$userId';
  static String transactionById(String id) => '$apiPrefix/transaction/id/$id';
  static String transactionDelete(String id) => '$apiPrefix/transaction/$id';
  static String transactionUpdate(String id) => '$apiPrefix/transaction/$id';
  static const String transactionsBulkDelete = '$apiPrefix/transaction/bulk-delete';

  // ── Profile ──────────────────────────────────────────────────────
  static String profile(String id) => '$apiPrefix/profile/$id';
  static String profilePassword(String id) => '$apiPrefix/profile/$id/password';
  static String profileDataExport(String id) => '$apiPrefix/profile/$id/data-export';
  static String profileDataImport(String id) => '$apiPrefix/profile/$id/data-import';

  // ── Categories ───────────────────────────────────────────────────
  static const String categories = '$apiPrefix/categories';
  static String categoryById(int id) => '$apiPrefix/categories/$id';
  static const String categoriesBulkDelete = '$apiPrefix/categories/bulk-delete';

  // ── Budgets ──────────────────────────────────────────────────────
  static const String budgets = '$apiPrefix/budgets';
  static const String budgetStatus = '$apiPrefix/budgets/status';
  static String budgetById(int id) => '$apiPrefix/budgets/$id';
  static const String budgetsBulkDelete = '$apiPrefix/budgets/bulk-delete';

  // ── Recurring ────────────────────────────────────────────────────
  static const String recurring = '$apiPrefix/recurring';
  static String recurringById(int id) => '$apiPrefix/recurring/$id';
  static const String recurringBulkDelete = '$apiPrefix/recurring/bulk-delete';

  // ── Reminders ────────────────────────────────────────────────────
  static const String reminders = '$apiPrefix/reminders';
  static String reminderById(int id) => '$apiPrefix/reminders/$id';
  static const String remindersBulkDelete = '$apiPrefix/reminders/bulk-delete';

  // ── Goals ────────────────────────────────────────────────────────
  static const String goals = '$apiPrefix/goals';
  static String goalById(int id) => '$apiPrefix/goals/$id';
  static String goalContribute(int id) => '$apiPrefix/goals/$id/contribute';
  static const String goalsBulkDelete = '$apiPrefix/goals/bulk-delete';

  // ── Notifications ────────────────────────────────────────────────
  static const String notificationSaveToken = '$apiPrefix/notifications/save-token';
  static const String notificationHistory = '$apiPrefix/notifications/history';
  static const String notificationMarkAllRead = '$apiPrefix/notifications/mark-all-read';
  static String notificationMarkOneRead(int id) => '$apiPrefix/notifications/$id/read';
  static const String notificationClear = '$apiPrefix/notifications/clear';
  static const String notificationPreferences = '$apiPrefix/notifications/preferences';

  // ── Feedback / Report a Problem ──────────────────────────────────
  static const String feedback = '$apiPrefix/feedback';

  // ── Exchange Rates ───────────────────────────────────────────────
  static const String exchangeRates = '$apiPrefix/exchange-rates';
  static const String exchangeRatesConvert = '$apiPrefix/exchange-rates/convert';

  // ── Health ───────────────────────────────────────────────────────
  static const String health = '/health';

  static const Duration connectTimeout = Duration(seconds: 15);
  // Generous enough to let the backend transparently retry a transient DB
  // connection blip before the client gives up.
  static const Duration receiveTimeout = Duration(seconds: 30);
}
