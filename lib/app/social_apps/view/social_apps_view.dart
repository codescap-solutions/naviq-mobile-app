import 'package:child_track/app/social_apps/model/app_usage_model.dart';
import 'package:child_track/app/social_apps/view_model/bloc/social_apps_bloc.dart';
import 'package:child_track/app/social_apps/view_model/bloc/app_lock_bloc.dart';
import 'package:child_track/app/social_apps/view_model/bloc/app_lock_state.dart';
import 'package:child_track/app/social_apps/view_model/bloc/app_lock_event.dart';
import 'package:child_track/app/social_apps/view_model/bloc/time_limit_bloc.dart';
import 'package:child_track/app/social_apps/view_model/bloc/time_limit_state.dart';
import 'package:child_track/app/social_apps/view_model/bloc/time_limit_event.dart';
import 'package:child_track/core/di/injector.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/services/subscription_feature_gate.dart';
import 'package:child_track/core/widgets/common_button.dart';
import 'package:child_track/core/widgets/social_apps_shimmer.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:google_fonts/google_fonts.dart';
import 'package:child_track/app/subscription/models/subscription_plan.dart';
import 'package:child_track/app/subscription/widgets/upgrade_restriction_dialog.dart';
import 'widgets/social_app_item.dart';

/// Free & Basic tiers may only *view* app usage/screen-time data; taking
/// action (lock an app, set/remove a time limit, block/unblock all) needs
/// Smart or Premium. Shared by [_SocialAppsViewState] and [_ScreenTimeHeader].
bool _guardScreenTimeAction(BuildContext context) {
  if (SubscriptionFeatureGate.canTakeScreenTimeAction()) return true;
  UpgradeRestrictionDialog.show(
    context,
    title: 'Upgrade to Take Action',
    message:
        'Your current plan only lets you view app usage. Upgrade to Smart or Premium '
        'to lock apps and set screen-time limits.',
    suggestedTier: SubscriptionTier.smart,
  );
  return false;
}

class SocialAppsView extends StatefulWidget {
  const SocialAppsView({super.key});

  @override
  State<SocialAppsView> createState() => _SocialAppsViewState();
}

class _SocialAppsViewState extends State<SocialAppsView> {
  late SocialAppsBloc _bloc;
  late AppLockBloc _appLockBloc;
  late TimeLimitBloc _timeLimitBloc;
  int _selectedTabIndex = 1; // Default to Today (index 1)
  final int _selectedFilterIndex = 0; // Default to All (index 0)

  @override
  void initState() {
    super.initState();
    _bloc = injector<SocialAppsBloc>();
    _appLockBloc = injector<AppLockBloc>();
    _timeLimitBloc = injector<TimeLimitBloc>();
    _fetchDataForIndex(_selectedTabIndex);
  }

