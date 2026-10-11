import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/navigation/route_names.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/core/services/firebase_notification_service.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:child_track/core/services/csv_file_logger.dart';
import 'account_view.dart';
import 'devices_view.dart';
import 'notification_settings_view.dart';
import '../../subscription/view/subscription_multi_plan_view.dart';
import '../../subscription/models/subscription_plan.dart' show SubscriptionTier;
import '../../subscription/widgets/upgrade_restriction_dialog.dart';
import 'package:child_track/core/services/subscription_feature_gate.dart';
import 'family_management_view.dart';
import 'help_view.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:child_track/core/widgets/figma_toggle.dart';

class SettingsView extends StatefulWidget {
  /// Settings is a root tab, so its back button has nothing to pop — when
  /// hosted in the Home tab bar this returns to the Home tab (same as Explore).
  final VoidCallback? onNavigateToHome;

  const SettingsView({super.key, this.onNavigateToHome});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _sharedPrefsService = SharedPrefsService();

  String? _currentChildId;
  bool _restrictDeletion = false;
  bool _block18Plus = false;

  bool _isPrimaryParent = true;

  @override
  void initState() {
    super.initState();
    _loadChildData();
  }

  void _loadChildData() {
    _isPrimaryParent = _sharedPrefsService.isPrimaryParent;
    _currentChildId = _sharedPrefsService.getString('child_id');
    _restrictDeletion = _sharedPrefsService.getBool('restrict_deletion');
    _block18Plus = _sharedPrefsService.getBool('block_18plus');
    setState(() {});
    _fetchServerSettings();
  }

