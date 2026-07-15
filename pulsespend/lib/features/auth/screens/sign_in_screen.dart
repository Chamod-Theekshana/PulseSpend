import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../providers/auth_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/auth_logo.dart';
import '../../../shared/widgets/primary_button.dart';
import '../widgets/totp_prompt_sheet.dart';
import 'reset_password_screen.dart';
import 'signup_email_screen.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      var needsTotp = await ref
          .read(authControllerProvider.notifier)
          .signIn(email: email, password: password);
      // 2FA challenge loop: keep prompting until a code works or the user
      // dismisses the sheet.
      String? error;
      while (needsTotp) {
        if (!mounted) return;
        final code = await TotpPromptSheet.show(context, errorText: error);
        if (code == null) break; // user dismissed
        try {
          needsTotp = await ref
              .read(authControllerProvider.notifier)
              .signIn(email: email, password: password, totpCode: code);
          error = null;
        } catch (e) {
          error = DioClient.toApiException(e).localizedMessage(context);
        }
      }
    } catch (e) {
      if (!mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.localizedMessage(context))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _forgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResetPasswordScreen(
          initialEmail: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: AuthLogo()),
                      const SizedBox(height: 28),
                      Text(
                        l.welcomeBack,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l.signInSubtitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: textSecondary, height: 1.4),
                      ),
                      const SizedBox(height: 36),
                      AppTextField(
                        controller: _emailController,
                        label: l.emailAddress,
                        hint: l.emailHint,
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
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _passwordController,
                        label: l.password,
                        hint: l.passwordHint,
                        obscureText: _obscurePassword,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: textSecondary,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Password is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _rememberMe = !_rememberMe),
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    activeColor: AppColors.primary,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    onChanged: (v) => setState(() => _rememberMe = v ?? true),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l.rememberMe,
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _forgotPassword,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              l.forgotPassword,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      PrimaryButton(label: l.signIn, isLoading: _isLoading, onPressed: _submit),
                      const SizedBox(height: 28),
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SignupEmailScreen()),
                            );
                          },
                          behavior: HitTestBehavior.opaque,
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(color: textSecondary, fontSize: 14.5, fontWeight: FontWeight.w500),
                              children: [
                                TextSpan(text: l.newHere),
                                TextSpan(
                                  text: l.createAccount,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
