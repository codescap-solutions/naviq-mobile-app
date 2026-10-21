import 'dart:math' show min;
import 'package:child_track/app/home/view_model/bloc/homepage_bloc.dart';
import 'package:child_track/app/subscription/view/subscription_multi_plan_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/app/home/view/trips_view.dart';
import 'package:child_track/app/geofencing/view/geo_fencing_view.dart';
import 'package:child_track/app/social_apps/view/social_apps_view.dart';
import 'package:child_track/app/explore/view/emergency_contacts_view.dart';
import 'package:child_track/app/explore/view/parents_contact_view.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/core/utils/responsive_font.dart';

class ExploreView extends StatelessWidget {
  final VoidCallback onNavigateToHome;

  const ExploreView({super.key, required this.onNavigateToHome});

  @override
  Widget build(BuildContext context) {
    final sharedPrefsService = injector<SharedPrefsService>();

    return Scaffold(
      backgroundColor: Color(0xFFF4F8FE),
      appBar: figmaAppBar(context, title: 'Explore', onBack: onNavigateToHome),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(10.w, 16.w, 10.w, 16.w),
          child: Column(
            children: [
              _sectionLabel('Main Features'),
              // CARD 1: Core Parental Controls
              _buildSectionCard(
                children: [
                  _buildExploreItem(
                    iconAsset: 'assets/icons/explore_scroll.svg',
                    title: 'Scroll',
                    subtitle: 'Screentime Tracker & Controller',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SocialAppsView()),
                      );
                    },
                  ),
                  _buildExploreItem(
                    iconAsset: 'assets/icons/explore_geofencing.svg',
                    title: 'Geofencing',
                    subtitle: 'Set virtual location boundaries',
                    onTap: () {
                      final childId = sharedPrefsService.getString('child_id');
                      final parentId = sharedPrefsService.getString(
                        'parent_id',
                      );
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GeoFencingView(
                            childId: childId,
                            parentId: parentId,
                          ),
                        ),
                      ).then((_) {
                        injector<HomepageBloc>().add(GetHomepageData());
                      });
                    },
                  ),
                  _buildExploreItem(
                    iconAsset: 'assets/icons/explore_route_history.svg',
                    title: 'Route History',
                    subtitle: 'View past travel routes',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TripsView()),
                      );
                    },
                  ),
                  _buildExploreItem(
                    iconAsset: 'assets/icons/explore_live_tracking.svg',
                    title: 'Live Tracking',
                    subtitle: 'Real-time location updates',
                    onTap: onNavigateToHome,
                  ),
                ],
              ),

              SizedBox(height: 12.w),

              _sectionLabel('Additionals'),
              // CARD 2: Additional Controls
              _buildSectionCard(
                children: [
                  _buildExploreItem(
                    iconAsset: 'assets/icons/explore_parents_contact.svg',
                    title: 'Parents Contact',
                    subtitle: "Contact displayed in kid's device",
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ParentsContactView()),
                      );
                    },
                  ),
                  _buildExploreItem(
                    iconAsset: 'assets/icons/explore_request_tracking.svg',
                    title: 'Request Tracking',
                    subtitle: 'Tracking permission of others',
                    onTap: () {
                      _showActiveSharesRevocationSheet(context);
                    },
                  ),
                  _buildExploreItem(
                    iconAsset: 'assets/icons/explore_emergency_contact.svg',
                    title: 'Emergency Contact',
                    subtitle: 'People related to kid',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EmergencyContactsView(),
                        ),
                      );
                    },
                  ),
                  _buildExploreItem(
                    iconAsset: 'assets/icons/explore_subscription.svg',
                    title: 'Subscription',
                    subtitle: 'Your plan details',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SubscriptionMultiPlanView(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Group label above a card (Figma Body Small: Poppins Regular 12 / 20).
  Widget _sectionLabel(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: EdgeInsets.fromLTRB(10.w, 0, 10.w, 4.w),
      child: Text(
        text,
        style: FigmaText.bodySmall.copyWith(color: const Color(0xFF707784)),
      ),
    ),
  );

  /// White 24px-radius card; rows are separated by a 1px #EEF0F4 divider
  /// inset 20px on both sides, followed by an 8px gap (Figma Explore).
  Widget _buildSectionCard({required List<Widget> children}) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 22.w),
            child: Divider(height: 1, thickness: 1, color: Color(0xFFEEF0F4)),
          ),
        );
      }
      rows.add(children[i]);
    }
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.w),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20.w,
            offset: Offset(0.w, 4.w),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.w),
        child: Column(children: rows),
      ),
    );
  }

  Widget _buildExploreItem({
    required String iconAsset,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(22.w, 17.w, 22.w, 17.w),
        child: Row(
          children: [
            // Figma: bare 26px blue icon, no tile.
            SvgPicture.asset(
              iconAsset,
              width: 26.w,
              height: 26.w,
              colorFilter: ColorFilter.mode(
                FigmaColors.primary,
                BlendMode.srcIn,
              ),
            ),
            SizedBox(width: 18.w),
            Expanded(
              child: Padding(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 16.0.sp,
                        fontWeight: FontWeight.w400,
                        height: 24 / 16,
                        letterSpacing: 0.2,
                        color: Color(0xFF0F1320),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 12.0.sp,
                        fontWeight: FontWeight.w400,
                        height: 20 / 12,
                        letterSpacing: 0.2,
                        color: Color(0xFF4A5267),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SvgPicture.asset(
              'assets/icons/settings_chevron.svg',
              width: 18.w,
              height: 18.w,
              colorFilter: ColorFilter.mode(Color(0xFF707784), BlendMode.srcIn),
            ),
          ],
        ),
      ),
    );
  }

  void _showActiveSharesRevocationSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.w)),
      ),
      builder: (sheetContext) {
        return const _ActiveOutgoingSharesSheetContent();
      },
    );
  }
}

