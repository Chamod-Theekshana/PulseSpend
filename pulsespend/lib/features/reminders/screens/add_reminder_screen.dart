import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/reminder_model.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/reminders_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

class AddReminderScreen extends ConsumerStatefulWidget {
  const AddReminderScreen({super.key});

  @override
  ConsumerState<AddReminderScreen> createState() => _AddReminderScreenState();
}

class _AddReminderScreenState extends ConsumerState<AddReminderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  String? _selectedCategory;
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  int _remindDaysBefore = 1;
  bool _isLoading = false;

  static const _reminderOptions = [0, 1, 2, 3, 5, 7];

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a category')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final currency = ref.read(profileControllerProvider).currency;
      final reminder = ReminderModel(
        id: 0,
        userId: '',
        title: _titleController.text.trim(),
        amount: double.parse(_amountController.text.trim()),
        currency: currency,
        category: _selectedCategory!,
        dueDate: _dueDate,
        remindDaysBefore: _remindDaysBefore,
      );
      await ref.read(remindersControllerProvider.notifier).create(reminder);
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
    final categories = ref.watch(categoriesControllerProvider).expenseCategories;

    return Scaffold(
      appBar: AppBar(title: const Text('New Bill Reminder')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              AppTextField(
                controller: _titleController,
                label: 'Title',
                hint: 'e.g. Electricity bill, Rent',
                textCapitalization: TextCapitalization.sentences,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _amountController,
                label: 'Amount due',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                prefixIcon: const Icon(Icons.attach_money_rounded),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text('Category', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: categories
                    .map((c) => GestureDetector(
                          onTap: () => setState(() => _selectedCategory = c.name),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: _selectedCategory == c.name ? AppColors.primary : AppColors.lightSurfaceAlt,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _selectedCategory == c.name ? AppColors.primary : AppColors.lightBorder,
                              ),
                            ),
                            child: Text(
                              c.name,
                              style: TextStyle(
                                color: _selectedCategory == c.name ? Colors.white : AppColors.lightTextPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDueDate,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(color: AppColors.lightSurfaceAlt, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      const Icon(Icons.event_outlined, size: 20),
                      const SizedBox(width: 12),
                      Text('Due ${_dueDate.day}/${_dueDate.month}/${_dueDate.year}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Remind me', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _reminderOptions
                    .map((d) => ChoiceChip(
                          label: Text(d == 0 ? 'On due date' : '$d day${d == 1 ? '' : 's'} before'),
                          selected: _remindDaysBefore == d,
                          onSelected: (_) => setState(() => _remindDaysBefore = d),
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: _remindDaysBefore == d ? Colors.white : AppColors.lightTextPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 28),
              PrimaryButton(label: 'Create Reminder', isLoading: _isLoading, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
