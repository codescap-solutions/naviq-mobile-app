import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/app/auth/view/onboarding/kid_added_view.dart';
import 'package:child_track/core/navigation/route_names.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/widgets/figma_primary_button.dart';
import 'package:child_track/core/widgets/common_textfield.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:child_track/core/models/child_profile.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';

class AddKidView extends StatefulWidget {
  final ChildProfile? childToEdit;

  /// Add a kid tracked by a GPS device: asks for its serial number and skips
  /// the child-code pairing step (there is no phone to pair).
  final bool withDevice;
  const AddKidView({super.key, this.childToEdit, this.withDevice = false});

  @override
  State<AddKidView> createState() => _AddKidViewState();
}

class _AddKidViewState extends State<AddKidView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _serialController = TextEditingController();
  final _childRepo = injector<ChildRepo>();
  final _homeRepo = injector<HomeRepository>();
  final _sharedPrefsService = SharedPrefsService();
  bool _isLoading = false;

  // Selected avatar state (Boy 1 as default)
  String _selectedAvatar = 'assets/images/childavatar/Boy 03.png';
  File? _customAvatarFile;

  final List<String> _presetAvatars = [
    'assets/images/childavatar/Boy 03.png',
    'assets/images/childavatar/Boy 12.png',
    'assets/images/childavatar/Boy 16.png',
    'assets/images/childavatar/Girl 01.png',
    'assets/images/childavatar/Girl 12.png',
    'assets/images/childavatar/Girl 13.png',
  ];

  // Selected travel mode state (Van as default)
  String _selectedTravelMode = '🚐';

  // Selected birth date details
  int? _selectedYear;
  String? _selectedMonth;

  // Static options matching Figma
  final List<int> _years = List.generate(
    18,
    (index) => DateTime.now().year - index,
  );
  final List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.childToEdit != null) {
      final child = widget.childToEdit!;
      _nameController.text = child.childName;
      _ageController.text = child.age?.toString() ?? '';
      if (child.avatar != null && child.avatar!.isNotEmpty) {
        final avatarVal = child.avatar!;
        if (avatarVal.startsWith('http') || avatarVal.startsWith('/')) {
          _selectedAvatar = '+';
          if (!avatarVal.startsWith('http')) {
            _customAvatarFile = File(avatarVal);
          }
        } else {
          final matchingPreset = _presetAvatars.firstWhere(
            (path) => path.endsWith(avatarVal),
            orElse: () => _presetAvatars.first,
          );
          _selectedAvatar = matchingPreset;
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _serialController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.childToEdit != null;
    return Scaffold(
      backgroundColor: const Color(0xFFEDF4FE),
      // Figma: white header band with the 52px back circle and a centred Bold
      // title; the soft blue gradient only starts below it.
      appBar: figmaAppBar(context, title: isEdit ? 'Edit Kid' : 'Add Kid'),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFAFBFD), Color(0xFFEDF4FE)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 27.w),
                  _buildHeader(isEdit),
                  SizedBox(height: 21.w),
                  _buildAvatarSelector(),
                  SizedBox(height: 21.w),
                  _buildDetailsSection(isEdit),
                  SizedBox(height: 24.w),
                  _buildTravelModeSelector(),
                  SizedBox(height: 64.w),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: FigmaPrimaryButton(
                      label: isEdit ? 'Update' : 'Continue',
                      isLoading: _isLoading,
                      onPressed: _onSubmit,
                    ),
                  ),
                  SizedBox(height: 33.w),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isEdit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isEdit ? 'EDIT CHILD DETAILS' : 'CHILD DETAILS',
          style: FigmaText.eyebrow,
        ),
        SizedBox(height: 8.w),
        Text(
          isEdit ? 'Update child information' : 'Tell us about your child',
          style: FigmaText.pageTitle,
        ),
        SizedBox(height: 4.w),
        Text(
          isEdit
              ? 'Update the profile name or choose a new avatar.'
              : 'This personalises tracking alerts for their age & routine.',
          style: FigmaText.caption,
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _customAvatarFile = File(image.path);
          _selectedAvatar = '+'; // Indicates custom avatar is selected
        });
      }
    } catch (e) {
      AppLogger.error('Error picking image: $e');
      if (mounted) {
        AppSnackbar.showError(context, 'Failed to pick image');
      }
    }
  }

  /// Figma avatar / travel-mode tile: 48px circle (or rounded square) with a
  /// blue ring when selected.
  Widget _avatarRing({
    required bool selected,
    required Widget child,
    required BorderRadius radius,
    Color? color,
  }) => Container(
    width: 48.w,
    height: 48.w,
    decoration: BoxDecoration(color: color, borderRadius: radius),
    foregroundDecoration: BoxDecoration(
      borderRadius: radius,
      border: Border.all(
        color: selected ? FigmaColors.primary : Colors.transparent,
        width: 2.5,
      ),
    ),
    child: child,
  );

  Widget _buildAvatarSelector() {
    final hasCustom = _customAvatarFile != null;
    final squareRadius = BorderRadius.circular(16.w);
    final circle = BorderRadius.circular(48.w);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choose Avatar', style: FigmaText.sectionLabel),
        SizedBox(height: 8.w),
        // Figma: 48px circles filling the avatar art (no white ring), a grey
        // rounded-square "+" for a custom photo pinned to the right.
        Padding(
          padding: EdgeInsets.only(right: 20.w),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      for (final avatar in _presetAvatars)
                        Padding(
                          padding: EdgeInsets.only(right: 16.w),
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _selectedAvatar = avatar;
                              _customAvatarFile = null;
                            }),
                            child: _avatarRing(
                              selected: _selectedAvatar == avatar && !hasCustom,
                              radius: circle,
                              child: ClipOval(
                                child: Image.asset(avatar, fit: BoxFit.cover),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: _pickImage,
                child: _avatarRing(
                  selected: _selectedAvatar == '+' && hasCustom,
                  radius: squareRadius,
                  color: FigmaColors.border,
                  child: hasCustom
                      ? ClipRRect(
                          borderRadius: squareRadius,
                          child: Image.file(
                            _customAvatarFile!,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Icon(
                          Icons.add_rounded,
                          color: FigmaColors.ink,
                          size: 30.w,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Plain white dropdown (Figma: 38px high, 8px radius, no outline).
  InputDecoration get _dropdownDecoration {
    OutlineInputBorder border([BorderSide side = BorderSide.none]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.w),
          borderSide: side,
        );
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      constraints: BoxConstraints.tightFor(height: 38.w),
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w),
      border: border(),
      enabledBorder: border(),
      focusedBorder: border(
        const BorderSide(color: FigmaColors.primary, width: 1.5),
      ),
      errorBorder: border(const BorderSide(color: AppColors.error)),
      focusedErrorBorder: border(
        const BorderSide(color: AppColors.error, width: 1.5),
      ),
    );
  }

  Widget _dropdown<T>({
    required String hint,
    required T? value,
    required List<T> options,
    required ValueChanged<T?> onChanged,
    required String requiredMessage,
  }) => DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    hint: Text(hint, style: FigmaText.input),
    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: FigmaColors.ink),
    decoration: _dropdownDecoration,
    style: FigmaText.input,
    items: [
      for (final o in options)
        DropdownMenuItem<T>(value: o, child: Text(o.toString())),
    ],
    onChanged: onChanged,
    validator: (v) => v == null ? requiredMessage : null,
  );

  /// White outlined text field used for the name / age inputs.
  Widget _outlinedField({
    required TextEditingController controller,
    required String hint,
    required TextInputType keyboardType,
    required String? Function(String?) validator,
  }) => CommonTextField(
    controller: controller,
    hintText: hint,
    keyboardType: keyboardType,
    fillColor: Colors.white,
    borderColor: FigmaColors.fieldBorder,
    borderRadius: 16.w,
    contentPadding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 18.w),
    hintStyle: FigmaText.inputHint,
    validator: validator,
  );

  /// Same 10–11 digit rule as the Devices screen's link sheet.
  Widget _buildSerialField() => CommonTextField(
    controller: _serialController,
    hintText: 'Device serial number',
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    maxLength: 11,
    fillColor: Colors.white,
    borderColor: FigmaColors.fieldBorder,
    borderRadius: 16.w,
    contentPadding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 18.w),
    hintStyle: FigmaText.inputHint,
    suffixIcon: IconButton(
      tooltip: 'Where to find the serial number',
      icon: Icon(Icons.info_outline_rounded, color: FigmaColors.body),
      onPressed: () => AppSnackbar.showInfo(
        context,
        'The 10 or 11-digit serial number is printed on the back of the '
        'tracker package.',
      ),
    ),
    validator: (v) {
      final serial = v?.trim() ?? '';
      if (serial.isEmpty) return 'Please enter the device serial number';
      if (serial.length < 10) return 'Serial number must be 10 or 11 digits';
      return null;
    },
  );

  Widget _buildDetailsSection(bool isEdit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter Details', style: FigmaText.sectionLabel),
        SizedBox(height: 12.w),
        // Figma: 58px white pill, 1px dark outline, hint only (no label above,
        // no leading icon).
        _outlinedField(
          controller: _nameController,
          hint: 'Name of the Kid',
          keyboardType: TextInputType.name,
          validator: (v) =>
              v == null || v.isEmpty ? 'Please enter child name' : null,
        ),
        if (widget.withDevice && !isEdit) ...[
          SizedBox(height: 16.w),
          _buildSerialField(),
        ],
        SizedBox(height: 25.w),
        Text('Age', style: FigmaText.fieldLabel),
        SizedBox(height: 16.w),
        if (isEdit)
          _outlinedField(
            controller: _ageController,
            hint: 'Enter child age',
            keyboardType: TextInputType.number,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please enter child age';
              final age = int.tryParse(v);
              return age == null || age <= 0
                  ? 'Please enter a valid age'
                  : null;
            },
          )
        else
          // Figma: one "Age" label over a Year / Month pair of white dropdowns.
          Padding(
            padding: EdgeInsets.only(right: 38.w),
            child: Row(
              children: [
                Expanded(
                  child: _dropdown<int>(
                    hint: 'Year',
                    value: _selectedYear,
                    options: _years,
                    onChanged: (v) => setState(() => _selectedYear = v),
                    requiredMessage: 'Year required',
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _dropdown<String>(
                    hint: 'Month',
                    value: _selectedMonth,
                    options: _months,
                    onChanged: (v) => setState(() => _selectedMonth = v),
                    requiredMessage: 'Month required',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static const _travelModes = [
    (emoji: '🚐', label: 'Van'),
    (emoji: '🚌', label: 'Bus'),
    (emoji: '🚶', label: 'Walk'),
    (emoji: '🚗', label: 'Car'),
    (emoji: '🛺', label: 'Auto'),
  ];

  Widget _buildTravelModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How does your child travel to school?',
          style: FigmaText.sectionLabel,
        ),
        SizedBox(height: 8.w),
        Wrap(
          spacing: 5.w,
          children: [
            for (final mode in _travelModes)
              GestureDetector(
                onTap: () => setState(() => _selectedTravelMode = mode.emoji),
                child: _travelTile(
                  mode.emoji,
                  mode.label,
                  _selectedTravelMode == mode.emoji,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _travelTile(String emoji, String label, bool selected) =>
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 63.w,
        height: 66.w,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.w),
          border: Border.all(
            color: selected ? const Color(0xFFA9B4C8) : FigmaColors.border,
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: TextStyle(fontSize: 20.0.sp)),
            SizedBox(height: 4.w),
            Text(label, style: FigmaText.poppins(12, color: FigmaColors.body)),
          ],
        ),
      );

  void _onSubmit() {
    if (_formKey.currentState?.validate() ?? false) {
      if (widget.childToEdit == null) {
        if (_selectedYear == null) {
          AppSnackbar.showError(context, 'Please select child\'s birth year');
          return;
        }
        if (_selectedMonth == null) {
          AppSnackbar.showError(context, 'Please select child\'s birth month');
          return;
        }
        _createChild();
      } else {
        _updateChild();
      }
    }
  }

  Future<void> _updateChild() async {
    setState(() => _isLoading = true);
    try {
      final name = _nameController.text.trim();
      String? avatarValue;

      if (_customAvatarFile != null) {
        final uploadResponse = await _childRepo.uploadAvatar(
          _customAvatarFile!,
        );
        if (uploadResponse.isSuccess && uploadResponse.data != null) {
          avatarValue = uploadResponse.data;
        } else {
          if (mounted) {
            AppSnackbar.showError(
              context,
              uploadResponse.message.isEmpty
                  ? 'Failed to upload avatar'
                  : uploadResponse.message,
            );
            setState(() => _isLoading = false);
          }
          return;
        }
      } else if (_selectedAvatar != '+') {
        avatarValue = _selectedAvatar.split('/').last;
      } else {
        avatarValue = widget.childToEdit?.avatar;
      }

      final ageText = _ageController.text.trim();
      final ageVal = int.tryParse(ageText);

      // Call backend PUT update API
      final updateResponse = await _homeRepo.updateChild(
        childId: widget.childToEdit!.childId,
        name: name,
        age: ageVal,
        avatar: avatarValue,
      );

      if (updateResponse.isSuccess) {
        final children = _sharedPrefsService.getChildren();
        final updatedList = children.map((c) {
          if (c.childId == widget.childToEdit!.childId) {
            return c.copyWith(
              childName: name,
              avatar: avatarValue,
              age: ageVal,
            );
          }
          return c;
        }).toList();

        await _sharedPrefsService.saveChildren(updatedList);

        // If active child, update name and avatar in preferences
        final activeChildId = _sharedPrefsService.getString('child_id') ?? '';
        if (activeChildId == widget.childToEdit!.childId) {
          await _sharedPrefsService.setString('child_name', name);
          if (avatarValue != null) {
            await _sharedPrefsService.setString('child_avatar', avatarValue);
          }
        }

        if (mounted) {
          AppSnackbar.showSuccess(
            context,
            'Child profile updated successfully',
          );
          Navigator.of(context).pop(true);
        }
      } else {
        if (mounted) {
          AppSnackbar.showError(
            context,
            updateResponse.message.isEmpty
                ? 'Failed to update child profile'
                : updateResponse.message,
          );
        }
      }
    } catch (e) {
      AppLogger.error('Error updating child: ${e.toString()}');
      if (mounted) {
        AppSnackbar.showError(
          context,
          'Failed to update child: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createChild() async {
    setState(() => _isLoading = true);
    try {
      final name = _nameController.text.trim();
      final age = DateTime.now().year - _selectedYear!;

      String travelOption;
      switch (_selectedTravelMode) {
        case '🚐':
          travelOption = 'Van';
          break;
        case '🚌':
          travelOption = 'Bus';
          break;
        case '🚶':
          travelOption = 'Walk';
          break;
        case '🚗':
          travelOption = 'Car';
          break;
        case '🛺':
          travelOption = 'Auto';
          break;
        default:
          travelOption = 'Van';
      }

      String? avatarValue;

      if (_customAvatarFile != null) {
        final uploadResponse = await _childRepo.uploadAvatar(
          _customAvatarFile!,
        );
        if (uploadResponse.isSuccess && uploadResponse.data != null) {
          avatarValue = uploadResponse.data;
        } else {
          if (mounted) {
            AppSnackbar.showError(
              context,
              uploadResponse.message.isEmpty
                  ? 'Failed to upload avatar'
                  : uploadResponse.message,
            );
            setState(() => _isLoading = false);
          }
          return;
        }
      } else {
        avatarValue = _selectedAvatar.split('/').last;
      }

      final response = await _childRepo.createChild(
        name: name,
        age: age,
        travelOption: travelOption,
        avatar: avatarValue,
        deviceImei: widget.withDevice ? _serialController.text.trim() : null,
      );

      if (response.isSuccess && response.data != null) {
        final childData = response.data!['child'] as Map<String, dynamic>?;
        final childCode = childData?['child_code'] as String?;
        final childId = childData?['child_id'] as String?;

        if (childId != null) {
          await _sharedPrefsService.setString('child_id', childId);
          final currentCount =
              _sharedPrefsService.getInt('children_count') ?? 0;
          final isFirstChild = currentCount == 0;
          await _sharedPrefsService.setInt('children_count', currentCount + 1);

          if (childCode != null) {
            await _sharedPrefsService.setString('child_code', childCode);

            AppLogger.info('Linking child to parent with code: $childCode');
            final linkResponse = await _homeRepo.linkChild(
              childCode: childCode,
            );

            if (linkResponse.isSuccess) {
              AppLogger.info('Child linked to parent successfully');
            } else {
              AppLogger.warning(
                'Failed to link child to parent: ${linkResponse.message}',
              );
            }
          }

          AppLogger.info(
            'Child created successfully. ID: $childId, Code: $childCode',
          );

          if (mounted && widget.withDevice) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => KidAddedView(
                  kidName: name,
                  serial: _serialController.text.trim(),
                ),
              ),
            );
          } else if (mounted && childCode != null) {
            Navigator.of(context).pushReplacementNamed(
              RouteNames.childCode,
              arguments: {
                'childCode': childCode,
                'childId': childId,
                'isFirstChild': isFirstChild,
              },
            );
          } else if (mounted) {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil(RouteNames.home, (route) => false);
          }
        } else {
          if (mounted) {
            AppSnackbar.showError(context, 'Child ID not received');
          }
        }
      } else {
        if (mounted) {
          AppSnackbar.showError(context, response.message);
        }
      }
    } catch (e) {
      AppLogger.error('Error creating child: ${e.toString()}');
      if (mounted) {
        AppSnackbar.showError(
          context,
          'Failed to create child: ${e.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
