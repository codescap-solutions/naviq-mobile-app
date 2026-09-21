import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/utils/app_snackbar.dart';

import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class AddContactView extends StatefulWidget {
  final int? contactIndex;
  final List<Map<String, dynamic>> contactsList;

  const AddContactView({
    super.key,
    this.contactIndex,
    required this.contactsList,
  });

  @override
  State<AddContactView> createState() => _AddContactViewState();
}

class _AddContactViewState extends State<AddContactView> {
  final SharedPrefsService _sharedPrefsService = injector<SharedPrefsService>();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  late final TextEditingController _nameController;
  late final TextEditingController _relationController;
  late final TextEditingController _phoneController;

  @override
  void initState() {
    super.initState();
    
    String initialName = '';
    String initialRelation = '';
    String initialPhone = '';

    if (widget.contactIndex != null) {
      final contact = widget.contactsList[widget.contactIndex!];
      initialName = contact['name'] ?? '';
      initialRelation = contact['relation'] ?? '';
      initialPhone = contact['phone'] ?? '';
    }

    _nameController = TextEditingController(text: initialName);
    _relationController = TextEditingController(text: initialRelation);
    _phoneController = TextEditingController(text: initialPhone);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _relationController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    // Guards against double-submit from rapid taps while the request below
    // is in flight — this button previously had no loading/disabled state
    // at all, so nothing stopped a second tap from firing a duplicate
    // addParentContact/editParentContact call.
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await _submitContact();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitContact() async {
    final name = _nameController.text.trim();
    final relation = _relationController.text.trim();
    final phone = _phoneController.text.trim();

    final List<Map<String, dynamic>> updatedList = List.from(
      widget.contactsList.map((e) => Map<String, dynamic>.from(e)),
    );

    if (widget.contactIndex != null) {
      final index = widget.contactIndex!;
      final bool isDefault = updatedList[index]['is_default'] == true;
      final String id = updatedList[index]['id'] ?? 'contact_${DateTime.now().millisecondsSinceEpoch}';
      
      if (!id.startsWith('contact_') && !id.startsWith('default_')) {
        final response = await injector<HomeRepository>().editParentContact(
          id: id,
          name: name,
          relation: relation,
          phone: phone,
        );
        if (!response.isSuccess) {
          AppSnackbar.showError(context, response.message.isNotEmpty ? response.message : 'Failed to update contact on server');
          return;
        }
      }

      updatedList[index] = {
        'id': id,
        'name': name,
        'phone': phone,
        'relation': relation,
        'is_default': isDefault,
      };

      if (isDefault) {
        _sharedPrefsService.setString('parent_name', name);
        _sharedPrefsService.setString('parent_phone', phone);
      }
    } else {
      final response = await injector<HomeRepository>().addParentContact(
        name: name,
        relation: relation,
        phone: phone,
      );
      
      String newId = 'contact_${DateTime.now().millisecondsSinceEpoch}';
      if (response.isSuccess && response.data != null) {
        final data = response.data;
        if (data is Map && data['id'] != null) {
          newId = data['id'].toString();
        }
      } else if (!response.isSuccess) {
        AppSnackbar.showError(context, response.message.isNotEmpty ? response.message : 'Failed to save contact to server');
        return;
      }

      updatedList.add({
        'id': newId,
        'name': name,
        'phone': phone,
        'relation': relation,
        'is_default': false,
      });
    }

    final String encoded = jsonEncode(updatedList);
    _sharedPrefsService.setString('parents_contacts', encoded);

    AppSnackbar.showSuccess(
      context,
      widget.contactIndex != null
          ? 'Contact updated successfully'
          : 'Contact saved successfully',
    );
    
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditMode = widget.contactIndex != null;

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
          isEditMode ? 'Edit Contact' : 'Add Contact',
          style: GoogleFonts.poppins(
            fontSize: 20.0.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0C1D37),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Name',
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0C1D37),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  style: GoogleFonts.poppins(
                    fontSize: 15.0.sp,
                    color: const Color(0xFF0C1D37),
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter Name',
                    hintStyle: GoogleFonts.poppins(color: const Color(0xFF94A3B8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(
                      CupertinoIcons.person,
                      color: Color(0xFF94A3B8),
                      size: 20,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFF0066FF), width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.red, width: 1.0),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.red, width: 1.5),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter contact name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Relation with Child',
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0C1D37),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _relationController,
                  style: GoogleFonts.poppins(
                    fontSize: 15.0.sp,
                    color: const Color(0xFF0C1D37),
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. Mother, Father',
                    hintStyle: GoogleFonts.poppins(color: const Color(0xFF94A3B8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(
                      CupertinoIcons.group,
                      color: Color(0xFF94A3B8),
                      size: 20,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFF0066FF), width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.red, width: 1.0),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.red, width: 1.5),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter relation (e.g. Mother, Father)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Phone Number',
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0C1D37),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.poppins(
                    fontSize: 15.0.sp,
                    color: const Color(0xFF0C1D37),
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter Phone Number',
                    hintStyle: GoogleFonts.poppins(color: const Color(0xFF94A3B8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(
                      CupertinoIcons.phone,
                      color: Color(0xFF94A3B8),
                      size: 20,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFF0066FF), width: 1.5),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.red, width: 1.0),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.red, width: 1.5),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 40),
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
                    onPressed: _isSubmitting ? null : _saveContact,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isEditMode ? 'Update' : 'Save Contact',
                            style: GoogleFonts.poppins(
                              fontSize: 16.0.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
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