  Future<void> _fetchServerSettings() async {
    if (_currentChildId != null) {
      final response = await injector<HomeRepository>().getWebFilterStatus(
        childId: _currentChildId!,
      );
      if (response.isSuccess && response.data != null) {
        setState(() => _block18Plus = response.data!);
        await _sharedPrefsService.setBool('block_18plus', response.data!);
      }

      final restrictRes = await injector<HomeRepository>()
          .getDeletionRestrictionStatus(childId: _currentChildId!);
      if (restrictRes.isSuccess && restrictRes.data != null) {
        setState(() => _restrictDeletion = restrictRes.data!);
        await _sharedPrefsService.setBool(
          'restrict_deletion',
          restrictRes.data!,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF7F8FA),
      appBar: figmaAppBar(
        context,
        title: 'Settings',
        onBack: widget.onNavigateToHome,
        trailing: FigmaCircleButton(
          child: SvgPicture.asset(
            'assets/help/help_search.svg',
            width: 24.w,
            height: 24.w,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(vertical: 13.0.w),
          child: Column(
            children: [
              // 1. Premium Protection Banner
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                child: _buildPremiumBanner(),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Column(
                  children: [
                    // 2. PRIVACY & SECURITY
                    _buildSectionHeader("PRIVACY & SECURITY"),
                    _buildSectionCard(
                      children: [
                        _buildSettingsTile(
                          leading: Image.asset(
                            'assets/icons/Image (Restrict from Deleting).png',
                            width: 26.w,
                            height: 26.w,
                          ),
                          title: 'Restrict from Deleting',
                          trailing: FigmaToggle(
                            value: _restrictDeletion,
                            onChanged: (value) async {
                              if (!_isPrimaryParent) {
                                AppSnackbar.showError(
                                  context,
                                  'Guardians have view-only access. Only primary parents can change this setting.',
                                );
                                return;
                              }
                              // Turning it ON is a Smart / Premium feature; switching an
                              // already-on setting OFF is never blocked.
                              if (value &&
                                  !SubscriptionFeatureGate.canRestrictDeletion()) {
                                UpgradeRestrictionDialog.show(
                                  context,
                                  title: 'Restrict from Deleting',
                                  message:
                                      'Stopping the app from being deleted is available on Smart and Premium plans.',
                                  suggestedTier: SubscriptionTier.smart,
                                );
                                return;
                              }
                              if (_currentChildId != null) {
                                final response =
                                    await injector<HomeRepository>()
                                        .updateDeletionRestriction(
                                          childId: _currentChildId!,
                                          enabled: value,
                                        );
                                if (!response.isSuccess) {
                                  AppSnackbar.showError(
                                    context,
                                    'Failed to update restriction: ${response.message}',
                                  );
                                  return;
                                }
                              }
                              await _sharedPrefsService.setBool(
                                'restrict_deletion',
                                value,
                              );
                              setState(() => _restrictDeletion = value);
                            },
                          ),
                        ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0xFFEEF0F4),
                        ),
                        _buildSettingsTile(
                          leading: Image.asset(
                            'assets/icons/Image (Block 18+ Websites).png',
                            width: 26.w,
                            height: 26.w,
                          ),
                          title: 'Block 18+ Websites',
                          trailing: FigmaToggle(
                            value: _block18Plus,
                            onChanged: (value) async {
                              if (!_isPrimaryParent) {
                                AppSnackbar.showError(
                                  context,
                                  'Guardians have view-only access. Only primary parents can change this setting.',
                                );
                                return;
                              }
                              if (value &&
                                  !SubscriptionFeatureGate.canBlockAdultWebsites()) {
                                UpgradeRestrictionDialog.show(
                                  context,
                                  title: 'Block 18+ Websites',
                                  message:
                                      'Blocking 18+ websites is available on the Premium plan.',
                                  suggestedTier: SubscriptionTier.premium,
                                );
                                return;
                              }
                              if (_currentChildId != null) {
                                final response =
                                    await injector<HomeRepository>()
                                        .updateWebFilter(
                                          childId: _currentChildId!,
                                          enabled: value,
                                        );
                                if (!response.isSuccess) {
                                  AppSnackbar.showError(
                                    context,
                                    'Failed to update filter: ${response.message}',
                                  );
                                  return;
                                }
                              }
                              await _sharedPrefsService.setBool(
                                'block_18plus',
                                value,
                              );
                              setState(() => _block18Plus = value);
                            },
                          ),
                        ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0xFFEEF0F4),
                        ),
                        _buildSettingsTile(
                          leading: Image.asset(
                            'assets/icons/Image (Family Management).png',
                            width: 26.w,
                            height: 26.w,
                          ),
                          title: 'Family Management',
                          trailing: SvgPicture.asset(
                            'assets/icons/settings_chevron.svg',
                            width: 18.w,
                            height: 18.w,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FamilyManagementView(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    // 3. ACCOUNT & NOTIFICATIONS
                    _buildSectionHeader("ACCOUNT & NOTIFICATIONS"),
                    _buildSectionCard(
                      children: [
                        _buildSettingsTile(
                          leading: Image.asset(
                            'assets/icons/Image (Notification Settings).png',
                            width: 26.w,
                            height: 26.w,
                          ),
                          title: 'Notification Settings',
                          trailing: SvgPicture.asset(
                            'assets/icons/settings_chevron.svg',
                            width: 18.w,
                            height: 18.w,
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => NotificationSettingsView(),
                            ),
                          ),
                        ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0xFFEEF0F4),
                        ),
                        _buildSettingsTile(
                          leading: Image.asset(
                            'assets/icons/Image (Login & Security).png',
                            width: 26.w,
                            height: 26.w,
                          ),
                          title: 'Login & Security',
                          trailing: SvgPicture.asset(
                            'assets/icons/settings_chevron.svg',
                            width: 18.w,
                            height: 18.w,
                          ),
                          onTap: () => _showLoginSecurityOptions(context),
                        ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0xFFEEF0F4),
                        ),
                        _buildSettingsTile(
                          leading: Image.asset(
                            'assets/icons/Image (Account).png',
                            width: 26.w,
                            height: 26.w,
                          ),
                          title: 'Account',
                          trailing: SvgPicture.asset(
                            'assets/icons/settings_chevron.svg',
                            width: 18.w,
                            height: 18.w,
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => AccountView()),
                          ),
                        ),
                      ],
                    ),

                    // 4. MORE
                    _buildSectionHeader("MORE"),
                    _buildSectionCard(
                      children: [
                        _buildSettingsTile(
                          leading: Image.asset(
                            'assets/icons/Image (Devices).png',
                            width: 26.w,
                            height: 26.w,
                          ),
                          title: 'Devices',
                          trailing: SvgPicture.asset(
                            'assets/icons/settings_chevron.svg',
                            width: 18.w,
                            height: 18.w,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => DevicesView()),
                            );
                          },
                        ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0xFFEEF0F4),
                        ),
                        _buildSettingsTile(
                          leading: Image.asset(
                            'assets/icons/Image (Help).png',
                            width: 26.w,
                            height: 26.w,
                          ),
                          title: 'Help',
                          trailing: SvgPicture.asset(
                            'assets/icons/settings_chevron.svg',
                            width: 18.w,
                            height: 18.w,
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => HelpView()),
                          ),
                        ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Color(0xFFEEF0F4),
                        ),
                        _buildSettingsTile(
                          leading: Image.asset(
                            'assets/icons/Image (About App).png',
                            width: 26.w,
                            height: 26.w,
                          ),
                          title: 'About App',
                          trailing: SvgPicture.asset(
                            'assets/icons/settings_chevron.svg',
                            width: 18.w,
                            height: 18.w,
                          ),
                          onTap: () => _showAboutAppDialog(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumBanner() {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 5.w),
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFE8D6), Color(0xFFFFECD6)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14.w),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/icons/Image (Shield)Big.png',
            width: 80.w,
            height: 80.w,
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Ensure Better Protection",
                  style: GoogleFonts.poppins(
                    fontSize: 16.0.sp,
                    fontWeight: FontWeight.w700,
                    height: 22 / 16,
                    color: Color(0xFF0F1320),
                  ),
                ),
                SizedBox(height: 4.w),
                Text(
                  "at half price of a family meal",
                  style: GoogleFonts.poppins(
                    fontSize: 12.0.sp,
                    fontWeight: FontWeight.w400,
                    height: 16.5 / 12,
                    color: Color(0xFF4A5267),
                  ),
                ),
                SizedBox(height: 4.w),
                Text(
                  "60% of users prefer Premium",
                  style: GoogleFonts.poppins(
                    fontSize: 11.0.sp,
                    fontWeight: FontWeight.w400,
                    height: 16.5 / 11,
                    color: Color(0xFF4A5267),
                  ),
                ),
                SizedBox(height: 9.w),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SubscriptionMultiPlanView(),
                      ),
                    );
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 5.w,
                    ),
                    decoration: BoxDecoration(
                      color: Color(0xFF0069F9),
                      borderRadius: BorderRadius.circular(8.w),
                    ),
                    child: Text(
                      "Know More",
                      style: GoogleFonts.poppins(
                        fontSize: 11.0.sp,
                        fontWeight: FontWeight.w600,
                        height: 16.5 / 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: 4.w, bottom: 8.6.w, top: 20.6.w),
        child: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 11.0.sp,
            fontWeight: FontWeight.w400,
            height: 16.5 / 11,
            color: Color(0xFF9BA4B5),
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.w),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 4.w,
            offset: Offset(0.w, 1.w),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingsTile({
    required Widget leading,
    required String title,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 15.w),
        child: Row(
          children: [
            leading,
            SizedBox(width: 16.w),
            Expanded(
              child: Text(
                title,
                // Same as the Explore row titles: Regular 16 / 24, 0.2px.
                style: GoogleFonts.poppins(
                  fontSize: 16.0.sp,
                  fontWeight: FontWeight.w400,
                  height: 24 / 16,
                  color: Color(0xFF0F1320),
                  letterSpacing: 0.2,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  Future<void> _shareLogs(BuildContext context) async {
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Preparing logs…')));

      final paths = await CsvFileLogger.instance.getAllLogPaths();
      if (paths.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          AppSnackbar.showError(context, 'No log files found yet');
        }
        return;
      }

      final xFiles = paths.map((p) => XFile(p)).toList();
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
      await SharePlus.instance.share(
        ShareParams(files: xFiles, subject: 'NaviQ Background Logs'),
      );
    } catch (e) {
      AppLogger.error('Share logs error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        AppSnackbar.showError(context, 'Failed to share logs: $e');
      }
    }
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

  void _showLoginSecurityOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.w)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 10.w),
              Container(
                width: 40.w,
                height: 4.w,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2.w),
                ),
              ),
              SizedBox(height: 20.w),
              ListTile(
                leading: Icon(Icons.share, color: AppColors.primaryColor),
                title: Text('Share Background Logs'),
                subtitle: Text('Export CSV logs for debugging'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _shareLogs(context);
                },
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text('Delete Account'),
                subtitle: Text('Permanently delete your account'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDeleteAccountDialog(context);
                },
              ),
              Divider(),
              ListTile(
                leading: Icon(Icons.logout, color: Colors.red),
                title: Text('Logout'),
                subtitle: Text('Logout from the app'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showPremiumLogoutDialog(context);
                },
              ),
              SizedBox(height: 20.w),
            ],
          ),
        );
      },
    );
  }

  void _showPremiumLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24.w),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24.w),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20.w,
                  offset: Offset(0.w, 8.w),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Premium Badge Icon with Gradient
                Container(
                  width: 64.w,
                  height: 64.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF0066FF), Color(0xFF6F9EFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 32.w,
                  ),
                ),
                SizedBox(height: 18.w),
                Text(
                  'Unlock Premium Protection',
                  style: GoogleFonts.poppins(
                    fontSize: 20.0.sp,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0C1D37),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8.w),
                Text(
                  'Logging out will disable real-time alerts and location updates. Upgrade to Premium to keep your child fully protected.',
                  style: GoogleFonts.poppins(
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20.w),

                // Bullet points of premium features
                Column(
                  children: [
                    _buildDialogFeatureRow('Real-time location & geofencing'),
                    SizedBox(height: 10.w),
                    _buildDialogFeatureRow('SOS emergency notification alerts'),
                    SizedBox(height: 10.w),
                    _buildDialogFeatureRow(
                      'Advanced web filtering (Block 18+)',
                    ),
                  ],
                ),
                SizedBox(height: 24.w),

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  height: 48.w,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF0066FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.w),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.pop(dialogContext); // Close modal
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SubscriptionMultiPlanView(),
                        ),
                      );
                    },
                    child: Text(
                      'Upgrade to Premium',
                      style: GoogleFonts.poppins(
                        fontSize: 14.5.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12.w),
                SizedBox(
                  width: double.infinity,
                  height: 48.w,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.w),
                      ),
                    ),
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      Navigator.pop(dialogContext); // Close modal

                      // Perform logout
                      AppSnackbar.showLoading(context, 'Logging out...');

                      try {
                        await FirebaseNotificationService()
                            .removeTokenFromServer()
                            .timeout(
                              Duration(seconds: 4),
                              onTimeout: () {
                                AppLogger.warning(
                                  'removeTokenFromServer timed out',
                                );
                              },
                            );
                      } catch (e) {
                        AppLogger.error('Failed to remove token: $e');
                      }

                      await injector<SharedPrefsService>().logout();

                      AppSnackbar.hideLoading(context);

                      navigator.pushNamedAndRemoveUntil(
                        RouteNames.onBoarding,
                        (route) => false,
                      );
                    },
                    child: Text(
                      'Logout Anyway',
                      style: GoogleFonts.poppins(
                        fontSize: 14.0.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDialogFeatureRow(String text) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(4.w),
          decoration: BoxDecoration(
            color: Color(0xFFE0EDFF),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check, color: Color(0xFF0066FF), size: 12.w),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 13.0.sp,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0C1D37),
            ),
          ),
        ),
      ],
    );
  }

  void _showAboutAppDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'NaviQ',
      applicationVersion: 'Naviq Dev 1.0.4(Oct 9)',
      applicationIcon: Container(
        padding: EdgeInsets.all(8.w),
        decoration: BoxDecoration(
          color: AppColors.primaryColor,
          borderRadius: BorderRadius.circular(12.w),
        ),
        child: Icon(Icons.child_care, color: Colors.white, size: 32.w),
      ),
      children: [
        SizedBox(height: 16.w),
        Text(
          'Keeping children safe and parents connected.',
          style: TextStyle(fontSize: 14.0.sp, color: Colors.grey),
        ),
        SizedBox(height: 8.w),
        Text(
          '© 2026 CodeScap Solutions',
          style: TextStyle(fontSize: 12.0.sp, color: Colors.grey),
        ),
      ],
    );
  }
}
