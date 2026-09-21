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
      appBar: AppBar(
        leading: Container(
          margin: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new,
              size: 18,
              color: Colors.black,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(
          'Account',
          style: TextStyle(
            fontSize: 24.0.sp,
            fontWeight: FontWeight.w800,
            color: Colors.black,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,

        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSizes.paddingL),
        children: [
          Padding(
            padding: EdgeInsets.only(left: 8, bottom: 8),
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
              children: const [
                SettingTile(
                  leading: Icon(
                    Icons.mail_outline_rounded,
                    color: Color(0xFF6B7280),
                  ),
                  title: 'Email',
                  subtitle: 'Not entered',
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Color(0xFFD1D5DB),
                  ),
                ),
                SizedBox(height: 10),
                Divider(height: 1, color: Color(0xFFF3F4F6)),
                SizedBox(height: 10),
                SettingTile(
                  leading: Icon(
                    Icons.format_paint_outlined,
                    color: Color(0xFF6B7280),
                  ),
                  title: 'Theme',
                  subtitle: 'System',
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Color(0xFFD1D5DB),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: EdgeInsets.only(left: 8, bottom: 8),
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
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFF6B7280),
              ),
              title: 'Delete Account',
              titleColor: const Color(0xFFD33D29), // Dark red like Figma
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
        title: const Text("Delete Account"),
        content: const Text(
          "This will permanently delete your account and associated data.\n\n"
          "You will be redirected to a deletion request form.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _openDeleteForm();
            },
            child: const Text(
              "Continue",
              style: TextStyle(color: Colors.white),
            ),
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
