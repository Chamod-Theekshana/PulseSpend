import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n_ext.dart';


import '../profile/screens/settings_screen.dart';
import '../transactions/screens/add_transaction_screen.dart';
import '../transactions/screens/transactions_screen.dart';
import '../../shared/widgets/profile_drawer.dart';
import '../analytics/screens/analytics_screen.dart';
import 'dashboard_screen.dart';

/// Bottom navigation shell with a custom Figma-style composite navigation bar.
/// Features a seamless top dome and an upward soft shadow line.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  final _screens = const [
    DashboardScreen(),
    AnalyticsScreen(),
    TransactionsScreen(),
    SettingsScreen(),
  ];

  void _onTabTapped(int i) {
    HapticFeedback.lightImpact();
    setState(() => _index = i);
  }

  void _openAddTransaction() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ProfileDrawerScope(
      child: Builder(
        builder: (drawerCtx) => Stack(
          children: [
            // ── Main Scaffold (no bottomNavigationBar so drawer covers full screen) ──
            Scaffold(
              body: IndexedStack(index: _index, children: [
                // DashboardScreen uses Builder internally to find ProfileDrawerScope above
                const DashboardScreen(),
                _screens[1],
                _screens[2],
                _screens[3],
              ]),
              extendBody: true,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            ),

            // ── Nav bar layered ABOVE the drawer (last in Stack = top) ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _FigmaDockedNavBar(
                currentIndex: _index,
                onTap: _onTabTapped,
                onFabTap: _openAddTransaction,
                isDark: isDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// COMPOSITE FIGMA NAVBAR 
// ──────────────────────────────────────────────────────────
class _FigmaDockedNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onFabTap;
  final bool isDark;

  const _FigmaDockedNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.onFabTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? AppColors.darkSurface : Colors.white;
    final unselectedColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final l = context.l10n;

    return SizedBox(
      height: 120, // Baseline height: 20px top dome protrusion + 64px flat bar
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Custom painted background vector containing the upward shadow line
          Positioned.fill(
            child: CustomPaint(
              painter: _NavbarBackgroundPainter(
                color: bgColor,
                isDark: isDark,
              ),
            ),
          ),

          // 2. Navigation items constrained strictly to the lower 64px flat area
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            bottom: 0,
            child: Row(
              children: [
                _DockNavTile(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: l.navHome,
                  isSelected: currentIndex == 0,
                  selectedColor: AppColors.primary,
                  unselectedColor: unselectedColor,
                  onTap: () => onTap(0),
                ),
                _DockNavTile(
                  icon: Icons.equalizer_rounded,
                  activeIcon: Icons.equalizer_rounded,
                  label: l.navAnalytics,
                  isSelected: currentIndex == 1,
                  selectedColor: AppColors.primary,
                  unselectedColor: unselectedColor,
                  onTap: () => onTap(1),
                ),
                const Expanded(child: SizedBox()), // Center gap reserved for the Dome
                _DockNavTile(
                  icon: Icons.swap_horiz_rounded,
                  activeIcon: Icons.swap_horiz_rounded,
                  label: l.navActivity,
                  isSelected: currentIndex == 2,
                  selectedColor: AppColors.primary,
                  unselectedColor: unselectedColor,
                  onTap: () => onTap(2),
                ),
                _DockNavTile(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings_rounded,
                  label: l.navSettings,
                  isSelected: currentIndex == 3,
                  selectedColor: AppColors.primary,
                  unselectedColor: unselectedColor,
                  onTap: () => onTap(3),
                ),
              ],
            ),
          ),

          // 3. Pinned FAB, mathematically locked to the center of the dome
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: _CenterActionFab(onTap: onFabTap),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// BOOLEAN UNION PAINTER (Flat Bar + Dome + Upward Shadow)
// ──────────────────────────────────────────────────────────
class _NavbarBackgroundPainter extends CustomPainter {
  final Color color;
  final bool isDark;

  const _NavbarBackgroundPainter({
    required this.color,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Lower flat bar occupying from y=20 to y=84
    final Rect flatBarRect = Rect.fromLTWH(0, 20, size.width, size.height - 20);
    final Path flatBarPath = Path()..addRect(flatBarRect);

    // 2. Top-center dome (70x70 circle centered at x: mid, y: 35)
    final Rect domeRect = Rect.fromCenter(
      center: Offset(size.width / 2, 35),
      width: 80,
      height: 75,
    );
    final Path domePath = Path()..addOval(domeRect);

    // 3. Merge both into a single continuous vector geometry
    final Path unifiedShape = Path.combine(PathOperation.union, flatBarPath, domePath);

    // ──────────────────────────────────────────────────────────
    // UPWARD SHADOW LINE IMPLEMENTATION
    // ──────────────────────────────────────────────────────────
    // Shift a duplicate of the path 3 pixels UPWARD (-3) along the Y axis
    final Path topShadowPath = unifiedShape.shift(const Offset(0, -3));
    final Paint topShadowPaint = Paint()
      ..color = isDark 
          ? Colors.white.withValues(alpha: 0.3) // Soft white glow in dark mode
          : Colors.black.withValues(alpha: 0.1) // Premium subtle top-shadow
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);

    // Draw the upward shadow layer first
    canvas.drawPath(topShadowPath, topShadowPaint);

    // Draw the solid body over it (automatically clipping/hiding the bottom half of the shadow)
    canvas.drawPath(
      unifiedShape,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _NavbarBackgroundPainter oldDelegate) =>
      color != oldDelegate.color || isDark != oldDelegate.isDark;
}

// ──────────────────────────────────────────────────────────
// SOLID FLAT FAB
// ──────────────────────────────────────────────────────────
class _CenterActionFab extends StatefulWidget {
  final VoidCallback onTap;
  const _CenterActionFab({required this.onTap});

  @override
  State<_CenterActionFab> createState() => _CenterActionFabState();
}

class _CenterActionFabState extends State<_CenterActionFab>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.90,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.reverse(),
      onTapUp: (_) {
        _controller.forward();
        widget.onTap();
      },
      onTapCancel: () => _controller.forward(),
      child: ScaleTransition(
        scale: _controller,
        child: ClipOval(
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: 65, // 54px inside a 70px dome leaves an immaculate 8px white halo
            height: 65,
            color: AppColors.primary,
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 45),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// NAV TILE
// ──────────────────────────────────────────────────────────
class _DockNavTile extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  const _DockNavTile({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                isSelected ? activeIcon : icon,
                key: ValueKey(isSelected),
                color: isSelected ? selectedColor : unselectedColor,
                size: 26,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? selectedColor : unselectedColor,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}