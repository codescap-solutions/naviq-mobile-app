import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/core/utils/app_snackbar.dart';

class FamilyManagementView extends StatefulWidget {
  const FamilyManagementView({super.key});

  @override
  State<FamilyManagementView> createState() => _FamilyManagementViewState();
}

class _FamilyManagementViewState extends State<FamilyManagementView> {
  final SharedPrefsService _sharedPrefsService = injector<SharedPrefsService>();
  final HomeRepository _homeRepo = injector<HomeRepository>();
  final ImagePicker _imagePicker = ImagePicker();
  List<Map<String, dynamic>> _guardians = [];
  bool _isPrimaryParent = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _isPrimaryParent = _sharedPrefsService.isPrimaryParent;
    _fetchGuardians();
  }

  // Backed by GET /parent/guardians (guardian.controller.js: getGuardians) —
  // this used to read/write a local-only 'family_guardians' SharedPreferences
  // key, so "adding a guardian" never actually created an account or reached
  // the server: the person could never log in and see the child. Now this is
  // the real family list — the primary parent first (is_default:true),
  // followed by any real role-3 guardian accounts.
  Future<void> _fetchGuardians() async {
    setState(() => _isLoading = true);
    final response = await _homeRepo.getGuardians();
    if (!mounted) return;

    if (response.isSuccess && response.data != null) {
      setState(() {
        _guardians = response.data!
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _isLoading = false;
      });

      // Keep the locally-cached parent_name/parent_avatar in sync with the
      // server's own record — other screens read those keys directly.
      final defaultGuardian = _guardians.firstWhere(
        (g) => g['is_default'] == true,
        orElse: () => <String, dynamic>{},
      );
      if (defaultGuardian.isNotEmpty) {
        _sharedPrefsService.setString('parent_name', defaultGuardian['name'] ?? '');
        if (defaultGuardian['avatar_url'] != null) {
          _sharedPrefsService.setString('parent_avatar', defaultGuardian['avatar_url']);
        }
      }
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        AppSnackbar.showError(
          context,
          response.message.isEmpty ? 'Failed to load family members' : response.message,
        );
      }
    }
  }

  Future<void> _pickImageForGuardian(int index) async {
    // Show Gallery/Camera selector
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Profile Photo',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0C1D37),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF0066FF)),
              title: Text('Choose from Gallery', style: GoogleFonts.manrope()),
              onTap: () async {
                Navigator.pop(context);
                final XFile? file = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                if (file != null) {
                  _updateGuardianAvatar(index, file.path);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF0066FF)),
              title: Text('Take a Photo', style: GoogleFonts.manrope()),
              onTap: () async {
                Navigator.pop(context);
                final XFile? file = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 85);
                if (file != null) {
                  _updateGuardianAvatar(index, file.path);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateGuardianAvatar(int index, String path) async {
    final guardian = _guardians[index];
    final id = guardian['id'] as String?;
    if (id == null) return;

    final response = await _homeRepo.uploadGuardianAvatar(id: id, file: File(path));
    if (!mounted) return;

    if (response.isSuccess && response.data != null) {
      setState(() {
        _guardians[index]['avatar_url'] = response.data;
      });

      if (guardian['is_default'] == true) {
        _sharedPrefsService.setString('parent_avatar', response.data!);
      }

      AppSnackbar.showSuccess(context, 'Profile photo updated successfully');
    } else {
      AppSnackbar.showError(
        context,
        response.message.isEmpty ? 'Failed to update photo' : response.message,
      );
    }
  }

  Widget _buildAvatar(String? path) {
    if (path == null || path.isEmpty) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF0066FF),
            width: 2.0,
          ),
        ),
        child: const Icon(
          CupertinoIcons.person_fill,
          color: Color(0xFF0066FF),
          size: 32,
        ),
      );
    }

    ImageProvider provider;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      provider = NetworkImage(path);
    } else if (path.startsWith('assets/')) {
      provider = AssetImage(path);
    } else {
      provider = FileImage(File(path));
    }

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF0066FF),
          width: 2.0,
        ),
        image: DecorationImage(
          image: provider,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  void _showAddGuardianSheet() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            bool isSubmitting = false;

            Future<void> submit() async {
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              if (name.isEmpty || phone.isEmpty) {
                AppSnackbar.showError(context, 'Please enter both name and phone number');
                return;
              }

              setSheetState(() => isSubmitting = true);
              // Real account: POST /parent/guardians creates a role-3 User
              // linked to this family — the phone number can then actually
              // log in (OTP, same as any parent) and see this child.
              final response = await _homeRepo.addGuardian(name: name, phoneNumber: phone);
              if (!mounted) return;
              setSheetState(() => isSubmitting = false);

              if (response.isSuccess) {
                Navigator.pop(context);
                await _fetchGuardians();
                if (mounted) AppSnackbar.showSuccess(context, '$name added as guardian');
              } else {
                AppSnackbar.showError(
                  context,
                  response.message.isEmpty ? 'Failed to add guardian' : response.message,
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Add Guardian',
                          style: GoogleFonts.manrope(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0C1D37),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.black, size: 24),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Name',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0C1D37),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        hintText: 'Enter Name',
                        hintStyle: GoogleFonts.manrope(color: const Color(0xFF94A3B8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Phone Number',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0C1D37),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: 'Enter Phone Number',
                        hintStyle: GoogleFonts.manrope(color: const Color(0xFF94A3B8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0066FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: isSubmitting ? null : submit,
                        child: isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : Text(
                                'Continue',
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditGuardianSheet(int index) {
    final guardian = _guardians[index];
    final id = guardian['id'] as String?;
    final editController = TextEditingController(text: guardian['name']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            bool isSubmitting = false;

            Future<void> submit() async {
              final newName = editController.text.trim();
              if (newName.isEmpty) {
                AppSnackbar.showError(context, 'Name cannot be empty');
                return;
              }
              if (id == null) {
                Navigator.pop(context);
                return;
              }

              setSheetState(() => isSubmitting = true);
              final response = await _homeRepo.updateGuardianName(id: id, name: newName);
              if (!mounted) return;
              setSheetState(() => isSubmitting = false);

              if (response.isSuccess) {
                setState(() {
                  _guardians[index]['name'] = newName;
                });
                if (guardian['is_default'] == true) {
                  _sharedPrefsService.setString('parent_name', newName);
                }
                Navigator.pop(context);
                if (mounted) AppSnackbar.showSuccess(context, 'Name updated successfully');
              } else {
                AppSnackbar.showError(
                  context,
                  response.message.isEmpty ? 'Failed to update name' : response.message,
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.black, size: 24),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    Text(
                      'Edit Name',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0C1D37),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: editController,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Colors.black, width: 2.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: isSubmitting ? null : submit,
                        child: isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                              )
                            : Text(
                                'Update',
                                style: GoogleFonts.manrope(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteGuardian(int index) {
    final guardian = _guardians[index];
    final id = guardian['id'] as String?;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Guardian',
          style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete ${guardian['name']} as a guardian?',
          style: GoogleFonts.manrope(),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: GoogleFonts.manrope(color: Colors.grey)),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: Text('Delete', style: GoogleFonts.manrope(color: Colors.red, fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(context);
              if (id == null) return;

              // DELETE /parent/guardians/:id — soft-deletes the guardian's
              // account server-side and revokes their refresh tokens, so
              // they're logged out immediately, not just removed from this
              // list on this device.
              final response = await _homeRepo.deleteGuardian(id);
              if (!mounted) return;

              if (response.isSuccess) {
                setState(() {
                  _guardians.removeAt(index);
                });
                AppSnackbar.showSuccess(context, 'Guardian deleted');
              } else {
                AppSnackbar.showError(
                  context,
                  response.message.isEmpty ? 'Failed to delete guardian' : response.message,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leadingWidth: 56,
        leading: Center(
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.chevron_left,
                  color: Colors.black,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
        title: Text(
          'Family',
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0C1D37),
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchGuardians,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _guardians.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Text(
                              'No family members found.',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _guardians.length,
                      itemBuilder: (context, index) {
                        final guardian = _guardians[index];
                        final isDefault = guardian['is_default'] == true;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16.0),
                          padding: const EdgeInsets.all(16.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0C1D37).withValues(alpha: 0.04),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // Avatar
                              GestureDetector(
                                onTap: () {
                                  if (!_isPrimaryParent && isDefault) {
                                    _pickImageForGuardian(index);
                                  } else if (_isPrimaryParent) {
                                    _pickImageForGuardian(index);
                                  } else {
                                    AppSnackbar.showError(context, 'Only primary parent can edit other members');
                                  }
                                },
                                child: _buildAvatar(guardian['avatar_url']),
                              ),
                              const SizedBox(width: 16),
                              // Name and Phone
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      guardian['name'] ?? '',
                                      style: GoogleFonts.manrope(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF0C1D37),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          CupertinoIcons.phone,
                                          size: 14,
                                          color: Color(0xFF94A3B8),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          guardian['phone_number'] ?? '',
                                          style: GoogleFonts.manrope(
                                            fontSize: 13,
                                            color: const Color(0xFF64748B),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              // Actions (Edit, Delete)
                              if (_isPrimaryParent) ...[
                                // Edit Button
                                GestureDetector(
                                  onTap: () => _showEditGuardianSheet(index),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFEFF6FF),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      CupertinoIcons.pencil,
                                      color: Color(0xFF0066FF),
                                      size: 18,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Delete Button (Only for custom guardians)
                                if (!isDefault)
                                  GestureDetector(
                                    onTap: () => _confirmDeleteGuardian(index),
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFFEF2F2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.trash,
                                        color: Color(0xFFEF4444),
                                        size: 18,
                                      ),
                                    ),
                                  )
                                else
                                  const SizedBox(width: 36), // spacing match
                              ] else ...[
                                // Secondary guardians cannot edit/delete members
                                const SizedBox.shrink(),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ),
      floatingActionButton: _isPrimaryParent
          ? FloatingActionButton(
              onPressed: _showAddGuardianSheet,
              backgroundColor: const Color(0xFF0066FF),
              shape: const CircleBorder(),
              elevation: 4,
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            )
          : null,
    );
  }
}
