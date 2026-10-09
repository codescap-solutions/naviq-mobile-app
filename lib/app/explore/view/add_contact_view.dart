import 'dart:convert';
import 'package:child_track/core/widgets/figma_app_bar.dart';
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
      final String id =
          updatedList[index]['id'] ??
          'contact_${DateTime.now().millisecondsSinceEpoch}';

      if (!id.startsWith('contact_') && !id.startsWith('default_')) {
        final response = await injector<HomeRepository>().editParentContact(
          id: id,
          name: name,
          relation: relation,
          phone: phone,
        );
        if (!response.isSuccess) {
          AppSnackbar.showError(
            context,
            response.message.isNotEmpty
                ? response.message
                : 'Failed to update contact on server',
          );
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
        AppSnackbar.showError(
          context,
          response.message.isNotEmpty
              ? response.message
              : 'Failed to save contact to server',
        );
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
      backgroundColor: Color(0xFFF8FAFC),
      appBar: figmaAppBar(
        context,
        title: isEditMode ? 'Edit Contact' : 'Add Contact',
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.0.w),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 8.w),
                Text(
                  'Name',
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0C1D37),
                  ),
                ),
                SizedBox(height: 8.w),
                TextFormField(
                  controller: _nameController,
                  style: GoogleFonts.poppins(
                    fontSize: 15.0.sp,
                    color: Color(0xFF0C1D37),
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter Name',
                    hintStyle: GoogleFonts.poppins(color: Color(0xFF94A3B8)),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 14.w,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(
                      CupertinoIcons.person,
                      color: Color(0xFF94A3B8),
                      size: 20.w,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(
                        color: Color(0xFF0066FF),
                        width: 1.5.w,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(color: Colors.red, width: 1.0.w),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(color: Colors.red, width: 1.5.w),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter contact name';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 20.w),
                Text(
                  'Relation with Child',
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0C1D37),
                  ),
                ),
                SizedBox(height: 8.w),
                TextFormField(
                  controller: _relationController,
                  style: GoogleFonts.poppins(
                    fontSize: 15.0.sp,
                    color: Color(0xFF0C1D37),
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. Mother, Father',
                    hintStyle: GoogleFonts.poppins(color: Color(0xFF94A3B8)),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 14.w,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(
                      CupertinoIcons.group,
                      color: Color(0xFF94A3B8),
                      size: 20.w,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(
                        color: Color(0xFF0066FF),
                        width: 1.5.w,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(color: Colors.red, width: 1.0.w),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(color: Colors.red, width: 1.5.w),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter relation (e.g. Mother, Father)';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 20.w),
                Text(
                  'Phone Number',
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0C1D37),
                  ),
                ),
                SizedBox(height: 8.w),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: GoogleFonts.poppins(
                    fontSize: 15.0.sp,
                    color: Color(0xFF0C1D37),
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter Phone Number',
                    hintStyle: GoogleFonts.poppins(color: Color(0xFF94A3B8)),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 14.w,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(
                      CupertinoIcons.phone,
                      color: Color(0xFF94A3B8),
                      size: 20.w,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(
                        color: Color(0xFF0066FF),
                        width: 1.5.w,
                      ),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(color: Colors.red, width: 1.0.w),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16.w),
                      borderSide: BorderSide(color: Colors.red, width: 1.5.w),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter phone number';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 40.w),
                SizedBox(
                  width: double.infinity,
                  height: 54.w,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF0066FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.w),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isSubmitting ? null : _saveContact,
                    child: _isSubmitting
                        ? SizedBox(
                            width: 22.w,
                            height: 22.w,
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
