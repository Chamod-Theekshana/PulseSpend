import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/ocr/receipt_parser.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/transaction_model.dart';
import '../../../models/wallet_model.dart';
import '../../../shared/utils/image_utils.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/groups_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../providers/transactions_provider.dart';
import '../../../providers/wallets_provider.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/wallet_dropdown.dart';
import '../widgets/group_split_editor.dart';
import '../widgets/split_editor.dart';

/// What the user is recording. Transfer isn't a transaction the way the other
/// two are — it hits a different endpoint and produces a −/+ pair — but it
/// belongs in the same screen: "what happened to my money" is one question, and
/// hiding transfers elsewhere pushes people to mis-record loan repayments and
/// card payments as income.
enum _TxKind { expense, income, transfer }

/// Add or edit a transaction. Mirrors validateTransactionBody exactly:
/// - amount must be non-zero, sign determines income/expense
/// - splits only allowed for expenses, need >= 2 entries, must sum to total
/// - tags: lowercase, letters/numbers/_/- , max 30 chars each, max 20 tags
class AddTransactionScreen extends ConsumerStatefulWidget {
  final TransactionModel? existing;

  const AddTransactionScreen({super.key, this.existing});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _tagController = TextEditingController();

  _TxKind _kind = _TxKind.expense;

  bool get _isExpense => _kind == _TxKind.expense;
  bool get _isTransfer => _kind == _TxKind.transfer;

  /// Transfer ends. Wallet id 0 = the virtual Default bucket.
  int? _fromWalletId;
  int? _toWalletId;

  String? _selectedCategory;
  DateTime _date = DateTime.now();
  List<String> _tags = [];
  List<TransactionSplit> _splits = [];
  bool _isSplitMode = false;
  bool _isLoading = false;

  /// Receipt image: an https URL (kept from the existing transaction), a
  /// data:image/... URI (newly picked, uploaded server-side to Cloudinary), or
  /// null (none / removed). The backend clears the receipt when absent, so on
  /// edit the existing URL is resent to preserve it.
  String? _receipt;

  /// Selected wallet id; null on create = default wallet, 0 on edit = move
  /// back to the default wallet (the backend treats 0 as "clear").
  int? _walletId;

  /// When set, this expense is shared with that group (Splitwise-lite: split
  /// equally between members in the group's balance view).
  int? _groupId;

