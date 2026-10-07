import 'package:child_track/app/childapp/view_model/repository/child_repo.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/navigation/route_names.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/widgets/common_textfield.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:child_track/core/models/child_profile.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';

class AddKidView extends StatefulWidget {
  final ChildProfile? childToEdit;
  const AddKidView({super.key, this.childToEdit});

  @override
  State<AddKidView> createState() => _AddKidViewState();
}

class _AddKidViewState extends State<AddKidView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF4FE),
      // Figma: white header band with the 52px back circle and a centred Bold
      // title; the soft blue gradient only starts below it.
      appBar: figmaAppBar(
        context,
        title: widget.childToEdit != null ? 'Edit Kid' : 'Add Kid',
        titleSize: 22,
        titleColor: const Color(0xFF16181A),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingL),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 28),
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildAvatarSelector(),
                  const SizedBox(height: 20),
                  _buildDetailsSection(),
                  const SizedBox(height: 24),
                  _buildTravelModeSelector(),
                  const SizedBox(height: 64),
                  _buildSubmitButton(),
                  const SizedBox(height: AppSizes.spacingXL),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.childToEdit != null ? 'EDIT CHILD DETAILS' : 'CHILD DETAILS',
          style: GoogleFonts.poppins(
            fontSize: 12.0.sp,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.2,
            color: const Color(0xFF0069F9),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.childToEdit != null
              ? 'Update child information'
              : 'Tell us about your child',
          style: GoogleFonts.poppins(
            fontSize: 24.0.sp,
            fontWeight: FontWeight.w700,
            height: 1.5,
            color: const Color(0xFF16181A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.childToEdit != null
              ? 'Update the profile name or choose a new avatar.'
              : 'This personalises tracking alerts for their age & routine.',
          style: GoogleFonts.poppins(
            fontSize: 12.0.sp,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF4A5267),
          ),
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

  Widget _buildAvatarSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose Avatar',
          style: GoogleFonts.poppins(
            fontSize: 12.0.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF16181A),
          ),
        ),
        const SizedBox(height: 10),
        // Figma: 48px circles filling the avatar art (no white ring), a grey
        // rounded-square "+" for a custom photo pinned to the right.
        Padding(
          padding: const EdgeInsets.only(right: 20),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      ..._presetAvatars.map((avatar) {
                        final isSelected =
                            _selectedAvatar == avatar &&
                            _customAvatarFile == null;
                        return Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedAvatar = avatar;
                                _customAvatarFile = null;
                              });
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              foregroundDecoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF0069F9)
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: ClipOval(
                                child: Image.asset(avatar, fit: BoxFit.cover),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: _pickImage,
                child: Builder(
                  builder: (context) {
                    final hasCustom = _customAvatarFile != null;
                    final isSelected = _selectedAvatar == '+' && hasCustom;
                    return Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDDE1EA),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF0069F9)
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: hasCustom
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.file(
                                _customAvatarFile!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(
                              Icons.add_rounded,
                              color: Color(0xFF16181A),
                              size: 30,
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  TextStyle get _figmaHint => GoogleFonts.poppins(
    fontSize: 16.0.sp,
    fontWeight: FontWeight.w400,
    color: const Color(0xFF6B7280),
  );

  TextStyle get _figmaDropdownStyle => GoogleFonts.poppins(
    fontSize: 16.0.sp,
    fontWeight: FontWeight.w400,
    color: const Color(0xFF16181A),
  );

  InputDecoration get _figmaDropdownDecoration => InputDecoration(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF0069F9), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.error, width: 1.5),
    ),
  );

  Widget _buildFigmaLabel(String text) => Text(
    text,
    style: GoogleFonts.poppins(
      fontSize: 16.0.sp,
      fontWeight: FontWeight.w500,
      color: const Color(0xFF4A5267),
    ),
  );

  Widget _buildDetailsSection() {
    final isEditMode = widget.childToEdit != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter Details',
          style: GoogleFonts.poppins(
            fontSize: 12.0.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF16181A),
          ),
        ),
        const SizedBox(height: 12),
        // Name field — Figma: 58px white pill, 1px dark outline, hint only
        // (no label above, no leading icon).
        CommonTextField(
          controller: _nameController,
          hintText: 'Name of the Kid',
          keyboardType: TextInputType.name,
          fillColor: Colors.white,
          borderColor: const Color(0xFF404040),
          borderRadius: 16,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 18,
          ),
          hintStyle: _figmaHint,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter child name';
            }
            return null;
          },
        ),
        const SizedBox(height: 25),
        if (isEditMode) ...[
          _buildFigmaLabel('Age'),
          const SizedBox(height: 16),
          CommonTextField(
            controller: _ageController,
            hintText: 'Enter child age',
            keyboardType: TextInputType.number,
            fillColor: Colors.white,
            borderColor: const Color(0xFF404040),
            borderRadius: 16,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 40,
              vertical: 18,
            ),
            hintStyle: _figmaHint,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter child age';
              }
              final ageVal = int.tryParse(value);
              if (ageVal == null || ageVal <= 0) {
                return 'Please enter a valid age';
              }
              return null;
            },
          ),
        ] else ...[
          // Figma: one "Age" label over a Year / Month pair of plain white
          // dropdowns (the per-field "Birth Year/Month" captions are gone).
          _buildFigmaLabel('Age'),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(right: 38),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedYear,
                    isExpanded: true,
                    hint: Text('Year', style: _figmaDropdownStyle),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF16181A),
                    ),
                    decoration: _figmaDropdownDecoration,
                    style: _figmaDropdownStyle,
                    items: _years.map((year) {
                      return DropdownMenuItem<int>(
                        value: year,
                        child: Text(year.toString()),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedYear = val;
                      });
                    },
                    validator: (val) => val == null ? 'Year required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedMonth,
                    isExpanded: true,
                    hint: Text('Month', style: _figmaDropdownStyle),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF16181A),
                    ),
                    decoration: _figmaDropdownDecoration,
                    style: _figmaDropdownStyle,
                    items: _months.map((month) {
                      return DropdownMenuItem<String>(
                        value: month,
                        child: Text(month),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedMonth = val;
                      });
                    },
                    validator: (val) => val == null ? 'Month required' : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTravelModeSelector() {
    final modes = [
      {'emoji': '🚐', 'label': 'Van'},
      {'emoji': '🚌', 'label': 'Bus'},
      {'emoji': '🚶', 'label': 'Walk'},
      {'emoji': '🚗', 'label': 'Car'},
      {'emoji': '🛺', 'label': 'Auto'},
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How does your child travel to school?',
          style: GoogleFonts.poppins(
            fontSize: 12.0.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF16181A),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 5,
          children: modes.map((mode) {
            final emoji = mode['emoji']!;
            final label = mode['label']!;
            final isSelected = _selectedTravelMode == emoji;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedTravelMode = emoji;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 63,
                height: 66,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFA9B4C8)
                        : const Color(0xFFDDE1EA),
                    width: isSelected ? 2.0 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(emoji, style: TextStyle(fontSize: 20.0.sp)),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: GoogleFonts.poppins(
                        fontSize: 12.0.sp,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF4A5267),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: _isLoading ? null : _onSubmit,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: _isLoading
                ? const Color(0xFF0069F9).withValues(alpha: 0.5)
                : const Color(0xFF0069F9),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
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
                  widget.childToEdit != null ? 'Update' : 'Continue',
                  style: GoogleFonts.poppins(
                    fontSize: 20.0.sp,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

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

          if (mounted && childCode != null) {
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
