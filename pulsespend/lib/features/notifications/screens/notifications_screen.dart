import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/notification_model.dart';
import '../../../providers/notifications_provider.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_list.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _iconForType(String? type) {
    switch (type) {
      case 'budget_alert':
        return Icons.warning_amber_rounded;
      case 'goal_completed':
        return Icons.flag_circle_rounded;
      case 'reminder':
        return Icons.notifications_active_rounded;
      case 'recurring':
        return Icons.autorenew_rounded;
      case 'transaction':
        return Icons.receipt_long_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (state.items.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'read_all') {
                  ref.read(notificationsControllerProvider.notifier).markAllRead();
                } else if (value == 'clear') {
                  ref.read(notificationsControllerProvider.notifier).clearAll();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'read_all', child: Text('Mark all as read')),
                const PopupMenuItem(value: 'clear', child: Text('Clear all')),
              ],
            ),
        ],
      ),
      body: state.isLoading && state.items.isEmpty
          ? const ShimmerList()
          : state.items.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'No notifications',
                  message: "You're all caught up. We'll let you know when something needs attention.",
                )
              : RefreshIndicator(
                  onRefresh: () => ref.read(notificationsControllerProvider.notifier).refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, i) {
                      final n = state.items[i];
                      return _NotificationTile(
                        notification: n,
                        onTap: () {
                          if (!n.read) {
                            ref.read(notificationsControllerProvider.notifier).markOneRead(n.id);
                          }
                        },
                        icon: _iconForType(n.type),
                      );
                    },
                  ),
                ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;
  final IconData icon;

  const _NotificationTile({required this.notification, required this.onTap, required this.icon});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notification.read ? Colors.transparent : AppColors.primaryLight.withOpacity(0.4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(fontWeight: notification.read ? FontWeight.w600 : FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(notification.body, style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormatter.relative(notification.createdAt),
                    style: const TextStyle(color: AppColors.lightTextTertiary, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (!notification.read)
              Container(
                margin: const EdgeInsets.only(top: 6, left: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}
