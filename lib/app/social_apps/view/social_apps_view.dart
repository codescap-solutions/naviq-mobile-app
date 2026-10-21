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
import 'package:child_track/core/widgets/figma_app_bar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:child_track/core/constants/app_colors.dart';
import 'package:child_track/core/constants/app_sizes.dart';
import 'package:child_track/core/constants/app_text_styles.dart';
import 'package:child_track/core/services/subscription_feature_gate.dart';
import 'package:child_track/core/widgets/common_button.dart';
import 'package:child_track/core/widgets/social_apps_shimmer.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
      final yesterday = now.subtract(Duration(days: 1));
      final dateStr = yesterday.toIso8601String().split('T')[0];
      _bloc.add(FetchAppUsage(date: dateStr));
    } else if (index == 1) {
      // Today
      _bloc.add(FetchAppUsage(date: todayStr));
    } else {
      // Week — last 7 days (today to 6 days ago)
      final weekStart = now.subtract(Duration(days: 6));
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
        backgroundColor: Color(0xFFF7F8FA),
        appBar: figmaAppBar(context, title: 'Scroll'),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14.0.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 12.w),
                AdvancedSegmentedTab(
                  onTabChanged: (index) {
                    setState(() {
                      _selectedTabIndex = index;
                    });
                    _fetchDataForIndex(index);
                  },
                ),
                SizedBox(height: 20.w),
                Expanded(child: _buildAppsList()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Screen-time card — first item of the scrolling body, so it (and the
  /// app rows after it) slide up underneath the fixed tab bar.
  Widget _buildHeader() {
    return BlocBuilder<AppLockBloc, AppLockState>(
      builder: (context, lockState) {
        final lockedPackages = lockState is AppLockLoaded
            ? lockState.lockedPackages
            : <String>{};
        return BlocBuilder<SocialAppsBloc, SocialAppsState>(
          builder: (context, state) {
            // Collect all package names visible right now
            List<String> allPackages = [];
            if (state is SocialAppsLoaded) {
              final data = _selectedTabIndex == 2
                  ? state.data.summaryApps
                  : state.data.dailyUsage[state.selectedDate] ?? [];
              allPackages = data
                  .where((a) => !isEssentialApp(a.packageName, a.appName))
                  .map((a) => a.packageName)
                  .toList();
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
    );
  }

  Widget _buildAppsList() {
    return BlocBuilder<SocialAppsBloc, SocialAppsState>(
      builder: (context, state) {
        if (state is SocialAppsLoading) {
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildHeader(),
              SizedBox(height: 400.w, child: SocialAppsShimmer()),
            ],
          );
        } else if (state is SocialAppsError) {
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              _buildHeader(),
              Column(
                children: [
                  Text(state.message, style: AppTextStyles.body1),
                  SizedBox(height: AppSizes.spacingS.w),
                  CommonButton(
                    text: 'Retry',
                    onPressed: () => _fetchDataForIndex(_selectedTabIndex),
                  ),
                ],
              ),
            ],
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
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildHeader(),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 32.w),
                  child: Center(
                    child: Text(
                      'No usage data for this period',
                      style: AppTextStyles.textSecondary,
                    ),
                  ),
                ),
              ],
            );
          }

          // Apply Filter
          return BlocBuilder<AppLockBloc, AppLockState>(
            builder: (context, lockState) {
              final lockedPackages = lockState is AppLockLoaded
                  ? lockState.lockedPackages
                  : <String>{};

              final filteredData = dailyData.where((app) {
                if (_selectedFilterIndex == 0) return true; // All
                final isLocked = lockedPackages.contains(app.packageName);
                if (_selectedFilterIndex == 1) return !isLocked; // Active
                if (_selectedFilterIndex == 2) return isLocked; // Blocked
                return true;
              }).toList();

              if (filteredData.isEmpty) {
                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildHeader(),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 32.w),
                      child: Center(
                        child: Text(
                          _selectedFilterIndex == 1
                              ? 'No active apps'
                              : _selectedFilterIndex == 2
                              ? 'No blocked apps'
                              : 'No apps found',
                          style: AppTextStyles.textSecondary,
                        ),
                      ),
                    ),
                  ],
                );
              }

              final int maxUsage = filteredData
                  .map((a) => a.usageTime)
                  .fold(0, (m, v) => v > m ? v : m);

              return ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: filteredData.length + 2, // header + spacing
                itemBuilder: (context, listIndex) {
                  if (listIndex == 0) return _buildHeader();
                  final index = listIndex - 1;
                  if (index == filteredData.length) {
                    return Column(
                      children: [SizedBox(height: AppSizes.spacingL.w)],
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
                            usageFraction: maxUsage > 0
                                ? app.usageTime / maxUsage
                                : 0,
                            isLocked: isLocked,
                            lockable: !isEssentialApp(
                              app.packageName,
                              displayName,
                            ),
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
        return SizedBox.shrink();
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
  /// True when every visible app is already locked
  bool get _allBlocked =>
      widget.allPackages.isNotEmpty &&
      widget.allPackages.every((p) => widget.lockedPackages.contains(p));

  Future<void> _onBlockAll(BuildContext context) async {
    if (!_guardScreenTimeAction(context)) return;
    if (widget.allPackages.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No apps to block')));
      return;
    }

    // Show duration picker dialog
    final Duration? duration = await showModalBottomSheet<Duration>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
    widget.appLockBloc?.add(
      UnblockAllApps(
        packageNames: widget.allPackages
            .where(widget.lockedPackages.contains)
            .toList(),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removing time limit...'),
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
      final yesterday = now.subtract(Duration(days: 1));
      return "Yesterday · ${weekdays[yesterday.weekday % 7]}, ${months[yesterday.month - 1]} ${yesterday.day}";
    } else if (widget.selectedTabIndex == 1) {
      return "Today · ${weekdays[now.weekday % 7]}, ${months[now.month - 1]} ${now.day}";
    } else {
      final weekStart = now.subtract(Duration(days: 6));
      return "This Week · ${months[weekStart.month - 1]} ${weekStart.day} - ${months[now.month - 1]} ${now.day}";
    }
  }

  /// Single rounded track with a 25/50/75% divider overlay (Figma).
  Widget _buildProgressBar(double percentage, {required double height}) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        Widget divider(double at) => Positioned(
          left: w * at,
          top: 0.w,
          bottom: 0.w,
          child: Container(
            width: height > 8 ? 2 : 1.5,
            color: Colors.white.withValues(alpha: height > 8 ? 0.6 : 0.7),
          ),
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: Container(
            height: height,
            color: height > 8 ? Color(0xFFDDE1EA) : Color(0xFFEEF0F4),
            child: Stack(
              children: [
                Positioned(
                  left: 0.w,
                  top: 0.w,
                  bottom: 0.w,
                  width: w * percentage,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Color(0xFFF5A623),
                      borderRadius: BorderRadius.circular(height),
                    ),
                  ),
                ),
                divider(0.25),
                divider(0.50),
                divider(0.75),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      margin: EdgeInsets.only(bottom: 16.w),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFB7185), Color(0xFFF43F5E)], // Rose/coral gradient
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20.w),
        boxShadow: [
          BoxShadow(
            color: Color(0xFFF43F5E).withValues(alpha: 0.15),
            blurRadius: 10.w,
            offset: Offset(0, 4.w),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.yellow,
                  size: 20.w,
                ),
                Positioned(
                  bottom: 2.w,
                  child: Icon(
                    Icons.flash_on_rounded,
                    color: Colors.yellow,
                    size: 12.w,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 14.w),
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
                SizedBox(height: 2),
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
    final double hours = widget.totalUsageSeconds / 3600.0;
    final double percentage = (widget.totalUsageSeconds / limitSeconds).clamp(
      0.0,
      1.0,
    );
    final String hoursStr = hours.toStringAsFixed(1);

    // Comparison text
    final prevSeconds = widget.previousPeriodUsageSeconds;
    final double? prevHours = prevSeconds != null ? prevSeconds / 3600.0 : null;
    final double? diffHours = prevHours != null ? hours - prevHours : null;
    final bool isWeekTab = widget.selectedTabIndex == 2;

    String comparisonText = "";
    if (widget.selectedTabIndex == 0) {
      comparisonText = "-0.5 hours than previous day";
    } else if (widget.selectedTabIndex == 1) {
      comparisonText = "+1.6 hours than yesterday";
    } else if (diffHours != null) {
      final sign = diffHours >= 0 ? "+" : "-";
      comparisonText =
          "$sign${diffHours.abs().toStringAsFixed(1)}h vs last week";
    } else {
      comparisonText = "No data for last week";
    }

    final bool isWeek = isWeekTab;
    final String limitHoursText = isWeek ? '42' : '6';
    final String weekLimitText =
        "${(percentage * 100).toInt()}% of $limitHoursText hour Limit";

    final headerRow = Container(
      decoration: BoxDecoration(
        color: Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(8.w),
      ),
      padding: EdgeInsets.fromLTRB(8.w, 8.w, isWeek ? 12.w : 8.w, 8.w),
      child: Row(
        children: [
          isWeek
              ? Container(
                  width: 50.w,
                  height: 50.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Color(0xFFEBF3FF),
                    shape: BoxShape.circle,
                  ),
                  child: SvgPicture.asset(
                    'assets/icons/scroll_monitor_week.svg',
                    width: 20.w,
                    height: 20.w,
                  ),
                )
              : Container(
                  width: 40.w,
                  height: 40.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Color(0xFF0069F9).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8.w),
                  ),
                  child: SvgPicture.asset(
                    'assets/icons/scroll_monitor_day.svg',
                    width: 22.w,
                    height: 19.w,
                  ),
                ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Screen Time",
                  style: GoogleFonts.poppins(
                    fontSize: 16.0.sp,
                    fontWeight: FontWeight.w400,
                    height: 24 / 16,
                    letterSpacing: 0.2,
                    color: isWeek ? Color(0xFF16181A) : Colors.black,
                  ),
                ),
                Text(
                  _getFormattedDate(),
                  style: GoogleFonts.poppins(
                    fontSize: 12.0.sp,
                    fontWeight: FontWeight.w400,
                    height: 20 / 12,
                    letterSpacing: 0.2,
                    color: Color(0xFF9BA4B5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final valueRow = Row(
      textBaseline: TextBaseline.alphabetic,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      children: [
        Text(
          hoursStr,
          style: GoogleFonts.poppins(
            fontSize: 24.0.sp,
            fontWeight: FontWeight.w700,
            height: 28 / 24,
            color: Color(0xFF0F1320),
          ),
        ),
        SizedBox(width: 4.w),
        Text(
          isWeek ? "hrs used" : "h / $limitHoursText hours",
          style: GoogleFonts.poppins(
            fontSize: 12.0.sp,
            fontWeight: FontWeight.w400,
            height: 20 / 12,
            letterSpacing: 0.2,
            color: isWeek ? Color(0xFF0F1320) : Color(0xFF4A5267),
          ),
        ),
        Spacer(),
        Text(
          isWeek ? weekLimitText : comparisonText,
          style: GoogleFonts.poppins(
            fontSize: 12.0.sp,
            fontWeight: FontWeight.w400,
            height: 20 / 12,
            letterSpacing: 0.2,
            color: isWeek ? Color(0xFF2D3035) : Color(0xFFF78635),
          ),
        ),
      ],
    );

    final blockPill = Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: widget.allPackages.isEmpty
            ? null
            : () => allBlocked ? _onUnblockAll(context) : _onBlockAll(context),
        child: Container(
          height: 34.w,
          constraints: BoxConstraints(minWidth: 100.w),
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.w),
          decoration: BoxDecoration(
            color: allBlocked ? Color(0xFFEF4444) : Color(0xFF0069F9),
            borderRadius: BorderRadius.circular(44.w),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16.w,
                height: 16.w,
                child: allBlocked
                    ? Icon(
                        Icons.lock_open_rounded,
                        size: 16.w,
                        color: Color(0xFFF7F8FA),
                      )
                    : Center(
                        child: SvgPicture.asset(
                          'assets/icons/scroll_clock_white.svg',
                          width: 13.3.w,
                          height: 13.3.w,
                        ),
                      ),
              ),
              SizedBox(width: 5.w),
              Text(
                allBlocked ? "Remove Time Limit" : "Set New Limit",
                // height 1 + even leading: the text's visual centre sits on
                // the row's centre, level with the icon.
                textHeightBehavior: TextHeightBehavior(
                  leadingDistribution: TextLeadingDistribution.even,
                ),
                style: GoogleFonts.poppins(
                  fontSize: 14.0.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  letterSpacing: 0.2,
                  color: Color(0xFFF7F8FA),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14.w),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: isWeek ? 10 : 8,
                offset: Offset(0, 2.w),
              ),
            ],
          ),
          padding: isWeek
              ? EdgeInsets.all(12.w)
              : EdgeInsets.fromLTRB(20.w, 17.w, 20.w, 19.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              headerRow,
              SizedBox(height: isWeek ? 20 : 14),
              valueRow,
              SizedBox(height: isWeek ? 12 : 6),
              _buildProgressBar(percentage, height: isWeek ? 10 : 7),
              if (!isWeek) ...[SizedBox(height: 26.w), blockPill],
              if (isWeek) ...[
                SizedBox(height: 20.w),
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Color(0xFFEBF3FF),
                    borderRadius: BorderRadius.circular(14.w),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (diffHours != null && prevHours != null) ...[
                        Padding(
                          padding: EdgeInsets.all(16.w),
                          child: Column(
                            children: [
                              Text(
                                "${diffHours.abs().toStringAsFixed(1)} hr",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  fontSize: 32.0.sp,
                                  fontWeight: FontWeight.w700,
                                  height: 40 / 32,
                                  color: Color(0xFF16181A),
                                ),
                              ),
                              SizedBox(height: 4.w),
                              Text(
                                diffHours <= 0
                                    ? "reduced from last week"
                                    : "increased from last week",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  fontSize: 16.0.sp,
                                  fontWeight: FontWeight.w400,
                                  height: 24 / 16,
                                  letterSpacing: 0.2,
                                  color: Color(0xFF2D3035),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 8.w),
                        Text(
                          "$hoursStr hr this week  ·  ${prevHours.toStringAsFixed(1)} hr last week",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 12.0.sp,
                            fontWeight: FontWeight.w400,
                            height: 20 / 12,
                            letterSpacing: 0.2,
                            color: Color(0xFF707784),
                          ),
                        ),
                        SizedBox(height: 8.w),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14.w,
                            vertical: 12.w,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12.w),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                diffHours <= 0
                                    ? "New Limit, New Achievement"
                                    : "Screen Time Trending Up",
                                style: GoogleFonts.poppins(
                                  fontSize: 20.0.sp,
                                  fontWeight: FontWeight.w400,
                                  height: 28 / 20,
                                  letterSpacing: 0.2,
                                  color: Color(0xFF2D3035),
                                ),
                              ),
                              SizedBox(height: 4.w),
                              Text(
                                diffHours <= 0
                                    ? "A new limit can help bring the screen time down even more."
                                    : "Consider setting a lower daily limit to bring this back down.",
                                style: GoogleFonts.poppins(
                                  fontSize: 12.0.sp,
                                  fontWeight: FontWeight.w400,
                                  height: 20 / 12,
                                  letterSpacing: 0.2,
                                  color: Color(0xFF2D3035),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.w),
                          child: Center(
                            child: Text(
                              "No usage data available for last week yet",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 12.0.sp,
                                fontWeight: FontWeight.w400,
                                height: 20 / 12,
                                letterSpacing: 0.2,
                                color: Color(0xFF707784),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 20.w),
                GestureDetector(
                  onTap: () => allBlocked
                      ? _onUnblockAll(context)
                      : _onBlockAll(context),
                  child: Container(
                    height: 56.w,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: allBlocked ? Color(0xFFEF4444) : Color(0xFF0069F9),
                      borderRadius: BorderRadius.circular(14.w),
                    ),
                    child: Text(
                      allBlocked ? "Remove Time Limit" : "Change Time Limit",
                      style: GoogleFonts.poppins(
                        fontSize: 20.0.sp,
                        fontWeight: FontWeight.w400,
                        height: 28 / 20,
                        letterSpacing: 0.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 16.w),
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

  /// Figma "counter" bottom sheet: white, 30px top radius, two bold wheels
  /// with Hrs / Min labels over a pale-blue selection band, 346x56 "Set".
  @override
  Widget build(BuildContext context) {
    final disabled = _hours == 0 && _minutes == 0;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16.w,
        12.w,
        16.w,
        24.w + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30.w),
          topRight: Radius.circular(30.w),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 195.w,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 57.w,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFB9E2FF).withValues(alpha: 0.6),
                        Color(0xFFB9E2FF).withValues(alpha: 0.35),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(8.w),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildWheel(
                      count: 24,
                      selected: _hours,
                      controller: _hourCtrl,
                      onChanged: (i) => setState(() => _hours = i),
                    ),
                    _unitLabel('Hrs'),
                    _buildWheel(
                      count: 12,
                      selected: _minutes ~/ 5,
                      controller: _minCtrl,
                      valueLabel: (i) => (i * 5).toString().padLeft(2, '0'),
                      onChanged: (i) => setState(() => _minutes = i * 5),
                    ),
                    _unitLabel('Min'),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 4.w),
          Align(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 346.w),
              child: GestureDetector(
                onTap: disabled
                    ? null
                    : () => Navigator.pop(
                        context,
                        Duration(hours: _hours, minutes: _minutes),
                      ),
                child: Opacity(
                  opacity: disabled ? 0.5 : 1,
                  child: Container(
                    height: 56.w,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Color(0xFF0069F9),
                      borderRadius: BorderRadius.circular(14.w),
                    ),
                    child: Text(
                      'Set',
                      style: GoogleFonts.poppins(
                        fontSize: 20.0.sp,
                        fontWeight: FontWeight.w400,
                        height: 28 / 20,
                        letterSpacing: 0.2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unitLabel(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 20.0.sp,
          fontWeight: FontWeight.w400,
          height: 28 / 20,
          letterSpacing: 0.2,
          color: Color(0xFF9BA4B5),
        ),
      ),
    );
  }

  Widget _buildWheel({
    required int count,
    required int selected,
    required FixedExtentScrollController controller,
    required ValueChanged<int> onChanged,
    String Function(int)? valueLabel,
  }) {
    return SizedBox(
      width: 73.w,
      height: 195.w,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 65,
        diameterRatio: 100,
        perspective: 0.0001,
        physics: FixedExtentScrollPhysics(),
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
                style: GoogleFonts.poppins(
                  fontSize: 40.0.sp,
                  fontWeight: FontWeight.w700,
                  height: 52 / 40,
                  color: isSel
                      ? Colors.black
                      : Colors.black.withValues(alpha: 0.08),
                ),
              ),
            );
          },
          childCount: count,
        ),
      ),
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
          padding: EdgeInsets.only(right: 8.0.w),
          child: GestureDetector(
            onTap: () => onFilterChanged(index),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 250),
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.w),
              decoration: BoxDecoration(
                color: isSelected ? Color(0xffE8EEFF) : Colors.white,
                borderRadius: BorderRadius.circular(12.w),
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
      height: 40.w,
      padding: EdgeInsets.all(3.w),
      decoration: BoxDecoration(
        color: Color(0xFFEBF3FF),
        borderRadius: BorderRadius.circular(14.w),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          // Figma: three equal buttons with a 4px gap inside 3px padding.
          final double tabW = (box.maxWidth - 8) / 3;
          return Stack(
            children: [
              // Sliding selection background
              AnimatedPositioned(
                duration: Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: _controller.index * (tabW + 4),
                top: 0.w,
                bottom: 0.w,
                width: tabW,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14.w),
                  ),
                ),
              ),

              // Actual tabs
              TabBar(
                dividerHeight: 0,
                controller: _controller,
                indicatorColor: Colors.transparent,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                labelColor: Color(0xFF0F1320),
                unselectedLabelColor: Color(0xFF0F1320),
                labelPadding: EdgeInsets.zero,
                labelStyle: GoogleFonts.poppins(
                  fontSize: 16.0.sp,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                ),
                unselectedLabelStyle: GoogleFonts.poppins(
                  fontSize: 16.0.sp,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.2,
                ),
                tabs: tabs.map((e) => Tab(text: e)).toList(),
                onTap: (index) {
                  // Handled by listener
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
