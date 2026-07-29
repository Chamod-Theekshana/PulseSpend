import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/security/biometric_service.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../widgets/settings_widgets.dart';
import '../widgets/two_factor_enroll_sheet.dart';
import 'change_password_screen.dart';
import '../../../l10n/l10n_ext.dart';

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
                      SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SettingsSectionTitle('Two-factor authentication'),
          SettingsCard(
            children: [
              Consumer(builder: (context, ref, _) {
                final statusAsync = ref.watch(twoFactorStatusProvider);
                final enabled = statusAsync.value ?? false;
                return SettingsSwitchTile(
                  icon: Icons.verified_user_outlined,
                  title: 'Authenticator app (TOTP)',
                  subtitle: enabled
                      ? 'A 6-digit code is required when signing in'
                      : 'Require a 6-digit code from an authenticator app at sign-in',
                  value: enabled,
                  onChanged: statusAsync.isLoading
                      ? null
                      : (v) async {
                          if (v) {
                            final done = await TwoFactorEnrollSheet.show(context);
                            if (done == true) ref.invalidate(twoFactorStatusProvider);
                          } else {
                            final disabled = await showDialog<bool>(
                              context: context,
                              builder: (_) => const _DisableTwoFactorDialog(),
                            );
                            if (disabled == true) ref.invalidate(twoFactorStatusProvider);
                          }
                        },
                );
              }),
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

/// Turning 2FA off needs the password AND a current authenticator (or
/// recovery) code — matches the backend's disable requirements.
class _DisableTwoFactorDialog extends ConsumerStatefulWidget {
  const _DisableTwoFactorDialog();

  @override
  ConsumerState<_DisableTwoFactorDialog> createState() => _DisableTwoFactorDialogState();
}

class _DisableTwoFactorDialogState extends ConsumerState<_DisableTwoFactorDialog> {
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _disable() async {
    final password = _passwordController.text;
    final code = _codeController.text.trim();
    if (password.isEmpty || code.isEmpty) {
      setState(() => _error = 'Password and code are required');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .disableTwoFactor(password: password, code: code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = DioClient.toApiException(e).localizedMessage(context));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Turn off two-factor?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Confirm with your password and a current authenticator code '
            '(or a recovery code).',
            style: TextStyle(fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _passwordController,
            label: 'Password',
            obscureText: true,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _codeController,
            label: 'Authenticator or recovery code',
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12.5)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _disable,
          child: Text(_isLoading ? 'Turning off…' : 'Turn off'),
        ),
      ],
    );
  }
}
