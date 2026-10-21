import 'package:flutter/material.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/utils/responsive_font.dart';

/// "All Set!" trust page, shared by the child permission flow and the parent
/// sign-up flow. [onGoHome] null disables the button (busy).
class AllSetContent extends StatelessWidget {
  final VoidCallback? onGoHome;

  const AllSetContent({super.key, required this.onGoHome});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Spacer(flex: 3),
                  Text(
                    'All Set!',
                    textAlign: TextAlign.center,
                    style: FigmaText.poppins(
                      32,
                      weight: FontWeight.w700,
                      lineHeight: 40,
                      color: FigmaColors.ink,
                    ),
                  ),
                  SizedBox(height: 12.w),
                  Text(
                    'Your security and privacy\nsettings are now configured.',
                    textAlign: TextAlign.center,
                    style: FigmaText.bodyMedium.copyWith(
                      color: FigmaColors.body,
                    ),
                  ),
                  Spacer(flex: 2),
                  Container(
                    decoration: BoxDecoration(
                      color: Color(0xFFF8F9FB),
                      borderRadius: BorderRadius.circular(20.w),
                      border: Border.all(color: FigmaColors.border),
                    ),
                    child: Column(
                      children: [
                        _row(
                          Icons.lock_outline_rounded,
                          'Security',
                          'Your account is protected',
                        ),
                        Divider(height: 1, color: FigmaColors.border),
                        _row(
                          Icons.visibility_outlined,
                          'Privacy',
                          'Your information is private',
                        ),
                        Divider(height: 1, color: FigmaColors.border),
                        _row(
                          Icons.shield_outlined,
                          'Permissions',
                          'App access is set',
                        ),
                      ],
                    ),
                  ),
                  Spacer(flex: 2),
                  Row(
                    children: [
                      Text('🎉 ', style: FigmaText.bodyMedium),
                      Expanded(
                        child: Text(
                          "You're ready to use the app securely!",
                          style: FigmaText.bodyMedium.copyWith(
                            color: FigmaColors.body,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.w),
                  SizedBox(
                    height: 60.w,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FigmaColors.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.w),
                        ),
                      ),
                      onPressed: onGoHome,
                      icon: Icon(
                        Icons.home_outlined,
                        color: Colors.white,
                        size: 24.w,
                      ),
                      label: Text(
                        'Go Home',
                        style: FigmaText.bodyLarge.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.w),
                  SizedBox(
                    height: 60.w,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Color(0xFFC4C8D0), width: 2.w),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.w),
                        ),
                      ),
                      onPressed: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Tutorial coming soon!'),
                              duration: Duration(seconds: 2),
                            ),
                          ),
                      icon: Icon(
                        Icons.play_arrow_outlined,
                        color: FigmaColors.ink,
                        size: 24.w,
                      ),
                      label: Text(
                        'Watch Tutorial',
                        style: FigmaText.bodyLarge.copyWith(
                          color: FigmaColors.ink,
                        ),
                      ),
                    ),
                  ),
                  Spacer(flex: 1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String title, String subtitle) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.w),
      child: Row(
        children: [
          Container(
            width: 44.w,
            height: 44.w,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: FigmaColors.ink, size: 22.w),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: FigmaText.bodyMedium.copyWith(color: FigmaColors.ink),
                ),
                Text(
                  subtitle,
                  style: FigmaText.bodySmall.copyWith(color: FigmaColors.body),
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF10B981),
            size: 24.w,
          ),
        ],
      ),
    );
  }
}
