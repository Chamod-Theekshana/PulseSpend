import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../notifications/screens/notifications_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileControllerProvider).user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final scaffoldBgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF3F4F6);
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final sectionTitleColor = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: scaffoldBgColor,
      appBar: AppBar(
        backgroundColor: scaffoldBgColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Profile Settings',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 100),
        children: [
          // Profile Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  backgroundImage: profile?.profilePhoto != null && profile!.profilePhoto!.isNotEmpty
                      ? NetworkImage(profile.profilePhoto!)
                      : null,
                  child: profile?.profilePhoto == null || profile!.profilePhoto!.isEmpty
                      ? Text(
                          (profile?.name?.isNotEmpty == true
                                  ? profile!.name![0]
                                  : profile?.email.isNotEmpty == true
                                      ? profile!.email[0]
                                      : '?')
                              .toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
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
                        profile?.name ?? 'My Profile',
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile?.email ?? '',
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Account Section
          _SectionTitle(title: 'Account', color: sectionTitleColor),
          _SettingsCard(
            cardColor: cardColor,
            children: [
              _SettingsTile(
                icon: Icons.person_outline,
                title: 'Manage Profile',
                textColor: textColor,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
              ),
              _Divider(isDark: isDark),
              _SettingsTile(
                icon: Icons.lock_outline,
                title: 'Password & Security',
                textColor: textColor,
                onTap: () {}, // TODO: Implement password & security
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Preferences Section
          _SectionTitle(title: 'Preferences', color: sectionTitleColor),
          _SettingsCard(
            cardColor: cardColor,
            children: [
              _SettingsTile(
                icon: Icons.notifications_none,
                title: 'Notifications',
                textColor: textColor,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
              ),
              _Divider(isDark: isDark),
              _SettingsTile(
                icon: Icons.light_mode_outlined,
                title: 'Theme',
                textColor: textColor,
                trailingText: profile?.theme == 'dark' ? 'Dark Mode' : 'Light Mode',
                onTap: () {}, // TODO: Implement theme selector
              ),
              _Divider(isDark: isDark),
              _SettingsTile(
                icon: Icons.currency_pound,
                title: 'Default Currency',
                textColor: textColor,
                trailingText: profile?.currency ?? 'USD',
                onTap: () {}, // TODO: Implement currency selector
              ),
              _Divider(isDark: isDark),
              _SettingsTile(
                icon: Icons.calendar_today_outlined,
                title: 'Date Format',
                textColor: textColor,
                trailingText: profile?.dateFormat ?? 'DD/MM/YYYY',
                onTap: () {}, // TODO: Implement date format selector
              ),
              _Divider(isDark: isDark),
              _SettingsTile(
                icon: Icons.translate,
                title: 'Language',
                textColor: textColor,
                trailingText: profile?.language ?? 'English',
                onTap: () {}, // TODO: Implement language selector
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Support Section
          _SectionTitle(title: 'Support', color: sectionTitleColor),
          _SettingsCard(
            cardColor: cardColor,
            children: [
              _SettingsTile(
                icon: Icons.assignment_outlined,
                title: 'About',
                textColor: textColor,
                onTap: () {}, // TODO: Implement about
              ),
              _Divider(isDark: isDark),
              _SettingsTile(
                icon: Icons.error_outline,
                title: 'Report a Problem',
                textColor: textColor,
                onTap: () {}, // TODO: Implement report a problem
              ),
              _Divider(isDark: isDark),
              _SettingsTile(
                icon: Icons.help_outline,
                title: 'Help Center',
                textColor: textColor,
                onTap: () {}, // TODO: Implement help center
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Add Account & Logout
          _SettingsCard(
            cardColor: cardColor,
            children: [
              _SettingsTile(
                icon: Icons.person_add_alt_1_outlined,
                title: 'Add Account',
                textColor: textColor,
                onTap: () {}, // TODO: Implement add account
              ),
              _Divider(isDark: isDark),
              _SettingsTile(
                icon: Icons.logout,
                title: 'Logout',
                textColor: Colors.red,
                iconColor: Colors.red,
                showArrow: false,
                onTap: () {
                  ref.read(authControllerProvider.notifier).logout();
                },
              ),
            ],
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionTitle({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final Color cardColor;

  const _SettingsCard({required this.children, required this.cardColor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color textColor;
  final Color? iconColor;
  final String? trailingText;
  final bool showArrow;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.textColor,
    this.iconColor,
    this.trailingText,
    this.showArrow = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultIconColor = isDark ? Colors.white : Colors.black87;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? defaultIconColor, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText!,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (showArrow)
              Icon(
                Icons.arrow_forward_ios,
                color: isDark ? Colors.grey[600] : Colors.black,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;
  
  const _Divider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: isDark ? Colors.grey[800] : Colors.grey[200],
      indent: 56, // Align with text
      endIndent: 16,
    );
  }
}
