import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pin_code_fields/pin_code_fields.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/repository_providers.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/auth_header.dart';
import '../../../shared/widgets/primary_button.dart';

enum _ResetStep { email, otp, password }

/// Self-service password reset: email → 6-digit passkey → new password.
/// Mirrors the signup flow's look (AuthHeader + pin boxes + fields) and talks
/// to the /api/auth/reset/* endpoints (passwordResetController.ts). On success
/// the user returns to sign-in — old sessions are revoked server-side.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String? initialEmail;
  const ResetPasswordScreen({super.key, this.initialEmail});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(text: widget.initialEmail ?? '');
  final _pinController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _ResetStep _step = _ResetStep.email;
  bool _isLoading = false;
  bool _isResending = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _otpError;
  String _resetToken = '';

  @override
  void dispose() {
    _emailController.dispose();
    _pinController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim().toLowerCase();

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _sendOTP() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).sendResetOTP(_email);
      if (!mounted) return;
      setState(() => _step = _ResetStep.otp);
      _showSnack('If that email is registered, a passkey is on its way.');
    } catch (e) {
      _showSnack(DioClient.toApiException(e).message, color: AppColors.expense);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOTP() async {
    if (_pinController.text.trim().length != 6) {
      setState(() => _otpError = 'Enter the 6-digit passkey');
      return;
    }
    setState(() {
      _isLoading = true;
      _otpError = null;
    });
    try {
      _resetToken = await ref
          .read(authRepositoryProvider)
          .verifyResetOTP(email: _email, passkey: _pinController.text.trim());
      if (!mounted) return;
      setState(() => _step = _ResetStep.password);
    } catch (e) {
      setState(() => _otpError = DioClient.toApiException(e).message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendOTP() async {
    setState(() => _isResending = true);
    try {
      await ref.read(authRepositoryProvider).sendResetOTP(_email);
      _showSnack('Passkey resent — check your inbox');
    } catch (e) {
      _showSnack(DioClient.toApiException(e).message, color: AppColors.expense);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _completeReset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).completeReset(
            email: _email,
            password: _passwordController.text,
            resetToken: _resetToken,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSnack('Password reset! Sign in with your new password.', color: AppColors.income);
    } catch (e) {
      _showSnack(DioClient.toApiException(e).message, color: AppColors.expense);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceAlt = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                switch (_step) {
                  _ResetStep.email => const AuthHeader(
                      icon: Icons.lock_reset_rounded,
                      title: 'Reset your password',
                      subtitle: Text("Enter your account email and we'll send a one-time passkey."),
                    ),
                  _ResetStep.otp => AuthHeader(
                      icon: Icons.mark_email_read_outlined,
                      title: 'Check your inbox',
                      subtitle: Text.rich(
                        TextSpan(
                          text: 'Enter the 6-digit passkey we sent to ',
                          children: [
                            TextSpan(
                              text: _email,
                              style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _ResetStep.password => const AuthHeader(
                      icon: Icons.lock_outline_rounded,
                      title: 'Set a new password',
                      subtitle: Text("At least 8 characters, with an uppercase letter and a number."),
                    ),
                },
                const SizedBox(height: 32),

                // ── Step content ──
                if (_step == _ResetStep.email) ...[
                  AppTextField(
                    controller: _emailController,
                    label: 'Email address',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: const Icon(Icons.mail_outline_rounded),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Email is required';
                      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(label: 'Send Passkey', isLoading: _isLoading, onPressed: _sendOTP),
                ] else if (_step == _ResetStep.otp) ...[
                  PinCodeTextField(
                    appContext: context,
                    length: 6,
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    animationType: AnimationType.fade,
                    backgroundColor: Colors.transparent,
                    textStyle: TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
                    pinTheme: PinTheme(
                      shape: PinCodeFieldShape.box,
                      borderRadius: BorderRadius.circular(14),
                      fieldHeight: 54,
                      fieldWidth: 46,
                      borderWidth: 1.4,
                      activeColor: AppColors.primary,
                      selectedColor: AppColors.primary,
                      inactiveColor: border,
                      activeFillColor: surfaceAlt,
                      selectedFillColor: surfaceAlt,
                      inactiveFillColor: surfaceAlt,
                    ),
                    enableActiveFill: true,
                    onCompleted: (_) => _verifyOTP(),
                    onChanged: (_) {},
                  ),
                  if (_otpError != null) ...[
                    const SizedBox(height: 12),
                    Text(_otpError!, style: const TextStyle(color: AppColors.expense)),
                  ],
                  const SizedBox(height: 28),
                  PrimaryButton(label: 'Verify', isLoading: _isLoading, onPressed: _verifyOTP),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: _isResending ? null : _resendOTP,
                      child: Text(_isResending ? 'Resending…' : "Didn't get it? Resend passkey"),
                    ),
                  ),
                ] else ...[
                  AppTextField(
                    controller: _passwordController,
                    label: 'New password',
                    obscureText: _obscure1,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure1 ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: textSecondary,
                      ),
                      onPressed: () => setState(() => _obscure1 = !_obscure1),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 8) return 'At least 8 characters';
                      if (!RegExp(r'[A-Z]').hasMatch(value)) return 'Add an uppercase letter';
                      if (!RegExp(r'[0-9]').hasMatch(value)) return 'Add a number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _confirmController,
                    label: 'Confirm password',
                    obscureText: _obscure2,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure2 ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: textSecondary,
                      ),
                      onPressed: () => setState(() => _obscure2 = !_obscure2),
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(label: 'Reset Password', isLoading: _isLoading, onPressed: _completeReset),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
