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
///
///  Production / staging (REQUIRED — use HTTPS, never ship the http:// dev URLs):
///    flutter build apk --dart-define=API_BASE_URL=https://api.yourdomain.com
///  This override takes precedence over every dev default below and applies to
///  both REST (Dio) and the realtime socket.
/// ════════════════════════════════════════════════════════════════════
class ApiConfig {
  ApiConfig._();

  // ── Configuration ─────────────────────────────────────────────────

  /// Explicit base URL override (e.g. a production HTTPS host). When set via
  /// --dart-define=API_BASE_URL=... it wins over the dev defaults, so release
  /// builds never fall back to cleartext http:// LAN addresses.
  static const String _baseUrlOverride =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Set this to your PC's LAN IP when testing on a real device.
  /// e.g. '192.168.1.100'
  static const String _realDeviceIp = '10.169.229.180';

  static const int _port = 5001;

  /// Pass --dart-define=USE_REAL_DEVICE=true when running on a real device.
  static const bool _useRealDevice =
      bool.fromEnvironment('USE_REAL_DEVICE', defaultValue: false);

  /// Base URL — resolved at compile time.
  ///
  ///  API_BASE_URL set → that value   (production HTTPS host)
  ///  Emulator         → http://10.0.2.2:5001   (Android loopback alias to host)
  ///  Real device      → http://<_realDeviceIp>:5001
  static String get baseUrl {
    if (_baseUrlOverride.isNotEmpty) return _baseUrlOverride;
    return _useRealDevice ? 'http://$_realDeviceIp:$_port' : 'http://10.0.2.2:$_port';
  }

  /// True when talking to the backend over plaintext HTTP (dev only). Useful to
  /// gate warnings or refuse to persist sensitive data in insecure builds.
  static bool get isInsecureTransport => baseUrl.startsWith('http://');

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

  // Self-service password reset (email OTP)
  static const String resetSend = '$apiPrefix/auth/reset/send';
  static const String resetVerify = '$apiPrefix/auth/reset/verify';
  static const String resetComplete = '$apiPrefix/auth/reset/complete';

  // TOTP 2FA
  static const String twoFaStatus = '$apiPrefix/auth/2fa/status';
  static const String twoFaEnroll = '$apiPrefix/auth/2fa/enroll';
  static const String twoFaVerify = '$apiPrefix/auth/2fa/verify';
  static const String twoFaDisable = '$apiPrefix/auth/2fa/disable';

  // ── Transactions ─────────────────────────────────────────────────
  static const String transactions = '$apiPrefix/transaction';
  static String transactionsByUser(String userId) => '$apiPrefix/transaction/$userId';
  static String transactionSummary(String userId) => '$apiPrefix/transaction/summary/$userId';
  static String transactionExportCsv(String userId) => '$apiPrefix/transaction/export/$userId';
  static String transactionReportPdf(String userId) => '$apiPrefix/transaction/report-pdf/$userId';
  static String transactionById(String id) => '$apiPrefix/transaction/id/$id';
  static String transactionDelete(String id) => '$apiPrefix/transaction/$id';
  static String transactionUpdate(String id) => '$apiPrefix/transaction/$id';
  static const String transactionsBulkDelete = '$apiPrefix/transaction/bulk-delete';
  static const String transactionsBulkImport = '$apiPrefix/transaction/bulk-import';

  // ── Profile ──────────────────────────────────────────────────────
  static String profile(String id) => '$apiPrefix/profile/$id';
  static String profilePassword(String id) => '$apiPrefix/profile/$id/password';
  static String profileDataExport(String id) => '$apiPrefix/profile/$id/data-export';
  static String profileRoundup(String id) => '$apiPrefix/profile/$id/roundup';
  static String profileDataImport(String id) => '$apiPrefix/profile/$id/data-import';
  static String profileCancelDeletion(String id) => '$apiPrefix/profile/$id/cancel-deletion';

  // ── Categories ───────────────────────────────────────────────────
  static const String categories = '$apiPrefix/categories';
  static String categoryById(int id) => '$apiPrefix/categories/$id';
  static const String categoriesBulkDelete = '$apiPrefix/categories/bulk-delete';

  // ── Budgets ──────────────────────────────────────────────────────
  static const String budgets = '$apiPrefix/budgets';
  static const String budgetStatus = '$apiPrefix/budgets/status';
  static const String budgetTotalStatus = '$apiPrefix/budgets/total-status';
  static const String budgetTotal = '$apiPrefix/budgets/total';
  static String budgetById(int id) => '$apiPrefix/budgets/$id';
  static const String budgetsBulkDelete = '$apiPrefix/budgets/bulk-delete';

  // ── Recurring ────────────────────────────────────────────────────
  static const String recurring = '$apiPrefix/recurring';
  static const String recurringDetected = '$apiPrefix/recurring/detected';
  static const String recurringDetectedDismiss = '$apiPrefix/recurring/detected/dismiss';
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
  static String goalContributions(int id) => '$apiPrefix/goals/$id/contributions';
  static String goalAutoRule(int id) => '$apiPrefix/goals/$id/auto';
  static const String goalsBulkDelete = '$apiPrefix/goals/bulk-delete';

  // ── Notifications ────────────────────────────────────────────────
  static const String notificationSaveToken = '$apiPrefix/notifications/save-token';
  static const String notificationHistory = '$apiPrefix/notifications/history';
  static const String notificationMarkAllRead = '$apiPrefix/notifications/mark-all-read';
  static String notificationMarkOneRead(int id) => '$apiPrefix/notifications/$id/read';
  static const String notificationClear = '$apiPrefix/notifications/clear';
  static const String notificationPreferences = '$apiPrefix/notifications/preferences';

  // ── Analytics ────────────────────────────────────────────────────
  static const String analytics = '$apiPrefix/analytics';
  static const String analyticsDigest = '$apiPrefix/analytics/digest';
  static const String analyticsInsights = '$apiPrefix/analytics/insights';
  static const String analyticsDaily = '$apiPrefix/analytics/daily';

  // ── Feedback / Report a Problem ──────────────────────────────────
  static const String feedback = '$apiPrefix/feedback';

  // ── Shared / Family Groups ───────────────────────────────────────
  static const String groups = '$apiPrefix/groups';
  static const String groupJoin = '$apiPrefix/groups/join';
  static String groupMembers(int id) => '$apiPrefix/groups/$id/members';
  static String groupTransactions(int id) => '$apiPrefix/groups/$id/transactions';
  static String groupBalances(int id) => '$apiPrefix/groups/$id/balances';
  static String groupGoals(int id) => '$apiPrefix/groups/$id/goals';
  static String groupSettle(int id) => '$apiPrefix/groups/$id/settle';
  static String groupLeave(int id) => '$apiPrefix/groups/$id/leave';

  // ── Wallets / Accounts ───────────────────────────────────────────
  static const String wallets = '$apiPrefix/wallets';
  static const String walletBalances = '$apiPrefix/wallets/balances';
  static const String walletNetWorth = '$apiPrefix/wallets/net-worth';
  static const String walletTransfer = '$apiPrefix/wallets/transfer';
  static String walletById(int id) => '$apiPrefix/wallets/$id';

  // ── Debts / IOUs ─────────────────────────────────────────────────
  static const String debts = '$apiPrefix/debts';
  static String debtSettle(int id) => '$apiPrefix/debts/$id/settle';
  static String debtById(int id) => '$apiPrefix/debts/$id';

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
