import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'profile_provider.dart';

/// Maps the human-readable language names stored on the profile (and shown in
/// the Settings language picker) to their locale codes.
const Map<String, Locale> kLanguageLocales = {
  'English': Locale('en'),
  'Sinhala': Locale('si'),
  'Tamil': Locale('ta'),
  'Spanish': Locale('es'),
  'French': Locale('fr'),
  'German': Locale('de'),
  'Hindi': Locale('hi'),
};

/// The active [Locale], driven by `profile.language`. Watching only the
/// language field keeps rebuilds minimal (Section 8: provider `select`).
final localeProvider = Provider<Locale>((ref) {
  final language = ref.watch(
    profileControllerProvider.select((s) => s.user?.language),
  );
  return kLanguageLocales[language] ?? const Locale('en');
});
