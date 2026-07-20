import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import '../../core/theme/app_colors.dart';

/// The app's single loading spinner — halfTriangleDot from
/// loading_animation_widget. Every loader in the app funnels through here, so
/// restyling them all (a different animation, colour, or size) is a one-file edit.
///
/// Defaults to the primary accent; pass [color] for on-colour surfaces
/// (e.g. `Colors.white` inside a filled button). [size] matches the footprint of
/// the spinner it replaces (page ≈ 44, inline ≈ 18–24, button ≈ 22).
class AppLoader extends StatelessWidget {
  final double size;
  final Color? color;

  const AppLoader({super.key, this.size = 28, this.color});

  @override
  Widget build(BuildContext context) => LoadingAnimationWidget.halfTriangleDot(
        color: color ?? AppColors.primary,
        size: size,
      );
}
