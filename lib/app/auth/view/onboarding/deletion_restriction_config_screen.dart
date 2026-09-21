import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:child_track/core/services/device_info_service.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:child_track/app/auth/view/onboarding/permission_sequence_screen.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class DeletionRestrictionConfigScreen extends StatefulWidget {
  const DeletionRestrictionConfigScreen({super.key});

  @override
  State<DeletionRestrictionConfigScreen> createState() =>
      _DeletionRestrictionConfigScreenState();
}

class _DeletionRestrictionConfigScreenState
    extends State<DeletionRestrictionConfigScreen> with WidgetsBindingObserver {
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      _checkAndroidPermissionSilently();
    }
  }

  Future<void> _checkAndroidPermissionSilently() async {
    final enabled = await injector<DeviceInfoService>().checkAccessibilityPermission();
    if (enabled && mounted) {
      _navigateToNextScreen();
    }
  }

  void _navigateToNextScreen() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const PermissionSequenceScreen(),
      ),
    );
  }

  Future<void> _handleAction() async {
    if (Platform.isAndroid) {
      await injector<DeviceInfoService>().openAccessibilitySettings();
    } else {
      final Uri url = Uri.parse('App-Prefs:root=SCREEN_TIME');
      try {
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          if (mounted) {
            AppSnackbar.showError(context, 'Could not open Screen Time settings. Please open Settings manually.');
          }
        }
      } catch (e) {
        // Fallback to general settings if custom scheme fails
        final Uri generalSettings = Uri.parse('App-Prefs:root=Settings');
        await launchUrl(generalSettings, mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _handleProceed() async {
    if (Platform.isAndroid) {
      setState(() => _isChecking = true);
      final hasPermission = await injector<DeviceInfoService>().checkAccessibilityPermission();
      setState(() => _isChecking = false);

      if (hasPermission) {
        _navigateToNextScreen();
      } else {
        if (mounted) {
          AppSnackbar.showError(
            context,
            'Please enable the NaviQ Accessibility Service to protect the app from being deleted.',
          );
        }
      }
    } else {
      // iOS doesn't support programmatic validation of Screen Time, so proceed directly
      _navigateToNextScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              _buildHeader(),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: _buildInstructionsCard(),
                ),
              ),
              const SizedBox(height: 20),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFFFECE0),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6600).withValues(alpha: 0.1),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(
            Icons.security_rounded,
            size: 36,
            color: Color(0xFFFF6600),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          Platform.isAndroid ? 'Enable Deletion Protection' : 'Protect App from Deleting',
          style: GoogleFonts.poppins(
            fontSize: 24.0.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          Platform.isAndroid
              ? 'Your parent has requested to prevent this app from being uninstalled.'
              : 'Configure Screen Time restrictions to prevent this app from being deleted.',
          style: GoogleFonts.poppins(
            fontSize: 14.0.sp,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF64748B),
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildInstructionsCard() {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEFF2F6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: Platform.isAndroid ? _buildAndroidSteps() : _buildIosSteps(),
      ),
    );
  }

  List<Widget> _buildAndroidSteps() {
    return [
      Text(
        'Required Setup Steps',
        style: GoogleFonts.poppins(
          fontSize: 16.0.sp,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF0F172A),
        ),
      ),
      const SizedBox(height: 16),
      _buildStepRow(
        stepNumber: '1',
        text: 'Tap the "Open Accessibility Settings" shortcut button below.',
      ),
      _buildStepDivider(),
      _buildStepRow(
        stepNumber: '2',
        text: 'Scroll down and select "NaviQ" under Downloaded Services.',
      ),
      _buildStepDivider(),
      _buildStepRow(
        stepNumber: '3',
        text: 'Toggle the service to "On" to activate uninstallation protection.',
      ),
    ];
  }

  List<Widget> _buildIosSteps() {
    return [
      Text(
        'Required Setup Steps',
        style: GoogleFonts.poppins(
          fontSize: 16.0.sp,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF0F172A),
        ),
      ),
      const SizedBox(height: 16),
      _buildStepRow(
        stepNumber: '1',
        text: 'Tap the "Open Screen Time Settings" shortcut button below.',
      ),
      _buildStepDivider(),
      _buildStepRow(
        stepNumber: '2',
        text: 'Navigate to "Content & Privacy Restrictions" and turn it On.',
      ),
      _buildStepDivider(),
      _buildStepRow(
        stepNumber: '3',
        text: 'Select "iTunes & App Store Purchases".',
      ),
      _buildStepDivider(),
      _buildStepRow(
        stepNumber: '4',
        text: 'Tap "Deleting Apps" and change setting to "Don\'t Allow".',
      ),
    ];
  }

  Widget _buildStepRow({required String stepNumber, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFFEFF6FF),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              stepNumber,
              style: GoogleFonts.poppins(
                fontSize: 14.0.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0066FF),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 14.0.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF334155),
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 13, top: 4, bottom: 4),
      child: Container(
        width: 2,
        height: 20,
        color: const Color(0xFFEFF6FF),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF0066FF), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: Colors.white,
            ),
            onPressed: _handleAction,
            icon: Icon(
              Platform.isAndroid ? Icons.settings_accessibility : Icons.open_in_new_rounded,
              color: const Color(0xFF0066FF),
              size: 20,
            ),
            label: Text(
              Platform.isAndroid ? 'Open Accessibility Settings' : 'Open Screen Time Settings',
              style: GoogleFonts.poppins(
                fontSize: 15.0.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0066FF),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            onPressed: _isChecking ? null : _handleProceed,
            child: _isChecking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Text(
                    Platform.isAndroid ? 'Verify & Proceed' : 'I have Enabled It',
                    style: GoogleFonts.poppins(
                      fontSize: 15.0.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
