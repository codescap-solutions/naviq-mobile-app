import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:flutter/material.dart';

/// Figma "add kid popup": bottom sheet that explains the two ways to add a
/// child (install the app / buy a tracker) and offers both actions.
/// Both callbacks run after the sheet has closed.
Future<void> showAddKidSheet(
  BuildContext context, {
  required VoidCallback onAddKid,
  required VoidCallback onPurchaseDevice,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _AddKidSheet(
      onAddKid: () {
        Navigator.pop(sheetContext);
        onAddKid();
      },
      onPurchaseDevice: () {
        Navigator.pop(sheetContext);
        onPurchaseDevice();
      },
    ),
  );
}

class _AddKidSheet extends StatelessWidget {
  final VoidCallback onAddKid;
  final VoidCallback onPurchaseDevice;

  const _AddKidSheet({required this.onAddKid, required this.onPurchaseDevice});

  static const _tint = Color(0xFFF2F7FF);
  static const _tintBorder = Color(0xFFD6E6FD);
  static const _iconBg = Color(0xFFE3EDFC);

  @override
  Widget build(BuildContext context) {
    // Figma: 32px side padding inside the 428 frame, 16px above the handle.
    return Container(
      padding: EdgeInsets.fromLTRB(
        32.w,
        16.w,
        32.w,
        16.w + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.w)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 59.w,
            height: 6.w,
            decoration: BoxDecoration(
              color: Color(0xFFDDE1EA),
              borderRadius: BorderRadius.circular(3.w),
            ),
          ),
          SizedBox(height: 16.w),
          Text(
            'Add your kid in easy steps\nto access this feature',
            textAlign: TextAlign.center,
            style: FigmaText.poppins(
              24,
              weight: FontWeight.w700,
              lineHeight: 33,
            ),
          ),
          SizedBox(height: 24.w),
          _buildSteps(),
          SizedBox(height: 24.w),
          _FilledButton(
            icon: Icons.add_rounded,
            label: 'Add Kid',
            onTap: onAddKid,
          ),
          SizedBox(height: 12.w),
          _FilledButton(
            icon: Icons.shopping_bag_outlined,
            label: 'Purchase Device',
            outlined: true,
            onTap: onPurchaseDevice,
          ),
          SizedBox(height: 12.w),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildSteps() {
    return Container(
      padding: EdgeInsets.all(19.w),
      decoration: BoxDecoration(
        color: _tint,
        borderRadius: BorderRadius.circular(16.w),
        border: Border.all(color: _tintBorder),
      ),
      child: Column(
        children: [
          _step(
            Icons.smartphone_outlined,
            "Install on kid's device",
            "Download our app on your child's phone or tablet to start "
                'tracking their location and activity in real-time.',
          ),
          Container(
            height: 1.w,
            margin: EdgeInsets.symmetric(vertical: 12.w),
            color: _tintBorder,
          ),
          _step(
            Icons.shopping_bag_outlined,
            'Get a tracking device',
            'No smartphone needed. Purchase a dedicated GPS tracker and '
                "attach it to your kid's bag or clothing.",
          ),
        ],
      ),
    );
  }

  Widget _step(IconData icon, String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36.w,
          height: 36.w,
          decoration: BoxDecoration(color: _iconBg, shape: BoxShape.circle),
          child: Icon(icon, size: 18.w, color: FigmaColors.primary),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: FigmaText.poppins(
                  16,
                  weight: FontWeight.w600,
                  lineHeight: 20,
                ),
              ),
              SizedBox(height: 4.w),
              Text(
                body,
                style: FigmaText.poppins(
                  14,
                  color: FigmaColors.body,
                  lineHeight: 20,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Terms / Privacy are styled as links only — the app has no URLs for them
  /// yet (the login screen's links are no-ops too).
  Widget _buildFooter() {
    final base = FigmaText.poppins(
      11,
      color: Color(0xFF9BA4B5),
      lineHeight: 12,
    );
    final link = base.copyWith(color: FigmaColors.primary);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(
            text:
                'Both methods keep your child safe. The app requires a '
                'compatible device. ',
          ),
          TextSpan(text: 'Terms & Conditions', style: link),
          TextSpan(text: ' & '),
          TextSpan(text: 'Privacy Policy', style: link),
          TextSpan(text: ' apply.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// 60px pill button: solid blue, or white with a blue outline.
class _FilledButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool outlined;
  final VoidCallback onTap;

  const _FilledButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = outlined ? FigmaColors.primary : Colors.white;
    final radius = BorderRadius.circular(16.w);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          height: 60.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: outlined ? Colors.white : FigmaColors.primary,
            borderRadius: radius,
            border: outlined
                ? Border.all(color: FigmaColors.primary, width: 1.5)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20.w, color: fg),
              SizedBox(width: 8.w),
              Text(
                label,
                style: FigmaText.poppins(
                  20,
                  weight: FontWeight.w500,
                  color: fg,
                  lineHeight: 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
