import 'package:flutter/material.dart';
import '../../../shared/widgets/app_loader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/repository_providers.dart';
import '../../../shared/widgets/primary_button.dart';

/// Three-step TOTP enrollment: scan QR (or copy the secret) → verify a code →
/// save the one-shot recovery codes. 2FA only turns on after a successful
/// verify, so a mis-scanned QR can never lock the user out.
class TwoFactorEnrollSheet extends ConsumerStatefulWidget {
  const TwoFactorEnrollSheet({super.key});

  /// Pops with true when 2FA was enabled.
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const TwoFactorEnrollSheet(),
    );
  }

  @override
  ConsumerState<TwoFactorEnrollSheet> createState() => _TwoFactorEnrollSheetState();
}

class _TwoFactorEnrollSheetState extends ConsumerState<TwoFactorEnrollSheet> {
  final _pinController = TextEditingController();

  String? _secret;
  String? _otpauthUrl;
  List<String> _recoveryCodes = const [];
  bool _verified = false;
  bool _isVerifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _enroll();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _enroll() async {
    try {
      final e = await ref.read(authRepositoryProvider).enrollTwoFactor();
      if (!mounted) return;
      setState(() {
        _secret = e.secret;
        _otpauthUrl = e.otpauthUrl;
        _recoveryCodes = e.recoveryCodes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = DioClient.toApiException(e).localizedMessage(context));
    }
  }

  Future<void> _verify(String code) async {
    if (code.trim().length < 6 || _isVerifying) return;
    setState(() {
      _isVerifying = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyTwoFactor(code.trim());
      if (!mounted) return;
      setState(() => _verified = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = DioClient.toApiException(e).localizedMessage(context));
      _pinController.clear();
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _copy(String text, String toast) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFE4E4E4);
    final surfaceAlt = isDark ? AppColors.darkSurface : const Color(0xFFF7F7F9);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _verified ? 'Save your recovery codes' : 'Set up two-factor authentication',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_verified)
            ..._buildRecoveryStep(textPrimary, textSecondary, surfaceAlt, border)
          else if (_otpauthUrl == null)
            ..._buildLoading(textSecondary)
          else
            ..._buildScanStep(textPrimary, textSecondary, surfaceAlt, border),
        ],
      ),
    );
  }

  List<Widget> _buildLoading(Color textSecondary) => [
        const SizedBox(height: 40),
        if (_error != null)
          Column(children: [
            Text(_error!, style: const TextStyle(color: AppColors.expense)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _enroll, child: const Text('Retry')),
          ])
        else
          const Center(child: AppLoader(size: 40)),
        const SizedBox(height: 40),
      ];

  List<Widget> _buildScanStep(
      Color textPrimary, Color textSecondary, Color surfaceAlt, Color border) {
    return [
      Text(
        '1. Scan this QR code with Google Authenticator, Authy, or any TOTP app.',
        style: TextStyle(fontSize: 13, color: textSecondary, height: 1.4),
      ),
      const SizedBox(height: 16),
      Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white, // QR needs a light background in both themes
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: QrImageView(
            data: _otpauthUrl!,
            version: QrVersions.auto,
            size: 190,
          ),
        ),
      ),
      const SizedBox(height: 14),
      // Manual-entry fallback for devices without a camera flow.
      InkWell(
        onTap: () => _copy(_secret!, 'Secret copied'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _secret!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                    letterSpacing: 1.1,
                    color: textPrimary,
                  ),
                ),
              ),
              Icon(Icons.copy_rounded, size: 16, color: textSecondary),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      Text(
        '2. Enter the 6-digit code the app shows to confirm it works.',
        style: TextStyle(fontSize: 13, color: textSecondary, height: 1.4),
      ),
      const SizedBox(height: 12),
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
        onCompleted: _verify,
        onChanged: (_) {},
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(_error!, style: const TextStyle(color: AppColors.expense, fontSize: 12.5)),
      ],
      const SizedBox(height: 12),
      PrimaryButton(
        label: 'Verify & enable',
        isLoading: _isVerifying,
        onPressed: () => _verify(_pinController.text),
      ),
    ];
  }

  List<Widget> _buildRecoveryStep(
      Color textPrimary, Color textSecondary, Color surfaceAlt, Color border) {
    return [
      Text(
        'Two-factor authentication is on. If you lose your authenticator, one of '
        'these one-time codes signs you in. Store them somewhere safe — they '
        'will not be shown again.',
        style: TextStyle(fontSize: 13, color: textSecondary, height: 1.4),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Wrap(
          spacing: 18,
          runSpacing: 10,
          children: [
            for (final code in _recoveryCodes)
              Text(
                code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: textPrimary,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => _copy(_recoveryCodes.join('\n'), 'Recovery codes copied'),
        icon: const Icon(Icons.copy_rounded, size: 18),
        label: const Text('Copy all codes'),
      ),
      const SizedBox(height: 12),
      PrimaryButton(
        label: "I've saved them — done",
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ];
  }
}
