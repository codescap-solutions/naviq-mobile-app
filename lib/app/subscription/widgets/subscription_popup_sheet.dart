import 'package:flutter/material.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import '../models/subscription_plan.dart';
import '../view_model/subscription_repository.dart';
import '../view/subscription_detail_view.dart';
import '../view/subscription_multi_plan_view.dart';

class SubscriptionPopup {
  static void show(BuildContext context, SubscriptionTier tier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SubscriptionPopupSheet(tier: tier),
    );
  }
}

class _SubscriptionPopupSheet extends StatefulWidget {
  final SubscriptionTier tier;

  const _SubscriptionPopupSheet({required this.tier});

  @override
  State<_SubscriptionPopupSheet> createState() =>
      _SubscriptionPopupSheetState();
}

class _SubscriptionPopupSheetState extends State<_SubscriptionPopupSheet> {
  late Future<SubscriptionPlan?> _planFuture;
  bool _isYearlySelected = true;

  @override
  void initState() {
    super.initState();
    _planFuture = _fetchPlan();
  }

  Future<SubscriptionPlan?> _fetchPlan() async {
    final repo = injector<SubscriptionRepository>();
    final response = await repo.getPlans();
    if (response.isSuccess && response.data != null) {
      try {
        return response.data!.firstWhere((p) => p.tier == widget.tier);
      } catch (e) {
        return response.data!.first;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: FutureBuilder<SubscriptionPlan?>(
        future: _planFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 300,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (!snapshot.hasData || snapshot.data == null) {
            return const SizedBox(
              height: 300,
              child: Center(child: Text('Failed to load plan details')),
            );
          }

          final plan = snapshot.data!;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Title Header
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.all_inclusive,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    plan.name,
                    style: AppTextStyles.headline3.copyWith(
                      fontSize: 24.0.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (plan.yearlyDiscountBadge != null) ...[
                Text(
                  '${plan.yearlyDiscountBadge} with the Yearly plan',
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Pricing Cards
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isYearlySelected = false),
                      child: _buildPricingCard(
                        plan,
                        isYearly: false,
                        isSelected: !_isYearlySelected,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isYearlySelected = true),
                      child: _buildPricingCard(
                        plan,
                        isYearly: true,
                        isSelected: _isYearlySelected,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Subtitle (Everything in Basic Plan and)
              if (widget.tier == SubscriptionTier.smart)
                Text(
                  'Everything in Basic Plan and',
                  style: AppTextStyles.body1.copyWith(
                    color: AppColors.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (widget.tier == SubscriptionTier.premium)
                Text(
                  'Everything in Smart Plan and',
                  style: AppTextStyles.body1.copyWith(
                    color: AppColors.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              if (widget.tier != SubscriptionTier.basic &&
                  widget.tier != SubscriptionTier.starter)
                const SizedBox(height: 16),

              // Features List
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: plan.features
                        .take(6)
                        .map((f) => _buildFeatureRow(f.name))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Know More Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SubscriptionDetailView(
                          plan: plan,
                          isYearly: _isYearlySelected,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Know More',
                    style: AppTextStyles.button.copyWith(
                      color: Colors.white,
                      fontSize: 16.0.sp,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // View All Plans
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SubscriptionMultiPlanView(),
                    ),
                  );
                },
                child: Text(
                  'View All Plans',
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.primaryColor,
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Disclaimer
              Text(
                'Recurring billing, cancel anytime. Save 25% with Yearly plan compared to Monthly. Subscription auto-renews at same price until cancelled via App Store Settings. Terms & Conditions & Privacy Policy apply.',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(
                  color: Colors.grey[500],
                  fontSize: 10.0.sp,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPricingCard(
    SubscriptionPlan plan, {
    required bool isYearly,
    required bool isSelected,
  }) {
    final price = isYearly ? (plan.yearlyPrice ?? 0) : plan.monthlyPrice;
    final title = isYearly ? '1 year' : '1 month';
    final perMonthPrice = isYearly ? (price / 12).round() : price.round();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue[50]?.withValues(alpha: 0.3)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.primaryColor : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.body1.copyWith(
                  color: Colors.grey[600],
                  fontSize: 14.0.sp,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '₹ ${price.round()}',
                style: AppTextStyles.headline3.copyWith(
                  fontSize: 24.0.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue[50] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '₹ $perMonthPrice /mon',
                  style: AppTextStyles.caption.copyWith(
                    color: isSelected
                        ? AppColors.primaryColor
                        : Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (isYearly && plan.yearlyDiscountBadge != null)
          Positioned(
            top: -12,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                plan.yearlyDiscountBadge!,
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFeatureRow(String text) {
    return Padding(
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
              text,
              style: AppTextStyles.body1.copyWith(
                color: Colors.grey[800],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
