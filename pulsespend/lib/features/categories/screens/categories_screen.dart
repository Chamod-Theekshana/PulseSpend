import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/category_model.dart';
import '../../../providers/categories_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/category_icon.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/shimmer_list.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  void _openEditor(BuildContext context, {CategoryModel? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategoryEditorSheet(existing: existing),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, CategoryModel category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('"${category.name}" will be removed. Existing transactions keep this label as text.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(categoriesControllerProvider.notifier).delete(category.id);
    } catch (e) {
      if (!context.mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(categoriesControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => _openEditor(context)),
        ],
      ),
      body: state.isLoading && state.items.isEmpty
          ? const ShimmerList(itemHeight: 60)
          : state.items.isEmpty
              ? EmptyState(
                  icon: Icons.category_outlined,
                  title: 'No categories yet',
                  message: 'Add categories to organize your transactions, budgets, and reports.',
                  actionLabel: 'Add Category',
                  onAction: () => _openEditor(context),
                )
              : RefreshIndicator(
                  onRefresh: () => ref.read(categoriesControllerProvider.notifier).refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final c = state.items[i];
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      final textPrimary =
                          isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
                      final textSecondary =
                          isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
                      final typeColor = c.type == 'income'
                          ? AppColors.income
                          : (c.type == 'both' ? AppColors.primary : AppColors.expense);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CategoryIcon(category: c.name, size: 40),
                          title: Text(
                            c.name,
                            style: TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: typeColor.withValues(alpha: isDark ? 0.20 : 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    c.type[0].toUpperCase() + c.type.substring(1),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: typeColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit_outlined, size: 20, color: textSecondary),
                                onPressed: () => _openEditor(context, existing: c),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded,
                                    size: 20,
                                    color: isDark
                                        ? AppColors.darkTextTertiary
                                        : AppColors.lightTextTertiary),
                                onPressed: () => _confirmDelete(context, ref, c),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _CategoryEditorSheet extends ConsumerStatefulWidget {
  final CategoryModel? existing;
  const _CategoryEditorSheet({this.existing});

  @override
  ConsumerState<_CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends ConsumerState<_CategoryEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late String _type = widget.existing?.type ?? 'expense';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      if (widget.existing != null) {
        await ref.read(categoriesControllerProvider.notifier).update(
              widget.existing!.id,
              name: _nameController.text.trim(),
              type: _type,
            );
      } else {
        await ref.read(categoriesControllerProvider.notifier).create(
              name: _nameController.text.trim(),
              type: _type,
            );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chipBg = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final chipBorder = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final chipText = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    Widget typeChip(String value, String label, Color selectedColor) {
      final selected = _type == value;
      return Expanded(
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => setState(() => _type = value),
          selectedColor: selectedColor,
          backgroundColor: chipBg,
          side: BorderSide(color: selected ? selectedColor : chipBorder),
          labelStyle: TextStyle(
            color: selected ? Colors.white : chipText,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.existing != null ? 'Edit Category' : 'New Category',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: _nameController,
              label: 'Name',
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                typeChip('expense', 'Expense', AppColors.expense),
                const SizedBox(width: 8),
                typeChip('income', 'Income', AppColors.income),
                const SizedBox(width: 8),
                typeChip('both', 'Both', AppColors.primary),
              ],
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: widget.existing != null ? 'Save Changes' : 'Add Category',
              isLoading: _isLoading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
