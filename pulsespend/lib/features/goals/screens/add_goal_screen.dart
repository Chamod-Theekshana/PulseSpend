import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../models/goal_model.dart';
import '../../../providers/goals_provider.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

class AddGoalScreen extends ConsumerStatefulWidget {
  const AddGoalScreen({super.key});

  @override
  ConsumerState<AddGoalScreen> createState() => _AddGoalScreenState();
}

class _AddGoalScreenState extends ConsumerState<AddGoalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();
  DateTime? _deadline;
  int? _groupId; // share with this group (all members can contribute)
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final currency = ref.read(profileControllerProvider).currency;
      final goal = GoalModel(
        id: 0,
        userId: '',
        name: _nameController.text.trim(),
        targetAmount: double.parse(_targetController.text.trim()),
        currentAmount: 0,
        currency: currency,
        deadline: _deadline,
        groupId: _groupId,
      );
      await ref.read(goalsControllerProvider.notifier).create(goal);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.localizedMessage(context))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(profileControllerProvider).currency;

    return Scaffold(
      appBar: AppBar(title: const Text('New Goal')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              AppTextField(
                controller: _nameController,
                label: 'Goal name',
                hint: 'e.g. Emergency Fund, Japan Trip',
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _targetController,
                label: 'Target amount ($currency)',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                prefixIcon: const Icon(Icons.flag_outlined),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDeadline,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).inputDecorationTheme.fillColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        _deadline == null
                            ? 'Target date (optional)'
                            : '${_deadline!.day}/${_deadline!.month}/${_deadline!.year}',
                      ),
                    ],
                  ),
                ),
              ),
              // ── Share with group (optional; shows only when groups exist) ──
              Consumer(builder: (context, ref, _) {
                final groups = ref.watch(groupsControllerProvider).items;
                if (groups.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text('Share with group', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Just me'),
                          selected: _groupId == null,
                          onSelected: (_) => setState(() => _groupId = null),
                        ),
                        for (final g in groups)
                          ChoiceChip(
                            label: Text(g.name),
                            selected: _groupId == g.id,
                            onSelected: (_) => setState(() => _groupId = g.id),
                          ),
                      ],
                    ),
                  ],
                );
              }),
              const SizedBox(height: 28),
              PrimaryButton(label: 'Create Goal', isLoading: _isLoading, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
