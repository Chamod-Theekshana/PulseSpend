import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

/// Collects the second factor during sign-in: a 6-digit authenticator code,
/// or (via the toggle) a one-shot recovery code. Pops with the entered code,
/// or null if dismissed. Shown again with [errorText] when a code is rejected.
class TotpPromptSheet extends StatefulWidget {
  final String? errorText;
  const TotpPromptSheet({super.key, this.errorText});

  /// Returns the entered code, or null when the user dismissed the sheet.
  static Future<String?> show(BuildContext context, {String? errorText}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TotpPromptSheet(errorText: errorText),
    );
  }

  @override
  State<TotpPromptSheet> createState() => _TotpPromptSheetState();
}

class _TotpPromptSheetState extends State<TotpPromptSheet> {
  final _pinController = TextEditingController();
  final _recoveryController = TextEditingController();
  bool _useRecovery = false;

  @override
  void dispose() {
    _pinController.dispose();
    _recoveryController.dispose();
    super.dispose();
  }

  void _submit(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final border = isDark ? AppColors.darkBorder : const Color(0xFFE4E4E4);
    final surfaceAlt = isDark ? AppColors.darkSurface : const Color(0xFFF7F7F9);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Text('Two-factor verification',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _useRecovery
                ? 'Enter one of your saved recovery codes. Each code works once.'
                : 'Enter the 6-digit code from your authenticator app.',
            style: TextStyle(fontSize: 13, color: textSecondary, height: 1.4),
          ),
          if (widget.errorText != null) ...[
            const SizedBox(height: 10),
            Text(widget.errorText!,
                style: const TextStyle(color: AppColors.expense, fontSize: 12.5)),
          ],
          const SizedBox(height: 20),
          if (_useRecovery) ...[
            AppTextField(
              controller: _recoveryController,
              label: 'Recovery code',
              hint: 'xxxx-xxxx',
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Verify',
              onPressed: () => _submit(_recoveryController.text),
            ),
          ] else ...[
            PinCodeTextField(
              appContext: context,
              length: 6,
              controller: _pinController,
              keyboardType: TextInputType.number,
              autoFocus: true,
              animationType: AnimationType.fade,
              // Transparent, or the hidden input inherits the global filled
              // input theme and paints a rectangle behind the 6 boxes.
              backgroundColor: Colors.transparent,
              textStyle:
                  TextStyle(color: textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
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
              onCompleted: _submit,
              onChanged: (_) {},
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Verify',
              onPressed: () => _submit(_pinController.text),
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _useRecovery = !_useRecovery),
              child: Text(
                _useRecovery ? 'Use authenticator code instead' : 'Use a recovery code instead',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
