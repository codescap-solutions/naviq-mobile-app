import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/subscription_manager.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import '../models/subscription_plan.dart';
import '../view_model/subscription_repository.dart';
import 'subscription_multi_plan_view.dart';

/// Dedicated "Current Plan" screen — shows the signed-in parent's active
/// tier, its features, and (for a paid tier) the renewal date/status pulled
/// from RevenueCat, with a way to change plans. Previously the only path
/// from Settings went straight to the upgrade/plan-picker screen, so there
/// was nowhere a parent could just see what they're already on.
class CurrentPlanView extends StatefulWidget {
  const CurrentPlanView({super.key});

  @override
  State<CurrentPlanView> createState() => _CurrentPlanViewState();
}

class _CurrentPlanViewState extends State<CurrentPlanView> {
  late Future<_CurrentPlanData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<_CurrentPlanData> _loadData() async {
    final tier = SubscriptionManager.instance.currentTier;

    SubscriptionPlan? plan;
    try {
      final response = await injector<SubscriptionRepository>().getPlans();
      if (response.isSuccess && response.data != null) {
        try {
          plan = response.data!.firstWhere((p) => p.tier == tier);
        } catch (_) {
          plan = null;
        }
      }
    } catch (_) {
      plan = null;
    }

    EntitlementInfo? entitlement;
    if (SubscriptionManager.instance.hasPremiumAccess) {
      try {
        final customerInfo = await Purchases.getCustomerInfo();
        entitlement = customerInfo.entitlements.active['premium_access'];
      } catch (_) {
        entitlement = null;
      }
    }

    return _CurrentPlanData(tier: tier, plan: plan, entitlement: entitlement);
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '--';
    final date = DateTime.tryParse(isoDate);
    if (date == null) return '--';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Current Plan',
          style: GoogleFonts.poppins(
            fontSize: 24.0.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0C1D37),
          ),
        ),
      ),
      body: FutureBuilder<_CurrentPlanData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data;
          final tier = data?.tier ?? SubscriptionTier.starter;
          final plan = data?.plan;
          final entitlement = data?.entitlement;
          final isFree = tier == SubscriptionTier.starter;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isFree
                        ? const Color(0xFFF1F5F9)
                        : const Color(0xFFE5EFFF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isFree
                                  ? Icons.card_giftcard_rounded
                                  : Icons.workspace_premium_rounded,
                              color: AppColors.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  plan?.name ?? 'Starter (Free)',
                                  style: AppTextStyles.headline3.copyWith(
                                    fontSize: 20.0.sp,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  isFree
                                      ? 'Free plan'
                                      : (entitlement?.willRenew == true
                                            ? 'Auto-renews'
                                            : 'Active'),
                                  style: AppTextStyles.body1.copyWith(
                                    color: Colors.grey[700],
                                    fontSize: 13.0.sp,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (!isFree) ...[
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        _buildInfoRow(
                          entitlement?.willRenew == true
                              ? 'Renews on'
                              : 'Expires on',
                          _formatDate(entitlement?.expirationDate),
                        ),
                        if (entitlement?.latestPurchaseDate != null) ...[
                          const SizedBox(height: 10),
                          _buildInfoRow(
                            'Member since',
                            _formatDate(entitlement?.originalPurchaseDate),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (plan != null && plan.features.isNotEmpty) ...[
                  Text(
                    'What\'s included',
                    style: AppTextStyles.headline5.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16.0.sp,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...plan.features.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 14,
                              color: AppColors.primaryColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              f.name,
                              style: AppTextStyles.body1.copyWith(
                                color: Colors.grey[800],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionMultiPlanView(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      isFree ? 'View Plans' : 'Change Plan',
                      style: AppTextStyles.button.copyWith(
                        color: Colors.white,
                        fontSize: 16.0.sp,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.body1.copyWith(
            color: Colors.grey[700],
            fontSize: 13.0.sp,
          ),
        ),
        Text(
          value,
          style: AppTextStyles.body1.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 13.0.sp,
          ),
        ),
      ],
    );
  }
}

class _CurrentPlanData {
  final SubscriptionTier tier;
  final SubscriptionPlan? plan;
  final EntitlementInfo? entitlement;

  const _CurrentPlanData({required this.tier, this.plan, this.entitlement});
}
