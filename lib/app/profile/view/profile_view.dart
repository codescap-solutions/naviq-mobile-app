import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/core/services/shared_prefs_service.dart';
import 'package:child_track/core/di/injector.dart';
import 'package:child_track/core/utils/app_snackbar.dart';
import 'package:child_track/core/models/child_profile.dart';
import 'package:child_track/app/home/view_model/bloc/homepage_bloc.dart';
import 'package:child_track/app/home/view_model/home_repo.dart';
import 'package:child_track/app/auth/view/onboarding/add_kid_view.dart';

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
          now.difference(_lastResumeRefreshAt!) < const Duration(seconds: 5)) {
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
      Future.delayed(const Duration(milliseconds: 300), () {
        widget.onNavigateToHome();
      });
    }
  }

  void _showMoreActions(ChildProfile child) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: Text('Edit profile of ${child.childName}'),
                onTap: () async {
                  Navigator.pop(context);
                  final updated = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddKidView(childToEdit: child),
                    ),
                  );
                  if (updated == true) {
                    _loadChildren();
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
                title: Text(
                  'Delete profile of ${child.childName}',
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final repo = injector<HomeRepository>();
                  final response = await repo.deleteChild(child.childId);

                  if (response.isSuccess) {
                    final list = _sharedPrefsService.getChildren();
                    list.removeWhere((c) => c.childId == child.childId);
                    await _sharedPrefsService.saveChildren(list);

                    // If we deleted the active child, switch to another child or clear
                    final activeChildId = _sharedPrefsService.getString(
                      'child_id',
                    );
                    if (activeChildId == child.childId) {
                      if (list.isNotEmpty) {
                        await _sharedPrefsService.switchChild(
                          list.first.childId,
                        );
                        injector<HomepageBloc>().add(GetHomepageData());
                      } else {
                        await _sharedPrefsService.removeChildId();
                        await _sharedPrefsService.setString('child_name', '');
                      }
                    }

                    _loadChildren();
                    if (context.mounted) {
                      AppSnackbar.showSuccess(
                        context,
                        'Profile of ${child.childName} deleted successfully',
                      );
                    }
                  } else {
                    if (context.mounted) {
                      AppSnackbar.showError(
                        context,
                        response.message.isEmpty
                            ? 'Failed to delete child profile'
                            : response.message,
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        toolbarHeight: 80,
        backgroundColor: const Color(0xFF48546A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leadingWidth: 72,
        leading: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: GestureDetector(
              onTap: widget.onNavigateToHome,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFFE2E8F0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.chevron_left,
                  color: Color(0xFF0C1D37),
                  size: 18,
                ),
              ),
            ),
          ),
        ),
        title: Text(
          'Profiles',
          style: GoogleFonts.manrope(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        actions: [
          // Manual refresh — the same child list is otherwise only fetched
          // once at HomePage's initState (see _loadChildren doc above), so
          // a child added from another device wouldn't appear here without
          // this until a full logout+login.
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: GestureDetector(
                onTap: _isRefreshing ? null : _loadChildren,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE2E8F0),
                    shape: BoxShape.circle,
                  ),
                  child: _isRefreshing
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF0C1D37),
                          ),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          color: Color(0xFF0C1D37),
                          size: 22,
                        ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: GestureDetector(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddKidView()),
                  );
                  _loadChildren();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE2E8F0),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Color(0xFF0C1D37),
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _children.isEmpty
          ? SafeArea(child: _buildEmptyState())
          : SafeArea(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: _children.length,
                itemBuilder: (context, index) {
                  final child = _children[index];

                  final status = child.isActive
                      ? 'online & tracking'
                      : 'last active: ${_formatLastActive(child.lastActiveAt)}';
                  final screenTime = child.formattedScreenTimeToday;
                  final maxSpeed =
                      '${child.todayMaxSpeedKmph.toStringAsFixed(0)} km/hr';
                  final entireRoute =
                      '${child.todayRouteKm.toStringAsFixed(1)} km';

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 8.0,
                    ),
                    child: _buildProfileCard(
                      name: child.childName,
                      childCode: child.childCode,
                      avatar: child.avatar,
                      status: status,
                      screenTime: screenTime,
                      maxSpeed: maxSpeed,
                      entireRoute: entireRoute,
                      isActive: child.isActive,
                      onTap: () => _setActiveChild(child),
                      onMorePressed: () => _showMoreActions(child),
                    ),
                  );
                },
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

  Widget _buildProfileCard({
    required String name,
    required String childCode,
    required String? avatar,
    required String status,
    required String screenTime,
    required String maxSpeed,
    required String entireRoute,
    required bool isActive,
    required VoidCallback onTap,
    required VoidCallback onMorePressed,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0C1D37).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            // Top Section (Blue Gradient)
            GestureDetector(
              onTap: onTap,
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF5F9EFA),
                      Color(0xFF3B82F6),
                      Color(0xFF1D4ED8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    // Decorative Circle 1
                    Positioned(
                      top: -40,
                      right: -40,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    // Decorative Circle 2
                    Positioned(
                      bottom: -60,
                      left: -20,
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                    ),
                    // Active Badge
                    if (isActive)
                      Positioned(
                        top: 16,
                        left: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'active',
                            style: GoogleFonts.manrope(
                              color: const Color(0xFF15803D),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    // More Button
                    Positioned(
                      top: 16,
                      right: 16,
                      child: GestureDetector(
                        onTap: onMorePressed,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.more_horiz_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    // Avatar & Text info
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 20),
                          // Profile Avatar image/placeholder
                          GestureDetector(
                            onTap: onTap,
                            child: Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: _buildAvatarWidget(avatar),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Name text + tap-to-copy child code — parents
                          // previously had to retype/screenshot the code by
                          // hand to share it with a guardian or re-pair a
                          // device; same Clipboard pattern already used in
                          // child_code_screen.dart's onboarding flow.
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: childCode));
                              AppSnackbar.showSuccess(
                                context,
                                'Child code copied: $childCode',
                              );
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$name ($childCode)',
                                  style: GoogleFonts.manrope(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.copy_rounded,
                                  size: 16,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Status text
                          Text(
                            status,
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Bottom Section (Stats Row)
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: const BoxDecoration(color: Colors.white),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        icon: Icons.access_time_outlined,
                        value: screenTime,
                        label: 'screen time',
                      ),
                    ),
                    Container(
                      height: 32,
                      width: 1,
                      color: const Color(0xFFE2E8F0),
                    ),
                    Expanded(
                      child: _buildStatItem(
                        icon: Icons.bolt_rounded,
                        value: maxSpeed,
                        label: 'max speed',
                      ),
                    ),
                    Container(
                      height: 32,
                      width: 1,
                      color: const Color(0xFFE2E8F0),
                    ),
                    Expanded(
                      child: _buildStatItem(
                        icon: Icons.location_on_outlined,
                        value: entireRoute,
                        label: 'entire route',
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

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF0C1D37), size: 16),
            const SizedBox(width: 6),
            Text(
              value,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0C1D37),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarWidget(String? avatar) {
    if (avatar == null || avatar.isEmpty) {
      return Center(
        child: Icon(
          Icons.person_rounded,
          color: Colors.blue.shade300,
          size: 48,
        ),
      );
    }
    if (avatar.startsWith('http')) {
      return ClipOval(
        child: Image.network(
          avatar,
          width: 88,
          height: 88,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.person_rounded, color: Colors.blue.shade300, size: 48),
        ),
      );
    }

    final isPng =
        avatar.endsWith('.png') ||
        avatar.contains('Boy') ||
        avatar.contains('Girl');
    final finalPath = isPng
        ? 'assets/images/childavatar/${avatar.replaceAll('.svg', '.png')}'
        : 'assets/images/childavatar/$avatar';

    return ClipOval(
      child: Image.asset(
        finalPath,
        width: 88,
        height: 88,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.person_rounded, color: Colors.blue.shade300, size: 48),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.child_care_rounded,
                size: 64,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "No Connected Kids",
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0C1D37),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Add a child profile to start tracking and managing their screen time.",
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: const Color(0xFF64748B),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddKidView()),
                  );
                  _loadChildren();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0066FF),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "Add Kid",
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
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
