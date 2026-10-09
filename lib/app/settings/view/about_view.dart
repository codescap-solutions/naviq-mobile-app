import 'package:child_track/core/utils/responsive_font.dart';
import 'package:flutter/material.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'widgets/section_card.dart';
import 'widgets/setting_tile.dart';

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 18.w),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('About'),
        backgroundColor: AppColors.surfaceColor,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListView(
        padding: EdgeInsets.all(AppSizes.paddingL),
        children: [
          SectionCard(
            child: Column(
              children: [
                SettingTile(
                  leading: Icon(Icons.card_membership_outlined),
                  title: 'Subscription',
                  subtitle: 'Active until June 08 2025',
                ),
                Divider(height: 1),
                SettingTile(
                  leading: Icon(Icons.numbers),
                  title: 'Version',
                  subtitle: '656545313265',
                ),
                Divider(height: 1),
                SettingTile(
                  leading: Icon(Icons.badge_outlined),
                  title: 'Your ID',
                  subtitle: '122122',
                ),
                Divider(height: 1),
                SettingTile(
                  leading: Icon(Icons.article_outlined),
                  title: 'Terms of use',
                ),
                Divider(height: 1),
                SettingTile(
                  leading: Icon(Icons.privacy_tip_outlined),
                  title: 'Privacy Policy',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
