import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import '../../../core/services/revenue_cat_service.dart';
import '../models/subscription_plan.dart';

class SubscriptionDetailView extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool isYearly;

  const SubscriptionDetailView({
    super.key,
    required this.plan,
    required this.isYearly,
  });

  @override
  Widget build(BuildContext context) {
    // Determine colors based on plan
    final isSmart = plan.tier == SubscriptionTier.smart;
    final isBasic = plan.tier == SubscriptionTier.basic;
    final isStarter = plan.tier == SubscriptionTier.starter;

    final Color bgColor = isStarter
        ? const Color(0xFFF1F5F9)
        : isBasic
        ? const Color(0xFFF1F5F9)
        : const Color(0xFFE5EFFF);

    final String title = isStarter
        ? 'Get Started'
        : isBasic
        ? 'Go Basic'
        : isSmart
        ? 'Go Smart'
        : 'Go Premium';

    final String priceText = plan.isFree
        ? 'Free forever'
        : isYearly
        ? 'From only ₹${plan.yearlyPrice?.toInt()} a year!'
        : 'From only ₹${plan.monthlyPrice.toInt()} a month!';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Text(
                    title,
                    style: AppTextStyles.headline3.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        priceText,
                        style: AppTextStyles.subtitle2.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF334155),
                        ),
                      ),
                      if (plan.yearlyDiscountBadge != null && isYearly) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0E7FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            plan.yearlyDiscountBadge!,
                            style: AppTextStyles.overline.copyWith(
                              color: AppColors.primaryColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Features List
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(color: bgColor),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: plan.features.map((feature) {
                          return _buildFeatureRow(feature);
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: () => _handlePurchase(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: Text(
              isStarter
                  ? 'Choose Starter'
                  : isBasic
                  ? 'Choose Basic'
                  : isSmart
                  ? 'Choose Plus'
                  : 'Choose Premium',
              style: AppTextStyles.button.copyWith(
                color: Colors.white,
                fontSize: 16.0.sp,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handlePurchase(BuildContext context) async {
    if (plan.tier == SubscriptionTier.starter) return;

    final productId = Platform.isIOS
        ? (isYearly ? plan.yearlyAppleProductId : plan.monthlyAppleProductId)
        : (isYearly ? plan.yearlyGoogleProductId : plan.monthlyGoogleProductId);

    if (productId == null || productId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product ID not configured for this plan.'),
        ),
      );
      return;
    }

    // Show loading overlay
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await RevenueCatService.instance.purchaseProductById(productId);

      if (context.mounted) Navigator.pop(context); // Dismiss loading

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase successful! Premium features unlocked.'),
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on PlatformException catch (e) {
      if (context.mounted) Navigator.pop(context); // Dismiss loading

      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        return; // User intentionally cancelled, do nothing
      }

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Purchase error: ${e.message}')));
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // Dismiss loading
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase failed: ${e.toString()}')),
        );
      }
    }
  }

  Widget _buildFeatureRow(SubscriptionFeature feature) {
    IconData getIconForFeature(String name) {
      name = name.toLowerCase();
      if (name.contains('tracking')) return Icons.navigation_outlined;
      if (name.contains('geofence')) return Icons.map_outlined;
      if (name.contains('sos')) return Icons.error_outline;
      if (name.contains('battery')) return Icons.battery_charging_full_outlined;
      if (name.contains('weather')) return Icons.cloud_outlined;
      if (name.contains('movement') || name.contains('history')) {
        return Icons.show_chart_outlined;
      }
      if (name.contains('steps')) return Icons.directions_walk_outlined;
      if (name.contains('parent') || name.contains('login')) {
        return Icons.people_outline;
      }
      if (name.contains('support')) return Icons.headset_mic_outlined;
      if (name.contains('emergency') || name.contains('share')) {
        return Icons.share_outlined;
      }
      if (name.contains('mood')) return Icons.favorite_border;
      if (name.contains('tamper')) return Icons.volume_off_outlined;
      if (name.contains('call')) return Icons.phone_missed_outlined;
      if (name.contains('block') || name.contains('18+')) {
        return Icons.language_outlined;
      }
      return Icons.check_circle_outline;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(
            getIconForFeature(feature.name),
            color: Colors.black54,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.name,
                  style: AppTextStyles.subtitle2.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                // Optional subtitle description could go here if added to model
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: AppColors.primaryColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 16),
          ),
        ],
      ),
    );
  }
}
