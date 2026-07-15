import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../providers/auth_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/auth_header.dart';
import '../../../shared/widgets/primary_button.dart';
import 'signup_verify_screen.dart';

/// Step 1 of the passkey signup flow: collect email, ask the backend to
/// send a one-time passkey (see POST /api/auth/send-passkey).
class SignupEmailScreen extends ConsumerStatefulWidget {
  const SignupEmailScreen({super.key});

  @override
  ConsumerState<SignupEmailScreen> createState() => _SignupEmailScreenState();
}

class _SignupEmailScreenState extends ConsumerState<SignupEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final email = _emailController.text.trim().toLowerCase();
    try {
      await ref.read(authControllerProvider.notifier).sendPasskey(email);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SignupVerifyScreen(email: email)),
      );
    } catch (e) {
      if (!mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.localizedMessage(context))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AuthHeader(
                  icon: Icons.person_add_alt_1_rounded,
                  title: 'Create your account',
                  subtitle: Text("We'll email you a one-time passkey to verify it's you."),
                ),
                const SizedBox(height: 32),
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
                PrimaryButton(label: 'Send Passkey', isLoading: _isLoading, onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
