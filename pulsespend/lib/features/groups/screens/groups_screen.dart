import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/group_model.dart';
import '../../../providers/groups_provider.dart';
import '../../../shared/widgets/empty_state.dart';
import 'group_detail_screen.dart';

/// Lists the shared "family" groups the user belongs to, with actions to create
/// a new group or join one via an invite code.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _TextPromptDialog(
        title: 'New shared group',
        label: 'Group name',
        hint: 'e.g. Home, Trip to Kandy',
        actionLabel: 'Create',
        capitalization: TextCapitalization.words,
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final group = await ref.read(groupsControllerProvider.notifier).create(name);
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
        );
      }
    }
  }

  Future<void> _joinGroup(BuildContext context, WidgetRef ref) async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _TextPromptDialog(
        title: 'Join a group',
        label: 'Invite code',
        hint: 'e.g. 7KD2Q9AB',
        actionLabel: 'Join',
        capitalization: TextCapitalization.characters,
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      final group = await ref.read(groupsControllerProvider.notifier).join(code);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Joined "${group.name}"'), backgroundColor: AppColors.income),
        );
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.toApiException(e).localizedMessage(context))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(groupsControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Shared Groups'),
        actions: [
          IconButton(
            tooltip: 'Join with code',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => _joinGroup(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createGroup(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New group'),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => ref.read(groupsControllerProvider.notifier).refresh(),
        child: state.isLoading && state.items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.items.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      EmptyState(
                        icon: Icons.groups_outlined,
                        title: 'No shared groups yet',
                        message: 'Create a group for your household or trip, then invite others with a code. Everyone sees a combined view of spending.',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: state.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final g = state.items[i];
                      return _GroupTile(
                        group: g,
                        isDark: isDark,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => GroupDetailScreen(group: g)),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

/// A small prompt dialog that owns its own [TextEditingController] and disposes
/// it in [State.dispose] — which the framework calls only after the dialog's
/// dismiss animation finishes. Disposing the controller in the caller right
/// after `showDialog` returns instead crashes, because the still-animating
/// TextField touches the freed controller.
class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String label;
  final String hint;
  final String actionLabel;
  final TextCapitalization capitalization;

  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.actionLabel,
    this.capitalization = TextCapitalization.none,
  });

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: widget.capitalization,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}

class _GroupTile extends StatelessWidget {
  final GroupModel group;
  final bool isDark;
  final VoidCallback onTap;

  const _GroupTile({required this.group, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Material(
      color: isDark ? AppColors.darkSurface : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? AppColors.darkBorder : const Color(0xFFF1F1F1)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.groups_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${group.memberCount} member${group.memberCount == 1 ? '' : 's'} · ${group.isOwner ? 'Owner' : 'Member'}',
                      style: TextStyle(fontSize: 12.5, color: textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
