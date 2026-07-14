import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../shared/widgets/auth_header.dart';
import '../../../shared/widgets/primary_button.dart';
import 'signup_password_screen.dart';

/// Step 2 of the passkey signup flow: verify the 6-digit passkey emailed in
/// step 1 (see POST /api/auth/verify-passkey). On success the backend
/// returns a short-lived `signupToken` needed for the final step.
class SignupVerifyScreen extends ConsumerStatefulWidget {
  final String email;

  const SignupVerifyScreen({super.key, required this.email});

  @override
  ConsumerState<SignupVerifyScreen> createState() => _SignupVerifyScreenState();
}

class _SignupVerifyScreenState extends ConsumerState<SignupVerifyScreen> {
  final _pinController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_pinController.text.trim().length != 6) {
      setState(() => _errorText = 'Enter the 6-digit passkey');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      final signupToken = await ref.read(authControllerProvider.notifier).verifyPasskey(
            email: widget.email,
            passkey: _pinController.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SignupPasswordScreen(email: widget.email, signupToken: signupToken),
        ),
      );
    } catch (e) {
      final apiEx = DioClient.toApiException(e);
      setState(() => _errorText = apiEx.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _isResending = true);
    try {
      await ref.read(authControllerProvider.notifier).sendPasskey(widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passkey resent — check your inbox')),
      );
    } catch (e) {
      if (!mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.message)));
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceAlt = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuthHeader(
                icon: Icons.mark_email_read_outlined,
                title: 'Check your inbox',
                subtitle: Text.rich(
                  TextSpan(
                    text: 'Enter the 6-digit passkey we sent to ',
                    children: [
                      TextSpan(
                        text: widget.email,
                        style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              PinCodeTextField(
                appContext: context,
                length: 6,
                controller: _pinController,
                keyboardType: TextInputType.number,
                animationType: AnimationType.fade,
                // Transparent, or the hidden input inherits the global filled
                // input theme and paints a rectangle behind the 6 boxes.
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
                onCompleted: (_) => _verify(),
                onChanged: (_) {},
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(_errorText!, style: const TextStyle(color: AppColors.expense)),
              ],
              const SizedBox(height: 28),
              PrimaryButton(label: 'Verify', isLoading: _isLoading, onPressed: _verify),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _isResending ? null : _resend,
                  child: Text(_isResending ? 'Resending…' : "Didn't get it? Resend passkey"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
