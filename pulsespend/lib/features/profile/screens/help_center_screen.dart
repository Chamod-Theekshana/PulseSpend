import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'report_problem_screen.dart';

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  static const _faqs = <(String, String)>[
    (
      'How do I add a transaction?',
      'Tap the + button in the center of the bottom bar, enter the amount, pick a '
          'category and save. Use a negative amount (or the expense toggle) for spending.'
    ),
    (
      'How do budgets work?',
      'Open the drawer → Budget Management and set a monthly limit per category. '
          'PulseSpend tracks your spending against it and can alert you as you get close.'
    ),
    (
      'Can I change my currency or date format?',
      'Yes — go to Settings → Preferences and pick your Default Currency or Date '
          'Format. Existing amounts are re-displayed in your chosen currency symbol.'
    ),
    (
      'How do savings goals work?',
      'Create a goal with a target amount and optional deadline, then contribute to '
          'it over time. Your progress shows on the dashboard.'
    ),
    (
      'How do I back up my data?',
      'Settings → Manage Profile → Export Data downloads a JSON backup you can share '
          'or re-import later from the same screen.'
    ),
    (
      'I have multiple accounts — can I switch?',
      'Yes. Settings → Add Account lets you sign into another account and switch '
          'between them without logging out each time.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Help Center')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.support_agent_rounded, color: Colors.white, size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Need a hand?',
                        style: TextStyle(
                            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Browse common questions below or contact us.',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'FREQUENTLY ASKED',
            style: TextStyle(
              color: textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: border),
                child: Column(
                  children: [
                    for (var i = 0; i < _faqs.length; i++)
                      ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        iconColor: AppColors.primary,
                        title: Text(
                          _faqs[i].$1,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        children: [
                          Text(
                            _faqs[i].$2,
                            style: TextStyle(
                                fontSize: 13.5, height: 1.5, color: textSecondary),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReportProblemScreen()),
            ),
            icon: const Icon(Icons.mail_outline_rounded),
            label: const Text('Still need help? Contact us'),
          ),
        ],
      ),
    );
  }
}