class _ActiveOutgoingSharesSheetContent extends StatefulWidget {
  const _ActiveOutgoingSharesSheetContent();

  @override
  State<_ActiveOutgoingSharesSheetContent> createState() =>
      __ActiveOutgoingSharesSheetContentState();
}

class __ActiveOutgoingSharesSheetContentState
    extends State<_ActiveOutgoingSharesSheetContent> {
  List<dynamic>? _activeShares;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchActiveShares();
  }

  Future<void> _fetchActiveShares() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await injector<HomeRepository>()
          .getActiveOutgoingShares();
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (response.isSuccess && response.data != null) {
            _activeShares = response.data;
          } else {
            _errorMessage = response.message;
          }
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = err.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20.w,
        16.w,
        20.w,
        16.w + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40.w,
              height: 5.w,
              margin: EdgeInsets.only(bottom: 16.w),
              decoration: BoxDecoration(
                color: Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(3.w),
              ),
            ),
          ),
          Text(
            'Active Location Sharing',
            style: GoogleFonts.poppins(
              fontSize: 18.0.sp,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0C1D37),
            ),
          ),
          SizedBox(height: 6.w),
          Text(
            'Manage active location permissions granted to other parents.',
            style: GoogleFonts.poppins(
              fontSize: 12.0.sp,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
          SizedBox(height: 20.w),
          if (_isLoading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 40.w),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF0066FF)),
              ),
            )
          else if (_errorMessage != null)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 40.w),
              child: Center(
                child: Text(
                  'Error: $_errorMessage',
                  style: GoogleFonts.poppins(
                    color: Colors.redAccent,
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else if (_activeShares == null || _activeShares!.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 40.w),
              child: Center(
                child: Text(
                  'No active location sharing sessions',
                  style: GoogleFonts.poppins(
                    fontSize: 14.0.sp,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _activeShares!.length,
                separatorBuilder: (context, index) => SizedBox(height: 12.w),
                itemBuilder: (context, index) {
                  final shareData =
                      _activeShares![index] as Map<String, dynamic>;
                  final String shareId =
                      shareData['share_id']?.toString() ??
                      shareData['id']?.toString() ??
                      '';
                  final String phone =
                      shareData['recipient_phone']?.toString() ?? '';
                  final String childName =
                      shareData['child_name']?.toString() ?? 'Child';
                  final String expiresAtStr =
                      shareData['expires_at']?.toString() ?? '';

                  int minutesLeft = 0;
                  try {
                    if (expiresAtStr.isNotEmpty) {
                      final expiresAt = DateTime.parse(expiresAtStr);
                      minutesLeft = expiresAt
                          .difference(DateTime.now())
                          .inMinutes;
                      if (minutesLeft < 0) minutesLeft = 0;
                    }
                  } catch (e) {
                    // ignore
                  }

                  return Container(
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16.w),
                      border: Border.all(color: Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44.w,
                              height: 44.w,
                              decoration: BoxDecoration(
                                color: Color(0xFFEFF6FF),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                childName
                                    .substring(0, min(2, childName.length))
                                    .toUpperCase(),
                                style: GoogleFonts.poppins(
                                  fontSize: 14.0.sp,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0066FF),
                                ),
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sharing $childName with',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13.0.sp,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0C1D37),
                                  ),
                                ),
                                Text(
                                  phone,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12.0.sp,
                                    color: Color(0xFF475569),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Expires in $minutesLeft mins',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11.0.sp,
                                    color: Color(0xFF94A3B8),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFFEF2F2),
                            foregroundColor: Color(0xFFEF4444),
                            elevation: 0,
                            padding: EdgeInsets.symmetric(
                              horizontal: 12.w,
                              vertical: 8.w,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.w),
                            ),
                          ),
                          onPressed: () async {
                            setState(() {
                              _isLoading = true;
                            });

                            final revokeRes = await injector<HomeRepository>()
                                .revokeLocationSharing(shareId: shareId);

                            if (mounted) {
                              if (revokeRes.isSuccess) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Stopped sharing location of $childName successfully',
                                    ),
                                    backgroundColor: Color(0xFFEF4444),
                                  ),
                                );
                                // Re-fetch list
                                _fetchActiveShares();
                              } else {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Failed to stop sharing: ${revokeRes.message}',
                                    ),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                                setState(() {
                                  _isLoading = false;
                                });
                              }
                            }
                          },
                          child: Text(
                            'Stop',
                            style: GoogleFonts.poppins(
                              fontSize: 12.0.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          SizedBox(height: 16.w),
        ],
      ),
    );
  }
}
