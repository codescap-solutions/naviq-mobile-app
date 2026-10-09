import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'widgets/section_card.dart';
import 'widgets/setting_tile.dart';

class AccountView extends StatelessWidget {
  const AccountView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: figmaAppBar(
        context,
        title: 'Account',
      ),
      body: ListView(
        padding: EdgeInsets.all(AppSizes.paddingL),
        children: [
          Padding(
            padding: EdgeInsets.only(left: 8.w, bottom: 8.w),
            child: Text(
              'PREFERENCES',
              style: TextStyle(
                fontSize: 12.0.sp,
                fontWeight: FontWeight.w700,
                color: Color(0xFF9FA5B4),
                letterSpacing: 1.0,
              ),
            ),
          ),
          SectionCard(
            child: Column(
              children: [
                SettingTile(
                  leading: Icon(
                    Icons.mail_outline_rounded,
                    color: Color(0xFF6B7280),
                  ),
                  title: 'Email',
                  subtitle: 'Not entered',
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 14.w,
                    color: Color(0xFFD1D5DB),
                  ),
                ),
                SizedBox(height: 10.w),
                Divider(height: 1, color: Color(0xFFF3F4F6)),
                SizedBox(height: 10.w),
                SettingTile(
                  leading: Icon(
                    Icons.format_paint_outlined,
                    color: Color(0xFF6B7280),
                  ),
                  title: 'Theme',
                  subtitle: 'System',
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 14.w,
                    color: Color(0xFFD1D5DB),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 32.w),
          Padding(
            padding: EdgeInsets.only(left: 8.w, bottom: 8.w),
            child: Text(
              'DANGER ZONE',
              style: TextStyle(
                fontSize: 12.0.sp,
                fontWeight: FontWeight.w700,
                color: Color(0xFF9FA5B4),
                letterSpacing: 1.0,
              ),
            ),
          ),
          SectionCard(
            child: SettingTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFF6B7280),
              ),
              title: 'Delete Account',
              titleColor: Color(0xFFD33D29), // Dark red like Figma
              onTap: () => _showDeleteAccountDialog(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Delete Account"),
        content: Text(
          "This will permanently delete your account and associated data.\n\n"
          "You will be redirected to a deletion request form.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _openDeleteForm();
            },
            child: Text("Continue", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _openDeleteForm() async {
    final Uri url = Uri.parse(
      "https://docs.google.com/forms/d/e/1FAIpQLSdmxHaRpEqVL1ACZWxk35c9dxvIc6evS-pBfHNc-hHdPJHdfg/viewform",
    );

    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        debugPrint('Could not open delete account form');
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }
}
