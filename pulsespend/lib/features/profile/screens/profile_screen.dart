import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/app_loader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../providers/repository_providers.dart';
import '../../../shared/utils/image_utils.dart';
import '../../auth/screens/splash_gate.dart';
import '../widgets/settings_widgets.dart';
import '../../../l10n/l10n_ext.dart';

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
  bool _isExportingCsv = false;
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).brightness == Brightness.dark
                ? const ColorScheme.dark(primary: AppColors.primary)
                : const ColorScheme.light(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDob = picked;
      });
    }
  }

  Future<void> _saveChanges() async {
    // Unfocus keyboard before saving for better UX
    FocusScope.of(context).unfocus();
    
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
        _showModernSnackBar('Profile updated successfully!', isError: false);
      }
    } catch (e) {
      if (mounted) {
        _showModernSnackBar(DioClient.toApiException(e).localizedMessage(context), isError: true);
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
        _showModernSnackBar(DioClient.toApiException(e).localizedMessage(context), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportDataCsv() async {
    setState(() => _isExportingCsv = true);
    try {
      final userId = ref.read(currentUserIdProvider);
      final csv = await ref.read(profileRepositoryProvider).exportDataCsv(userId);

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/pulsespend_export.csv');
      await file.writeAsString(csv);

      await Share.shareXFiles([XFile(file.path)], text: 'My PulseSpend Data (CSV)');
    } catch (e) {
      if (mounted) {
        _showModernSnackBar(DioClient.toApiException(e).localizedMessage(context), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isExportingCsv = false);
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
          _showModernSnackBar('Data imported successfully!', isError: false);
        }
      }
    } catch (e) {
      if (mounted) {
        _showModernSnackBar(DioClient.toApiException(e).localizedMessage(context), isError: true);
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );

    if (password == null) return; // cancelled
    if (password.isEmpty) {
      if (mounted) {
        _showModernSnackBar('Password is required to delete account', isError: true);
      }
      return;
    }

    setState(() => _isDeleting = true);
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount(password);
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SplashGate()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        _showModernSnackBar(DioClient.toApiException(e).localizedMessage(context), isError: true);
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

        // Limit size to ~1.5MB
        if (bytes.lengthInBytes > 1.5 * 1024 * 1024) {
          if (mounted) {
            _showModernSnackBar('Image is too large. Please select an image under 1.5MB.', isError: true);
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
        _showModernSnackBar('Failed to pick image: $e', isError: true);
      }
    }
  }

  void _showModernSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: isError ? AppColors.expense : AppColors.income,
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(profileControllerProvider, (previous, next) {
      if (previous?.user == null && next.user != null) {
        // User loaded, update controllers smoothly
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
          style: TextStyle(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800, // Slightly bolder for modern look
            letterSpacing: -0.3,
          ),
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(context.l10n.actionRetry),
                        ),
                      ],
                    )
                  : const AppLoader(size: 36))
          : CustomScrollView(
              // Adds a premium iOS-style bounce effect
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(user, isDark),
                        const SizedBox(height: 36),

                        const SettingsSectionTitle('Personal Information'),
                        const SizedBox(height: 12),
                        _buildCard(isDark, [
                          _field(
                            label: 'First Name',
                            icon: Icons.person_outline_rounded,
                            child: _textInput(_firstNameController, 'e.g. John'),
                          ),
                          _field(
                            label: 'Surname',
                            icon: Icons.badge_outlined,
                            child: _textInput(_surnameController, 'e.g. Doe'),
                          ),
                          _field(
                            label: 'Date of Birth',
                            icon: Icons.cake_outlined,
                            child: _buildDatePicker(isDark),
                          ),
                          _field(
                            label: 'Gender',
                            icon: Icons.wc_rounded,
                            child: _buildGenderDropdown(isDark),
                          ),
                          _field(
                            label: 'Contact No.',
                            icon: Icons.phone_outlined,
                            child: _textInput(_contactNoController, 'e.g. +94 71 234 5678', keyboardType: TextInputType.phone),
                            isLast: true,
                          ),
                        ]),
                        const SizedBox(height: 28),

                        _buildSaveButton(),
                        const SizedBox(height: 40),

                        const SettingsSectionTitle('Data & Backup'),
                        const SizedBox(height: 12),
                        _buildBackupSection(isDark),
                        const SizedBox(height: 40),

                        // ── Danger zone ──
                        const SettingsSectionTitle('Danger Zone'),
                        const SizedBox(height: 12),
                        _DeleteAccountButton(
                          loading: _isDeleting,
                          onTap: _confirmDeleteAccount,
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, 
                                size: 16, 
                                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Deletes your account and all data after a 7-day grace period. '
                                  'Signing in again within 7 days lets you cancel the deletion.',
                                  style: TextStyle(
                                    color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                                    fontSize: 12.5,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(dynamic user, bool isDark) {
    final surface = isDark ? AppColors.darkSurface : Colors.white;
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

    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickProfilePhoto,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Gradient ring + soft glow around the avatar.
                Container(
                  padding: const EdgeInsets.all(4), // Slightly thicker ring
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: surface,
                      border: Border.all(color: surface, width: 4),
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
                                fontSize: 38,
                              ),
                            ),
                          ),
                  ),
                ),
                // Premium Camera Badge
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceAlt : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            user.email,
            style: TextStyle(
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(bool isDark, List<Widget> children) {
    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final border = isDark ? AppColors.darkBorder : Colors.transparent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        
        color: surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
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
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 55,
            height: 55,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
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
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.5), width: 1.5),
        ),
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
          fontSize: 15.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildDatePicker(bool isDark) {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
        ),
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
                  fontWeight: _selectedDob != null ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.unfold_more_rounded,
                size: 20,
                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderDropdown(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedGender == null || !['Male', 'Female', 'Other'].contains(_selectedGender)
              ? 'Male'
              : _selectedGender,
          isExpanded: true,
          isDense: true,
          padding: const EdgeInsets.symmetric(vertical: 5),
          borderRadius: BorderRadius.circular(16),
          icon: Icon(Icons.unfold_more_rounded,
              size: 20, color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
          dropdownColor: isDark ? AppColors.darkSurface : Colors.white,
          style: TextStyle(
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
          items: ['Male', 'Female', 'Other']
              .map((v) => DropdownMenuItem<String>(value: v, child: Text(v)))
              .toList(),
          onChanged: (v) => setState(() => _selectedGender = v),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      height: 56,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _isSaving ? null : _saveChanges,
          child: Center(
            child: _isSaving
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: AppLoader(size: 24, color: Colors.white),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Save Changes',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackupSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.data_object_rounded,
                label: 'Export JSON',
                subtitle: 'Full Backup',
                loading: _isExporting,
                onTap: _exportData,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _ActionCard(
                icon: Icons.table_chart_rounded,
                label: 'Export CSV',
                subtitle: 'Spreadsheet',
                loading: _isExportingCsv,
                onTap: _exportDataCsv,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: _ActionCard(
            icon: Icons.settings_backup_restore_rounded,
            label: 'Import Data',
            subtitle: 'Restore from a JSON backup file',
            loading: _isImporting,
            onTap: _importData,
            isDark: isDark,
            horizontal: true,
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool loading;
  final VoidCallback onTap;
  final bool isDark;
  final bool horizontal;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.loading,
    required this.onTap,
    required this.isDark,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder.withValues(alpha: 0.5);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: loading ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: horizontal
                ? Row(
                    children: [
                      _buildIconBox(),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextContent(isDark)),
                      if (loading) const AppLoader(size: 20) else const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildIconBox(),
                          if (loading) const AppLoader(size: 20),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildTextContent(isDark),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconBox() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppColors.primary, size: 22),
    );
  }

  Widget _buildTextContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 11.5,
            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          ),
        ),
      ],
    );
  }
}

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.expense.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_amber_rounded, color: AppColors.expense, size: 24),
          ),
          const SizedBox(width: 12),
          Text(
            'Delete account?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This permanently erases your account and all your data — '
            'transactions, budgets, goals, and reminders. This cannot be undone.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            obscureText: true,
            autofocus: true,
            style: TextStyle(
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              fontWeight: FontWeight.w600,
            ),
            onSubmitted: (_) => Navigator.pop(context, _controller.text),
            decoration: InputDecoration(
              labelText: 'Enter your password to confirm',
              labelStyle: TextStyle(
                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.expense, width: 2),
              ),
              isDense: true,
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), 
          style: TextButton.styleFrom(
            foregroundColor: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
          ),
          child: Text(context.l10n.actionCancel, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.expense,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _DeleteAccountButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;

  const _DeleteAccountButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.expense.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: loading ? null : onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.expense.withValues(alpha: 0.3)),
          ),
          child: Center(
            child: loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: AppLoader(size: 22, color: AppColors.expense),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_forever_rounded, size: 22, color: AppColors.expense),
                      SizedBox(width: 10),
                      Text(
                        'Delete Account',
                        style: TextStyle(
                          color: AppColors.expense,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
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