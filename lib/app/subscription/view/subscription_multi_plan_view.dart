import 'package:flutter/material.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/dio_client.dart';
import 'package:child_track/core/services/base_service.dart';
import '../models/subscription_plan.dart';
import '../view_model/subscription_repository.dart';
import 'subscription_detail_view.dart';

class SubscriptionMultiPlanView extends StatefulWidget {
  const SubscriptionMultiPlanView({super.key});

  @override
  State<SubscriptionMultiPlanView> createState() =>
      _SubscriptionMultiPlanViewState();
}

class _SubscriptionMultiPlanViewState extends State<SubscriptionMultiPlanView> {
  late final SubscriptionRepository _repository;
  late Future<BaseResponse<List<SubscriptionPlan>>> _plansFuture;
  bool _isYearly = false;

  @override
  void initState() {
    super.initState();
    _repository = SubscriptionRepository(dioClient: injector<DioClient>());
    _plansFuture = _repository.getPlans();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Subscription',
          style: AppTextStyles.headline4.copyWith(
            fontSize: 20.0.sp,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: double.infinity),
              // Toggle Button
              _buildToggle(),
              const SizedBox(height: 30),

              // Plans (Smart, Ultimate, Basic, Starter)
              FutureBuilder<BaseResponse<List<SubscriptionPlan>>>(
                future: _plansFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: CircularProgressIndicator(),
                    );
                  } else if (snapshot.hasError ||
                      !snapshot.hasData ||
                      snapshot.data!.data == null ||
                      snapshot.data!.data!.isEmpty) {
                    // Previously a dead end — the only way to retry a
                    // failed/empty plans fetch was leaving this screen and
                    // coming back (which re-runs initState). Every other
                    // fetch-failure screen in the app (geofencing, social
                    // apps) offers an explicit Retry button; this matches.
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          const Text('Failed to load plans.'),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _plansFuture = _repository.getPlans(forceRefresh: true);
                              });
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  final plans = snapshot.data!.data!;
                  return Column(
                    children: plans
                        .map((plan) => _buildPlanCard(plan))
                        .toList(),
                  );
                },
              ),

              const SizedBox(height: 20),
              Text(
                'cancel at anytime',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Terms & Privacy Policy',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryColor,
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _isYearly = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: !_isYearly ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(30),
                boxShadow: !_isYearly
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month,
                    size: 16,
                    color: !_isYearly ? Colors.black87 : Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Monthly',
                    style: AppTextStyles.subtitle2.copyWith(
                      fontWeight: FontWeight.w600,
                      color: !_isYearly ? Colors.black87 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _isYearly = true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _isYearly ? AppColors.primaryColor : Colors.transparent,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: _isYearly ? Colors.white : Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Yearly',
                    style: AppTextStyles.subtitle2.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _isYearly ? Colors.white : Colors.black54,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Save 20%',
                      style: AppTextStyles.overline.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 9.0.sp,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan) {
    // Determine colors based on plan
    final isSmart = plan.tier == SubscriptionTier.smart;
    final isPremium = plan.tier == SubscriptionTier.premium;
    final isBasic = plan.tier == SubscriptionTier.basic;
    final isStarter = plan.tier == SubscriptionTier.starter;

    Color bgColor = Colors.white;
    Color borderColor = Colors.transparent;

    if (isSmart) {
      bgColor = const Color(0xFFE5EFFF);
      borderColor = AppColors.primaryColor;
    } else if (isPremium) {
      bgColor = const Color(0xFFFFF7E0);
    } else if (isBasic) {
      bgColor = const Color(0xFFF1F5F9);
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                SubscriptionDetailView(plan: plan, isYearly: _isYearly),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Side: Pricing & Name
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (plan.badge != null &&
                            plan.badge != 'Recommended') ...[
                          Text(
                            plan.badge!,
                            style: AppTextStyles.overline.copyWith(
                              color: isPremium
                                  ? const Color(0xFFF5A623)
                                  : AppColors.primaryColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (isStarter) ...[
                          Text(
                            'Starter',
                            style: AppTextStyles.subtitle2.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.send_rounded,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (!isStarter) ...[
                          if (isPremium)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEDD5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.workspace_premium,
                                color: Color(0xFFF5A623),
                              ),
                            )
                          else if (isSmart)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFBFDBFE),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.shield_outlined,
                                color: AppColors.primaryColor,
                              ),
                            ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          plan.name,
                          style: AppTextStyles.headline4.copyWith(
                            fontWeight: FontWeight.w800,
                            color: isPremium
                                ? const Color(0xFFF5A623)
                                : isSmart
                                ? AppColors.primaryColor
                                : isBasic
                                ? AppColors.primaryColor
                                : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '₹',
                              style: AppTextStyles.subtitle1.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _isYearly && plan.yearlyPrice != null
                                  ? '${plan.yearlyPrice?.toInt()}'
                                  : plan.isFree
                                  ? '0'
                                  : '${plan.monthlyPrice.toInt()}',
                              style: AppTextStyles.headline3.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          plan.isFree
                              ? 'forever free'
                              : _isYearly
                              ? '/year'
                              : '/month',
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (plan.yearlyPrice != null && !_isYearly) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isSmart
                                  ? const Color(0xFFBFDBFE)
                                  : isPremium
                                  ? const Color(0xFFFFEDD5)
                                  : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '₹${(plan.monthlyPrice * 12).toInt()}/yr',
                              style: AppTextStyles.overline.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isPremium
                                    ? const Color(0xFFF5A623)
                                    : isSmart
                                    ? AppColors.primaryColor
                                    : Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Right Side: Features & Button
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...plan.features
                            .take(8)
                            .map(
                              (f) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 16,
                                      color: isPremium
                                          ? const Color(0xFFF5A623)
                                          : Colors.grey.shade400,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        f.name,
                                        style: AppTextStyles.caption.copyWith(
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        if (plan.tagline != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            plan.tagline!,
                            style: AppTextStyles.overline.copyWith(
                              color: const Color(0xFFF5A623),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        SubscriptionDetailView(
                                          plan: plan,
                                          isYearly: _isYearly,
                                        ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isPremium
                                    ? const Color(0xFFF5A623)
                                    : isBasic
                                    ? const Color(0xFF1E293B)
                                    : AppColors.primaryColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                elevation: 0,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    plan.ctaText,
                                    style: AppTextStyles.button.copyWith(
                                      color: Colors.white,
                                      fontSize: 12.0.sp,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isSmart)
              Positioned(
                top: -12,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Recommended',
                    style: AppTextStyles.overline.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
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
