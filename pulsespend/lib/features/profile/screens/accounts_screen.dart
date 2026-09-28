import 'package:flutter/material.dart';
import '../../../shared/widgets/app_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../auth/screens/add_account_screen.dart';
import '../../auth/screens/splash_gate.dart';
import '../../../l10n/l10n_ext.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  late Future<List<StoredAccount>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(authControllerProvider.notifier).listAccounts();
  }

  void _reload() {
    setState(() {
      _future = ref.read(authControllerProvider.notifier).listAccounts();
    });
  }

  Future<void> _switch(StoredAccount account) async {
    final activeId = ref.read(authControllerProvider).userId;
    if (account.userId == activeId) return;
    await ref.read(authControllerProvider.notifier).switchAccount(account.userId);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashGate()),
      (route) => false,
    );
  }

  Future<void> _remove(StoredAccount account) async {
    final activeId = ref.read(authControllerProvider).userId;
    final isActive = account.userId == activeId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove account?'),
        content: Text(
          isActive
              ? 'This signs out ${account.email} on this device.'
              : 'Remove ${account.email} from this device? You can add it again later.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.actionCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.expense)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(authControllerProvider.notifier).removeAccount(account.userId);
    if (!mounted) return;
    if (isActive) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashGate()),
        (route) => false,
      );
    } else {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeId = ref.watch(authControllerProvider).userId;
    final activeUser = ref.watch(profileControllerProvider).user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Accounts')),
      body: FutureBuilder<List<StoredAccount>>(
        future: _future,
        builder: (context, snapshot) {
          final accounts = snapshot.data ?? const <StoredAccount>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Text(
                'Signed in on this device',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: AppLoader(size: 40)),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      children: [
                        for (var i = 0; i < accounts.length; i++) ...[
                          if (i > 0)
                            Divider(height: 1, color: border, indent: 72, endIndent: 12),
                          _AccountRow(
                            account: accounts[i],
                            isActive: accounts[i].userId == activeId,
                            displayName: accounts[i].userId == activeId
                                ? (activeUser?.fullName)
                                : null,
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                            onTap: () => _switch(accounts[i]),
                            onRemove: () => _remove(accounts[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddAccountScreen()),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add another account'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  final StoredAccount account;
  final bool isActive;
  final String? displayName;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _AccountRow({
    required this.account,
    required this.isActive,
    required this.displayName,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final initial = (account.email.isNotEmpty ? account.email[0] : '?').toUpperCase();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName?.isNotEmpty == true ? displayName! : account.email,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.income.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Active',
                              style: TextStyle(
                                color: AppColors.income,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.email,
                      style: TextStyle(fontSize: 12.5, color: textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: Icon(Icons.logout_rounded, size: 20, color: textSecondary),
                tooltip: 'Remove',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
