import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/services/revenue_cat_service.dart';
import 'package:child_track/core/services/subscription_manager.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import '../../subscription/models/subscription_plan.dart';
import '../../subscription/view/subscription_multi_plan_view.dart';

class DevicesView extends StatefulWidget {
  const DevicesView({super.key});

  @override
  State<DevicesView> createState() => _DevicesViewState();
}

class _DevicesViewState extends State<DevicesView> {
  bool _isLoading = true;
  bool _simulatedPurchased = false; // toggle for manual testing

  @override
  void initState() {
    super.initState();
    _checkSubscriptionStatus();
  }

  Future<void> _checkSubscriptionStatus() async {
    try {
      final customerInfo = await RevenueCatService.instance.getCustomerInfo();
      if (customerInfo != null && customerInfo.entitlements.active.isNotEmpty) {
        setState(() {
          _simulatedPurchased = true;
        });
      }
    } catch (e) {
      // Ignore error for offline / dev testing
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: Center(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.chevron_left,
                  color: AppColors.textPrimary,
                  size: 16,
                ),
              ),
            ),
          ),
        ),
        title: Text(
          _simulatedPurchased ? 'My Device' : 'Device',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 24.0.sp,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.search,
                  color: AppColors.textPrimary,
                  size: 16,
                ),
              ),
            ),
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_simulatedPurchased ? _buildPurchasedView() : _buildNonPurchasedView()),
      bottomNavigationBar: kDebugMode
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_buildDebugTierSwitcher() != null) _buildDebugTierSwitcher()!,
                if (_buildDebugToggle() != null) _buildDebugToggle()!,
              ],
            )
          : null,
    );
  }

  // ── Debug / Demo review toggle ─────────────────────────────────────────────
  Widget? _buildDebugToggle() {
    if (!kDebugMode) return null;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: const BoxDecoration(
          color: Color(0xFFF1F5F9),
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Review Simulator Tool:",
              style: GoogleFonts.poppins(
                fontSize: 12.0.sp,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
            Row(
              children: [
                Text(
                  "Not Purchased",
                  style: GoogleFonts.poppins(
                    fontSize: 11.0.sp,
                    fontWeight: _simulatedPurchased ? FontWeight.w500 : FontWeight.w800,
                    color: _simulatedPurchased ? AppColors.textSecondary : AppColors.primaryColor,
                  ),
                ),
                Switch(
                  activeThumbColor: AppColors.primaryColor,
                  value: _simulatedPurchased,
                  onChanged: (val) {
                    setState(() {
                      _simulatedPurchased = val;
                    });
                  },
                ),
                Text(
                  "Purchased",
                  style: GoogleFonts.poppins(
                    fontSize: 11.0.sp,
                    fontWeight: _simulatedPurchased ? FontWeight.w800 : FontWeight.w500,
                    color: _simulatedPurchased ? AppColors.primaryColor : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Debug tier switcher ─────────────────────────────────────────────────────
  // The toggle above only flips this screen's own local "purchased" demo
  // state — it never touched SubscriptionManager.instance, which is the
  // actual source of truth the tier-gated features (geofence limits, trip
  // history window, Social Apps lock actions, Help channels, the floating
  // upgrade banner, ...) read via SubscriptionFeatureGate. Without going
  // through a real RevenueCat sandbox purchase, there was no way to exercise
  // those gates end-to-end. debugSetTier exists specifically for this (see
  // its doc comment in subscription_manager.dart) but was never wired to any
  // UI. debugSetTier only changes in-memory state for the current app
  // session — it doesn't touch RevenueCat or the backend, so a real
  // checkAndUpdateStatus() call (app restart, or a real purchase) overrides
  // it back to the real entitlement.
  Widget? _buildDebugTierSwitcher() {
    if (!kDebugMode) return null;
    return AnimatedBuilder(
      animation: SubscriptionManager.instance,
      builder: (context, _) {
        final current = SubscriptionManager.instance.currentTier;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Text(
                "Debug tier:",
                style: GoogleFonts.poppins(
                  fontSize: 12.0.sp,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: SubscriptionTier.values.map((tier) {
                    final isSelected = tier == current;
                    return GestureDetector(
                      onTap: () {
                        // ignore: invalid_use_of_visible_for_testing_member
                        SubscriptionManager.instance.debugSetTier(tier);
                        AppSnackbar.showSuccess(
                          context,
                          'Debug tier set to ${tier.id} (this session only)',
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primaryColor : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? AppColors.primaryColor : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Text(
                          tier.id,
                          style: GoogleFonts.poppins(
                            fontSize: 11.0.sp,
                            fontWeight: FontWeight.w800,
                            color: isSelected ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Non-Purchased View ──────────────────────────────────────────────────────
  Widget _buildNonPurchasedView() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(AppSizes.paddingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Illustration card (TrackPod Pro blue gradient card)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFDBEAFE), Color(0xFF93C5FD)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "GPS TRACKER",
                          style: GoogleFonts.poppins(
                            fontSize: 11.0.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF2563EB),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "TrackPod Pro",
                          style: GoogleFonts.poppins(
                            fontSize: 22.0.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0C1D37),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Live",
                            style: GoogleFonts.poppins(
                              fontSize: 11.0.sp,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: Image.asset(
                    'assets/images/device.png',
                    height: 100,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.watch_rounded,
                        size: 80,
                        color: AppColors.primaryColor,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildPodMetric("±2m", "Accuracy"),
                      _buildPodMetricDivider(),
                      _buildPodMetric("24H", "Coverage"),
                      _buildPodMetricDivider(),
                      _buildPodMetric("7d", "Battery"),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          Text(
            "Features",
            style: GoogleFonts.poppins(
              fontSize: 16.0.sp,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0C1D37),
            ),
          ),
          const SizedBox(height: 12),
          
          // Features Grid (2x2)
          Row(
            children: [
              _buildMockupFeatureCard(
                icon: Icons.location_on_rounded,
                iconColor: const Color(0xFF3B82F6),
                iconBg: const Color(0xFFEFF6FF),
                title: "Accurate Tracking",
                subtitle: "±2m GPS precision",
              ),
              const SizedBox(width: 12),
              _buildMockupFeatureCard(
                icon: Icons.access_time_filled_rounded,
                iconColor: const Color(0xFF10B981),
                iconBg: const Color(0xFFECFDF5),
                title: "24H Tracking",
                subtitle: "All-day coverage",
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMockupFeatureCard(
                icon: Icons.battery_std_rounded,
                iconColor: const Color(0xFFF59E0B),
                iconBg: const Color(0xFFFEF3C7),
                title: "7-Day Battery",
                subtitle: "Ultra-long life",
              ),
              const SizedBox(width: 12),
              _buildMockupFeatureCard(
                icon: Icons.shield_rounded,
                iconColor: const Color(0xFF8B5CF6),
                iconBg: const Color(0xFFF5F3FF),
                title: "Safe Zone",
                subtitle: "Geo-fence alerts",
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Bottom Purchase Card (TrackPod Pro rs 2499)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1D4ED8).withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "TrackPod Pro",
                          style: GoogleFonts.poppins(
                            fontSize: 13.0.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "rs 2499",
                          style: GoogleFonts.poppins(
                            fontSize: 24.0.sp,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "SAVE 20%",
                        style: GoogleFonts.poppins(
                          fontSize: 11.0.sp,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildCheckText("Free shipping"),
                    _buildCheckText("1yr warranty"),
                    _buildCheckText("30d returns"),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionMultiPlanView(),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.shopping_cart_outlined,
                          color: Color(0xFF1D4ED8),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Buy Now",
                          style: GoogleFonts.poppins(
                            fontSize: 15.0.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1D4ED8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => _showLinkDeviceSheet(context),
              child: Text(
                "Already have a tracker? Link Existing Tracker",
                style: GoogleFonts.poppins(
                  fontSize: 13.0.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildPodMetric(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 16.0.sp,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0C1D37),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11.0.sp,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildPodMetricDivider() {
    return Container(
      width: 1,
      height: 24,
      color: const Color(0xFF64748B).withValues(alpha: 0.2),
    );
  }

  Widget _buildMockupFeatureCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.01),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 14.0.sp,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0C1D37),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.poppins(
                fontSize: 11.0.sp,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckText(String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white70, size: 12),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 10.0.sp,
            fontWeight: FontWeight.w500,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  // ── Purchased View ──────────────────────────────────────────────────────────
  Widget _buildPurchasedView() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(AppSizes.paddingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Card (TrackPod Pro blue gradient card)
          GestureDetector(
            onTap: () => _showDeviceManagementSheet(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFDBEAFE), Color(0xFF93C5FD)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFBFDBFE)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF93C5FD).withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "GPS TRACKER",
                            style: GoogleFonts.poppins(
                              fontSize: 11.0.sp,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF2563EB),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "TrackPod Pro",
                            style: GoogleFonts.poppins(
                              fontSize: 22.0.sp,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0C1D37),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              "Live",
                              style: GoogleFonts.poppins(
                                fontSize: 11.0.sp,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Image.asset(
                      'assets/images/device.png',
                      height: 100,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.watch_rounded,
                          size: 80,
                          color: AppColors.primaryColor,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildPodMetric("±2m", "Accuracy"),
                        _buildPodMetricDivider(),
                        _buildPodMetric("24H", "Coverage"),
                        _buildPodMetricDivider(),
                        _buildPodMetric("7d", "Battery"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Battery Life Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.battery_std_rounded, color: Color(0xFFF59E0B), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Battery Life",
                            style: GoogleFonts.poppins(
                              fontSize: 14.0.sp,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0C1D37),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "~6.1 days remaining",
                            style: GoogleFonts.poppins(
                              fontSize: 11.0.sp,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      "87%",
                      style: GoogleFonts.poppins(
                        fontSize: 14.0.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    value: 0.87,
                    minHeight: 6,
                    backgroundColor: Color(0xFFFEF3C7),
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF59E0B)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // GPS Signal Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on_rounded, color: Color(0xFF3B82F6), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "GPS Signal",
                        style: GoogleFonts.poppins(
                          fontSize: 14.0.sp,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0C1D37),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Last updated 2s ago",
                        style: GoogleFonts.poppins(
                          fontSize: 11.0.sp,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                // Cell signal bars
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildSignalBar(8, true),
                    const SizedBox(width: 2),
                    _buildSignalBar(12, true),
                    const SizedBox(width: 2),
                    _buildSignalBar(16, true),
                    const SizedBox(width: 2),
                    _buildSignalBar(20, false),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Today's Tracking Header
          Text(
            "Today's Tracking",
            style: GoogleFonts.poppins(
              fontSize: 16.0.sp,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0C1D37),
            ),
          ),
          const SizedBox(height: 12),

          // Activity Graph Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Activity (24H)",
                      style: GoogleFonts.poppins(
                        fontSize: 13.0.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        AppSnackbar.showInfo(context, "Full activity history coming soon");
                      },
                      child: Text(
                        "View All",
                        style: GoogleFonts.poppins(
                          fontSize: 13.0.sp,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Custom Activity Graph
                _buildActivityGraph(),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSignalBar(double height, bool isActive) {
    return Container(
      width: 3.5,
      height: height,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  Widget _buildActivityGraph() {
    final barHeights = [6, 8, 5, 4, 8, 12, 28, 26, 18, 20, 24, 28, 30, 28, 25, 20, 18, 14, 12, 16, 20, 10, 6, 4];
    final isActive = List.generate(24, (index) => index >= 6 && index <= 20);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(24, (index) {
            return Container(
              width: 7,
              height: barHeights[index].toDouble(),
              decoration: BoxDecoration(
                color: isActive[index] ? const Color(0xFF3B82F6) : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "12AM",
              style: GoogleFonts.poppins(
                fontSize: 10.0.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF94A3B8),
              ),
            ),
            Text(
              "12PM",
              style: GoogleFonts.poppins(
                fontSize: 10.0.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF94A3B8),
              ),
            ),
            Text(
              "Now",
              style: GoogleFonts.poppins(
                fontSize: 10.0.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Modal Actions & Dialogs ─────────────────────────────────────────────────
  void _showLinkDeviceSheet(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController();
    bool sheetLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24,
                left: 24,
                right: 24,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Link Existing Tracker",
                          style: GoogleFonts.poppins(
                            fontSize: 20.0.sp,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetContext),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Enter the 10-digit device ID or serial number printed on the back of your NaviQ tracker package.",
                      style: GoogleFonts.poppins(
                        fontSize: 13.0.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      maxLength: 10,
                      decoration: InputDecoration(
                        hintText: "e.g., 9028341122",
                        prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Please enter device ID";
                        }
                        if (value.length < 10) {
                          return "Device ID must be 10 digits";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: sheetLoading
                            ? null
                            : () async {
                                if (formKey.currentState!.validate()) {
                                  setSheetState(() {
                                    sheetLoading = true;
                                  });
                                  final navigator = Navigator.of(sheetContext);
                                  final messengerContext = context;
                                  await Future.delayed(const Duration(milliseconds: 1500));
                                  if (mounted) {
                                    setState(() {
                                      _simulatedPurchased = true;
                                    });
                                    navigator.pop();
                                    if (messengerContext.mounted) {
                                      AppSnackbar.showSuccess(
                                        messengerContext,
                                        "Device linked successfully!",
                                      );
                                    }
                                  }
                                }
                              },
                        child: sheetLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : Text(
                                "Connect Device",
                                style: GoogleFonts.poppins(
                                  fontSize: 16.0.sp,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
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
      },
    );
  }

  void _showDeviceManagementSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  "Device Management",
                  style: GoogleFonts.poppins(
                    fontSize: 18.0.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.volume_up_rounded, color: Color(0xFF3B82F6), size: 20),
                ),
                title: Text("Ping / Ring Device", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _triggerPingAnimation(context);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.restart_alt_rounded, color: Color(0xFFF59E0B), size: 20),
                ),
                title: Text("Reboot Device", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRebootDialog(context);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF2F2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 20),
                ),
                title: Text(
                  "Unlink Device",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFFEF4444)),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showUnlinkDialog(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _triggerPingAnimation(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _PingSimulationDialog(onCancel: () => Navigator.pop(dialogContext));
      },
    );
  }

  void _showRebootDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isRebooting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                "Reboot Tracker?",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
              ),
              content: isRebooting
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 12),
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          "Sending reboot command...",
                          style: GoogleFonts.poppins(fontSize: 14.0.sp, color: AppColors.textSecondary),
                        ),
                      ],
                    )
                  : Text(
                      "This will remotely restart the tracker device. It may take 1-2 minutes to reconnect online.",
                      style: GoogleFonts.poppins(fontSize: 14.0.sp, color: AppColors.textSecondary, height: 1.4),
                    ),
              actions: isRebooting
                  ? null
                  : [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(
                          "Cancel",
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          setDialogState(() {
                            isRebooting = true;
                          });
                          final navigator = Navigator.of(dialogContext);
                          final messengerContext = context;
                          await Future.delayed(const Duration(milliseconds: 1500));
                          navigator.pop();
                          if (messengerContext.mounted) {
                            AppSnackbar.showSuccess(messengerContext, "Reboot command sent successfully!");
                          }
                        },
                        child: Text(
                          "Reboot",
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: const Color(0xFFF59E0B)),
                        ),
                      ),
                    ],
            );
          },
        );
      },
    );
  }

  void _showUnlinkDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isUnlinking = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                "Unlink Device?",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFEF4444),
                ),
              ),
              content: isUnlinking
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 12),
                        const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFFEF4444))),
                        const SizedBox(height: 16),
                        Text(
                          "Removing tracker association...",
                          style: GoogleFonts.poppins(fontSize: 14.0.sp, color: AppColors.textSecondary),
                        ),
                      ],
                    )
                  : Text(
                      "Are you sure you want to unlink this tracker from your account? This child will no longer be tracked using this hardware device.",
                      style: GoogleFonts.poppins(fontSize: 14.0.sp, color: AppColors.textSecondary, height: 1.4),
                    ),
              actions: isUnlinking
                  ? null
                  : [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(
                          "Keep Linked",
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          setDialogState(() {
                            isUnlinking = true;
                          });
                          final navigator = Navigator.of(dialogContext);
                          final messengerContext = context;
                          await Future.delayed(const Duration(milliseconds: 1500));
                          if (mounted) {
                            setState(() {
                              _simulatedPurchased = false;
                            });
                          }
                          navigator.pop();
                          if (messengerContext.mounted) {
                            AppSnackbar.showSuccess(messengerContext, "Device unlinked successfully.");
                          }
                        },
                        child: Text(
                          "Unlink",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ],
            );
          },
        );
      },
    );
  }
}

class _PingSimulationDialog extends StatefulWidget {
  final VoidCallback onCancel;
  const _PingSimulationDialog({required this.onCancel});

  @override
  State<_PingSimulationDialog> createState() => _PingSimulationDialogState();
}

class _PingSimulationDialogState extends State<_PingSimulationDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        widget.onCancel();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Locating Device",
              style: GoogleFonts.poppins(
                fontSize: 18.0.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Sending signal to play alarm...",
              style: GoogleFonts.poppins(
                fontSize: 13.0.sp,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 40),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: (1.0 - _controller.value).clamp(0.0, 1.0),
                        child: Container(
                          width: 60 + 100 * _controller.value,
                          height: 60 + 100 * _controller.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primaryColor.withValues(alpha: 0.4),
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: (1.0 - (_controller.value + 0.33) % 1.0).clamp(0.0, 1.0),
                        child: Container(
                          width: 60 + 100 * ((_controller.value + 0.33) % 1.0),
                          height: 60 + 100 * ((_controller.value + 0.33) % 1.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primaryColor.withValues(alpha: 0.5),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: (1.0 - (_controller.value + 0.66) % 1.0).clamp(0.0, 1.0),
                        child: Container(
                          width: 60 + 100 * ((_controller.value + 0.66) % 1.0),
                          height: 60 + 100 * ((_controller.value + 0.66) % 1.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primaryColor.withValues(alpha: 0.7),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.primaryColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryColor.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: const Icon(
                          Icons.volume_up_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: widget.onCancel,
                child: Text(
                  "Stop Ping",
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
