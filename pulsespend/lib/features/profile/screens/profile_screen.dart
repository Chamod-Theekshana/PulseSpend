import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../shared/utils/image_utils.dart';
import '../../auth/screens/splash_gate.dart';
import '../widgets/settings_widgets.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late TextEditingController _firstNameController;
  late TextEditingController _surnameController;
  late TextEditingController _contactNoController;
  DateTime? _selectedDob;
  String? _selectedGender;
  bool _isSaving = false;
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isDeleting = false;
  String? _pickedProfilePhoto;

  @override
  void initState() {
    super.initState();
    final user = ref.read(profileControllerProvider).user;
    _firstNameController = TextEditingController(text: user?.firstName ?? '');
    _surnameController = TextEditingController(text: user?.surname ?? '');
    _contactNoController = TextEditingController(text: user?.contactNo ?? '');
    _selectedDob = user?.dob;
    _selectedGender = user?.gender;

    // Refresh profile whenever screen is opened to recover from any previous network errors
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _surnameController.dispose();
    _contactNoController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime(1998, 2, 12),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDob = picked;
      });
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    try {
      await ref.read(profileControllerProvider.notifier).update(
            firstName: _firstNameController.text.trim(),
            surname: _surnameController.text.trim(),
            contactNo: _contactNoController.text.trim(),
            dob: _selectedDob?.toIso8601String(),
            gender: _selectedGender,
            profilePhoto: _pickedProfilePhoto,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: AppColors.income),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: AppColors.expense),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _exportData() async {
    setState(() => _isExporting = true);
    try {
      final userId = ref.read(currentUserIdProvider);
      final data = await ref.read(profileRepositoryProvider).exportData(userId);

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/pulsespend_export.json');
      await file.writeAsString(jsonEncode(data));

      await Share.shareXFiles([XFile(file.path)], text: 'My PulseSpend Data Backup');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.expense),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importData() async {
    setState(() => _isImporting = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);

        await ref.read(profileControllerProvider.notifier).importData(data);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data imported successfully!'), backgroundColor: AppColors.income),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: AppColors.expense),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    // The dialog owns its own controller (see _DeleteAccountDialog) so it is
    // disposed only after the dismiss animation — disposing it here would crash
    // the still-animating TextField.
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );

    if (password == null) return; // cancelled
    if (password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password is required'), backgroundColor: AppColors.expense),
        );
      }
      return;
    }

    setState(() => _isDeleting = true);
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount(password);
      if (mounted) {
        // Account is gone — route to a fresh gate (sign-in, or the next account).
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SplashGate()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.expense),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();

        if (bytes.lengthInBytes > 1.5 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Image is too large. Please select an image under 1.5MB.'), backgroundColor: AppColors.expense),
            );
          }
          return;
        }

        final base64String = base64Encode(bytes);
        final dataUri = 'data:image/jpeg;base64,$base64String';

        setState(() {
          _pickedProfilePhoto = dataUri;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e'), backgroundColor: AppColors.expense),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(profileControllerProvider, (previous, next) {
      if (previous?.user == null && next.user != null) {
        // User loaded, update controllers
        _firstNameController.text = next.user!.firstName ?? '';
        _surnameController.text = next.user!.surname ?? '';
        _contactNoController.text = next.user!.contactNo ?? '';
        setState(() {
          _selectedDob = next.user!.dob;
          _selectedGender = next.user!.gender;
        });
      }
    });

    final state = ref.watch(profileControllerProvider);
    final user = state.user;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Manage Profile',
          style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: user == null
          ? Center(
              child: state.error != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.error!, style: const TextStyle(color: AppColors.expense)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => ref.read(profileControllerProvider.notifier).refresh(),
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                _buildHeader(user, isDark),
                const SizedBox(height: 28),

                const SettingsSectionTitle('Personal Information'),
                _buildCard(isDark, [
                  _field(
                    label: 'First Name',
                    icon: Icons.person_outline_rounded,
                    child: _textInput(_firstNameController, 'John'),
                  ),
                  _field(
                    label: 'Surname',
                    icon: Icons.badge_outlined,
                    child: _textInput(_surnameController, 'Christopher'),
                  ),
                  _field(
                    label: 'Date of Birth',
                    icon: Icons.cake_outlined,
                    child: InkWell(
                      onTap: _pickDate,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedDob != null
                                    ? DateFormat('MMMM dd, yyyy').format(_selectedDob!)
                                    : 'Select date of birth',
                                style: TextStyle(
                                  color: _selectedDob != null
                                      ? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)
                                      : (isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(Icons.calendar_month_rounded,
                                size: 18,
                                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _field(
                    label: 'Gender',
                    icon: Icons.wc_rounded,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedGender == null || !['Male', 'Female', 'Other'].contains(_selectedGender)
                            ? 'Male'
                            : _selectedGender,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(14),
                        icon: Icon(Icons.keyboard_arrow_down_rounded,
                            color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
                        dropdownColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                        style: TextStyle(
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                        items: ['Male', 'Female', 'Other']
                            .map((v) => DropdownMenuItem<String>(value: v, child: Text(v)))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedGender = v),
                      ),
                    ),
                  ),
                  _field(
                    label: 'Contact No.',
                    icon: Icons.phone_outlined,
                    child: _textInput(_contactNoController, '+94 71 216 0350',
                        keyboardType: TextInputType.phone),
                    isLast: true,
                  ),
                ]),
                const SizedBox(height: 28),

                _buildSaveButton(),
                const SizedBox(height: 28),

                const SettingsSectionTitle('Data & Backup'),
                Row(
                  children: [
                    Expanded(
                      child: _softAction(
                        icon: Icons.download_rounded,
                        label: 'Export',
                        loading: _isExporting,
                        onTap: _exportData,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _softAction(
                        icon: Icons.upload_rounded,
                        label: 'Import',
                        loading: _isImporting,
                        onTap: _importData,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Export a JSON backup of your data, or restore one you saved earlier.',
                    style: TextStyle(
                      color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Danger zone ──
                const SettingsSectionTitle('Danger Zone'),
                _DeleteAccountButton(
                  loading: _isDeleting,
                  onTap: _confirmDeleteAccount,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Permanently delete your account and all associated data. This cannot be undone.',
                    style: TextStyle(
                      color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(dynamic user, bool isDark) {
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final fullName = [user.firstName, user.surname]
        .where((s) => s != null && (s as String).trim().isNotEmpty)
        .map((s) => (s as String).trim())
        .join(' ');
    final displayName = fullName.isNotEmpty
        ? fullName
        : (user.name != null && (user.name as String).trim().isNotEmpty
            ? (user.name as String).trim()
            : (user.email as String).split('@').first);

    final hasPhoto = _pickedProfilePhoto != null ||
        (user.profilePhoto != null && (user.profilePhoto as String).isNotEmpty);

    return Column(
      children: [
        GestureDetector(
          onTap: _pickProfilePhoto,
          child: Stack(
            children: [
              // Gradient ring + soft glow around the avatar.
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.30),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: surface,
                    border: Border.all(color: surface, width: 3),
                    image: hasPhoto
                        ? DecorationImage(
                            image: getProfileImageProvider(_pickedProfilePhoto ?? user.profilePhoto!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: hasPhoto
                      ? null
                      : Center(
                          child: Text(
                            displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 36,
                            ),
                          ),
                        ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: surface, width: 2.5),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 15),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          displayName,
          style: TextStyle(
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          user.email,
          style: TextStyle(
            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Field card ─────────────────────────────────────────────────────────────

  Widget _buildCard(bool isDark, List<Widget> children) {
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(children: children),
    );
  }

  Widget _field({
    required String label,
    required IconData icon,
    required Widget child,
    bool isLast = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Container(
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
            ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _textInput(TextEditingController controller, String hint, {TextInputType? keyboardType}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
        fontSize: 15.5,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
          fontSize: 15.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ── Buttons ────────────────────────────────────────────────────────────────

  Widget _buildSaveButton() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.34),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isSaving ? null : _saveChanges,
          child: Center(
            child: _isSaving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Save Changes',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _softAction({
    required IconData icon,
    required String label,
    required bool loading,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final fill = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: loading ? null : onTap,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Confirmation dialog for account deletion. Owns its password controller and
/// disposes it in [State.dispose] (after the dismiss animation), returning the
/// entered password via Navigator.pop, or null if cancelled.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently erases your account and all your data — '
            'transactions, budgets, goals, reminders and more. This cannot be undone.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            onSubmitted: (_) => Navigator.pop(context, _controller.text),
            decoration: const InputDecoration(
              labelText: 'Enter your password to confirm',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Delete', style: TextStyle(color: AppColors.expense)),
        ),
      ],
    );
  }
}

/// Full-width destructive action for the Danger Zone. Kept visually distinct
/// (expense/red tint) from the soft primary actions above it.
class _DeleteAccountButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;

  const _DeleteAccountButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.expense.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: loading ? null : onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.expense.withValues(alpha: 0.4)),
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.expense),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_forever_rounded, size: 20, color: AppColors.expense),
                      SizedBox(width: 8),
                      Text(
                        'Delete Account',
                        style: TextStyle(
                          color: AppColors.expense,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
