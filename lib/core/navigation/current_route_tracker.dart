import 'package:flutter/material.dart';

/// Tracks the name of the currently-visible top-level route across the
/// whole app (regardless of which Navigator pushed it), so app-wide chrome
/// (e.g. the floating upgrade banner) can hide itself on specific screens
/// like splash/auth/onboarding without every screen having to opt in.
///
/// Register a single instance via `MaterialApp(navigatorObservers: [...])`.
class CurrentRouteTracker extends NavigatorObserver {
  static final ValueNotifier<String?> currentRouteName = ValueNotifier(null);

  void _update(Route<dynamic>? route) {
    currentRouteName.value = route?.settings.name;
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