  /// The frozen-at-submit split for the selected group; null when unset or the
  /// current split doesn't add up (which blocks submit).
  GroupSplitInput? _groupSplit;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final tx = widget.existing;
    if (tx != null) {
      _titleController.text = tx.title;
      _amountController.text = tx.amount.abs().toStringAsFixed(2);
      _notesController.text = tx.notes ?? '';
      _kind = tx.isExpense ? _TxKind.expense : _TxKind.income;
      _selectedCategory = tx.category;
      _date = tx.createdAt;
      _tags = List.of(tx.tags);
      _splits = List.of(tx.splits);
      _isSplitMode = tx.isSplit;
      _receipt = tx.receiptUrl;
      _walletId = tx.walletId;
    }
  }

  /// Pick a receipt photo (same pattern as the profile photo picker): gallery
  /// image → 1MB cap (body limit is 2MB and base64 inflates ~37%) → data URI.
  /// Returns the picked file's path (for OCR), or null.
  Future<String?> _pickReceipt() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result == null || result.files.single.path == null) return null;
      final path = result.files.single.path!;
      final bytes = await File(path).readAsBytes();
      if (bytes.lengthInBytes > 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Image is too large. Please pick one under 1MB.'),
              backgroundColor: AppColors.expense,
            ),
          );
        }
        return null;
      }
      setState(() => _receipt = 'data:image/jpeg;base64,${base64Encode(bytes)}');
      return path;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e'), backgroundColor: AppColors.expense),
        );
      }
      return null;
    }
  }

  /// "Scan receipt": attach the photo AND OCR it on-device (ML Kit) to pre-fill
  /// title/amount/date. Low-confidence fields stay untouched — the user always
  /// confirms before submitting; failure just leaves the photo attached.
  Future<void> _scanReceipt() async {
    final path = await _pickReceipt();
    if (path == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Scanning receipt…')));
    final scan = await ReceiptParser.scan(path);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();

    if (scan.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn\'t read the receipt — photo attached, fill in manually.')),
      );
      return;
    }

    final filled = <String>[];
    setState(() {
      if (scan.amount != null) {
        _amountController.text = scan.amount!.toStringAsFixed(2);
        filled.add('amount');
      }
      if (scan.merchant != null && _titleController.text.trim().isEmpty) {
        _titleController.text = scan.merchant!;
        filled.add('title');
      }
      if (scan.date != null) {
        _date = scan.date!;
        filled.add('date');
      }
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text('Filled ${filled.join(', ')} from the receipt — please verify.'),
        backgroundColor: AppColors.income,
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _addTag() {
    final raw = _tagController.text.trim().replaceFirst(RegExp(r'^#+'), '').toLowerCase();
    if (raw.isEmpty) return;
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,29}$').hasMatch(raw)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tags: letters, numbers, _ or - only (max 30 chars)')),
      );
      return;
    }
    if (_tags.contains(raw)) {
      _tagController.clear();
      return;
    }
    if (_tags.length >= 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 20 tags allowed')),
      );
      return;
    }
    setState(() {
      _tags.add(raw);
      _tagController.clear();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// Moves money between two wallets. Hits the transfer endpoint rather than
  /// creating a transaction: the backend writes a −/+ pair sharing one transfer
  /// id, so balances shift while income/expense analytics stay untouched — the
  /// whole reason a loan repayment must not be recorded as income.
  Future<void> _submitTransfer() async {
    final from = _fromWalletId;
    final to = _toWalletId;
    if (from == null || to == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick which wallet the money leaves and where it lands')),
      );
      return;
    }
    final amount = double.parse(_amountController.text.trim());
    // Captured before the pop — this context is defunct afterwards.
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isLoading = true);
    try {
      await ref.read(walletRepositoryProvider).transfer(
            fromWalletId: from,
            toWalletId: to,
            amount: amount,
          );
      ref.invalidate(walletBalancesProvider);
      ref.invalidate(netWorthProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Transfer complete ✓'), backgroundColor: AppColors.income),
      );
    } catch (e) {
      if (!mounted) return;
      final apiEx = DioClient.toApiException(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiEx.localizedMessage(context))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isTransfer) return _submitTransfer();
    if (_selectedCategory == null && !_isSplitMode) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a category')));
      return;
    }
    // A group is selected but its split doesn't add up (editor returned null).
    if (!_isTransfer && _groupId != null && _groupSplit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish the group split — pick who\'s in and make the amounts add up')),
      );
      return;
    }

    final amountAbs = double.parse(_amountController.text.trim());
    final signedAmount = _isExpense ? -amountAbs : amountAbs;

    if (_isSplitMode) {
      if (_splits.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Split transactions need at least 2 categories')),
        );
        return;
      }
      final sum = _splits.fold<double>(0, (acc, s) => acc + s.amount.abs());
      if ((sum - amountAbs).abs() > 0.05) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Splits must add up to the total (currently ${sum.toStringAsFixed(2)})')),
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final currency = ref.read(profileControllerProvider).currency;
      final transaction = TransactionModel(
        id: widget.existing?.id ?? 0,
        userId: widget.existing?.userId ?? '',
        title: _titleController.text.trim(),
        amount: signedAmount,
        currency: currency,
        category: _isSplitMode ? (_splits.first.category) : _selectedCategory!,
        createdAt: _date,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        receiptUrl: _receipt,
        walletId: _walletId,
        groupId: !_isTransfer ? _groupId : null,
        groupSplit: !_isTransfer && _groupId != null ? _groupSplit?.toJson() : null,
        tags: _tags,
        splits: _isSplitMode ? _splits : const [],
      );

      if (_isEditing) {
        await ref.read(transactionsControllerProvider.notifier).update(widget.existing!.id, transaction);
      } else {
        await ref.read(transactionsControllerProvider.notifier).create(transaction);
      }
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
    final categoriesState = ref.watch(categoriesControllerProvider);
    final relevantCategories =
        _isExpense ? categoriesState.expenseCategories : categoriesState.incomeCategories;
    final currency = ref.watch(profileControllerProvider).currency;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceAlt = isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Transaction' : 'Add Transaction')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              // Expense / Income / Transfer toggle. Transfer is create-only —
              // an existing transaction can't turn into a −/+ pair — and needs
              // somewhere to move money to, so it appears once wallets exist.
              Consumer(builder: (context, ref, _) {
                final hasWallets = ref.watch(walletsControllerProvider).items.isNotEmpty;
                final showTransfer = hasWallets && !_isEditing;
                return Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TypeToggleButton(
                          label: 'Expense',
                          selected: _kind == _TxKind.expense,
                          color: AppColors.expense,
                          onTap: () => setState(() {
                            _kind = _TxKind.expense;
                            _selectedCategory = null;
                          }),
                        ),
                      ),
                      Expanded(
                        child: _TypeToggleButton(
                          label: 'Income',
                          selected: _kind == _TxKind.income,
                          color: AppColors.income,
                          onTap: () => setState(() {
                            _kind = _TxKind.income;
                            _selectedCategory = null;
                            _isSplitMode = false;
                            _splits = [];
                          }),
                        ),
                      ),
                      if (showTransfer)
                        Expanded(
                          child: _TypeToggleButton(
                            label: 'Transfer',
                            selected: _kind == _TxKind.transfer,
                            color: AppColors.primary,
                            onTap: () => setState(() {
                              _kind = _TxKind.transfer;
                              _selectedCategory = null;
                              _isSplitMode = false;
                              _splits = [];
                              _groupId = null;
                            }),
                          ),
                        ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 20),
              // A transfer's title and date come from the server ("Transfer to
              // X" / now), so neither field applies.
              if (!_isTransfer) ...[
                AppTextField(
                  controller: _titleController,
                  label: 'Title',
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Title is required';
                    if (v.trim().length > 200) return 'Max 200 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],
              AppTextField(
                controller: _amountController,
                label: 'Amount ($currency)',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                prefixIcon: const Icon(Icons.attach_money_rounded),
                // The overdraft warning under the wallet chips compares this
                // against the selected wallet's balance live.
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              if (!_isTransfer) ...[
                const SizedBox(height: 16),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: surfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 20),
                        const SizedBox(width: 12),
                        Text('${_date.day}/${_date.month}/${_date.year}'),
                      ],
                    ),
                  ),
                ),
              ],
              // ── Transfer ends (replaces the wallet picker in transfer mode) ──
              if (_isTransfer) ...[
                const SizedBox(height: 16),
                WalletDropdown(
                  label: 'From wallet',
                  value: _fromWalletId,
                  excludeId: _toWalletId,
                  onChanged: (v) => setState(() => _fromWalletId = v),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Icon(Icons.arrow_downward_rounded,
                      size: 18, color: AppColors.primary.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 10),
                WalletDropdown(
                  label: 'To wallet',
                  value: _toWalletId,
                  excludeId: _fromWalletId,
                  onChanged: (v) => setState(() => _toWalletId = v),
                ),
                const SizedBox(height: 10),
                _TransferHint(
                  fromId: _fromWalletId,
                  toId: _toWalletId,
                  amountText: _amountController.text,
                ),
              ],
              // ── Wallet (only shown once the user has created wallets) ──
              Consumer(builder: (context, ref, _) {
                final wallets = ref.watch(walletsControllerProvider).items;
                if (wallets.isEmpty || _isTransfer) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text('Wallet', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CategoryChip(
                          label: 'Default',
                          selected: _walletId == null || _walletId == 0,
                          onTap: () => setState(
                              () => _walletId = _isEditing ? 0 : null),
                        ),
                        for (final w in wallets)
                          _CategoryChip(
                            label: w.name,
                            selected: _walletId == w.id,
                            onTap: () => setState(() => _walletId = w.id),
                          ),
                      ],
                    ),
                    // What the selected wallet holds, and a soft overdraft
                    // warning: the user can't judge "can I afford this from
                    // here" without seeing the balance. Warn-only — overdraft
                    // facilities are real, so the save still goes through.
                    _WalletBalanceLine(
                      walletId: _walletId,
                      isExpense: _isExpense,
                      amountText: _amountController.text,
                    ),
                    // Income into a credit/loan wallet is almost always borrowed
                    // money or a repayment — neither is earnings. Recording it as
                    // income inflates the balance and hides the debt, so nudge
                    // toward a transfer instead. A hint, not a block: refunds are
                    // a legitimate exception.
                    if (!_isExpense &&
                        wallets.any((w) => w.id == _walletId && w.isLiability)) ...[
                      const SizedBox(height: 10),
                      _LiabilityIncomeHint(
                        walletName: wallets.firstWhere((w) => w.id == _walletId).name,
                        // Hand over the right tool with the destination already
                        // filled in — the user only has to say where it came from.
                        onUseTransfer: () => setState(() {
                          _kind = _TxKind.transfer;
                          _toWalletId = _walletId;
                          _fromWalletId = null;
                          _selectedCategory = null;
                          _isSplitMode = false;
                          _splits = [];
                          _groupId = null;
                        }),
                      ),
                    ],
                    // An expense on a LOAN grows the principal — but a loan only
                    // grows by interest; buying things is what cards and cash
                    // are for. Warn-only: interest and fees are the legitimate
                    // reason to be here.
                    if (_isExpense &&
                        wallets.any((w) => w.id == _walletId && w.type == 'loan')) ...[
                      const SizedBox(height: 10),
                      _LoanExpenseHint(
                        walletName: wallets.firstWhere((w) => w.id == _walletId).name,
                      ),
                    ],
                  ],
                );
              }),
              const SizedBox(height: 16),
              if (!_isSplitMode && !_isTransfer) ...[
                Text('Category', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: relevantCategories
                      .map((c) => _CategoryChip(
                            label: c.name,
                            selected: _selectedCategory == c.name,
                            onTap: () => setState(() => _selectedCategory = c.name),
                          ))
                      .toList(),
                ),
              ],
              if (_isExpense) ...[
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Split across categories', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Divide this expense between 2+ categories', style: TextStyle(fontSize: 12)),
                  value: _isSplitMode,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() {
                    _isSplitMode = v;
                    if (v) _selectedCategory = null;
                  }),
                ),
                if (_isSplitMode)
                  SplitEditor(
                    totalAmount: double.tryParse(_amountController.text.trim()) ?? 0,
                    splits: _splits,
                    categories: relevantCategories.map((c) => c.name).toList(),
                    onChanged: (splits) => setState(() => _splits = splits),
                  ),
              ],
              // ── Share to group (Splitwise-lite; expenses AND income) ──
              // Income splits in reverse — the receiver owes the others their
              // share — but it's still the same editor on the absolute amount.
              if (!_isTransfer)
                Consumer(builder: (context, ref, _) {
                  final groups = ref.watch(groupsControllerProvider).items;
                  if (groups.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Text('Share to group', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Text(
                        'Pick who\'s in and how it splits — settled in the group\'s balances',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _CategoryChip(
                            label: 'Not shared',
                            selected: _groupId == null,
                            onTap: () => setState(() {
                              _groupId = null;
                              _groupSplit = null;
                            }),
                          ),
                          for (final g in groups)
                            _CategoryChip(
                              label: g.name,
                              selected: _groupId == g.id,
                              onTap: () => setState(() {
                                _groupId = g.id;
                                _groupSplit = null; // re-seeded by the editor
                              }),
                            ),
                        ],
                      ),
                      // The split editor: participants + mode + per-member values.
                      // Keyed by group so it fully rebuilds when the group changes.
                      if (_groupId != null)
                        GroupSplitEditor(
                          key: ValueKey(_groupId),
                          groupId: _groupId!,
                          totalAmount: double.tryParse(_amountController.text.trim()) ?? 0,
                          payerId: ref.read(currentUserIdProvider),
                          onChanged: (split) => _groupSplit = split,
                        ),
                    ],
                  );
                }),
              // Notes / receipt / tags describe a spend or an earning. A transfer
              // is just money changing pockets, and the endpoint takes none of
              // them, so the whole run drops out in transfer mode.
              if (!_isTransfer) ...[
                const SizedBox(height: 16),
                AppTextField(
                  controller: _notesController,
                  label: 'Notes (optional)',
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Text('Receipt (optional)', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                if (_receipt == null)
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickReceipt,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                            decoration: BoxDecoration(
                              color: surfaceAlt,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.receipt_long_outlined, size: 18, color: AppColors.primary),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text('Attach',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: _scanReceipt,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.10),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.document_scanner_outlined, size: 18, color: AppColors.primary),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text('Scan & fill',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13.5,
                                          color: AppColors.primary),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image(
                          image: getProfileImageProvider(_receipt!),
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: InkWell(
                          onTap: () => setState(() => _receipt = null),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: InkWell(
                          onTap: _pickReceipt,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                Text('Tags', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _tagController,
                        label: 'Add a tag',
                        hint: 'e.g. work, vacation',
                        onChanged: (_) {},
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _addTag,
                      icon: const Icon(Icons.add_rounded),
                      style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                    ),
                  ],
                ),
                if (_tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _tags
                        .map((tag) => Chip(
                              label: Text('#$tag'),
                              onDeleted: () => setState(() => _tags.remove(tag)),
                            ))
                        .toList(),
                  ),
                ],
              ],
              const SizedBox(height: 28),
              PrimaryButton(
                label: _isTransfer
                    ? 'Transfer'
                    : (_isEditing ? 'Save Changes' : 'Add Transaction'),
                isLoading: _isLoading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TypeToggleButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : (Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : (isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// Explains, in plain terms, what the chosen transfer actually does. Debt
/// wallets are where transfers earn their keep and where the mental model is
/// hardest, so those two directions get named outright: money out of a loan is
/// borrowing, money into it is a repayment. Neither is earning or spending,
/// which is exactly why this isn't an income/expense entry.
class _TransferHint extends ConsumerWidget {
  final int? fromId;
  final int? toId;
  final String amountText;

  const _TransferHint({required this.fromId, required this.toId, this.amountText = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (fromId == null || toId == null) return const SizedBox.shrink();

    final balances = ref.watch(walletBalancesProvider).asData?.value ?? const <WalletBalance>[];
    WalletBalance? at(int id) => balances.where((b) => b.wallet.id == id).firstOrNull;
    final from = at(fromId!);
    final to = at(toId!);
    if (from == null || to == null) return const SizedBox.shrink();

    // Warn-only overdraft check on the source: moving more than an asset wallet
    // holds is allowed (overdraft facilities exist) but shouldn't be a surprise.
    // A liability source is borrowing — its balance is negative by design.
    final amount = double.tryParse(amountText.trim()) ?? 0;
    final overdraws =
        !from.wallet.isLiability && amount > 0 && amount > from.balance + 0.01;

    final String message;
    if (to.wallet.isLiability && !from.wallet.isLiability) {
      message = 'Repayment: ${from.wallet.name} drops and you owe '
          '${to.wallet.name} less. Your net worth doesn\'t change — you swapped '
          'money for less debt. Interest is separate: record that as an expense.';
    } else if (from.wallet.isLiability && !to.wallet.isLiability) {
      message = 'Borrowing: ${to.wallet.name} goes up and you now owe '
          '${from.wallet.name} that much. Your net worth doesn\'t change — the '
          'cash is real, but so is the debt.';
    } else {
      message = 'Moves money without counting as income or spending, so your '
          'earnings and net worth stay the same.';
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: isDark ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (overdraws) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.warning),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  '${from.wallet.name} only has ${from.balance.toStringAsFixed(0)} '
                  '${from.displayCurrency} — this transfer will overdraw it.',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.warning, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The selected wallet's balance, with a soft warning when the typed expense
/// exceeds what's available — an asset wallet's balance (overdraft) or a
/// credit/card wallet's available credit (over-limit). Warn-only: overdraft
/// facilities are real and the credit limit is a soft ceiling (the server
/// records the charge either way), so this never blocks — it just makes going
/// over a choice, not a surprise.
class _WalletBalanceLine extends ConsumerWidget {
  final int? walletId;
  final bool isExpense;
  final String amountText;

  const _WalletBalanceLine({
    required this.walletId,
    required this.isExpense,
    required this.amountText,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(walletBalancesProvider).asData?.value ?? const <WalletBalance>[];
    final b = balances.where((x) => x.wallet.id == (walletId ?? 0)).firstOrNull;
    if (b == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;
    final amount = double.tryParse(amountText.trim()) ?? 0;
    final overdraws = isExpense && !b.wallet.isLiability && amount > 0 && amount > b.balance + 0.01;
    // Soft credit-limit warning: spending past available credit is allowed (the
    // server records it and echoes a note), we just flag it — like the overdraft.
    final overCredit = isExpense &&
        b.wallet.isLiability &&
        b.availableCredit != null &&
        amount > 0 &&
        amount > b.availableCredit! + 0.01;
    final warn = overdraws || overCredit;

    final label = b.wallet.isLiability
        ? (b.availableCredit != null
            ? 'Available credit: ${b.availableCredit!.toStringAsFixed(0)} ${b.displayCurrency}'
            : 'Owed: ${b.amountOwed.toStringAsFixed(0)} ${b.displayCurrency}')
        : 'Balance: ${b.balance.toStringAsFixed(0)} ${b.displayCurrency}';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(
            warn ? Icons.warning_amber_rounded : Icons.account_balance_wallet_outlined,
            size: 13,
            color: warn ? AppColors.warning : textTertiary,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              warn
                  ? '$label — ${overCredit ? 'over your available credit' : 'this spend will overdraw it'}'
                  : label,
              style: TextStyle(
                fontSize: 11.5,
                color: warn ? AppColors.warning : textTertiary,
                fontWeight: warn ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Warn-only nudge for an expense recorded directly on a LOAN wallet: a loan's
/// principal only grows through interest — purchases belong on cash or a card,
/// and repayments are transfers. Interest/fees are the legitimate reason to
/// proceed anyway.
class _LoanExpenseHint extends StatelessWidget {
  final String walletName;
  const _LoanExpenseHint({required this.walletName});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.warning.withValues(alpha: 0.12) : AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This grows what you owe on $walletName. A loan normally only grows '
              'by interest — if you\'re buying something, spend from the wallet '
              'the money is in. Interest or fees? Carry on.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nudge shown when income is being recorded into a credit/loan wallet — the
/// mistake that makes borrowed money look like earnings and hides the debt.
/// Recording income here reduces the debt without the money leaving anywhere,
/// so net worth quietly rises out of nothing. Rather than block it (a refund is
/// a legitimate reason to be here), this hands over the right tool in one tap.
class _LiabilityIncomeHint extends StatelessWidget {
  final String walletName;
  final VoidCallback onUseTransfer;

  const _LiabilityIncomeHint({required this.walletName, required this.onUseTransfer});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.warning.withValues(alpha: 0.12)
            : AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$walletName is a debt account. Paying it off isn\'t income — '
                  'the money has to come out of another wallet, or your net worth '
                  'grows out of nowhere. Only use income here for refunds.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onUseTransfer,
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: Text('Record a repayment to $walletName instead'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 8),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
