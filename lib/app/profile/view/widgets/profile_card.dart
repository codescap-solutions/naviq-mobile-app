import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

enum ProfileCardAction { edit, remove }

/// Child profile card from the Figma "Profile" frame (400 wide): blue header
/// with the "active" badge, avatar and "⋯" menu, then name / status, the child
/// code with a copy button, and the three daily stats.
class ProfileCard extends StatelessWidget {
  final String name;
  final String childCode;
  final String? avatar;
  final String status;
  final String screenTime;
  final String maxSpeed;
  final String entireRoute;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<ProfileCardAction> onAction;

  const ProfileCard({
    super.key,
    required this.name,
    required this.childCode,
    required this.avatar,
    required this.status,
    required this.screenTime,
    required this.maxSpeed,
    required this.entireRoute,
    required this.isSelected,
    required this.onTap,
    required this.onAction,
  });

  static const _blue = Color(0xFF2C67F0);
  static const _idleHeader = Color(0xFFBCBEC3); // non-selected child
  static const _divider = Color(0xFFEEF0F4);
  static const _mutedText = Color(0xFF9BA4B5);
  static const _danger = Color(0xFFDD4E47);
  static const _success = Color(0xFF57BC7B);

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16.w);
    // The whole card selects the child; the code chip and the menu button
    // handle their own taps.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 15.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: Border.all(color: _divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12.w,
              offset: Offset(0, 4.w),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Column(
            children: [
              _buildHeader(),
              SizedBox(height: 16.w),
              _centered(
                name,
                FigmaText.poppins(24, weight: FontWeight.w700, lineHeight: 28),
              ),
              SizedBox(height: 2.w),
              _centered(
                status,
                FigmaText.poppins(12, color: Color(0xFF2E3035), lineHeight: 20),
              ),
              SizedBox(height: 10.w),
              _buildCodeChip(context),
              _buildStats(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _centered(String text, TextStyle style) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 16.w),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: style,
    ),
  );

  /// 156px band (blue for the selected child, grey otherwise): badge (16,16),
  /// avatar 100 centred at y29, 36px menu button (right 16, top 16).
  Widget _buildHeader() {
    return Container(
      height: 156.w,
      width: double.infinity,
      color: isSelected ? _blue : _idleHeader,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(top: 29.w, child: _buildAvatar(100.w)),
          if (isSelected)
            Positioned(
              top: 16.w,
              left: 16.w,
              child: Container(
                height: 30.w,
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _divider,
                  borderRadius: BorderRadius.circular(10.w),
                ),
                child: Text(
                  'active',
                  style: FigmaText.poppins(
                    16,
                    weight: FontWeight.w600,
                    color: _success,
                    lineHeight: 24,
                  ),
                ),
              ),
            ),
          Positioned(top: 16.w, right: 16.w, child: _buildMenu()),
        ],
      ),
    );
  }

  Widget _buildMenu() {
    TextStyle item(Color color) => FigmaText.poppins(
      14,
      weight: FontWeight.w600,
      color: color,
      lineHeight: 20,
    );
    return PopupMenuButton<ProfileCardAction>(
      tooltip: 'Profile options',
      padding: EdgeInsets.zero,
      // Menu overlays the button, right edges ~18px apart (Material rounds the width to 112).
      offset: Offset(-18.w, 0),
      constraints: BoxConstraints(minWidth: 86.w),
      color: Color(0xFFF7F8FA),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.w)),
      onSelected: onAction,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: ProfileCardAction.edit,
          height: 38.w,
          padding: EdgeInsets.symmetric(horizontal: 14.w),
          child: Text('Edit Profile', style: item(_mutedText)),
        ),
        PopupMenuDivider(height: 1.w, color: _divider),
        PopupMenuItem(
          value: ProfileCardAction.remove,
          height: 38.w,
          padding: EdgeInsets.symmetric(horizontal: 14.w),
          child: Text('Remove', style: item(_danger)),
        ),
      ],
      child: Container(
        width: 36.w,
        height: 36.w,
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.more_horiz_rounded, color: Colors.white, size: 18.w),
      ),
    );
  }

  /// Child code + copy, so a guardian / second device can be paired without
  /// retyping it.
  Widget _buildCodeChip(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Copy child code $childCode',
      child: GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: childCode));
          AppSnackbar.showSuccess(context, 'Child code copied: $childCode');
        },
        child: Container(
          height: 32.w,
          padding: EdgeInsets.only(left: 14.w, right: 6.w),
          decoration: BoxDecoration(
            color: Color(0xFFEFF4FE),
            borderRadius: BorderRadius.circular(16.w),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Code',
                style: FigmaText.poppins(
                  12,
                  color: FigmaColors.body,
                  lineHeight: 18,
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                childCode,
                style: FigmaText.poppins(
                  14,
                  weight: FontWeight.w700,
                  lineHeight: 20,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(width: 8.w),
              Container(
                width: 24.w,
                height: 24.w,
                decoration: BoxDecoration(
                  color: FigmaColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.copy_rounded,
                  color: Colors.white,
                  size: 13.w,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Figma stats row: 73px high, three equal columns split by 1x40 dividers.
  Widget _buildStats() {
    return SizedBox(
      height: 73.w,
      child: Row(
        children: [
          Expanded(
            child: _stat(Icons.access_time_outlined, screenTime, 'screen time'),
          ),
          _statDivider(),
          Expanded(child: _stat(Icons.bolt_rounded, maxSpeed, 'max speed')),
          _statDivider(),
          Expanded(
            child: _stat(
              Icons.location_on_outlined,
              entireRoute,
              'entire route',
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(width: 1.w, height: 40.w, color: _divider);

  Widget _stat(IconData icon, String value, String label) {
    return Padding(
      padding: EdgeInsets.only(top: 16.w, bottom: 18.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Color(0xFF0F1320), size: 14.w),
              SizedBox(width: 4.w),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FigmaText.poppins(
                    14,
                    color: Color(0xFF0F1320),
                    lineHeight: 22.5,
                  ),
                ),
              ),
            ],
          ),
          Text(
            label,
            style: FigmaText.poppins(
              13,
              color: FigmaColors.body,
              lineHeight: 16.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(double size) {
    final fallback = Icon(
      Icons.person_rounded,
      color: Colors.blue.shade300,
      size: size * 0.45,
    );
    final Widget image;
    if (avatar == null || avatar!.isEmpty) {
      image = fallback;
    } else if (avatar!.startsWith('http')) {
      image = Image.network(
        avatar!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    } else {
      final isPng =
          avatar!.endsWith('.png') ||
          avatar!.contains('Boy') ||
          avatar!.contains('Girl');
      final path = isPng
          ? 'assets/images/childavatar/${avatar!.replaceAll('.svg', '.png')}'
          : 'assets/images/childavatar/$avatar';
      image = Image.asset(
        path,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color(0xFFF3F4F6),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}
