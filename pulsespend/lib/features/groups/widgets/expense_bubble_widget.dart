import 'package:flutter/material.dart';
import '../../../models/chat_message_model.dart';
import '../../../core/theme/app_colors.dart';

class ExpenseBubbleWidget extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onSettlePressed;
  final bool isMe;

  const ExpenseBubbleWidget({
    Key? key,
    required this.message,
    required this.onSettlePressed,
    required this.isMe,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final metadata = message.metadata ?? {};
    final double amount = (metadata['amount'] as num?)?.toDouble() ?? 0.0;
    final String title = metadata['title'] as String? ?? 'Shared Expense';
    final String splitWith = metadata['splitWith'] as String? ?? 'Group';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.75,
        margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primaryAccent.withOpacity(0.15) : AppColors.surfaceDark,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16.0),
            topRight: const Radius.circular(16.0),
            bottomLeft: Radius.circular(isMe ? 16.0 : 4.0),
            bottomRight: Radius.circular(isMe ? 4.0 : 16.0),
          ),
          border: Border.all(
            color: isMe ? AppColors.primaryAccent : Colors.grey.withOpacity(0.3),
            width: 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryAccent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '\$${amount.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Split with $splitWith', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const Divider(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isMe ? Colors.white : AppColors.primaryAccent,
                  foregroundColor: isMe ? AppColors.primaryAccent : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onSettlePressed,
                child: const Text('Settle Share'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}