import 'package:intl/intl.dart';

/// Date helpers respecting the user's chosen `date_format` profile field
/// (DD/MM/YYYY | MM/DD/YYYY | YYYY-MM-DD, per validators.ts).
class DateFormatter {
  DateFormatter._();

  static String forApi(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  static String display(DateTime date, {String pattern = 'DD/MM/YYYY'}) {
    switch (pattern) {
      case 'MM/DD/YYYY':
        return DateFormat('MM/dd/yyyy').format(date);
      case 'YYYY-MM-DD':
        return DateFormat('yyyy-MM-dd').format(date);
      case 'DD/MM/YYYY':
      default:
        return DateFormat('dd/MM/yyyy').format(date);
    }
  }

  static String relative(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24 && now.day == date.day) return '${diff.inHours}h ago';

    final yesterday = now.subtract(const Duration(days: 1));
    if (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) return DateFormat('EEEE').format(date);
    return DateFormat('MMM d, yyyy').format(date);
  }

  static String monthLabel(DateTime date) => DateFormat('MMMM yyyy').format(date);

  static String dayHeader(DateTime date) {
    final now = DateTime.now();
    final isToday = now.year == date.year && now.month == date.month && now.day == date.day;
    if (isToday) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday =
        yesterday.year == date.year && yesterday.month == date.month && yesterday.day == date.day;
    if (isYesterday) return 'Yesterday';
    return DateFormat('EEEE, MMM d').format(date);
  }
}
