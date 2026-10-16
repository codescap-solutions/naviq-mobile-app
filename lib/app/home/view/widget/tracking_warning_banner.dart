import 'package:child_track/app/home/model/child_tracking_snapshot.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:flutter/material.dart';

/// Parent-side explanation for a child whose location is frozen because of a
/// problem the backend has actual evidence for (see [TrackingWarning]).
///
/// The server's own wording ([UiDirective.bannerMessage]) is used when it is
/// tagged for this problem (`action_required == fix_child_device_clock`); the
/// fallback text covers the case where the location is not (yet) stale and the
/// directive carries no message.
class TrackingWarningBanner extends StatelessWidget {
  final ChildTrackingSnapshot snapshot;

  const TrackingWarningBanner({super.key, required this.snapshot});

  static const _clockFallback =
      "Child's phone clock is wrong, so its location can't be shown live. "
      'Ask them to turn on automatic date & time.';

  /// Null when there is nothing evidenced to warn about.
  static String? messageFor(ChildTrackingSnapshot snapshot) {
    final warning = snapshot.trackingWarning;
    if (warning == null || !warning.isClockSkew) return null;
    final directive = snapshot.uiDirective;
    return directive.actionRequired == 'fix_child_device_clock' && directive.bannerMessage.isNotEmpty
        ? directive.bannerMessage
        : _clockFallback;
  }

  @override
  Widget build(BuildContext context) {
    final message = messageFor(snapshot);
    if (message == null) return const SizedBox.shrink();
    return Container(
      key: const Key('tracking_warning_banner'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.w),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12.w),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 16.w, color: const Color(0xFFB91C1C)),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11.0.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF7F1D1D),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
