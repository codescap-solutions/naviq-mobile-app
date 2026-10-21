import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/widgets/common_button.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

/// Calling and texting must always work for a child (including emergencies),
/// so these apps can never be locked — neither one by one nor by "Set New
/// Limit" (block all). Android matches the dialer / messaging packages; iOS
/// only exposes opaque tokens, so it matches the resolved app name.
const _kEssentialPackages = {
  'com.android.dialer',
  'com.google.android.dialer',
  'com.samsung.android.dialer',
  'com.android.phone',
  'com.android.server.telecom',
  'com.android.contacts',
  'com.google.android.apps.messaging',
  'com.android.mms',
  'com.android.messaging',
  'com.samsung.android.messaging',
};
const _kEssentialNames = {'phone', 'messages', 'messaging', 'message'};

bool isEssentialApp(String packageName, String appName) =>
    _kEssentialPackages.contains(packageName) ||
    _kEssentialNames.contains(appName.trim().toLowerCase());

class SocialAppItem extends StatelessWidget {
  final ImageProvider icon;
  final String name;
  final String usage;
  final bool isLocked;

  /// False for Phone / Messages ([isEssentialApp]): the lock control is hidden.
  final bool lockable;
  final Function(bool, int)? onLockToggle;

  /// This app's usage relative to the busiest app in the list (0..1); drives
  /// the Figma blue-to-white row tint.
  final double usageFraction;

  /// Configured daily budget in minutes for this app, or null if none set.
  final int? dailyLimitMinutes;

  /// Called with the new limit in minutes, or null to clear it.
  final ValueChanged<int?>? onSetDailyLimit;

  const SocialAppItem({
    super.key,
    required this.icon,
    required this.name,
    required this.usage,
    required this.isLocked,
    this.lockable = true,
    this.onLockToggle,
    this.usageFraction = 0,
    this.dailyLimitMinutes,
    this.onSetDailyLimit,
  });

  @override
  Widget build(BuildContext context) {
    final double f = usageFraction.clamp(0.0, 1.0);
    return Container(
      height: 75.w,
      margin: EdgeInsets.fromLTRB(4.w, 0.w, 4.w, 8.w),
      decoration: BoxDecoration(
        color: Colors.white,
        // Figma: pale-blue wash fading to white; busier apps get more of it.
        gradient: f < 0.02
            ? null
            : LinearGradient(
                colors: [Color(0xFFDEEFFE), Colors.white],
                stops: [0.0, 0.25 + 0.75 * f],
              ),
        borderRadius: BorderRadius.circular(14.w),
        border: Border.all(color: Color(0xFFEBF3FF), width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14.w),
        onTap: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Usage details for $name')));
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.8.w),
          child: Row(
            children: [
              _AppIcon(icon: icon),
              SizedBox(width: 16.w),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 16.0.sp,
                        fontWeight: FontWeight.w400,
                        height: 24 / 16,
                        letterSpacing: 0.2,
                        color: Color(0xFF0F1320),
                      ),
                    ),
                    SizedBox(height: 4.w),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 24.w,
                        constraints: BoxConstraints(minWidth: 87.w),
                        padding: EdgeInsets.symmetric(horizontal: 8.w),
                        decoration: BoxDecoration(
                          color: Color(0xFFEBF3FF),
                          borderRadius: BorderRadius.circular(8.w),
                        ),
                        child: Center(
                          widthFactor: 1,
                          child: Text(
                            usage,
                            style: GoogleFonts.poppins(
                              color: Color(0xFF4A5267),
                              fontSize: 11.0.sp,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (lockable)
                _LockIconButton(isLocked: isLocked, onLockToggle: onLockToggle)
              else
                SizedBox(width: 35.w),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final ImageProvider icon;

  const _AppIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50.w,
      height: 50.w,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.w),
        child: Image(
          image: icon,
          width: 50.w,
          height: 50.w,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 50.w,
              height: 50.w,
              color: Color(0xFFF1F5F9),
              child: Icon(Icons.apps, size: 20.w, color: Color(0xFF94A3B8)),
            );
          },
        ),
      ),
    );
  }
}

/// Shows/edits the daily usage budget for one app — separate from the
/// manual "lock now" toggle. Setting a limit here doesn't lock the app
/// immediately; it locks itself for the rest of the day once the child's
/// usage crosses it (server-side, via appTimeLimitEnforcer).
class _DailyLimitButton extends StatelessWidget {
  final int? dailyLimitMinutes;
  final ValueChanged<int?>? onSetDailyLimit;

  const _DailyLimitButton({this.dailyLimitMinutes, this.onSetDailyLimit});

