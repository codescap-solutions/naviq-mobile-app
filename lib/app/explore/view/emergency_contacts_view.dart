import 'dart:convert';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class EmergencyContactsView extends StatefulWidget {
  const EmergencyContactsView({super.key});

  @override
  State<EmergencyContactsView> createState() => _EmergencyContactsViewState();
}

class _EmergencyContactsViewState extends State<EmergencyContactsView> {
  final List<TextEditingController> _nameControllers = [];
  final List<TextEditingController> _relationControllers = [];
  final List<TextEditingController> _phoneControllers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 5; i++) {
      _nameControllers.add(TextEditingController());
      _relationControllers.add(TextEditingController());
      _phoneControllers.add(TextEditingController());
    }
    _loadContacts();
  }

  @override
  void dispose() {
    for (int i = 0; i < 5; i++) {
      _nameControllers[i].dispose();
      _relationControllers[i].dispose();
      _phoneControllers[i].dispose();
    }
    super.dispose();
  }

  void _loadContacts() {
    try {
      final String? encoded = SharedPrefsService.prefs.getString(
        'emergency_contacts',
      );
      if (encoded != null && encoded.isNotEmpty) {
        final List<dynamic> decoded = json.decode(encoded);
        for (int i = 0; i < min(5, decoded.length); i++) {
          final map = decoded[i] as Map<String, dynamic>;
          _nameControllers[i].text = map['name'] ?? '';
          _relationControllers[i].text = map['relation'] ?? '';
          _phoneControllers[i].text = map['phone'] ?? '';
        }
      }
    } catch (e) {
      AppLogger.error('Failed to parse emergency contacts: $e');
    }
  }

  Future<void> _saveContacts() async {
    setState(() {
      _isLoading = true;
    });

    final List<Map<String, String>> contactsList = [];
    for (int i = 0; i < 5; i++) {
      contactsList.add({
        'name': _nameControllers[i].text.trim(),
        'relation': _relationControllers[i].text.trim(),
        'phone': _phoneControllers[i].text.trim(),
      });
    }

    try {
      await SharedPrefsService.prefs.setString(
        'emergency_contacts',
        json.encode(contactsList),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Emergency contacts updated successfully!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save contacts: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: AppColors.primaryColor,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8.w,
        bottom: 24.w,
        left: 20.w,
        right: 20.w,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white,
                  size: 28.w,
                ),
              ),
            ),
          ),
          Text(
            'Parents Details',
            style: GoogleFonts.poppins(
              fontSize: 20.0.sp,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 14.0.sp,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0C1D37),
          ),
        ),
        SizedBox(height: 8.w),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.poppins(
            fontSize: 15.0.sp,
            fontWeight: FontWeight.w500,
            color: Color(0xFF0C1D37),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(
              fontSize: 14.0.sp,
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: Color(0xFFF8FAFC),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16.w,
              vertical: 16.w,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.w),
              borderSide: BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.w),
              borderSide: BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.w),
              borderSide: BorderSide(
                color: AppColors.primaryColor,
                width: 1.5.w,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactCard(int index) {
    final nameController = _nameControllers[index - 1];
    final relationController = _relationControllers[index - 1];
    final phoneController = _phoneControllers[index - 1];

    return Padding(
      padding: EdgeInsets.only(bottom: 32.0.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28.w,
                height: 28.w,
                decoration: BoxDecoration(
                  color: AppColors.primaryColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Text(
                'Contact $index',
                style: GoogleFonts.poppins(
                  fontSize: 16.0.sp,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0C1D37),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.w),
          _buildTextField(
            label: 'Name',
            hint: 'Enter full name',
            controller: nameController,
          ),
          SizedBox(height: 16.w),
          _buildTextField(
            label: 'Relation with Child',
            hint: 'e.g. Mother, Father, Uncle',
            controller: relationController,
          ),
          SizedBox(height: 16.w),
          _buildTextField(
            label: 'Phone Number',
            hint: '+1 000 000 0000',
            controller: phoneController,
            keyboardType: TextInputType.phone,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.w),
              child: Column(
                children: [
                  for (int i = 1; i <= 5; i++) _buildContactCard(i),
                  SizedBox(height: 16.w),
                  SizedBox(
                    width: double.infinity,
                    height: 54.w,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16.w),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _isLoading ? null : _saveContacts,
                      child: _isLoading
                          ? SizedBox(
                              width: 24.w,
                              height: 24.w,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              'Done',
                              style: GoogleFonts.poppins(
                                fontSize: 16.0.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: 24.w),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
