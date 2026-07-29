import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/profile_provider.dart';
import '../../features/auth/screens/splash_gate.dart';
import '../../features/budgets/screens/budgets_screen.dart';
import '../../features/categories/screens/categories_screen.dart';
import '../../features/debts/screens/debts_screen.dart';
import '../../features/goals/screens/goals_screen.dart';
import '../../features/groups/screens/groups_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/recurring/screens/recurring_screen.dart';
import '../../features/wallets/screens/wallets_screen.dart';
import '../utils/image_utils.dart';
import '../../l10n/l10n_ext.dart';

// ──────────────────────────────────────────────────────────
// Controller – exposes a ValueNotifier so any child widget can
// open / close the drawer without going through the widget tree.
// ──────────────────────────────────────────────────────────

/// Wrap any screen that wants the profile-drawer in this widget.
/// Call [ProfileDrawerController.of(context).open()] to show it.
class ProfileDrawerScope extends ConsumerStatefulWidget {
  final Widget child;
  const ProfileDrawerScope({super.key, required this.child});

  @override
  ConsumerState<ProfileDrawerScope> createState() => _ProfileDrawerScopeState();
}

class _ProfileDrawerScopeState extends ConsumerState<ProfileDrawerScope>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnim;
  late Animation<double> _fadeAnim;

  static const _drawerWidthFraction = 0.82;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slideAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void open() => _controller.forward();
  void close() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = screenWidth * _drawerWidthFraction;

    return _ProfileDrawerInheritedWidget(
      state: this,
      child: Stack(
        children: [
          // Main content
          widget.child,

          // Scrim
          AnimatedBuilder(
            animation: _fadeAnim,
            builder: (_, __) {
              if (_controller.status == AnimationStatus.dismissed) {
                return const SizedBox.shrink();
              }
              return GestureDetector(
                onTap: close,
                child: Container(
                  color: Colors.black.withValues(alpha: _fadeAnim.value * 0.45),
                ),
              );
            },
          ),

          // Drawer panel
          AnimatedBuilder(
            animation: _slideAnim,
            builder: (_, child) {
              final offset = -(1.0 - _slideAnim.value) * drawerWidth;
              return Transform.translate(
                offset: Offset(offset, 0),
                child: child,
              );
            },
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: drawerWidth,
                child: _ProfileDrawerPanel(onClose: close),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Inherited widget to expose open/close to descendants
class _ProfileDrawerInheritedWidget extends InheritedWidget {
  final _ProfileDrawerScopeState state;
  const _ProfileDrawerInheritedWidget({
    required this.state,
    required super.child,
  });

  @override
  bool updateShouldNotify(_ProfileDrawerInheritedWidget old) => false;
}

class ProfileDrawerController {
  static _ProfileDrawerScopeState? _of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ProfileDrawerInheritedWidget>()
        ?.state;
  }

  static void open(BuildContext context) => _of(context)?.open();
  static void close(BuildContext context) => _of(context)?.close();
}

// ──────────────────────────────────────────────────────────
// The actual drawer panel
// ──────────────────────────────────────────────────────────
class _ProfileDrawerPanel extends ConsumerWidget {
  final VoidCallback onClose;
  const _ProfileDrawerPanel({required this.onClose});

  /// Closes the drawer, then pushes [screen] once the slide-out animation has
  /// settled (so the transition isn't janky).
  void _go(BuildContext context, Widget screen) {
    onClose();
    Future.delayed(const Duration(milliseconds: 280), () {
      if (context.mounted) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = ref.watch(profileControllerProvider);
    final user = profile.user;

    final bgColor = isDark ? AppColors.darkBg : const Color(0xFFF5F5F7);
    final surfaceColor = isDark ? AppColors.darkSurface : Colors.white;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final dividerColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Material(
      elevation: 0,
      color: bgColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top: avatar + name + email + theme toggle ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  _DrawerAvatar(user: user),
                  const Spacer(),
                  // Dark / Light toggle
                  _ThemeToggle(isDark: isDark, ref: ref, user: user),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.fullName ?? 'User',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user?.email ?? '',
                    style: TextStyle(fontSize: 13, color: textSecondary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Financial Planning section ──
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Money section ──
                    _SectionHeader(label: 'Money', textSecondary: textSecondary),
                    _DrawerTile(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Wallets',
                      dividerColor: dividerColor,
                      surfaceColor: surfaceColor,
                      textPrimary: textPrimary,
                      onTap: () => _go(context, const WalletsScreen()),
                    ),
                    _DrawerTile(
                      icon: Icons.handshake_outlined,
                      label: 'IOUs',
                      dividerColor: dividerColor,
                      surfaceColor: surfaceColor,
                      textPrimary: textPrimary,
                      isLast: true,
                      onTap: () => _go(context, const DebtsScreen()),
                    ),

                    const SizedBox(height: 20),

                    // ── Financial Planning section ──
                    _SectionHeader(label: 'Financial Planning', textSecondary: textSecondary),
                    _DrawerTile(
                      icon: Icons.track_changes_outlined,
                      label: 'Saving Goals',
                      dividerColor: dividerColor,
                      surfaceColor: surfaceColor,
                      textPrimary: textPrimary,
                      onTap: () => _go(context, const GoalsScreen()),
                    ),
                    _DrawerTile(
                      icon: Icons.pie_chart_outline_rounded,
                      label: 'Budget Management',
                      dividerColor: dividerColor,
                      surfaceColor: surfaceColor,
                      textPrimary: textPrimary,
                      onTap: () => _go(context, const BudgetsScreen()),
                    ),
                    _DrawerTile(
                      icon: Icons.autorenew_rounded,
                      label: 'Recurring Transactions',
                      dividerColor: dividerColor,
                      surfaceColor: surfaceColor,
                      textPrimary: textPrimary,
                      isLast: true,
                      onTap: () => _go(context, const RecurringScreen()),
                    ),

                    const SizedBox(height: 20),

                    // ── More section ──
                    _SectionHeader(label: 'More', textSecondary: textSecondary),
                    _DrawerTile(
                      icon: Icons.groups_outlined,
                      label: 'Shared Groups',
                      dividerColor: dividerColor,
                      surfaceColor: surfaceColor,
                      textPrimary: textPrimary,
                      onTap: () => _go(context, const GroupsScreen()),
                    ),
                    _DrawerTile(
                      icon: Icons.sell_outlined,
                      label: 'Categories',
                      dividerColor: dividerColor,
                      surfaceColor: surfaceColor,
                      textPrimary: textPrimary,
                      isLast: true,
                      onTap: () => _go(context, const CategoriesScreen()),
                    ),

                    const SizedBox(height: 20),

                    // ── Account section ──
                    _SectionHeader(label: 'Account', textSecondary: textSecondary),
                    _DrawerTile(
                      icon: Icons.manage_accounts_outlined,
                      label: 'Profile Settings',
                      dividerColor: dividerColor,
                      surfaceColor: surfaceColor,
                      textPrimary: textPrimary,
                      isLast: true,
                      onTap: () => _go(context, const ProfileScreen()),
                    ),
                  ],
                ),
              ),
            ),

            // ── Logout ──
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
              child: Column(
                children: [
                  Divider(color: dividerColor, height: 1),
                  InkWell(
                    onTap: () => _confirmLogout(context, ref),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.expenseBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.logout_rounded,
                              color: AppColors.expense,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            'Logout',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.expense,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    onClose();
    await Future.delayed(const Duration(milliseconds: 280));
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashGate()),
        (route) => false,
      );
    }
  }
}

// ──────────────────────────────────────────────────────────
// Sub-widgets
// ──────────────────────────────────────────────────────────

class _DrawerAvatar extends StatelessWidget {
  final UserModel? user;
  const _DrawerAvatar({required this.user});

  @override
  Widget build(BuildContext context) {
    final initials = (user?.fullName.isNotEmpty == true
            ? user!.fullName[0]
            : '?')
        .toUpperCase();

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryLight,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: user?.profilePhoto != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Image(image: getProfileImageProvider(user!.profilePhoto!), fit: BoxFit.cover),
            )
          : Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                ),
              ),
            ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  final bool isDark;
  final WidgetRef ref;
  final UserModel? user;

  const _ThemeToggle({required this.isDark, required this.ref, required this.user});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final newTheme = isDark ? 'light' : 'dark';
        ref.read(profileControllerProvider.notifier).update(theme: newTheme);
      },
      child: Container(
        width: 68,
        height: 34,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2B2B45) : AppColors.primaryLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Stack(
          children: [
            // Thumb
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.all(3),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  isDark ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
            // Opposite icon (faded)
            Align(
              alignment: isDark ? Alignment.centerLeft : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.lightTextTertiary,
                  size: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color textSecondary;

  const _SectionHeader({required this.label, required this.textSecondary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textSecondary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color surfaceColor;
  final Color dividerColor;
  final Color textPrimary;
  final bool isLast;

  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.surfaceColor,
    required this.dividerColor,
    required this.textPrimary,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surfaceColor,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 16, 0),
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    Icon(icon, size: 22, color: AppColors.lightTextSecondary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: AppColors.lightTextTertiary,
                    ),
                  ],
                ),
              ),
            ),
            if (!isLast)
              Divider(
                height: 1,
                thickness: 1,
                indent: 60,
                endIndent: 0,
                color: dividerColor,
              ),
          ],
        ),
      ),
    );
  }
}