  String get _label {
    final m = dailyLimitMinutes!;
    if (m % 60 == 0) return '${m ~/ 60}h';
    if (m < 60) return '${m}m';
    return '${m ~/ 60}h ${m % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final hasLimit = dailyLimitMinutes != null && dailyLimitMinutes! > 0;

    return GestureDetector(
      onTap: () => _showDialog(context),
      child: Container(
        height: 40.w,
        padding: EdgeInsets.symmetric(horizontal: hasLimit ? 10.w : 8.w),
        width: hasLimit ? null : 36,
        decoration: BoxDecoration(
          color: hasLimit ? Color(0xFFEFF6FF) : Colors.transparent,
          shape: hasLimit ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: hasLimit ? BorderRadius.circular(18.w) : null,
          border: hasLimit
              ? null
              : Border.all(color: Color(0xFFCBD5E1), width: 1.5),
        ),
        child: hasLimit
            ? Text(
                _label,
                style: GoogleFonts.poppins(
                  fontSize: 12.0.sp,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0066FF),
                ),
              )
            : Icon(Icons.add_rounded, size: 18.w, color: Color(0xFF94A3B8)),
      ),
    );
  }

  Future<void> _showDialog(BuildContext context) async {
    final int? minutes = await showDialog<int?>(
      context: context,
      builder: (context) =>
          _DailyLimitPickerDialog(initialMinutes: dailyLimitMinutes),
    );
    // A dialog popped with no value (user tapped outside) leaves minutes
    // null with no way to distinguish from "clear" — only act when the
    // dialog explicitly returned a result via its buttons.
    if (minutes == -1) {
      onSetDailyLimit?.call(null); // explicit "remove limit"
    } else if (minutes != null && minutes > 0) {
      onSetDailyLimit?.call(minutes);
    }
  }
}

class _DailyLimitPickerDialog extends StatefulWidget {
  final int? initialMinutes;
  const _DailyLimitPickerDialog({this.initialMinutes});

  @override
  State<_DailyLimitPickerDialog> createState() =>
      _DailyLimitPickerDialogState();
}

