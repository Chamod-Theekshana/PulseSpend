import 'package:characters/characters.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../utils/image_utils.dart';

/// A person's avatar: their photo when they have one, otherwise their initials
/// on a colour derived from their user id.
///
/// The colour is keyed to the **user id**, not the name, so it stays stable if
/// someone renames themselves — the whole point of a colour-coded avatar is
/// that you learn to recognise it, and it shouldn't shift under you. Two people
/// with the same initials in a group get different colours for the same reason.
class UserAvatar extends StatelessWidget {
  /// Used for the initials and as the accessibility label.
  final String name;

  /// Cloudinary URL or data URI. Null/empty falls back to initials.
  final String? photoUrl;

  /// Stable colour seed. Falls back to [name] when absent.
  final String? userId;

  final double radius;

  /// Draws a ring around the avatar — used to mark the group owner.
  final Color? ringColor;

  const UserAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.userId,
    this.radius = 18,
    this.ringColor,
  });

  static Color colorFor(String seed) {
    if (seed.isEmpty) return AppColors.primary;
    final hash = seed.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
    return AppColors.categoryPalette[hash % AppColors.categoryPalette.length];
  }

  /// Up to two initials: "Nimal Perera" → "NP", "nimal" → "N".
  static String initialsFor(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final seed = (userId != null && userId!.isNotEmpty) ? userId! : name;
    final color = colorFor(seed);
    final hasPhoto = photoUrl != null && photoUrl!.trim().isNotEmpty;

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.18),
      foregroundImage: hasPhoto ? getProfileImageProvider(photoUrl!) : null,
      // Shown when there is no photo AND when a photo fails to load — the
      // second case matters, since a broken Cloudinary link would otherwise
      // leave an empty circle.
      onForegroundImageError: hasPhoto ? (_, __) {} : null,
      child: Text(
        initialsFor(name),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.72,
        ),
      ),
    );

    if (ringColor != null) {
      avatar = Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ringColor!, width: 1.6),
        ),
        child: avatar,
      );
    }

    return Semantics(label: name, child: avatar);
  }
}

/// A horizontal stack of overlapping avatars, e.g. "who is in this group".
/// Shows at most [max] and then a "+N" chip.
class AvatarStack extends StatelessWidget {
  final List<({String name, String? photoUrl, String userId})> people;
  final double radius;
  final int max;

  /// Colour behind the overlap gap — should match the surface the stack sits on.
  final Color backgroundColor;

  const AvatarStack({
    super.key,
    required this.people,
    required this.backgroundColor,
    this.radius = 14,
    this.max = 4,
  });

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();

    final shown = people.take(max).toList();
    final overflow = people.length - shown.length;
    final step = radius * 1.45; // overlap by roughly a quarter

    final children = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      final p = shown[i];
      children.add(Positioned(
        left: i * step,
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(shape: BoxShape.circle, color: backgroundColor),
          child: UserAvatar(
            name: p.name,
            photoUrl: p.photoUrl,
            userId: p.userId,
            radius: radius,
          ),
        ),
      ));
    }

    if (overflow > 0) {
      children.add(Positioned(
        left: shown.length * step,
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(shape: BoxShape.circle, color: backgroundColor),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text(
              '+$overflow',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.62,
              ),
            ),
          ),
        ),
      ));
    }

    final width = (shown.length + (overflow > 0 ? 1 : 0) - 1) * step + radius * 2 + 3;

    return SizedBox(
      height: radius * 2 + 3,
      width: width,
      child: Stack(children: children),
    );
  }
}
