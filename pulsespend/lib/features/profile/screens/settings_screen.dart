import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../shared/utils/image_utils.dart';
import '../../../shared/widgets/selection_sheet.dart';
import '../../auth/screens/splash_gate.dart';
import '../../groups/screens/groups_screen.dart';
import '../../notifications/screens/notification_preferences_screen.dart';
import '../../wallets/screens/wallets_screen.dart';
import '../widgets/settings_widgets.dart';
import 'about_screen.dart';
import 'accounts_screen.dart';
import 'help_center_screen.dart';
import 'profile_screen.dart';
import 'report_problem_screen.dart';
import 'security_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  // ── Option catalogues ──────────────────────────────────────────────
  static const _currencies = [
    ('LKR', 'Sri Lankan Rupee'),
    ('USD', 'US Dollar'),
    ('EUR', 'Euro'),
    ('GBP', 'British Pound'),
    ('INR', 'Indian Rupee'),
    ('AUD', 'Australian Dollar'),
    ('JPY', 'Japanese Yen'),
    ('CAD', 'Canadian Dollar'),
  ];

  static const _dateFormats = [
    ('DD/MM/YYYY', '31/12/2026'),
    ('MM/DD/YYYY', '12/31/2026'),
    ('YYYY-MM-DD', '2026-12-31'),
  ];

  static const _languages = [
    'English',
    'Sinhala',
    'Tamil',
    'Spanish',
    'French',
    'German',
    'Hindi',
  ];

  Future<void> _update(
    BuildContext context,
    WidgetRef ref, {
    String? theme,
    String? currency,
    String? dateFormat,
    String? language,
  }) async {
    try {
      await ref.read(profileControllerProvider.notifier).update(
            theme: theme,
            currency: currency,
            dateFormat: dateFormat,
            language: language,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DioClient.toApiException(e).message)),
      );
    }
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref, String current) async {
    final l = context.l10n;
    final choice = await showSelectionSheet<String>(
      context: context,
      title: 'Appearance',
      subtitle: 'Choose how PulseSpend looks',
      selected: current,
      options: [
        SelectionOption(
            value: 'system', title: l.themeSystem, icon: Icons.brightness_auto_outlined),
        SelectionOption(value: 'light', title: l.lightMode, icon: Icons.light_mode_outlined),
        SelectionOption(value: 'dark', title: l.darkMode, icon: Icons.dark_mode_outlined),
      ],
    );
    if (choice != null && choice != current && context.mounted) {
      await _update(context, ref, theme: choice);
    }
  }

  Future<void> _pickCurrency(BuildContext context, WidgetRef ref, String current) async {
    final choice = await showSelectionSheet<String>(
      context: context,
      title: 'Default Currency',
      subtitle: 'Used to display amounts across the app',
      selected: current,
      options: _currencies
          .map((c) => SelectionOption(
                value: c.$1,
                title: '${c.$1} · ${c.$2}',
                leading: _CurrencyBadge(symbol: CurrencyFormatter.symbolFor(c.$1)),
              ))
          .toList(),
    );
    if (choice != null && choice != current && context.mounted) {
      await _update(context, ref, currency: choice);
    }
  }

  Future<void> _pickDateFormat(BuildContext context, WidgetRef ref, String current) async {
    final choice = await showSelectionSheet<String>(
      context: context,
      title: 'Date Format',
      selected: current,
      options: _dateFormats
          .map((d) => SelectionOption(
                value: d.$1,
                title: d.$1,
                subtitle: 'e.g. ${d.$2}',
                icon: Icons.calendar_today_outlined,
              ))
          .toList(),
    );
    if (choice != null && choice != current && context.mounted) {
      await _update(context, ref, dateFormat: choice);
    }
  }

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref, String current) async {
    final choice = await showSelectionSheet<String>(
      context: context,
      title: 'Language',
      subtitle: 'App language for menus and labels',
      selected: current,
      options: _languages
          .map((l) => SelectionOption(value: l, title: l, icon: Icons.translate_rounded))
          .toList(),
    );
    if (choice != null && choice != current && context.mounted) {
      await _update(context, ref, language: choice);
    }
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
      if (context.mounted) {
        // Reset to a fresh gate so the next account (or sign-in) loads cleanly.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SplashGate()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileControllerProvider);
    final user = profile.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l = context.l10n;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          l.settingsTitle,
          style: TextStyle(
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          // ── Profile header card ──
          _ProfileHeaderCard(
            name: user?.fullName ?? 'My Profile',
            email: user?.email ?? '',
            photo: user?.profilePhoto,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          const SizedBox(height: 28),

          // ── Account ──
          SettingsSectionTitle(l.sectionAccount),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.person_outline_rounded,
                title: l.manageProfile,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
              ),
              SettingsTile(
                icon: Icons.lock_outline_rounded,
                title: l.passwordSecurity,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SecurityScreen()),
                ),
              ),
              SettingsTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Wallets',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WalletsScreen()),
                ),
              ),
              SettingsTile(
                icon: Icons.groups_outlined,
                title: 'Shared groups',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GroupsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Preferences ──
          SettingsSectionTitle(l.sectionPreferences),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.notifications_none_rounded,
                title: l.notifications,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationPreferencesScreen()),
                ),
              ),
              SettingsTile(
                icon: isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                title: l.theme,
                trailingText: switch (user?.theme) {
                  'dark' => l.darkMode,
                  'light' => l.lightMode,
                  _ => l.themeSystem,
                },
                showChevron: false,
                onTap: () => _pickTheme(context, ref, user?.theme ?? 'system'),
              ),
              SettingsTile(
                icon: Icons.payments_outlined,
                title: l.defaultCurrency,
                trailingText: profile.currency,
                showChevron: false,
                onTap: () => _pickCurrency(context, ref, profile.currency),
              ),
              SettingsTile(
                icon: Icons.calendar_today_outlined,
                title: l.dateFormat,
                trailingText: profile.dateFormatPattern,
                showChevron: false,
                onTap: () => _pickDateFormat(context, ref, profile.dateFormatPattern),
              ),
              SettingsTile(
                icon: Icons.translate_rounded,
                title: l.language,
                trailingText: profile.language,
                showChevron: false,
                onTap: () => _pickLanguage(context, ref, profile.language),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Support ──
          SettingsSectionTitle(l.sectionSupport),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.info_outline_rounded,
                title: l.about,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                ),
              ),
              SettingsTile(
                icon: Icons.report_gmailerrorred_rounded,
                title: l.reportProblem,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReportProblemScreen()),
                ),
              ),
              SettingsTile(
                icon: Icons.help_outline_rounded,
                title: l.helpCenter,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Accounts / Logout ──
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.people_alt_outlined,
                title: l.addAccount,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountsScreen()),
                ),
              ),
              SettingsTile(
                icon: Icons.logout_rounded,
                title: l.logout,
                iconColor: AppColors.expense,
                titleColor: AppColors.expense,
                showChevron: false,
                onTap: () => _confirmLogout(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  final String name;
  final String email;
  final String? photo;
  final VoidCallback onTap;

  const _ProfileHeaderCard({
    required this.name,
    required this.email,
    required this.photo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final hasPhoto = photo != null && photo!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [AppColors.darkSurface, AppColors.darkSurfaceAlt]
                  : [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: isDark ? 0.0 : 0.28),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white.withValues(alpha: 0.22),
                backgroundImage: hasPhoto ? getProfileImageProvider(photo!) : null,
                child: !hasPhoto
                    ? Text(
                        (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: isDark ? textPrimary : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      email,
                      style: TextStyle(
                        color: isDark ? textSecondary : Colors.white.withValues(alpha: 0.85),
                        fontSize: 13.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 13,
                              color: isDark ? AppColors.primary : Colors.white),
                          const SizedBox(width: 5),
                          Text(
                            'Edit profile',
                            style: TextStyle(
                              color: isDark ? AppColors.primary : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencyBadge extends StatelessWidget {
  final String symbol;
  const _CurrencyBadge({required this.symbol});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        symbol,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}
