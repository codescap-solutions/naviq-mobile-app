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
      final String? encoded = SharedPrefsService.prefs.getString('emergency_contacts');
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
          const SnackBar(
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
        top: MediaQuery.of(context).padding.top + 8,
        bottom: 24,
        left: 20,
        right: 20,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white,
                  size: 28,
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
            color: const Color(0xFF0C1D37),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.poppins(
            fontSize: 15.0.sp,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF0C1D37),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(
              fontSize: 14.0.sp,
              color: const Color(0xFF94A3B8),
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primaryColor, width: 1.5),
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
      padding: const EdgeInsets.only(bottom: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
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
              const SizedBox(width: 10),
              Text(
                'Contact $index',
                style: GoogleFonts.poppins(
                  fontSize: 16.0.sp,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0C1D37),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTextField(
            label: 'Name',
            hint: 'Enter full name',
            controller: nameController,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            label: 'Relation with Child',
            hint: 'e.g. Mother, Father, Uncle',
            controller: relationController,
          ),
          const SizedBox(height: 16),
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
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                children: [
                  for (int i = 1; i <= 5; i++) _buildContactCard(i),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _isLoading ? null : _saveContacts,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
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
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
