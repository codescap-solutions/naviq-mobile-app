import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:child_track/core/models/child_profile.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_bloc.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/app/auth/view/onboarding/add_kid_view.dart';
import 'package:child_track/app/profile/view/widgets/add_kid_sheet.dart';
import 'package:child_track/app/profile/view/widgets/profile_card.dart';
import 'package:child_track/app/settings/view/devices_view.dart';

class ProfileView extends StatefulWidget {
  final VoidCallback onNavigateToHome;
  // Bumped by HomePage every time this tab is tapped — see didUpdateWidget
  // below. Defaults to 0 so any other/older call site doesn't need updating.
  final int refreshToken;

  const ProfileView({
    super.key,
    required this.onNavigateToHome,
    this.refreshToken = 0,
  });

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> with WidgetsBindingObserver {
  late final SharedPrefsService _sharedPrefsService;
  List<ChildProfile> _children = [];
  bool _isRefreshing = false;
  DateTime? _lastResumeRefreshAt;

  @override
  void initState() {
    super.initState();
    _sharedPrefsService = injector<SharedPrefsService>();
    WidgetsBinding.instance.addObserver(this);
    _loadChildren();
  }

  @override
  void didUpdateWidget(covariant ProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // This screen lives inside HomePage's IndexedStack and is never
    // disposed/recreated on tab switch (see the comment on
    // didChangeAppLifecycleState below), so tapping into this tab from
    // another one doesn't re-run initState — only a widget rebuild, which
    // this catches via the bumped refreshToken prop.
    if (widget.refreshToken != oldWidget.refreshToken) {
      _loadChildren();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Mirrors HomePage's _refreshOnResume pattern: this screen is kept alive
  // inside HomePage's IndexedStack (never disposed/recreated on tab switch),
  // so without this the children list only ever refetches once at
  // HomePage's initState — a parent adding a child from another device
  // would never see it here short of a full logout+login. Same 5s debounce
  // guard against rapid pause/resume flicker.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_lastResumeRefreshAt != null &&
          now.difference(_lastResumeRefreshAt!) < Duration(seconds: 5)) {
        return;
      }
      _lastResumeRefreshAt = now;
      _loadChildren();
    }
  }

