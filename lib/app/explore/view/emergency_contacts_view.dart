import 'dart:convert';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:child_track/core/widgets/figma_primary_button.dart';
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

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10.w),
      borderSide: BorderSide(color: FigmaColors.border),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: FigmaText.poppins(12, weight: FontWeight.w600, lineHeight: 18),
        ),
        SizedBox(height: 6.w),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: FigmaText.poppins(14, lineHeight: 20),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: FigmaText.poppins(
              12,
              color: FigmaColors.hint,
              lineHeight: 18,
            ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14.w,
              vertical: 12.w,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: FigmaColors.primary),
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
          Text(
            'Contact $index',
            style: FigmaText.poppins(
              14,
              weight: FontWeight.w700,
              lineHeight: 20,
            ),
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
      backgroundColor: Color(0xFFF4F8FE),
      appBar: figmaAppBar(context, title: 'Parents Details'),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.w),
              child: Column(
                children: [
                  for (int i = 1; i <= 5; i++) _buildContactCard(i),
                  SizedBox(height: 16.w),
                  FigmaPrimaryButton(
                    label: 'Done',
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _saveContacts,
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