class _DailyLimitPickerDialogState extends State<_DailyLimitPickerDialog> {
  late int _hours;
  late int _minutes;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMinutes ?? 60;
    _hours = initial ~/ 60;
    _minutes = initial % 60;
    _hourController = FixedExtentScrollController(initialItem: _hours);
    _minuteController = FixedExtentScrollController(initialItem: _minutes ~/ 5);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  String get _description {
    if (_hours == 0 && _minutes == 0) return 'Select a daily budget';
    if (_hours == 0) return 'Locks itself after $_minutes min of use today';
    if (_minutes == 0) return 'Locks itself after $_hours hr of use today';
    return 'Locks itself after $_hours hr $_minutes min of use today';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 32.w),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceColor,
          borderRadius: BorderRadius.circular(24.w),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24.w,
              offset: Offset(0, 8.w),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 18.w, horizontal: 20.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryColor,
                    AppColors.primaryColor.withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24.w),
                  topRight: Radius.circular(24.w),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.hourglass_bottom_rounded,
                    color: Colors.white,
                    size: 22.w,
                  ),
                  SizedBox(width: 10.w),
                  Text(
                    'Daily Time Limit',
                    style: AppTextStyles.headline6.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 20.w, 20.w, 20.w),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 10.w,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12.w),
                      border: Border.all(
                        color: AppColors.primaryColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16.w,
                          color: AppColors.primaryColor,
                        ),
                        SizedBox(width: 6.w),
                        Flexible(
                          child: Text(
                            _description,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20.w),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildWheel(
                        label: 'Hrs',
                        count: 12,
                        selected: _hours,
                        controller: _hourController,
                        onChanged: (i) => setState(() => _hours = i),
                      ),
                      Padding(
                        padding: EdgeInsets.only(bottom: 20.w),
                        child: Text(
                          ' : ',
                          style: AppTextStyles.headline4.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      _buildWheel(
                        label: 'Min',
                        count: 12,
                        selected: _minutes ~/ 5,
                        controller: _minuteController,
                        valueLabel: (i) => (i * 5).toString().padLeft(2, '0'),
                        onChanged: (i) => setState(() => _minutes = i * 5),
                      ),
                    ],
                  ),
                  SizedBox(height: 20.w),
                  CommonButton(
                    text: 'Set Daily Limit',
                    onPressed: (_hours == 0 && _minutes == 0)
                        ? null
                        : () => Navigator.pop(context, _hours * 60 + _minutes),
                    width: double.infinity,
                    height: 50.w,
                  ),
                  if (widget.initialMinutes != null) ...[
                    SizedBox(height: 10.w),
                    TextButton(
                      onPressed: () => Navigator.pop(context, -1),
                      child: Text(
                        'Remove Limit',
                        style: AppTextStyles.body2.copyWith(
                          color: Color(0xFFEF4444),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWheel({
    required String label,
    required int count,
    required int selected,
    required FixedExtentScrollController controller,
    required ValueChanged<int> onChanged,
    String Function(int)? valueLabel,
  }) {
    const itemH = 52.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyles.overline.copyWith(
            color: AppColors.primaryColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        SizedBox(height: 6.w),
        Container(
          width: 90.w,
          height: itemH * 3,
          decoration: BoxDecoration(
            color: AppColors.backgroundColor,
            borderRadius: BorderRadius.circular(16.w),
            border: Border.all(color: AppColors.borderColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15.w),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: itemH,
                  left: 0.w,
                  right: 0.w,
                  child: Container(
                    height: itemH,
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.10),
                      border: Border.symmetric(
                        horizontal: BorderSide(
                          color: AppColors.primaryColor.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                  ),
                ),
                ListWheelScrollView.useDelegate(
                  controller: controller,
                  itemExtent: itemH,
                  diameterRatio: 1.4,
                  physics: FixedExtentScrollPhysics(),
                  onSelectedItemChanged: onChanged,
                  childDelegate: ListWheelChildBuilderDelegate(
                    builder: (ctx, i) {
                      if (i < 0 || i >= count) return null;
                      final isSel = i == selected;
                      final lbl = valueLabel != null
                          ? valueLabel(i)
                          : i.toString().padLeft(2, '0');
                      return Center(
                        child: Text(
                          lbl,
                          style: isSel
                              ? AppTextStyles.headline4.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                )
                              : AppTextStyles.body1.copyWith(
                                  color: AppColors.textHint,
                                ),
                        ),
                      );
                    },
                    childCount: count,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LockIconButton extends StatelessWidget {
  final bool isLocked;
  final Function(bool, int)? onLockToggle;

  const _LockIconButton({required this.isLocked, this.onLockToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (isLocked) {
          onLockToggle?.call(false, 0);
        } else {
          _showLockOptions(context);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 35.w,
        child: Center(
          child: SvgPicture.asset(
            isLocked
                ? 'assets/icons/scroll_lock_on.svg'
                : 'assets/icons/scroll_lock_off.svg',
            width: 25.w,
            height: isLocked ? 34 : 35,
          ),
        ),
      ),
    );
  }

  Future<void> _showLockOptions(BuildContext context) async {
    final String? result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const _LockOptionsSheet(),
    );

    if (result == 'always') {
      onLockToggle?.call(true, 0); // 0 means always lock
    } else if (result == 'time') {
      if (!context.mounted) return;
      _showDurationDialog(context);
    }
  }

  Future<void> _showDurationDialog(BuildContext context) async {
    final Duration? duration = await showDialog<Duration>(
      context: context,
      builder: (context) => const _LockDurationDialog(),
    );

    if (duration != null && onLockToggle != null) {
      onLockToggle!(true, duration.inMinutes);
    }
  }
}

class _LockOptionsSheet extends StatelessWidget {
  const _LockOptionsSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSizes.paddingL.w,
        AppSizes.paddingL.w,
        AppSizes.paddingL.w,
        AppSizes.paddingL.w + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppSizes.radiusL.w),
          topRight: Radius.circular(AppSizes.radiusL.w),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40.w,
            height: 4.w,
            decoration: BoxDecoration(
              color: AppColors.borderColor,
              borderRadius: BorderRadius.circular(2.w),
            ),
          ),
          SizedBox(height: AppSizes.spacingL.w),
          Text(
            'Select Lock Type',
            style: AppTextStyles.headline6.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: AppSizes.spacingXL.w),
          _OptionTile(
            icon: Icons.lock_outline_rounded,
            title: 'Lock Always',
            subtitle: 'App will be locked until you manually unlock it',
            onTap: () => Navigator.pop(context, 'always'),
          ),
          SizedBox(height: AppSizes.spacingM.w),
          _OptionTile(
            icon: Icons.timer_outlined,
            title: 'Time-Based Lock',
            subtitle: 'Set a specific duration for the lock',
            onTap: () => Navigator.pop(context, 'time'),
          ),
          SizedBox(height: AppSizes.spacingXXL.w),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusM.w),
        side: BorderSide(color: AppColors.borderColor),
      ),
      leading: Container(
        padding: EdgeInsets.all(10.w),
        decoration: BoxDecoration(
          color: AppColors.primaryColor.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.primaryColor, size: 24.w),
      ),
      title: Text(title, style: AppTextStyles.subtitle1),
      subtitle: Text(
        subtitle,
        style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
      ),
      trailing: Icon(Icons.arrow_forward_ios, size: 16.w),
    );
  }
}

class _LockDurationDialog extends StatefulWidget {
  const _LockDurationDialog();

  @override
  State<_LockDurationDialog> createState() => _LockDurationDialogState();
}

class _LockDurationDialogState extends State<_LockDurationDialog> {
  int _hours = 1;
  int _minutes = 30;

  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  bool _editingHours = false;
  bool _editingMinutes = false;
  late TextEditingController _hourTextCtrl;
  late TextEditingController _minuteTextCtrl;
  final FocusNode _hourFocus = FocusNode();
  final FocusNode _minuteFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _hourController = FixedExtentScrollController(initialItem: _hours);
    _minuteController = FixedExtentScrollController(initialItem: _minutes ~/ 5);
    _hourTextCtrl = TextEditingController(
      text: _hours.toString().padLeft(2, '0'),
    );
    _minuteTextCtrl = TextEditingController(
      text: _minutes.toString().padLeft(2, '0'),
    );

    _hourFocus.addListener(() {
      if (!_hourFocus.hasFocus) _commitHourEdit();
    });
    _minuteFocus.addListener(() {
      if (!_minuteFocus.hasFocus) _commitMinuteEdit();
    });
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _hourTextCtrl.dispose();
    _minuteTextCtrl.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    super.dispose();
  }

  void _commitHourEdit() {
    final val = int.tryParse(_hourTextCtrl.text) ?? _hours;
    setState(() {
      _hours = val.clamp(0, 23);
      _editingHours = false;
      _hourTextCtrl.text = _hours.toString().padLeft(2, '0');
    });
    _hourController.jumpToItem(_hours);
  }

  void _commitMinuteEdit() {
    var val = int.tryParse(_minuteTextCtrl.text) ?? _minutes;
    val = ((val / 5).round() * 5).clamp(0, 55);
    setState(() {
      _minutes = val;
      _editingMinutes = false;
      _minuteTextCtrl.text = _minutes.toString().padLeft(2, '0');
    });
    _minuteController.jumpToItem(_minutes ~/ 5);
  }

  String get _lockDescription {
    final h = _hours;
    final m = _minutes;
    if (h == 0 && m == 0) return 'Please select a duration';
    if (h == 0) return 'This app will be locked for $m min';
    if (m == 0) return 'This app will be locked for $h hr';
    return 'This app will be locked for $h hr $m min';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 32.w),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceColor,
          borderRadius: BorderRadius.circular(24.w),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24.w,
              offset: Offset(0, 8.w),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 18.w, horizontal: 20.w),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryColor,
                    AppColors.primaryColor.withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24.w),
                  topRight: Radius.circular(24.w),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    color: Colors.white,
                    size: 22.w,
                  ),
                  SizedBox(width: 10.w),
                  Text(
                    'Set Lock Duration',
                    style: AppTextStyles.headline6.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 20.w, 20.w, 20.w),
              child: Column(
                children: [
                  // ── Description chip ──
                  AnimatedContainer(
                    duration: Duration(milliseconds: 200),
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 10.w,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12.w),
                      border: Border.all(
                        color: AppColors.primaryColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16.w,
                          color: AppColors.primaryColor,
                        ),
                        SizedBox(width: 6.w),
                        Flexible(
                          child: Text(
                            _lockDescription,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 20.w),

                  // ── Scroll pickers ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Hours picker
                      _WheelPicker(
                        label: 'Hrs',
                        count: 24,
                        selectedIndex: _hours,
                        controller: _hourController,
                        isEditing: _editingHours,
                        textController: _hourTextCtrl,
                        focusNode: _hourFocus,
                        onScrollChanged: (idx) {
                          setState(() => _hours = idx);
                        },
                        onTapValue: () {
                          setState(() {
                            _editingHours = true;
                            _editingMinutes = false;
                          });
                          _hourTextCtrl.text = _hours.toString().padLeft(
                            2,
                            '0',
                          );
                          _hourTextCtrl.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _hourTextCtrl.text.length,
                          );
                          Future.microtask(() => _hourFocus.requestFocus());
                        },
                        onEditSubmit: _commitHourEdit,
                      ),

                      Padding(
                        padding: EdgeInsets.only(bottom: 20.w),
                        child: Text(
                          ' : ',
                          style: AppTextStyles.headline4.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),

                      // Minutes picker
                      _WheelPicker(
                        label: 'Min',
                        count: 12, // 0,5,10,...55 → 12 items
                        selectedIndex: _minutes ~/ 5,
                        controller: _minuteController,
                        isEditing: _editingMinutes,
                        textController: _minuteTextCtrl,
                        focusNode: _minuteFocus,
                        valueBuilder: (i) => (i * 5).toString().padLeft(2, '0'),
                        onScrollChanged: (idx) {
                          setState(() => _minutes = idx * 5);
                        },
                        onTapValue: () {
                          setState(() {
                            _editingMinutes = true;
                            _editingHours = false;
                          });
                          _minuteTextCtrl.text = _minutes.toString().padLeft(
                            2,
                            '0',
                          );
                          _minuteTextCtrl.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: _minuteTextCtrl.text.length,
                          );
                          Future.microtask(() => _minuteFocus.requestFocus());
                        },
                        onEditSubmit: _commitMinuteEdit,
                      ),
                    ],
                  ),

                  SizedBox(height: 20.w),

                  // ── Lock button ──
                  CommonButton(
                    text: 'Lock App',
                    onPressed: (_hours == 0 && _minutes == 0)
                        ? null
                        : () => Navigator.pop(
                            context,
                            Duration(hours: _hours, minutes: _minutes),
                          ),
                    width: double.infinity,
                    height: 50.w,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A vertical scroll-wheel column with tap-to-edit support.
class _WheelPicker extends StatelessWidget {
  final String label;
  final int count;
  final int selectedIndex;
  final FixedExtentScrollController controller;
  final bool isEditing;
  final TextEditingController textController;
  final FocusNode focusNode;
  final String Function(int)? valueBuilder;
  final ValueChanged<int> onScrollChanged;
  final VoidCallback onTapValue;
  final VoidCallback onEditSubmit;

  const _WheelPicker({
    required this.label,
    required this.count,
    required this.selectedIndex,
    required this.controller,
    required this.isEditing,
    required this.textController,
    required this.focusNode,
    required this.onScrollChanged,
    required this.onTapValue,
    required this.onEditSubmit,
    this.valueBuilder,
  });

  String _itemLabel(int index) {
    if (valueBuilder != null) return valueBuilder!(index);
    return index.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    const itemHeight = 52.0;
    const visibleCount = 3;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyles.overline.copyWith(
            color: AppColors.primaryColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        SizedBox(height: 6.w),
        Container(
          width: 90.w,
          height: itemHeight * visibleCount,
          decoration: BoxDecoration(
            color: AppColors.backgroundColor,
            borderRadius: BorderRadius.circular(16.w),
            border: Border.all(
              color: isEditing ? AppColors.primaryColor : AppColors.borderColor,
              width: isEditing ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15.w),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Highlight band behind center item
                Positioned(
                  top: itemHeight,
                  left: 0.w,
                  right: 0.w,
                  child: Container(
                    height: itemHeight,
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.10),
                      border: Border.symmetric(
                        horizontal: BorderSide(
                          color: AppColors.primaryColor.withValues(alpha: 0.25),
                          width: 1.w,
                        ),
                      ),
                    ),
                  ),
                ),

                // Wheel or inline text field
                if (isEditing)
                  Center(
                    child: SizedBox(
                      width: 60.w,
                      child: TextField(
                        controller: textController,
                        focusNode: focusNode,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        style: AppTextStyles.headline4.copyWith(
                          color: AppColors.primaryColor,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        onSubmitted: (_) => onEditSubmit(),
                      ),
                    ),
                  )
                else
                  ListWheelScrollView.useDelegate(
                    controller: controller,
                    itemExtent: itemHeight,
                    diameterRatio: 1.4,
                    physics: FixedExtentScrollPhysics(),
                    onSelectedItemChanged: onScrollChanged,
                    childDelegate: ListWheelChildBuilderDelegate(
                      builder: (ctx, index) {
                        if (index < 0 || index >= count) return null;
                        final isSelected = index == selectedIndex;
                        return GestureDetector(
                          onTap: isSelected ? onTapValue : null,
                          child: Center(
                            child: Text(
                              _itemLabel(index),
                              style: isSelected
                                  ? AppTextStyles.headline4.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    )
                                  : AppTextStyles.body1.copyWith(
                                      color: AppColors.textHint,
                                      fontWeight: FontWeight.w400,
                                    ),
                            ),
                          ),
                        );
                      },
                      childCount: count,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
