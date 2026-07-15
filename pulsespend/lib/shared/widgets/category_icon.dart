import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Maps a free-text category name (categories are user-defined strings in
/// this backend, not an enum) to a sensible icon, falling back to a generic
/// wallet icon for anything custom.
class CategoryIcon extends StatelessWidget {
  final String category;
  final double size;

  const CategoryIcon({super.key, required this.category, this.size = 44});

  static IconData _iconFor(String category) {
    final c = category.toLowerCase();
    if (c.contains('transfer')) return Icons.swap_horiz_rounded; // wallet transfer legs
    if (c.contains('food') || c.contains('grocer') || c.contains('restaurant')) return Icons.restaurant_rounded;
    if (c.contains('transport') || c.contains('fuel') || c.contains('car') || c.contains('taxi')) {
      return Icons.directions_car_filled_rounded;
    }
    if (c.contains('bill') || c.contains('utilit') || c.contains('electric') || c.contains('water')) {
      return Icons.receipt_long_rounded;
    }
    if (c.contains('shop')) return Icons.shopping_bag_rounded;
    if (c.contains('health') || c.contains('medic') || c.contains('doctor')) return Icons.favorite_rounded;
    if (c.contains('entertain') || c.contains('movie') || c.contains('game')) return Icons.movie_rounded;
    if (c.contains('salary') || c.contains('income') || c.contains('wage')) return Icons.payments_rounded;
    if (c.contains('rent') || c.contains('home') || c.contains('house')) return Icons.home_rounded;
    if (c.contains('travel') || c.contains('flight') || c.contains('trip')) return Icons.flight_takeoff_rounded;
    if (c.contains('education') || c.contains('school') || c.contains('book')) return Icons.school_rounded;
    if (c.contains('gift')) return Icons.card_giftcard_rounded;
    if (c.contains('invest')) return Icons.trending_up_rounded;
    if (c.contains('subscription') || c.contains('streaming')) return Icons.subscriptions_rounded;
    if (c.contains('phone') || c.contains('mobile') || c.contains('internet')) return Icons.wifi_rounded;
    if (c.contains('pet')) return Icons.pets_rounded;
    if (c.contains('other')) return Icons.category_rounded;
    return Icons.account_balance_wallet_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.categoryColor(category);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // A touch more tint in dark mode so the badge stays visible on the
        // near-black surface.
        color: color.withValues(alpha: isDark ? 0.24 : 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(_iconFor(category), color: color, size: size * 0.5),
    );
  }
}
