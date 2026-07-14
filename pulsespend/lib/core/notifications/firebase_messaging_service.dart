import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:flutter/material.dart';

import '../config/api_config.dart';
import '../network/dio_client.dart';
import 'notification_router.dart';

/// Background isolate handler. Must be a top-level function annotated with
/// `@pragma('vm:entry-point')`. The backend sends a `notification` block, so FCM
/// renders the banner automatically when the app is backgrounded/killed — this
/// stays minimal (a hook for future data-only processing / deep-linking).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally empty: no heavy work in the background isolate.
}

/// Thin wrapper around Firebase Cloud Messaging.
///
/// Everything is guarded so the app runs perfectly even when Firebase is not
/// configured yet (no `google-services.json` / `GoogleService-Info.plist`). In
/// that case push simply stays off and the in-app notification inbox — which is
/// socket-driven and independent of FCM — keeps working.
///
/// To turn real device push ON:
///   1. Create a Firebase project.
///   2. From `pulsespend/`, run:  flutterfire configure
///      (installs google-services.json / GoogleService-Info.plist + native config)
///   3. Rebuild. This service then obtains a token and registers it via
///      POST /api/notifications/save-token (see notificationsController.ts).
class FirebaseMessagingService {
  FirebaseMessagingService._();
  static final FirebaseMessagingService instance = FirebaseMessagingService._();

  bool _available = false;
  String? _token;

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  /// Android 8+ requires an explicit high-importance channel for heads-up banners.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'pulsespend_default',
    'PulseSpend Notifications',
    description: 'Budget alerts, reminders, goals and account updates',
    importance: Importance.high,
  );

  bool get isAvailable => _available;

  /// Initializes Firebase + FCM. Safe to call once at startup; a missing/broken
  /// Firebase config is swallowed so it never crashes the app.
  Future<void> init() async {
    try {
      await Firebase.initializeApp();

      final messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await messaging.requestPermission(alert: true, badge: true, sound: true);
      // iOS: show heads-up notifications while the app is foregrounded.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Local-notifications plugin: Android won't auto-display an FCM banner
      // while the app is in the FOREGROUND, so we render one ourselves from the
      // onMessage stream (background/killed banners are shown by FCM directly).
      await _localNotifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        // Foreground-banner tap → deep-link (payload = the FCM data.type).
        onDidReceiveNotificationResponse: (response) =>
            handleNotificationTap(response.payload),
      );
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_channel);
      // Android 13+ needs the POST_NOTIFICATIONS runtime permission, or banners
      // are silently dropped.
      await androidPlugin?.requestNotificationsPermission();
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);

      // Deep-linking: tap on a system banner while the app was backgrounded…
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => handleNotificationTap(message.data['type'] as String?),
      );
      // …or while it was fully terminated (deferred until the first frame so
      // the navigator exists before we push).
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => handleNotificationTap(initial.data['type'] as String?),
        );
      }

      _token = await messaging.getToken();
      messaging.onTokenRefresh.listen((token) {
        _token = token;
        _registerWithBackend(token);
      });

      _available = true;
    } catch (e) {
      _available = false;
      // ignore: avoid_print
      print('[FCM] Firebase Messaging unavailable (push disabled, in-app inbox still works): $e');
    }
  }

  /// Renders a heads-up banner for a message received while the app is in the
  /// foreground (Android suppresses FCM's own banner in that case). Title/body
  /// come from the FCM `notification` block, falling back to the `data` copy the
  /// backend also sends.
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] as String?;
    final body = notification?.body ?? message.data['body'] as String?;
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) return;

    await _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      // Carried through to onDidReceiveNotificationResponse for deep-linking.
      payload: message.data['type'] as String?,
    );
  }

  /// The current device token, or null when Firebase isn't configured.
  Future<String?> getToken() async {
    if (!_available) return null;
    if (_token != null) return _token;
    try {
      // Bounded so a slow/hanging FCM lookup can never stall the signup flow
      // (this is awaited in AuthController.completeSignup).
      _token = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 8));
    } catch (_) {}
    return _token;
  }

  /// Registers the current token with the backend for the signed-in user.
  /// Best-effort: silently no-ops when Firebase is off, offline, or unauthed
  /// (the auth layer re-registers on the next successful sign-in).
  Future<void> registerWithBackend() async {
    final token = await getToken();
    if (token != null) await _registerWithBackend(token);
  }

  Future<void> _registerWithBackend(String token) async {
    try {
      await DioClient.instance.dio
          .post(ApiConfig.notificationSaveToken, data: {'fcm_token': token});
    } catch (_) {
      // Not authenticated yet / offline — retried on next auth event.
    }
  }
}
