import 'package:flutter/material.dart';
import '../../../shared/widgets/app_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/group_model.dart';
import '../../../providers/groups_provider.dart';

/// How a shared expense or income is divided. Serialized into the transaction
/// body under `group_split`; the backend re-derives and freezes the amounts
/// (this is a request, never the final word — the server is the rounding
/// authority, and for income it inverts who-owes-whom).
class GroupSplitInput {
  final String mode; // equal | shares | percent | exact
  final List<GroupSplitParticipantInput> participants;

  const GroupSplitInput({required this.mode, required this.participants});

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'participants': [
          for (final p in participants)
            {'user_id': p.userId, if (p.value != null) 'value': p.value},
        ],
      };
}

class GroupSplitParticipantInput {
  final String userId;
  final double? value; // weight (shares) / percent / exact amount; null for equal

  const GroupSplitParticipantInput({required this.userId, this.value});
}

/// Picks who's in on a shared expense or income and how it's divided — modelled
/// on [SplitEditor] but keyed by member. Emits a [GroupSplitInput] (null while the
/// split doesn't add up, so the caller can block submit). Equal mode needs no
/// per-member inputs; the other three show a value field with a live
/// "adds up ✓ / remaining / over by" indicator.
class GroupSplitEditor extends ConsumerStatefulWidget {
  final int groupId;
  final double totalAmount;
  final String payerId;
  final ValueChanged<GroupSplitInput?> onChanged;

  const GroupSplitEditor({
    super.key,
    required this.groupId,
    required this.totalAmount,
    required this.payerId,
    required this.onChanged,
  });

  @override
  ConsumerState<GroupSplitEditor> createState() => _GroupSplitEditorState();
}

class _GroupSplitEditorState extends ConsumerState<GroupSplitEditor> {
  String _mode = 'equal';
  final Set<String> _selected = {};
  final Map<String, TextEditingController> _values = {};
  bool _seeded = false;

  @override
  void didUpdateWidget(covariant GroupSplitEditor old) {
    super.didUpdateWidget(old);
    // Total changed (user edited the amount) → the allocation indicator + equal
    // preview must recompute, and a valid split re-emits.
    if (old.totalAmount != widget.totalAmount) WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    for (final c in _values.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(List<GroupMember> members) {
    if (_seeded) return;
    _seeded = true;
    for (final m in members) {
      _selected.add(m.userId);
      _values[m.userId] = TextEditingController();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  /// Builds the split payload, or null when it doesn't currently add up.
  void _emit() {
    final ids = _selected.toList();
    if (ids.isEmpty) {
      widget.onChanged(null);
      return;
    }
    if (_mode == 'equal') {
      widget.onChanged(GroupSplitInput(
        mode: 'equal',
        participants: [for (final id in ids) GroupSplitParticipantInput(userId: id)],
      ));
      return;
    }
    final parts = <GroupSplitParticipantInput>[];
    for (final id in ids) {
      final v = double.tryParse(_values[id]?.text.trim() ?? '');
      if (v == null || v <= 0) {
        widget.onChanged(null); // incomplete → block submit
        return;
      }
      parts.add(GroupSplitParticipantInput(userId: id, value: v));
    }
    // Client-side pre-check mirrors the server so the user sees the state, but
    // the server re-derives and is authoritative.
    if (_mode == 'percent' && (_sum(parts) - 100).abs() > 0.1) return widget.onChanged(null);
    if (_mode == 'exact' && (_sum(parts) - widget.totalAmount).abs() > 0.02) return widget.onChanged(null);
    widget.onChanged(GroupSplitInput(mode: _mode, participants: parts));
  }

  double _sum(List<GroupSplitParticipantInput> parts) =>
      parts.fold(0.0, (s, p) => s + (p.value ?? 0));

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;

    return membersAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: SizedBox(width: 18, height: 18, child: AppLoader(size: 18))),
      ),
      error: (_, _) => Text('Couldn\'t load members', style: TextStyle(fontSize: 12, color: AppColors.expense)),
      data: (members) {
        _seed(members);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Text('Who\'s in on this?', style: TextStyle(fontSize: 12, color: textTertiary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in members)
                  _Chip(
                    label: m.userId == widget.payerId ? '${m.displayName} (you)' : m.displayName,
                    selected: _selected.contains(m.userId),
                    onTap: () => setState(() {
                      if (!_selected.remove(m.userId)) _selected.add(m.userId);
                      _emit();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _ModeToggle(
              mode: _mode,
              onChanged: (m) => setState(() {
                _mode = m;
                _emit();
              }),
            ),
            if (_mode != 'equal') ...[
              const SizedBox(height: 10),
              for (final m in members)
                if (_selected.contains(m.userId))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(m.displayName, style: const TextStyle(fontSize: 13))),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _values[m.userId],
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: _mode == 'percent' ? '%' : (_mode == 'shares' ? 'shares' : 'amount'),
                            ),
                            onChanged: (_) => setState(_emit),
                          ),
                        ),
                      ],
                    ),
                  ),
              _Indicator(mode: _mode, total: widget.totalAmount, sum: _currentSum()),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _selected.isEmpty
                      ? 'Pick at least one person'
                      : 'Split equally — ${(widget.totalAmount / _selected.length).toStringAsFixed(2)} each',
                  style: TextStyle(fontSize: 11.5, color: textTertiary),
                ),
              ),
          ],
        );
      },
    );
  }

  double _currentSum() {
    var s = 0.0;
    for (final id in _selected) {
      s += double.tryParse(_values[id]?.text.trim() ?? '') ?? 0;
    }
    return s;
  }
}

class _Indicator extends StatelessWidget {
  final String mode;
  final double total;
  final double sum;

  const _Indicator({required this.mode, required this.total, required this.sum});

  @override
  Widget build(BuildContext context) {
    final target = mode == 'percent' ? 100.0 : total;
    final tol = mode == 'percent' ? 0.1 : 0.02;
    final ok = (sum - target).abs() <= tol;
    final unit = mode == 'shares' ? 'shares' : (mode == 'percent' ? '%' : '');
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        mode == 'shares'
            ? 'Total ${sum.toStringAsFixed(0)} shares'
            : (ok
                ? 'Adds up ✓'
                : '${sum > target ? "Over by" : "Remaining"}: ${(sum - target).abs().toStringAsFixed(2)} $unit'),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: mode == 'shares' || ok ? AppColors.income : AppColors.warning,
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onChanged;

  const _ModeToggle({required this.mode, required this.onChanged});

  static const _modes = [
    ('equal', 'Equal'),
    ('shares', 'Shares'),
    ('percent', '%'),
    ('exact', 'Exact'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final m in _modes)
          _Chip(label: m.$2, selected: mode == m.$1, onTap: () => onChanged(m.$1)),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            color: selected
                ? Colors.white
                : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
          ),
        ),
      ),
    );
  }
}
