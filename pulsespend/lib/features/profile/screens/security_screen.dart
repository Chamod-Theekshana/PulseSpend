import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/security/biometric_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../providers/profile_provider.dart';
import '../widgets/settings_widgets.dart';
import 'change_password_screen.dart';

class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(profileControllerProvider).user;
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(title: const Text('Password & Security')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          const SettingsSectionTitle('Password'),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.lock_outline_rounded,
                title: 'Change Password',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SettingsSectionTitle('Sign-in'),
          SettingsCard(
            children: [
              SettingsSwitchTile(
                icon: Icons.fingerprint_rounded,
                title: 'Biometric unlock',
                subtitle: 'Use fingerprint, face, or device passcode to open the app',
                value: user?.biometricEnabled ?? false,
                onChanged: (v) async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    // Enabling: verify the device can authenticate, then confirm
                    // with a live prompt so we never turn on a lock the user
                    // can't pass.
                    if (v) {
                      final canAuth =
                          await BiometricService.instance.canAuthenticate();
                      if (!canAuth) {
                        messenger.showSnackBar(const SnackBar(
                          content: Text(
                            'Set up a fingerprint, face unlock, or device passcode first.',
                          ),
                        ));
                        return;
                      }
                      final confirmed = await BiometricService.instance
                          .authenticate(reason: 'Confirm to enable biometric unlock');
                      if (!confirmed) return;
                    }
                    await ref
                        .read(profileControllerProvider.notifier)
                        .update(biometricEnabled: v);
                    await SecureStorageService.instance.setBiometricEnabled(v);
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(DioClient.toApiException(e).message)),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Changing your password signs you out of all other devices.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
