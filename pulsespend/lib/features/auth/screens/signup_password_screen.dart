import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

/// Step 3 (final) of the passkey signup flow: choose a password and finish
/// account creation (see POST /api/auth/set-password). On success the
/// backend returns tokens immediately, so this signs the user straight in.
class SignupPasswordScreen extends ConsumerStatefulWidget {
  final String email;
  final String signupToken;

  const SignupPasswordScreen({super.key, required this.email, required this.signupToken});

  @override
  ConsumerState<SignupPasswordScreen> createState() => _SignupPasswordScreenState();
}

class _SignupPasswordScreenState extends ConsumerState<SignupPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(authControllerProvider.notifier).completeSignup(
            email: widget.email,
            password: _passwordController.text,
            signupToken: widget.signupToken,
          );
      // AuthController flips to authenticated -> SplashGate swaps to HomeShell.
    } catch (e) {
      if (!mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                Text(
                  'Set a password',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'At least 8 characters. Use something you don\'t use elsewhere.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.lightTextSecondary),
                ),
                const SizedBox(height: 32),
                AppTextField(
                  controller: _passwordController,
                  label: 'Password',
                  obscureText: _obscure1,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure1 ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure1 = !_obscure1),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 8) return 'At least 8 characters';
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
                    icon: Icon(_obscure2 ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure2 = !_obscure2),
                  ),
                  validator: (value) {
                    if (value != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                PrimaryButton(label: 'Create Account', isLoading: _isLoading, onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