  Future<void> _loadChildren() async {
    if (_isRefreshing) return;
    if (mounted) setState(() => _isRefreshing = true);

    final list = _sharedPrefsService.getChildren();
    if (mounted) {
      setState(() {
        _children = list;
      });
    }

    try {
      final repo = injector<HomeRepository>();
      final response = await repo.getChildrenProfiles();

      if (response.isSuccess && response.data != null) {
        final List<dynamic> data = response.data!;
        final apiChildren = data.map((json) {
          final apiChild = ChildProfile.fromMap(json as Map<String, dynamic>);
          final existingIdx = list.indexWhere(
            (c) => c.childId == apiChild.childId,
          );
          if (existingIdx != -1) {
            return apiChild.copyWith(authToken: list[existingIdx].authToken);
          }
          return apiChild;
        }).toList();

        await _sharedPrefsService.saveChildren(apiChildren);

        if (mounted) {
          setState(() {
            _children = apiChildren;
          });
        }
      }
    } catch (e) {
      // Ignore errors, we already displayed the local cache
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _setActiveChild(ChildProfile child) async {
    // 1. Switch child profile identity in local preferences
    await _sharedPrefsService.switchChild(child.childId);

    // 2. Fetch fresh homepage data/sockets for the newly selected child
    injector<HomepageBloc>().add(GetHomepageData());

    setState(() {});

    if (mounted) {
      AppSnackbar.showSuccess(
        context,
        'Switched active profile to ${child.childName}',
      );
      // Return to home map tab after brief delay
      Future.delayed(Duration(milliseconds: 300), () {
        widget.onNavigateToHome();
      });
    }
  }

  Future<void> _editChild(ChildProfile child) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddKidView(childToEdit: child)),
    );
    if (updated == true) _loadChildren();
  }

  Future<void> _confirmRemove(ChildProfile child) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${child.childName}?'),
        content: Text(
          "This deletes ${child.childName}'s profile and stops tracking.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _removeChild(child);
  }

  Future<void> _removeChild(ChildProfile child) async {
    final repo = injector<HomeRepository>();
    final response = await repo.deleteChild(child.childId);

    if (response.isSuccess) {
      final list = _sharedPrefsService.getChildren();
      list.removeWhere((c) => c.childId == child.childId);
      await _sharedPrefsService.saveChildren(list);

      // If we deleted the active child, switch to another child or clear
      final activeChildId = _sharedPrefsService.getString('child_id');
      if (activeChildId == child.childId) {
        if (list.isNotEmpty) {
          await _sharedPrefsService.switchChild(list.first.childId);
          injector<HomepageBloc>().add(GetHomepageData());
        } else {
          await _sharedPrefsService.removeChildId();
          await _sharedPrefsService.setString('child_name', '');
        }
      }

      _loadChildren();
      if (mounted) {
        AppSnackbar.showSuccess(
          context,
          'Profile of ${child.childName} deleted successfully',
        );
      }
    } else if (mounted) {
      AppSnackbar.showError(
        context,
        response.message.isEmpty
            ? 'Failed to delete child profile'
            : response.message,
      );
    }
  }

  /// Selected (active) child first, the rest in their existing order.
  List<ChildProfile> get _sortedChildren {
    final selectedId = _sharedPrefsService.getString('child_id');
    return [
      ..._children.where((c) => c.childId == selectedId),
      ..._children.where((c) => c.childId != selectedId),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final children = _sortedChildren;
    return Scaffold(
      backgroundColor: Color(0xFFF6F8FA),
      // Figma: white header band, 52px back / add circles, centred Bold
      // title. The old manual-refresh circle is now pull-to-refresh on the
      // list (same _loadChildren), so the header matches the single "+".
      appBar: figmaAppBar(
        context,
        title: 'Profiles',
        onBack: widget.onNavigateToHome,
        trailing: FigmaCircleButton(
          color: Colors.white,
          onTap: () => showAddKidSheet(
            context,
            onAddKid: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AddKidView()),
              );
              _loadChildren();
            },
            onPurchaseDevice: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DevicesView(showPurchasePitch: true),
              ),
            ),
          ),
          child: Icon(
            Icons.add_circle_outline_rounded,
            color: Color(0xFF0F1320),
            size: 24.w,
          ),
        ),
      ),
      body: _children.isEmpty
          ? SafeArea(child: _buildEmptyState())
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: _loadChildren,
                child: ListView.builder(
                  physics: AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(vertical: 8.w),
                  itemCount: children.length,
                  itemBuilder: (context, index) {
                    final child = children[index];

                    final status = child.isActive
                        ? 'online & tracking'
                        : 'last active: ${_formatLastActive(child.lastActiveAt)}';
                    final screenTime = child.formattedScreenTimeToday;
                    final maxSpeed =
                        '${child.todayMaxSpeedKmph.toStringAsFixed(0)} km/hr';
                    final entireRoute =
                        '${child.todayRouteKm.toStringAsFixed(1)} km';

                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.0.w,
                        vertical: 0.w,
                      ),
                      child: ProfileCard(
                        name: child.childName,
                        childCode: child.childCode,
                        avatar: child.avatar,
                        status: status,
                        screenTime: screenTime,
                        maxSpeed: maxSpeed,
                        entireRoute: entireRoute,
                        isSelected:
                            child.childId ==
                            _sharedPrefsService.getString('child_id'),
                        onTap: () => _setActiveChild(child),
                        onAction: (action) => switch (action) {
                          ProfileCardAction.edit => _editChild(child),
                          ProfileCardAction.remove => _confirmRemove(child),
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }

  /// Formats a past timestamp as a short relative string, e.g. "just now",
  /// "5m ago", "3h ago", "2d ago".
  String _formatLastActive(DateTime lastActiveAt) {
    final diff = DateTime.now().difference(lastActiveAt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.0.w, vertical: 48.0.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24.w),
              decoration: BoxDecoration(
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.child_care_rounded,
                size: 64.w,
                color: Color(0xFF3B82F6),
              ),
            ),
            SizedBox(height: 24.w),
            Text(
              "No Connected Kids",
              style: GoogleFonts.poppins(
                fontSize: 20.0.sp,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0C1D37),
              ),
            ),
            SizedBox(height: 8.w),
            Text(
              "Add a child profile to start tracking and managing their screen time.",
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14.0.sp,
                color: Color(0xFF64748B),
                height: 1.5,
              ),
            ),
            SizedBox(height: 32.w),
            SizedBox(
              width: 200.w,
              height: 48.w,
              child: ElevatedButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AddKidView()),
                  );
                  _loadChildren();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF0066FF),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.w),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, size: 20.w),
                    SizedBox(width: 8.w),
                    Text(
                      "Add Kid",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.0.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
