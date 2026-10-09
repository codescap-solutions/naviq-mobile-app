import 'package:child_track/core/utils/responsive_font.dart';
import 'package:flutter/material.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/widgets/common_button.dart';
import 'package:child_track/core/widgets/common_textfield.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/models/child_profile.dart';

class ProfileForm extends StatefulWidget {
  final bool isEdit;
  final String? initialName;
  final String? initialCode;

  const ProfileForm({
    super.key,
    required this.isEdit,
    this.initialName,
    this.initialCode,
  });

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _genderController;
  late final TextEditingController _dobController;
  late final TextEditingController _passwordController;
  late final TextEditingController _idController;
  late final SharedPrefsService _sharedPrefsService;

  @override
  void initState() {
    super.initState();
    _sharedPrefsService = injector<SharedPrefsService>();
    _nameController = TextEditingController(
      text: widget.initialName ?? 'VANCHAI',
    );
    _emailController = TextEditingController(text: 'yanchu@gmail.com');
    _phoneController = TextEditingController(text: '+14867888899');
    _genderController = TextEditingController(text: 'Male');
    _dobController = TextEditingController(text: '12/12/2000');
    _passwordController = TextEditingController(text: 'eWTrByvGc4');
    _idController = TextEditingController(
      text: widget.initialCode ?? '2723-202408282',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _genderController.dispose();
    _dobController.dispose();
    _passwordController.dispose();
    _idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          SizedBox(height: 16.w),
          _label('Name'),
          CommonTextField(
            controller: _nameController,
            hintText: 'Name',
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a name';
              }
              return null;
            },
          ),
          SizedBox(height: AppSizes.spacingM),
          _label('Email Id'),
          CommonTextField(
            controller: _emailController,
            hintText: 'Email',
            keyboardType: TextInputType.emailAddress,
          ),
          SizedBox(height: AppSizes.spacingM),
          _label('Phone Number'),
          CommonTextField(
            controller: _phoneController,
            hintText: 'Phone',
            keyboardType: TextInputType.phone,
          ),
          SizedBox(height: AppSizes.spacingM),
          _label('Gender'),
          _GenderField(controller: _genderController),
          SizedBox(height: AppSizes.spacingM),
          _label('Date of Birth ( DD/MM/YR )'),
          _DobField(controller: _dobController),
          SizedBox(height: AppSizes.spacingM),
          _label('Password'),
          CommonTextField(
            controller: _passwordController,
            hintText: 'Password',
            obscureText: true,
          ),
          if (!widget.isEdit) ...[
            SizedBox(height: AppSizes.spacingM),
            _label('ID Number / Child Code'),
            CommonTextField(
              controller: _idController,
              hintText: 'ID Number',
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter child ID number or code';
                }
                return null;
              },
            ),
          ],
          SizedBox(height: AppSizes.spacingXL),
          CommonButton(
            text: widget.isEdit ? 'Update' : 'Add',
            onPressed: () async {
              if (_formKey.currentState?.validate() ?? false) {
                final name = _nameController.text.trim();
                final code = _idController.text.trim();

                final children = _sharedPrefsService.getChildren();

                if (widget.isEdit) {
                  // Find child by matching their old name/code and update
                  final updatedList = children.map((c) {
                    if (c.childName == widget.initialName ||
                        c.childCode == widget.initialCode) {
                      return c.copyWith(childName: name);
                    }
                    return c;
                  }).toList();
                  await _sharedPrefsService.saveChildren(updatedList);

                  // Also check if we updated the currently active child name
                  final activeName =
                      _sharedPrefsService.getString('child_name') ?? '';
                  if (activeName == widget.initialName) {
                    await _sharedPrefsService.setString('child_name', name);
                  }
                } else {
                  // Add a new child profile
                  final childId =
                      'child_${DateTime.now().millisecondsSinceEpoch}';
                  final newChild = ChildProfile(
                    childId: childId,
                    childCode: code,
                    childName: name,
                    authToken: 'mock_token_$childId',
                    lastActiveAt: DateTime.now(),
                  );
                  await _sharedPrefsService.addChild(newChild);
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        widget.isEdit
                            ? 'Profile updated successfully'
                            : 'Added child profile successfully',
                      ),
                    ),
                  );
                  Navigator.pop(
                    context,
                    true,
                  ); // Return true to trigger refresh
                }
              }
            },
            height: 44.w,
            width: double.infinity,
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 6.w),
        child: Text(
          text,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _GenderField extends StatelessWidget {
  final TextEditingController controller;
  const _GenderField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: controller.text,
      items: [
        DropdownMenuItem(value: 'Male', child: Text('Male')),
        DropdownMenuItem(value: 'Female', child: Text('Female')),
        DropdownMenuItem(value: 'Other', child: Text('Other')),
      ],
      onChanged: (v) => controller.text = v ?? 'Male',
      decoration: InputDecoration(
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSizes.paddingM,
          vertical: AppSizes.paddingM,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
          borderSide: BorderSide(color: AppColors.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
          borderSide: BorderSide(color: AppColors.borderColor),
        ),
      ),
    );
  }
}

class _DobField extends StatelessWidget {
  final TextEditingController controller;
  const _DobField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime(now.year - 10, now.month, now.day),
          firstDate: DateTime(1970),
          lastDate: now,
        );
        if (picked != null) {
          final day = picked.day.toString().padLeft(2, '0');
          final month = picked.month.toString().padLeft(2, '0');
          final year = picked.year.toString();
          controller.text = '$day/$month/$year';
        }
      },
      child: IgnorePointer(
        child: CommonTextField(controller: controller, hintText: 'DD/MM/YR'),
      ),
    );
  }
}
