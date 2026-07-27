import 'package:flutter/material.dart';
import '../../../core/config/app_info.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/settings_widgets.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          const SizedBox(height: 12),
          Center(
            child: Column(
              children: [
                Container(
                  width: 104,
                  height: 104,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.18),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/PulseSpend Logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  AppInfo.name,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version ${AppInfo.version} (${AppInfo.build})',
                  style: TextStyle(fontSize: 13, color: textSecondary),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    AppInfo.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 1.5, color: textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.language_rounded,
                title: 'Website',
                trailingText: 'pulsespend.app',
                showChevron: false,
                onTap: () {},
              ),
              SettingsTile(
                icon: Icons.description_outlined,
                title: 'Terms of Service',
                onTap: () => _showLegal(context, 'Terms of Service', _terms),
              ),
              SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy',
                onTap: () => _showLegal(context, 'Privacy Policy', _privacy),
              ),
              SettingsTile(
                icon: Icons.workspace_premium_outlined,
                title: 'Licenses',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppInfo.name,
                  applicationVersion: AppInfo.version,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: Text(
              '© ${DateTime.now().year} PulseSpend · Made with care',
              style: TextStyle(fontSize: 12, color: textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _showLegal(BuildContext context, String title, String body) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Text(body, style: const TextStyle(height: 1.6, fontSize: 14)),
        ),
      ),
    ));
  }

  static const _terms =
      'By using PulseSpend you agree to track your own financial data responsibly. '
      'PulseSpend is provided "as is" without warranties of any kind. We are not a '
      'licensed financial advisor; figures shown are for personal budgeting only.\n\n'
      'You are responsible for keeping your account credentials secure. Do not share '
      'your password. You may export or delete your data at any time from Manage Profile.';

  static const _privacy =
      'We store only the data you enter — transactions, budgets, goals, reminders and '
      'your profile — to provide the app\'s features. Your data is transmitted over '
      'encrypted connections and is never sold.\n\n'
      'Profile photos and receipts are stored via our media provider. Push tokens are '
      'used solely to deliver the notifications you enable. You can request deletion of '
      'your account and data by contacting support.';
}
