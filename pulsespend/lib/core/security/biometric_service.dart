import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Thin wrapper around [LocalAuthentication] with all platform exceptions
/// swallowed into booleans, so callers never have to try/catch.
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  /// True when the device can perform *some* authentication — biometrics or a
  /// device passcode/PIN. Used to decide whether locking is even possible (we
  /// never lock a device with no way to unlock).
  Future<bool> canAuthenticate() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// True when a biometric (fingerprint/face) is enrolled — used to gate the
  /// settings toggle so we don't advertise biometrics the device lacks.
  Future<bool> hasEnrolledBiometrics() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final canCheck = await _auth.canCheckBiometrics;
      final available = await _auth.getAvailableBiometrics();
      return canCheck && available.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  /// Prompts the user to authenticate. Falls back to the device passcode when
  /// biometrics aren't available (so a failed fingerprint can't lock the user
  /// out permanently). Returns true only on success.
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
