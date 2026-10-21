import 'package:flutter/material.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/services/dio_client.dart';
import 'package:child_track/core/services/base_service.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:child_track/core/services/subscription_manager.dart';
import '../models/subscription_plan.dart';
import '../view_model/subscription_repository.dart';
import '../widgets/subscription_plan_card.dart';
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
  // Figma shows the screen with "Yearly" selected.
  bool _isYearly = true;

  @override
  void initState() {
    super.initState();
    _repository = SubscriptionRepository(dioClient: injector<DioClient>());
    _plansFuture = _repository.getPlans();
    // The "Current Plan" chip follows the live entitlement.
    SubscriptionManager.instance.addListener(_onPlanChanged);
    SubscriptionManager.instance.checkAndUpdateStatus();
  }

  void _onPlanChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SubscriptionManager.instance.removeListener(_onPlanChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF7F8FA),
      appBar: figmaAppBar(context, title: 'Subscription'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            12.w,
            12.w,
            12.w,
            30.w,
          ), // Figma: 12 each side
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: double.infinity),
              _buildToggle(),
              SizedBox(height: 44.w),

              // Plans, in the backend's sortOrder (Smart, Ultimate, Basic, Starter).
              FutureBuilder<BaseResponse<List<SubscriptionPlan>>>(
                future: _plansFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 40.w),
                      child: CircularProgressIndicator(),
                    );
                  } else if (snapshot.hasError ||
                      !snapshot.hasData ||
                      snapshot.data!.data == null ||
                      snapshot.data!.data!.isEmpty) {
                    // Every other fetch-failure screen in the app (geofencing,
                    // social apps) offers an explicit Retry button.
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 40.w),
                      child: Column(
                        children: [
                          Text('Failed to load plans.'),
                          SizedBox(height: 12.w),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _plansFuture = _repository.getPlans(
                                  forceRefresh: true,
                                );
                              });
                            },
                            child: Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  final plans = snapshot.data!.data!;
                  return Column(
                    children: [
                      for (var i = 0; i < plans.length; i++) ...[
                        if (i > 0) SizedBox(height: 14.w),
                        SubscriptionPlanCard(
                          plan: plans[i],
                          isYearly: _isYearly,
                          isCurrent:
                              plans[i].tier ==
                              SubscriptionManager.instance.currentTier,
                          daysLeft: SubscriptionManager.instance.daysLeft,
                          // Already on Premium: nothing to recommend above it.
                          showRecommendation:
                              SubscriptionManager.instance.currentTier !=
                              SubscriptionTier.premium,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SubscriptionDetailView(
                                plan: plans[i],
                                isYearly: _isYearly,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),

              SizedBox(height: 20.w),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'cancel at anytime',
                    style: GoogleFonts.poppins(
                      fontSize: 12.0.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Text(
                    'Terms & Privacy Policy',
                    style: GoogleFonts.poppins(
                      fontSize: 12.0.sp,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0069F9),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Monthly / Yearly toggle: 234 x 37 grey pill, 29px selected segment.
  Widget _buildToggle() {
    const slate = Color(0xFF4A5267);
    const blue = Color(0xFF0069F9);
    Widget segment({
      required bool selected,
      required VoidCallback onTap,
      required String label,
      Widget? trailing,
      required double horizontal,
    }) {
      final color = selected ? Colors.white : slate;
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 29.w,
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          decoration: BoxDecoration(
            color: selected ? blue : Colors.transparent,
            borderRadius: BorderRadius.circular(15.w),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: blue.withValues(alpha: 0.25),
                      blurRadius: 6.w,
                      offset: Offset(0.w, 2.w),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month_outlined, size: 14.w, color: color),
              SizedBox(width: 6.w),
              Text(
                label,
                // Figma "Body Small": Poppins Regular 12 / 20, 0.2px.
                style: FigmaText.poppins(
                  12,
                  color: color,
                  lineHeight: 20,
                  letterSpacing: 0.2,
                ),
              ),
              if (trailing != null) ...[SizedBox(width: 6.w), trailing],
            ],
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: Color(0xFFE8E9EB),
        borderRadius: BorderRadius.circular(20.w),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(
            selected: !_isYearly,
            onTap: () => setState(() => _isYearly = false),
            label: 'Monthly',
            horizontal: 13,
          ),
          segment(
            selected: _isYearly,
            onTap: () => setState(() => _isYearly = true),
            label: 'Yearly',
            horizontal: 11,
            trailing: Container(
              height: 14.w,
              padding: EdgeInsets.symmetric(horizontal: 5.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color(0xFF0DBF75),
                borderRadius: BorderRadius.circular(7.w),
              ),
              child: Text(
                'Save 20%',
                style: GoogleFonts.poppins(
                  fontSize: 8.0.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
