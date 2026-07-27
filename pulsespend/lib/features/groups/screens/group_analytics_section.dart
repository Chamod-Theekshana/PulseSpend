import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/currency_provider.dart';

class GroupAnalyticsSection extends ConsumerWidget {
  final int groupId;

  const GroupAnalyticsSection({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(groupAnalyticsProvider(groupId));
    final money = ref.watch(moneyFormatterProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return analyticsAsync.when(
      data: (data) {
        if (data.members.isEmpty) return const SizedBox.shrink();

        final maxTotal = data.members.map((m) => m.total).fold<double>(0.0, (m, e) => e > m ? e : m);
        if (maxTotal == 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Spending Breakdown',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...data.members.where((m) => m.total > 0).map((m) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(m.memberName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                          Text(money.format(m.total, data.currency),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Stacked horizontal bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 12,
                          width: double.infinity,
                          color: isDark ? Colors.white10 : Colors.black12,
                          child: LayoutBuilder(
                            builder: (ctx, constraints) {
                              final width = constraints.maxWidth;
                              double currentX = 0;

                              // Sort categories by amount descending for cleaner stack
                              final sortedEntries = m.categories.entries.toList()
                                ..sort((a, b) => b.value.compareTo(a.value));

                              return Stack(
                                children: sortedEntries.map((entry) {
                                  final catWidth = (entry.value / maxTotal) * width;
                                  final left = currentX;
                                  currentX += catWidth;
                                  
                                  // Add tiny separation between segments if there's multiple
                                  return Positioned(
                                    left: left,
                                    width: catWidth > 1 ? catWidth - 1 : catWidth,
                                    height: 12,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: AppColors.categoryColor(entry.key),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Legend
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: (m.categories.entries.where((e) => e.value > 0).toList()
                              ..sort((a, b) => b.value.compareTo(a.value)))
                            .map((entry) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: AppColors.categoryColor(entry.key),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${entry.key} ${money.format(entry.value, data.currency)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(e.toString(), style: const TextStyle(color: AppColors.expense)),
        ),
      ),
    );
  }
}