  void _fetchDataForIndex(int index) {
    final now = DateTime.now();
    final todayStr = now.toIso8601String().split('T')[0];

    if (index == 0) {
      // Yesterday
      final yesterday = now.subtract(const Duration(days: 1));
      final dateStr = yesterday.toIso8601String().split('T')[0];
      _bloc.add(FetchAppUsage(date: dateStr));
    } else if (index == 1) {
      // Today
      _bloc.add(FetchAppUsage(date: todayStr));
    } else {
      // Week — last 7 days (today to 6 days ago)
      final weekStart = now.subtract(const Duration(days: 6));
      final startDateStr = weekStart.toIso8601String().split('T')[0];
      _bloc.add(
        FetchAppUsage(
          date: todayStr,
          startDate: startDateStr,
          endDate: todayStr,
        ),
      );
    }
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => _bloc),
        BlocProvider.value(value: _appLockBloc..add(FetchLockedApps())),
        BlocProvider.value(value: _timeLimitBloc..add(FetchTimeLimits())),
      ],
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          leadingWidth: 72,
          leading: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(
                    CupertinoIcons.chevron_left,
                    color: Colors.black,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          title: Text(
            'Scroll',
            style: GoogleFonts.poppins(
              fontSize: 20.0.sp,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0C1D37),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  "Social Media",
                  style: GoogleFonts.poppins(
                    fontSize: 13.0.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0066FF),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                AdvancedSegmentedTab(
                  onTabChanged: (index) {
                    setState(() {
                      _selectedTabIndex = index;
                    });
                    _fetchDataForIndex(index);
                  },
                ),
                const SizedBox(height: 16),
                BlocBuilder<AppLockBloc, AppLockState>(
                  builder: (context, lockState) {
                    final lockedPackages = lockState is AppLockLoaded
                        ? lockState.lockedPackages
                        : const <String>{};
                    return BlocBuilder<SocialAppsBloc, SocialAppsState>(
                      builder: (context, state) {
                        // Collect all package names visible right now
                        List<String> allPackages = [];
                        if (state is SocialAppsLoaded) {
                          final data = _selectedTabIndex == 2
                              ? state.data.summaryApps
                              : state.data.dailyUsage[state.selectedDate] ?? [];
                          allPackages = data.map((a) => a.packageName).toList();
                        }
                        return _ScreenTimeHeader(
                          totalUsageSeconds: state is SocialAppsLoaded
                              ? state.data.totalUsageTime
                              : 0,
                          totalTimeFormatted: state is SocialAppsLoaded
                              ? state.data.totalUsageTimeFormatted
                              : '--',
                          previousPeriodUsageSeconds: state is SocialAppsLoaded
                              ? state.data.previousPeriodUsageTime
                              : null,
                          allPackages: allPackages,
                          lockedPackages: lockedPackages,
                          appLockBloc: _appLockBloc,
                          selectedTabIndex: _selectedTabIndex,
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 4),
                Expanded(child: _buildAppsList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppsList() {
    return BlocBuilder<SocialAppsBloc, SocialAppsState>(
      builder: (context, state) {
        if (state is SocialAppsLoading) {
          return const SocialAppsShimmer();
        } else if (state is SocialAppsError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(state.message, style: AppTextStyles.body1),
                const SizedBox(height: AppSizes.spacingS),
                CommonButton(
                  text: 'Retry',
                  onPressed: () => _fetchDataForIndex(_selectedTabIndex),
                ),
              ],
            ),
          );
        } else if (state is SocialAppsLoaded) {
          // For Week tab (index 2), merge all days into one combined list
          List<AppUsageItem> dailyData;
          if (_selectedTabIndex == 2) {
            // Summary is provided pre-aggregated by the backend
            dailyData = state.data.summaryApps;
          } else {
            dailyData = state.data.dailyUsage[state.selectedDate] ?? [];
          }

          if (dailyData.isEmpty) {
            return Center(
              child: Text(
                'No usage data for this period',
                style: AppTextStyles.textSecondary,
              ),
            );
          }

          // Apply Filter
          return BlocBuilder<AppLockBloc, AppLockState>(
            builder: (context, lockState) {
              final lockedPackages = lockState is AppLockLoaded
                  ? lockState.lockedPackages
                  : const <String>{};

              final filteredData = dailyData.where((app) {
                if (_selectedFilterIndex == 0) return true; // All
                final isLocked = lockedPackages.contains(app.packageName);
                if (_selectedFilterIndex == 1) return !isLocked; // Active
                if (_selectedFilterIndex == 2) return isLocked; // Blocked
                return true;
              }).toList();

              if (filteredData.isEmpty) {
                return Center(
                  child: Text(
                    _selectedFilterIndex == 1
                        ? 'No active apps'
                        : _selectedFilterIndex == 2
                        ? 'No blocked apps'
                        : 'No apps found',
                    style: AppTextStyles.textSecondary,
                  ),
                );
              }

              return ListView.builder(
                itemCount: filteredData.length + 1, // +1 for spacing
                itemBuilder: (context, index) {
                  if (index == filteredData.length) {
                    return Column(
                      children: [const SizedBox(height: AppSizes.spacingL)],
                    );
                  }

                  final app = filteredData[index];

                  // Detect iOS entries: they use opaque tokens like "usage_cat_XXX"
                  final isIOSEntry =
                      app.platform == 'ios' ||
                      app.packageName.startsWith('usage_cat_') ||
                      app.packageName.startsWith('usage_app_');

                  ImageProvider iconProvider;
                  if (isIOSEntry) {
                    // iOS entries can't have real icons — use default
                    iconProvider = const AssetImage(
                      'assets/images/APK_format_icon_(2014-2019).png',
                    );
                  } else if (app.iconUrl?.isNotEmpty ?? false) {
                    iconProvider = NetworkImage(app.iconUrl!);
                  } else if (app.iconBase64?.isNotEmpty ?? false) {
                    try {
                      iconProvider = MemoryImage(base64Decode(app.iconBase64!));
                    } catch (e) {
                      iconProvider = const AssetImage(
                        'assets/images/APK_format_icon_(2014-2019).png',
                      );
                    }
                  } else {
                    iconProvider = const AssetImage(
                      'assets/images/APK_format_icon_(2014-2019).png',
                    );
                  }

                  // Clean display name for iOS entries
                  String displayName;
                  if (isIOSEntry) {
                    // Use the resolved name from backend (written by Swift Label resolver)
                    // If it still looks like a hash placeholder, use numbered fallback
                    final backendName = app.appName;
                    if (backendName.isNotEmpty &&
                        !backendName.startsWith('Tracked') &&
                        !backendName.contains('(') &&
                        backendName.length > 2) {
                      displayName = backendName;
                    } else {
                      // Fallback: "Category 1" / "App 1" based on type
                      final isCategory = app.packageName.startsWith(
                        'usage_cat_',
                      );
                      displayName = isCategory
                          ? 'Category ${index + 1}'
                          : 'App ${index + 1}';
                    }
                  } else {
                    displayName = app.appName.isNotEmpty
                        ? app.appName
                        : app.packageName;
                  }

                  return BlocBuilder<AppLockBloc, AppLockState>(
                    builder: (context, lockState) {
                      final isLocked =
                          lockState is AppLockLoaded &&
                          lockState.lockedPackages.contains(app.packageName);

                      return BlocBuilder<TimeLimitBloc, TimeLimitState>(
                        builder: (context, limitState) {
                          final limitItem = limitState is TimeLimitLoaded
                              ? limitState.limitsByPackage[app.packageName]
                              : null;

                          return SocialAppItem(
                            icon: iconProvider,
                            name: displayName,
                            usage: app.usageTimeFormatted,
                            isLocked: isLocked,
                            onLockToggle: (isLocked, duration) {
                              if (!_guardScreenTimeAction(context)) return;
                              _appLockBloc.add(
                                ToggleAppLock(
                                  packageName: app.packageName,
                                  appName: displayName,
                                  isLocked: isLocked,
                                  durationMinutes: duration,
                                ),
                              );
                            },
                            dailyLimitMinutes: limitItem?.dailyLimitMinutes,
                            onSetDailyLimit: (minutes) {
                              if (!_guardScreenTimeAction(context)) return;
                              if (minutes == null) {
                                _timeLimitBloc.add(
                                  RemoveTimeLimit(app.packageName),
                                );
                              } else {
                                _timeLimitBloc.add(
                                  SetTimeLimit(
                                    packageName: app.packageName,
                                    appName: displayName,
                                    dailyLimitMinutes: minutes,
                                  ),
                                );
                              }
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _ScreenTimeHeader extends StatefulWidget {
  final int totalUsageSeconds;
  final String totalTimeFormatted;
  final int? previousPeriodUsageSeconds;
  final List<String> allPackages;
  final Set<String> lockedPackages;
  final AppLockBloc? appLockBloc;
  final int selectedTabIndex;

  const _ScreenTimeHeader({
    required this.totalUsageSeconds,
    required this.totalTimeFormatted,
    this.previousPeriodUsageSeconds,
    this.allPackages = const [],
    this.lockedPackages = const {},
    this.appLockBloc,
    required this.selectedTabIndex,
  });

  @override
  State<_ScreenTimeHeader> createState() => _ScreenTimeHeaderState();
}

class _ScreenTimeHeaderState extends State<_ScreenTimeHeader> {
  bool _weekExpanded = false;

  /// True when every visible app is already locked
  bool get _allBlocked =>
      widget.allPackages.isNotEmpty &&
      widget.allPackages.every((p) => widget.lockedPackages.contains(p));

  Future<void> _onBlockAll(BuildContext context) async {
    if (!_guardScreenTimeAction(context)) return;
    if (widget.allPackages.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No apps to block')));
      return;
    }

    // Show duration picker dialog
    final Duration? duration = await showDialog<Duration>(
      context: context,
      builder: (ctx) =>
          _BlockAllDurationDialog(appCount: widget.allPackages.length),
    );
    if (duration == null) return; // user cancelled

    widget.appLockBloc?.add(
      BlockAllApps(
        packageNames: widget.allPackages,
        durationMinutes: duration.inMinutes,
      ),
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Blocking ${widget.allPackages.length} apps'
            '${duration.inMinutes > 0 ? ' for ${duration.inMinutes} min' : ''}...',
          ),
        ),
      );
    }
  }

  void _onUnblockAll(BuildContext context) {
    if (!_guardScreenTimeAction(context)) return;
    for (final pkg in widget.allPackages) {
      if (widget.lockedPackages.contains(pkg)) {
        widget.appLockBloc?.add(
          ToggleAppLock(packageName: pkg, isLocked: false),
        );
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Unblocking ${widget.allPackages.length} apps...'),
      ),
    );
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    final weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    final months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];

    if (widget.selectedTabIndex == 0) {
      final yesterday = now.subtract(const Duration(days: 1));
      return "Yesterday · ${weekdays[yesterday.weekday % 7]}, ${months[yesterday.month - 1]} ${yesterday.day}";
    } else if (widget.selectedTabIndex == 1) {
      return "Today · ${weekdays[now.weekday % 7]}, ${months[now.month - 1]} ${now.day}";
    } else {
      final weekStart = now.subtract(const Duration(days: 6));
      return "${months[weekStart.month - 1]} ${weekStart.day} - ${months[now.month - 1]} ${now.day}";
    }
  }

  Widget _buildSegment(double fillFraction) {
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 8,
          color: const Color(0xFFE2E8F0), // background grey
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fillFraction,
            child: Container(
              color: const Color(0xFFF97316), // active orange
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSegmentedProgressBar(double percentage) {
    final segment1 = (percentage * 4).clamp(0.0, 1.0);
    final segment2 = ((percentage - 0.25) * 4).clamp(0.0, 1.0);
    final segment3 = ((percentage - 0.50) * 4).clamp(0.0, 1.0);
    final segment4 = ((percentage - 0.75) * 4).clamp(0.0, 1.0);

    return [
      _buildSegment(segment1),
      const SizedBox(width: 4),
      _buildSegment(segment2),
      const SizedBox(width: 4),
      _buildSegment(segment3),
      const SizedBox(width: 4),
      _buildSegment(segment4),
    ];
  }

  Widget _buildWarningBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFB7185), Color(0xFFF43F5E)], // Rose/coral gradient
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF43F5E).withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.yellow,
                  size: 20,
                ),
                Positioned(
                  bottom: 2,
                  child: Icon(
                    Icons.flash_on_rounded,
                    color: Colors.yellow,
                    size: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Social media Use high",
                  style: GoogleFonts.poppins(
                    fontSize: 15.0.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Keep restriction on apps",
                  style: GoogleFonts.poppins(
                    fontSize: 12.0.sp,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allBlocked = _allBlocked;
    final limitSeconds = widget.selectedTabIndex == 2 ? 42 * 3600 : 6 * 3600;
    final limitText = widget.selectedTabIndex == 2 ? "42h limit" : "6h limit";
    final double hours = widget.totalUsageSeconds / 3600.0;
    final double percentage = (widget.totalUsageSeconds / limitSeconds).clamp(
      0.0,
      1.0,
    );
    final String hoursStr = hours.toStringAsFixed(1);
    final String usedPctText = "${(percentage * 100).toInt()}% used";

    // Comparison text
    final prevSeconds = widget.previousPeriodUsageSeconds;
    final double? prevHours = prevSeconds != null ? prevSeconds / 3600.0 : null;
    final double? diffHours = prevHours != null ? hours - prevHours : null;
    final bool isWeekTab = widget.selectedTabIndex == 2;

    String comparisonText = "";
    if (widget.selectedTabIndex == 0) {
      comparisonText = "-0.5h vs previous day";
    } else if (widget.selectedTabIndex == 1) {
      comparisonText = "+1.6h vs yesterday";
    } else if (diffHours != null) {
      final sign = diffHours >= 0 ? "+" : "-";
      comparisonText =
          "$sign${diffHours.abs().toStringAsFixed(1)}h vs last week";
    } else {
      comparisonText = "No data for last week";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0C1D37).withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.desktop_windows_rounded,
                      color: Color(0xFF0066FF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Screen Time",
                          style: GoogleFonts.poppins(
                            fontSize: 16.0.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0C1D37),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getFormattedDate(),
                          style: GoogleFonts.poppins(
                            fontSize: 12.0.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Set Limit button
                  OutlinedButton(
                    onPressed: widget.allPackages.isEmpty
                        ? null
                        : () => allBlocked
                              ? _onUnblockAll(context)
                              : _onBlockAll(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: allBlocked
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF0066FF),
                      side: BorderSide(
                        color: allBlocked
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF0066FF),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          allBlocked ? "Unblock All" : "Set Limit",
                          style: GoogleFonts.poppins(
                            fontSize: 13.0.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          allBlocked
                              ? Icons.lock_open_rounded
                              : Icons.tune_rounded,
                          size: 15,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Middle Row: Values
              Row(
                textBaseline: TextBaseline.alphabetic,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                children: [
                  Text(
                    hoursStr,
                    style: GoogleFonts.poppins(
                      fontSize: 32.0.sp,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0C1D37),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "/ $limitText",
                    style: GoogleFonts.poppins(
                      fontSize: 14.0.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    usedPctText,
                    style: GoogleFonts.poppins(
                      fontSize: 14.0.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0066FF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Segmented Progress Bar
              Row(children: _buildSegmentedProgressBar(percentage)),
              const SizedBox(height: 20),

              // Footer Row — "Know More" only makes sense (and only expands
              // real data) on the Week tab, since that's the only period the
              // backend gives us a previous-period comparison for.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    comparisonText,
                    style: GoogleFonts.poppins(
                      fontSize: 13.0.sp,
                      fontWeight: FontWeight.w700,
                      // Same orange/amber as the usage progress bar above —
                      // was red, a hue mismatch vs the Figma spec.
                      color: const Color(0xFFF97316),
                    ),
                  ),
                  if (isWeekTab)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _weekExpanded = !_weekExpanded),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Know More",
                              style: GoogleFonts.poppins(
                                fontSize: 12.0.sp,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0066FF),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _weekExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: const Color(0xFF0066FF),
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              if (isWeekTab && _weekExpanded) ...[
                const SizedBox(height: 20),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 20),
                if (diffHours != null && prevHours != null) ...[
                  Center(
                    child: Column(
                      children: [
                        Text(
                          "${diffHours.abs().toStringAsFixed(1)} hr",
                          style: GoogleFonts.poppins(
                            fontSize: 24.0.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0C1D37),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          diffHours <= 0
                              ? "reduced from last week"
                              : "increased from last week",
                          style: GoogleFonts.poppins(
                            fontSize: 13.0.sp,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "$hoursStr hr this week  •  ${prevHours.toStringAsFixed(1)} hr last week",
                          style: GoogleFonts.poppins(
                            fontSize: 11.0.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          diffHours <= 0
                              ? "New Limit, New Achievement"
                              : "Screen Time Trending Up",
                          style: GoogleFonts.poppins(
                            fontSize: 13.0.sp,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0C1D37),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          diffHours <= 0
                              ? "A new limit can help bring the screen time down even more."
                              : "Consider setting a lower daily limit to bring this back down.",
                          style: GoogleFonts.poppins(
                            fontSize: 12.0.sp,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Center(
                    child: Text(
                      "No usage data available for last week yet",
                      style: GoogleFonts.poppins(
                        fontSize: 13.0.sp,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _onBlockAll(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0066FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      "Change Time Limit",
                      style: GoogleFonts.poppins(
                        fontSize: 14.0.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        // "Social media Use high" warning banner hidden per request — kept
        // in place (not deleted) in case it's revisited later.
        // _buildWarningBanner(),
      ],
    );
  }
}

// ─── Duration picker dialog for Block All ───

class _BlockAllDurationDialog extends StatefulWidget {
  final int appCount;
  const _BlockAllDurationDialog({required this.appCount});

  @override
  State<_BlockAllDurationDialog> createState() =>
      _BlockAllDurationDialogState();
}

class _BlockAllDurationDialogState extends State<_BlockAllDurationDialog> {
  int _hours = 0;
  int _minutes = 30;

  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minCtrl;

  @override
  void initState() {
    super.initState();
    _hourCtrl = FixedExtentScrollController(initialItem: _hours);
    _minCtrl = FixedExtentScrollController(initialItem: _minutes ~/ 5);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  String get _description {
    if (_hours == 0 && _minutes == 0) return 'Select a duration';
    if (_hours == 0)
      return '${widget.appCount} apps will be locked for $_minutes min';
    if (_minutes == 0)
      return '${widget.appCount} apps will be locked for $_hours hr';
    return '${widget.appCount} apps will be locked for $_hours hr $_minutes min';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryColor,
                    AppColors.primaryColor.withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Block All ${widget.appCount} Apps',
                      style: AppTextStyles.headline6.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                children: [
                  // Description chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primaryColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: AppColors.primaryColor,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _description,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Scroll pickers
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildWheel(
                        label: 'Hrs',
                        count: 24,
                        selected: _hours,
                        controller: _hourCtrl,
                        onChanged: (i) => setState(() => _hours = i),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Text(
                          ' : ',
                          style: AppTextStyles.headline4.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                      _buildWheel(
                        label: 'Min',
                        count: 12,
                        selected: _minutes ~/ 5,
                        controller: _minCtrl,
                        valueLabel: (i) => (i * 5).toString().padLeft(2, '0'),
                        onChanged: (i) => setState(() => _minutes = i * 5),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  CommonButton(
                    text: 'Block All Apps',
                    onPressed: (_hours == 0 && _minutes == 0)
                        ? null
                        : () => Navigator.pop(
                            context,
                            Duration(hours: _hours, minutes: _minutes),
                          ),
                    width: double.infinity,
                    height: 50,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWheel({
    required String label,
    required int count,
    required int selected,
    required FixedExtentScrollController controller,
    required ValueChanged<int> onChanged,
    String Function(int)? valueLabel,
  }) {
    const itemH = 52.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyles.overline.copyWith(
            color: AppColors.primaryColor,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 90,
          height: itemH * 3,
          decoration: BoxDecoration(
            color: AppColors.backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: itemH,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: itemH,
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: 0.10),
                      border: Border.symmetric(
                        horizontal: BorderSide(
                          color: AppColors.primaryColor.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                  ),
                ),
                ListWheelScrollView.useDelegate(
                  controller: controller,
                  itemExtent: itemH,
                  diameterRatio: 1.4,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: onChanged,
                  childDelegate: ListWheelChildBuilderDelegate(
                    builder: (ctx, i) {
                      if (i < 0 || i >= count) return null;
                      final isSel = i == selected;
                      final lbl = valueLabel != null
                          ? valueLabel(i)
                          : i.toString().padLeft(2, '0');
                      return Center(
                        child: Text(
                          lbl,
                          style: isSel
                              ? AppTextStyles.headline4.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                )
                              : AppTextStyles.body1.copyWith(
                                  color: AppColors.textHint,
                                ),
                        ),
                      );
                    },
                    childCount: count,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class FilterTabs extends StatelessWidget {
  final int selectedIndex;
  final int blockedCount;
  final ValueChanged<int> onFilterChanged;

  const FilterTabs({
    super.key,
    required this.selectedIndex,
    required this.blockedCount,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = ["All", "Active", "Blocked ($blockedCount)"];

    return Row(
      children: List.generate(tabs.length, (index) {
        final isSelected = index == selectedIndex;

        return Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: GestureDetector(
            onTap: () => onFilterChanged(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xffE8EEFF) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryColor.withValues(alpha: 0.3)
                      : Colors.transparent,
                ),
              ),
              child: Text(
                tabs[index],
                style: TextStyle(
                  fontSize: 14.0.sp,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? AppColors.primaryColor : Colors.black87,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class AdvancedSegmentedTab extends StatefulWidget {
  final ValueChanged<int>? onTabChanged;
  const AdvancedSegmentedTab({super.key, this.onTabChanged});

  @override
  State<AdvancedSegmentedTab> createState() => _AdvancedSegmentedTabState();
}

class _AdvancedSegmentedTabState extends State<AdvancedSegmentedTab>
    with SingleTickerProviderStateMixin {
  late TabController _controller;
  final tabs = ["Yesterday", "Today", "Week"];

  @override
  void initState() {
    super.initState();
    _controller = TabController(
      initialIndex: 1,
      length: tabs.length,
      vsync: this,
    );
    _controller.addListener(() {
      if (!_controller.indexIsChanging) {
        widget.onTabChanged?.call(_controller.index);
        setState(() {});
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
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xffEEF3FF),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          // Sliding animation background
          AnimatedAlign(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: _alignmentForIndex(_controller.index),
            child: Container(
              width: MediaQuery.of(context).size.width / 3 - 12,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          // Actual tabs
          TabBar(
            dividerHeight: 0,
            controller: _controller,
            indicatorColor: Colors.transparent,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            labelColor: Colors.black,
            unselectedLabelColor: Colors.black87,
            labelStyle: TextStyle(
              fontSize: 16.0.sp,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: TextStyle(
              fontSize: 15.0.sp,
              fontWeight: FontWeight.w500,
            ),
            tabs: tabs.map((e) => Tab(text: e)).toList(),
            onTap: (index) {
              // Handled by listener
            },
          ),
        ],
      ),
    );
  }

  /// Converts index to alignment for sliding animation
  Alignment _alignmentForIndex(int index) {
    switch (index) {
      case 0:
        return Alignment.centerLeft;
      case 1:
        return Alignment.center;
      case 2:
        return Alignment.centerRight;
      default:
        return Alignment.center;
    }
  }
}
