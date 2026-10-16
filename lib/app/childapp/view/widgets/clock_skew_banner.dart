import 'dart:async';
import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:child_track/core/services/tracking/clock_skew_monitor.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:flutter/material.dart';

/// Shown on the child's screen while the backend says this phone's clock is
/// wrong (its location is being refused for that reason). Disappears by itself
/// once a live point is accepted again — see [ClockSkewMonitor].
class ClockSkewBanner extends StatefulWidget {
  final double topExtra;
  final ClockSkewMonitor? monitor;
  final Duration pollEvery;
  final bool? isIOS;

  /// Opens the system Date & time settings (Android). Injectable for tests.
  final Future<void> Function()? onOpenSettings;

  const ClockSkewBanner({
    super.key,
    this.topExtra = 0,
    this.monitor,
    this.pollEvery = const Duration(seconds: 15),
    this.isIOS,
    this.onOpenSettings,
  });

  static Future<void> openDateSettings() =>
      const AndroidIntent(action: 'android.settings.DATE_SETTINGS').launch();

  @override
  State<ClockSkewBanner> createState() => _ClockSkewBannerState();
}

class _ClockSkewBannerState extends State<ClockSkewBanner> with WidgetsBindingObserver {
  ClockSkewStatus? _status;
  Timer? _timer;

  ClockSkewMonitor get _monitor => widget.monitor ?? ClockSkewMonitor.instance;
  bool get _isIOS => widget.isIOS ?? Platform.isIOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(widget.pollEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the Settings app: re-check straight away.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await _monitor.read();
    if (!mounted) return;
    if ((status == null) != (_status == null)) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    if (_status == null) return const SizedBox.shrink();
    final message = _isIOS
        ? "This phone's date & time looks wrong, so your location can't be shared. "
              'Open Settings › General › Date & Time and turn on Set Automatically.'
        : "This phone's date & time looks wrong, so your location can't be shared. "
              'Turn on automatic date & time.';
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8 + widget.topExtra,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule_rounded, color: Color(0xFFDC2626), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  key: const Key('clock_skew_message'),
                  style: TextStyle(
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF7F1D1D),
                  ),
                ),
              ),
              if (!_isIOS)
                GestureDetector(
                  key: const Key('clock_skew_fix'),
                  onTap: () => (widget.onOpenSettings ?? ClockSkewBanner.openDateSettings)(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Fix',
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
