import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_info.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

class ReportProblemScreen extends ConsumerStatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  ConsumerState<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends ConsumerState<ReportProblemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  String _category = 'problem';
  bool _isLoading = false;

  static const _categories = {
    'problem': ('Report a problem', Icons.error_outline_rounded),
    'suggestion': ('Suggest a feature', Icons.lightbulb_outline_rounded),
    'question': ('Ask a question', Icons.help_outline_rounded),
    'other': ('Something else', Icons.chat_bubble_outline_rounded),
  };

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String get _platform {
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(feedbackRepositoryProvider).submit(
            category: _category,
            subject: _subjectController.text.trim(),
            message: _messageController.text.trim(),
            email: ref.read(profileControllerProvider).user?.email,
            appVersion: '${AppInfo.version}+${AppInfo.build}',
            platform: _platform,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks! Your report has been sent.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Report a Problem')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Text(
              'What can we help with?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textPrimary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _categories.entries.map((e) {
                final selected = _category == e.key;
                return GestureDetector(
                  onTap: () => setState(() => _category = e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary
                          : (isDark ? AppColors.darkSurface : AppColors.lightSurface),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(e.value.$2,
                            size: 17, color: selected ? Colors.white : textSecondary),
                        const SizedBox(width: 7),
                        Text(
                          e.value.$1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            AppTextField(
              controller: _subjectController,
              label: 'Subject',
              hint: 'A short summary',
              validator: (v) =>
                  (v == null || v.trim().length < 3) ? 'Please add a short subject' : null,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _messageController,
              label: 'Message',
              hint: 'Describe what happened, or your idea…',
              maxLines: 6,
              validator: (v) =>
                  (v == null || v.trim().length < 10) ? 'Please add a bit more detail' : null,
            ),
            const SizedBox(height: 12),
            Text(
              'We\'ll include your app version ($_platform · ${AppInfo.version}) so we can help faster.',
              style: TextStyle(fontSize: 12.5, color: textSecondary, height: 1.4),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Send Report',
              isLoading: _isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
