import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/navigation/route_names.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/core/services/firebase_notification_service.dart';
import 'package:child_track/core/models/child_profile.dart';
import 'package:child_track/core/services/background_location_service.dart';
import 'package:child_track/core/utils/app_logger.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:flutter/cupertino.dart' show CupertinoSwitch, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:child_track/core/services/csv_file_logger.dart';
import 'package:child_track/core/services/subscription_feature_gate.dart';
import 'package:child_track/app/subscription/widgets/upgrade_restriction_dialog.dart';
import 'account_view.dart';
import 'devices_view.dart';
import 'notification_settings_view.dart';
import '../../subscription/view/subscription_multi_plan_view.dart';
import '../../subscription/view/current_plan_view.dart';
import 'family_management_view.dart';
import '../../chat/view/chat_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../chat/view_model/bloc/chat_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _sharedPrefsService = SharedPrefsService();

  String? _currentChildId;
  String? _childName;
  bool _restrictDeletion = false;
  bool _block18Plus = false;

  bool _isExpanded = false;
  bool _isPrimaryParent = true;
  List<ChildProfile> _children = [];

  @override
  void initState() {
    super.initState();
    _loadChildData();
  }

  void _loadChildData() {
    _isPrimaryParent = _sharedPrefsService.isPrimaryParent;
    _currentChildId = _sharedPrefsService.getString('child_id');
    _childName = _sharedPrefsService.getString('child_name');
    _restrictDeletion = _sharedPrefsService.getBool('restrict_deletion');
    _block18Plus = _sharedPrefsService.getBool('block_18plus');
    _children = _sharedPrefsService.getChildren();
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
      backgroundColor: const Color(
        0xFFF8FAFC,
      ), // Matching screenshot off-white bg
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leadingWidth: 68,
        leading: Center(
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.chevron_left,
                  color: Colors.black,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        title: Text(
          'Settings',
          style: GoogleFonts.poppins(
            fontSize: 32.0.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0C1D37),
          ),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  CupertinoIcons.search,
                  color: Colors.black,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            children: [
              // 1. Premium Protection Banner
              _buildPremiumBanner(),

              // 2. PRIVACY & SECURITY
              _buildSectionHeader("PRIVACY & SECURITY"),
              _buildSectionCard(
                children: [
                  _buildSettingsTile(
                    leading: Image.asset(
                      'assets/icons/Image (Restrict from Deleting).png',
                      width: 24,
                      height: 24,
                    ),
                    title: 'Restrict from Deleting',
                    trailing: Transform.scale(
                      alignment: Alignment.centerRight,
                      scale: 0.8,
                      child: CupertinoSwitch(
                        activeTrackColor: const Color(0xFF22C55E),
                        value: _restrictDeletion,
                        onChanged: (value) async {
                          if (!_isPrimaryParent) {
                            AppSnackbar.showError(
                              context,
                              'Guardians have view-only access. Only primary parents can change this setting.',
                            );
                            return;
                          }
                          if (_currentChildId != null) {
                            final response = await injector<HomeRepository>()
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
                  ),
                  const Divider(
                    height: 1,
                    color: Color(0xFFF1F5F9),
                    indent: 56,
                    endIndent: 16,
                  ),
                  _buildSettingsTile(
                    leading: Image.asset(
                      'assets/icons/Image (Block 18+ Websites).png',
                      width: 24,
                      height: 24,
                    ),
                    title: 'Block 18+ Websites',
                    trailing: Transform.scale(
                      alignment: Alignment.centerRight,
                      scale: 0.8,
                      child: CupertinoSwitch(
                        activeTrackColor: const Color(0xFF22C55E),
                        value: _block18Plus,
                        onChanged: (value) async {
                          if (!_isPrimaryParent) {
                            AppSnackbar.showError(
                              context,
                              'Guardians have view-only access. Only primary parents can change this setting.',
                            );
                            return;
                          }
                          if (_currentChildId != null) {
                            final response = await injector<HomeRepository>()
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
                  ),
                  const Divider(
                    height: 1,
                    color: Color(0xFFF1F5F9),
                    indent: 56,
                    endIndent: 16,
                  ),
                  _buildSettingsTile(
                    leading: Image.asset(
                      'assets/icons/Image (Family Management).png',
                      width: 24,
                      height: 24,
                    ),
                    title: 'Family Management',
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      color: Color(0xFF94A3B8),
                      size: 16,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FamilyManagementView(),
                        ),
                      );
                    },
                  ),
                  const Divider(
                    height: 1,
                    color: Color(0xFFF1F5F9),
                    indent: 56,
                    endIndent: 16,
                  ),
                  _buildSettingsTile(
                    leading: const Icon(
                      CupertinoIcons.person_crop_circle_fill_badge_plus,
                      color: Color(0xFF0066FF),
                      size: 24,
                    ),
                    title: 'Switch / Add Child',
                    trailing: Icon(
                      _isExpanded
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_right,
                      color: const Color(0xFF94A3B8),
                      size: 16,
                    ),
                    onTap: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                  ),
                  if (_isExpanded) ...[
                    const Divider(
                      height: 1,
                      color: Color(0xFFF1F5F9),
                      indent: 56,
                      endIndent: 16,
                    ),
                    Container(
                      color: const Color(0xFFF8FAFC),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        children: [
                          ..._buildInactiveChildTiles(),
                          const SizedBox(height: 8),
                          _buildAddChildTile(),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

              // 3. ACCOUNT & NOTIFICATIONS
              _buildSectionHeader("ACCOUNT & NOTIFICATIONS"),
              _buildSectionCard(
                children: [
                  _buildSettingsTile(
                    leading: Image.asset(
                      'assets/icons/Image (Notification Settings).png',
                      width: 24,
                      height: 24,
                    ),
                    title: 'Notification Settings',
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      color: Color(0xFF94A3B8),
                      size: 16,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationSettingsView(),
                      ),
                    ),
                  ),
                  const Divider(
                    height: 1,
                    color: Color(0xFFF1F5F9),
                    indent: 56,
                    endIndent: 16,
                  ),
                  _buildSettingsTile(
                    leading: Image.asset(
                      'assets/icons/Image (Login & Security).png',
                      width: 24,
                      height: 24,
                    ),
                    title: 'Login & Security',
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      color: Color(0xFF94A3B8),
                      size: 16,
                    ),
                    onTap: () => _showLoginSecurityOptions(context),
                  ),
                  const Divider(
                    height: 1,
                    color: Color(0xFFF1F5F9),
                    indent: 56,
                    endIndent: 16,
                  ),
                  _buildSettingsTile(
                    leading: Image.asset(
                      'assets/icons/Image (Account).png',
                      width: 24,
                      height: 24,
                    ),
                    title: 'Account',
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      color: Color(0xFF94A3B8),
                      size: 16,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AccountView()),
                    ),
                  ),
                  const Divider(
                    height: 1,
                    color: Color(0xFFF1F5F9),
                    indent: 56,
                    endIndent: 16,
                  ),
                  _buildSettingsTile(
                    leading: const Icon(
                      Icons.workspace_premium,
                      color: AppColors.primaryColor,
                      size: 24,
                    ),
                    title: 'Subscriptions',
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      color: Color(0xFF94A3B8),
                      size: 16,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CurrentPlanView(),
                      ),
                    ),
                  ),
                  const Divider(
                    height: 1,
                    color: Color(0xFFF1F5F9),
                    indent: 56,
                    endIndent: 16,
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
                      width: 24,
                      height: 24,
                    ),
                    title: 'Devices',
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      color: Color(0xFF94A3B8),
                      size: 16,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DevicesView()),
                      );
                    },
                  ),
                  const Divider(
                    height: 1,
                    color: Color(0xFFF1F5F9),
                    indent: 56,
                    endIndent: 16,
                  ),
                  _buildSettingsTile(
                    leading: Image.asset(
                      'assets/icons/Image (Help).png',
                      width: 24,
                      height: 24,
                    ),
                    title: 'Help',
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      color: Color(0xFF94A3B8),
                      size: 16,
                    ),
                    onTap: () => _showHelpOptions(context),
                  ),
                  const Divider(
                    height: 1,
                    color: Color(0xFFF1F5F9),
                    indent: 56,
                    endIndent: 16,
                  ),
                  _buildSettingsTile(
                    leading: Image.asset(
                      'assets/icons/Image (About App).png',
                      width: 24,
                      height: 24,
                    ),
                    title: 'About App',
                    trailing: const Icon(
                      CupertinoIcons.chevron_right,
                      color: Color(0xFF94A3B8),
                      size: 16,
                    ),
                    onTap: () => _showAboutAppDialog(context),
                  ),
                ],
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFE8D6), Color(0xFFFFECD6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/icons/Image (Shield)Big.png',
            width: 60,
            height: 60,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Ensure Better Protection",
                  style: GoogleFonts.poppins(
                    fontSize: 16.0.sp,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0C1D37),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "at half price of a family meal\n60% of users prefer Premium",
                  style: GoogleFonts.poppins(
                    fontSize: 12.0.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF64748B),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionMultiPlanView(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0066FF), // Primary blue button
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "Know More",
                      style: GoogleFonts.poppins(
                        fontSize: 12.0.sp,
                        fontWeight: FontWeight.bold,
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
        padding: const EdgeInsets.only(left: 0, bottom: 8, top: 18),
        child: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 11.0.sp,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF9BA4B5),
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
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 4,
            offset: const Offset(0, 1),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 15.0.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF0F1320),
                  letterSpacing: 0.1,
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
      ).showSnackBar(const SnackBar(content: Text('Preparing logs…')));

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

  void _showHelpOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF3E0),
                  child: Icon(Icons.chat, color: Color(0xFFEF6C00)),
                ),
                title: const Text('Chat with Support'),
                subtitle: const Text('Real-time assistance'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (!SubscriptionFeatureGate.helpChannels().chat) {
                    UpgradeRestrictionDialog.showHelpChannelBlocked(
                      context,
                      'Chat',
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BlocProvider.value(
                        value: injector<ChatBloc>(),
                        child: const ChatScreen(
                          recipientId:
                              '65b2a3f7e1b2c3d4e5f67890', // Placeholder Admin ID
                          recipientName: 'NaviQ Support',
                        ),
                      ),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE8F5E9),
                  child: Icon(Icons.email, color: Color(0xFF2E7D32)),
                ),
                title: const Text('Email Support'),
                subtitle: const Text('info.truenyx@gmail.com'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _launchContactUrl(
                    Uri(scheme: 'mailto', path: 'info.truenyx@gmail.com'),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE3F2FD),
                  child: Icon(Icons.phone, color: Color(0xFF1565C0)),
                ),
                title: const Text('Call Support'),
                subtitle: const Text('+91 90371 62751'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (!SubscriptionFeatureGate.helpChannels().call) {
                    UpgradeRestrictionDialog.showHelpChannelBlocked(
                      context,
                      'Call',
                    );
                    return;
                  }
                  _launchContactUrl(Uri(scheme: 'tel', path: '+919037162751'));
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showLoginSecurityOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.share, color: AppColors.primaryColor),
                title: const Text('Share Background Logs'),
                subtitle: const Text('Export CSV logs for debugging'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _shareLogs(context);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete Account'),
                subtitle: const Text('Permanently delete your account'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDeleteAccountDialog(context);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Logout'),
                subtitle: const Text('Logout from the app'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showPremiumLogoutDialog(context);
                },
              ),
              const SizedBox(height: 20),
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
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Premium Badge Icon with Gradient
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF0066FF), Color(0xFF6F9EFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.workspace_premium_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Unlock Premium Protection',
                  style: GoogleFonts.poppins(
                    fontSize: 20.0.sp,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0C1D37),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Logging out will disable real-time alerts and location updates. Upgrade to Premium to keep your child fully protected.',
                  style: GoogleFonts.poppins(
                    fontSize: 13.5.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF64748B),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // Bullet points of premium features
                Column(
                  children: [
                    _buildDialogFeatureRow('Real-time location & geofencing'),
                    const SizedBox(height: 10),
                    _buildDialogFeatureRow('SOS emergency notification alerts'),
                    const SizedBox(height: 10),
                    _buildDialogFeatureRow(
                      'Advanced web filtering (Block 18+)',
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0066FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.pop(dialogContext); // Close modal
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionMultiPlanView(),
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
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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
                              const Duration(seconds: 4),
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
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: Color(0xFFE0EDFF),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: Color(0xFF0066FF), size: 12),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 13.0.sp,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0C1D37),
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
      applicationVersion: 'Naviq Dev 1.0.4(Oct 2)',
      applicationIcon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primaryColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.child_care, color: Colors.white, size: 32),
      ),
      children: [
        const SizedBox(height: 16),
        Text(
          'Keeping children safe and parents connected.',
          style: TextStyle(fontSize: 14.0.sp, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Text(
          '© 2026 CodeScap Solutions',
          style: TextStyle(fontSize: 12.0.sp, color: Colors.grey),
        ),
      ],
    );
  }

  Future<void> _launchContactUrl(Uri url) async {
    try {
      if (!await launchUrl(url)) {
        if (mounted) {
          AppSnackbar.showError(context, 'Could not launch action');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, 'Error: $e');
      }
    }
  }

  List<Widget> _buildInactiveChildTiles() {
    final inactiveChildren = _children
        .where((e) => e.childId != _currentChildId)
        .toList();

    return inactiveChildren.map((child) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () => _showSwitchConfirmation(child),
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.containerBackground.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
              border: Border.all(color: Colors.white.withAlpha(50)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primaryColor.withValues(
                    alpha: 0.1,
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 20,
                    color: AppColors.primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        child.childName,
                        style: AppTextStyles.subtitle2.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        "Code: ${child.childCode}",
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.swap_horiz,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildAddChildTile() {
    return InkWell(
      onTap: () async {
        if (!_isPrimaryParent) {
          AppSnackbar.showError(
            context,
            'Guardians have view-only access. Only primary parents can add a new child.',
          );
          return;
        }
        await Navigator.pushNamed(context, RouteNames.addChild);
        _loadChildData();
      },
      borderRadius: BorderRadius.circular(AppSizes.radiusM),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primaryColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
          border: Border.all(
            color: AppColors.primaryColor.withValues(alpha: 0.2),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.add_circle_outline,
              color: AppColors.primaryColor,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              "Add New Child",
              style: AppTextStyles.subtitle2.copyWith(
                color: AppColors.primaryColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSwitchConfirmation(ChildProfile targetChild) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch Profile?'),
        content: Text(
          'Tracking will pause for $_childName and activate for ${targetChild.childName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _handleSwitch(targetChild);
    }
  }

  Future<void> _handleSwitch(ChildProfile child) async {
    try {
      AppSnackbar.showLoading(context, 'Switching child identity...');

      // 1. Stop background services if tracking on this device (child only)
      if (!_sharedPrefsService.isParent) {
        await BackgroundLocationService().stop();
        AppLogger.info('Multi-Child: Stopped background services');
      }

      // 2. Perform switch in storage (Update token, IDs, last_active)
      await _sharedPrefsService.switchChild(child.childId);
      AppLogger.info('Multi-Child: Storage updated for ${child.childId}');

      // 3. Re-initialize state
      _loadChildData();

      // 4. Restart services if tracking on this device (child only)
      if (!_sharedPrefsService.isParent) {
        await BackgroundLocationService().start();
        AppLogger.info('Multi-Child: Restarted background services');
      } else {
        AppLogger.info(
          'Multi-Child: Parent device, skipping background location service start',
        );
      }

      if (mounted) {
        // Clear loading snackbar
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        Navigator.pushNamedAndRemoveUntil(
          context,
          RouteNames.home,
          (route) => false,
        );
      }
    } catch (e) {
      AppLogger.error('Switch failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        AppSnackbar.showError(context, 'Failed to switch profile');
      }
    }
  }
}
