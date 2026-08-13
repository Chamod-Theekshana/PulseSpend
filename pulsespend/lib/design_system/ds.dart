/// PulseSpend design system.
///
/// One import gets a screen everything it needs:
///
/// ```dart
/// import '../../design_system/ds.dart';
/// ```
///
/// Rules of the road:
///   * No screen hardcodes a hex value, a radius or a padding number. Reach
///     for `context.tokens` (exported below) or an `AppTokens.space*` constant.
///   * If two screens need the same shape, it becomes a component here rather
///     than being copy-pasted. That is the whole point of this folder.
///   * Emphasis is deliberate: a hero outweighs a card, a card outweighs a
///     nested tile. Do not flatten that hierarchy by giving everything the
///     same size and shadow.
library;

export '../core/theme/app_colors.dart';
export '../core/theme/app_tokens.dart';
export 'ds_app_bar.dart';
export 'ds_cards.dart';
export 'ds_controls.dart';
export 'ds_data_display.dart';
export 'ds_foundations.dart';
export 'ds_hero_balance_card.dart';
export 'ds_spend_gauge.dart';
export 'ds_states.dart';
