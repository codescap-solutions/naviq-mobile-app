import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/widgets/common_button.dart';
import 'widgets/help_support_sheet.dart';

class HelpDetailView extends StatelessWidget {
  final String title;
  const HelpDetailView({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: figmaAppBar(
        context,
        title: 'Help',
      ),
      body: Padding(
        padding: EdgeInsets.all(AppSizes.paddingL),
        child: Container(
          padding: EdgeInsets.all(AppSizes.paddingL),
          decoration: BoxDecoration(
            color: Color(0xFFE6F0FF),
            borderRadius: BorderRadius.circular(AppSizes.radiusL),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.desktop_mac_rounded,
                    color: AppColors.primaryColor,
                  ),
                  SizedBox(width: AppSizes.spacingM),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(_getHelpContent(title)),
                ),
              ),
              SizedBox(height: AppSizes.spacingM),
              CommonButton(
                text: 'Chat With Us',
                onPressed: () => showHelpSupportOptions(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getHelpContent(String title) {
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('geofence')) {
      return 'Open Explore > Geofencing and tap to add a place. Search for the address or drop a pin, choose a radius and give it a name (Home, School...). You will be notified when your child arrives at or leaves the place.\n\nAlerts can be switched on or off per place, and in Settings > Notification Settings.';
    } else if (lowerTitle.contains('notification')) {
      return 'First check Settings > Notification Settings and make sure the alerts you want (arrival, departure, trips) are switched on.\n\nThen allow NaviQ to send notifications in your phone settings, and make sure battery saver is not restricting the app in the background.';
    } else if (lowerTitle.contains('link') && lowerTitle.contains('tracker')) {
      return 'Go to Settings > Devices, tap Link Device and enter the IMEI number printed on your GPS tracker. Once linked, the tracker\'s location, battery and alerts appear on the Home screen next to the phone\'s data.';
    } else if (lowerTitle.contains('delete') &&
        lowerTitle.contains('account')) {
      return 'Go to Settings > Account > Delete Account. You will be taken to a deletion request form. Deleting your account permanently removes your data and cannot be undone.';
    }
    if (lowerTitle.contains('location') ||
        lowerTitle.contains('troubleshoot') ||
        lowerTitle.contains('gps')) {
      return 'If you are experiencing location tracking issues, please ensure that GPS/Location services are enabled on the target device, background app refresh is permitted, and the device has a stable internet connection.\n\nIf the issue persists, try restarting the app or checking the device\'s battery saver settings, which may restrict background tracking.';
    } else if (lowerTitle.contains('cancel') ||
        lowerTitle.contains('subscription') ||
        lowerTitle.contains('billing')) {
      return 'To manage or cancel your subscription, go to Settings > Subscription. From there, you can view your current plan details, update billing information, or cancel your active subscription.\n\nIf you subscribed via Google Play Store or Apple App Store, you must manage it directly through your store account settings.';
    } else if (lowerTitle.contains('add') ||
        lowerTitle.contains('member') ||
        lowerTitle.contains('account') ||
        lowerTitle.contains('start')) {
      return 'You can add a new family member by navigating to the Family section in the main menu, tapping \'Add Member\', and selecting their role. If they are a kid, you can create their profile and share the generated link or pairing code to connect their device.';
    } else if (lowerTitle.contains('privacy') ||
        lowerTitle.contains('security')) {
      return 'Your privacy and security are our top priorities. Location data is securely encrypted and only accessible by authorized family members. You can review and adjust sharing permissions anytime in the privacy settings.';
    } else {
      return 'For support or detailed guidance regarding "$title", please review our online documentation or tap the button below to start a conversation with our support team.';
    }
  }
}
