import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // NOTE: If you wire up Firebase Cloud Messaging (the backend already
  // expects an `fcm_token` via POST /api/notifications/save-token — see
  // pushService.ts), initialize Firebase.initializeApp() here before
  // runApp(), and request notification permissions on first launch.

  runApp(const ProviderScope(child: PulseSpendApp()));
}
