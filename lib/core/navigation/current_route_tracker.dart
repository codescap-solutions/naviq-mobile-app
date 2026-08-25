import 'package:flutter/material.dart';

/// Tracks the name of the currently-visible top-level route across the
/// whole app (regardless of which Navigator pushed it), so app-wide chrome
/// (e.g. the floating upgrade banner) can hide itself on specific screens
/// like splash/auth/onboarding without every screen having to opt in.
///
/// Register a single instance via `MaterialApp(navigatorObservers: [...])`.
class CurrentRouteTracker extends NavigatorObserver {
  static final ValueNotifier<String?> currentRouteName = ValueNotifier(null);

  /// True whenever the current top-most route is a dialog/bottom-sheet
  /// (anything pushed via showDialog/showModalBottomSheet, both of which are
  /// PopupRoutes) rather than a full page. These routes are almost always
  /// unnamed (route.settings.name is null), so currentRouteName alone can't
  /// tell app-wide chrome like the floating upgrade banner to get out of the
  /// way — it would just see a null route name, which isn't in any
  /// screen-based exclusion list, and keep rendering (and intercepting
  /// taps) on top of the sheet/dialog. Confirmed on-device: the banner sat
  /// on top of the Help bottom sheet and ate taps meant for its "Call
  /// Support" row.
  static final ValueNotifier<bool> isModalRouteActive = ValueNotifier(false);

  void _update(Route<dynamic>? route) {
    currentRouteName.value = route?.settings.name;
    isModalRouteActive.value = route is PopupRoute;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _update(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _update(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _update(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _update(previousRoute);
  }
}
