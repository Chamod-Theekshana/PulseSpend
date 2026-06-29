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
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red),
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
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
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
            const SnackBar(content: Text('Data imported successfully!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
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
    final scaffoldBgColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF6F6F6);
    final textColor = isDark ? Colors.white : const Color(0xFF1F1F1F);
    final fieldBgColor = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final borderColor = isDark ? const Color(0xFF3C3C3C) : const Color(0xFFE5E5E5);

    return Scaffold(
      backgroundColor: scaffoldBgColor,
      appBar: AppBar(
        backgroundColor: scaffoldBgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textColor, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Manage Profile',
          style: TextStyle(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: user == null
          ? Center(
              child: state.error != null 
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.error!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => ref.read(profileControllerProvider.notifier).refresh(),
                          child: const Text('Retry'),
                        )
                      ],
                    )
                  : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Profile Avatar
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.1),
                          border: Border.all(color: AppColors.primary, width: 2),
                          image: user.profilePhoto != null && user.profilePhoto!.isNotEmpty
                              ? DecorationImage(
                                  image: NetworkImage(user.profilePhoto!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: user.profilePhoto == null || user.profilePhoto!.isEmpty
                            ? Center(
                                child: Text(
                                  (user.firstName?.isNotEmpty == true
                                          ? user.firstName![0]
                                          : user.name?.isNotEmpty == true
                                              ? user.name![0]
                                              : user.email.isNotEmpty == true
                                                  ? user.email[0]
                                                  : '?')
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 32,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit_outlined, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // First Name
                _buildLabel('First Name', textColor),
                const SizedBox(height: 8),
                _buildTextField(_firstNameController, 'John', fieldBgColor, borderColor, textColor),
                const SizedBox(height: 20),

                // Surname
                _buildLabel('Surname', textColor),
                const SizedBox(height: 8),
                _buildTextField(_surnameController, 'Christopher', fieldBgColor, borderColor, textColor),
                const SizedBox(height: 20),

                // Date of Birth
                _buildLabel('Date of Birth', textColor),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: fieldBgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _selectedDob != null ? DateFormat('MMMM dd, yyyy').format(_selectedDob!) : 'Select Date of Birth',
                          style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        Icon(Icons.calendar_month_outlined, color: textColor),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Gender
                _buildLabel('Gender', textColor),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: fieldBgColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedGender ?? 'Male',
                      isExpanded: true,
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: textColor),
                      dropdownColor: fieldBgColor,
                      style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w500),
                      items: ['Male', 'Female', 'Other'].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        setState(() {
                          _selectedGender = newValue;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Contact No
                _buildLabel('Contact No.', textColor),
                const SizedBox(height: 8),
                _buildTextField(_contactNoController, '+94 71 216 0350', fieldBgColor, borderColor, textColor),
                const SizedBox(height: 40),

                // Save Changes Button
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
                
                const SizedBox(height: 32),
                
                // Export and Import Data
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isExporting ? null : _exportData,
                        icon: _isExporting 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                            : const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Export Data'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isImporting ? null : _importData,
                        icon: _isImporting 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                            : const Icon(Icons.upload_rounded, size: 18),
                        label: const Text('Import Data'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildLabel(String text, Color color) {
    return Text(
      text,
      style: TextStyle(
        color: color.withValues(alpha: 0.7),
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, Color bg, Color border, Color text) {
    return TextField(
      controller: controller,
      style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: text.withValues(alpha: 0.4), fontWeight: FontWeight.w400),
        filled: true,
        fillColor: bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}
