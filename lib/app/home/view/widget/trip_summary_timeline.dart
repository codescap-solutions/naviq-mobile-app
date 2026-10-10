import 'package:child_track/app/home/model/last_trip_model.dart';
import 'package:child_track/core/constants/figma_tokens.dart';
import 'package:child_track/core/utils/responsive_font.dart';
import 'package:child_track/core/widgets/resolved_place_label.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

/// Figma trip-detail sheet: "08:43 am - 09:20 am" heading, then
/// start place · ride card · end place on one vertical blue line.
class TripSummarySheetBody extends StatelessWidget {
  final TripSegment trip;
  final double distanceKm;
  final int durationMinutes;

  const TripSummarySheetBody({
    super.key,
    required this.trip,
    required this.distanceKm,
    required this.durationMinutes,
  });

  static const _slate = Color(0xFF4B5567);
  static const _line = Color(0xFF1A73F5);

  static DateTime? _parse(String raw) => DateTime.tryParse(raw)?.toLocal();

  /// "Today" / "Yesterday" / "08 Oct 2026" — the screen title.
  static String dateTitle(String startTime) {
    final d = _parse(startTime);
    if (d == null) return 'Trip';
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Today';
    if (day == today.subtract(Duration(days: 1))) return 'Yesterday';
    return DateFormat('dd MMM yyyy').format(d);
  }

  bool get _ongoing => trip.endTime.isEmpty || _parse(trip.endTime) == null;

  Widget _clock(String raw, {required bool endOfTrip}) {
    final big = FigmaText.poppins(22, weight: FontWeight.w700, lineHeight: 30);
    final small = FigmaText.poppins(20, lineHeight: 30);
    final d = _parse(raw);
    if (d == null) return Text(endOfTrip ? 'now' : '--', style: big);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: DateFormat('hh:mm').format(d), style: big),
          TextSpan(
            text: ' ${DateFormat('a').format(d).toLowerCase()}',
            style: small,
          ),
        ],
      ),
    );
  }

  IconData _placeIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('home')) return Icons.home_rounded;
    if (n.contains('school')) return Icons.school_rounded;
    if (n.contains('office') || n.contains('work'))
      return Icons.business_rounded;
    return Icons.location_on_rounded;
  }

  (String, IconData) get _mode {
    switch (trip.rideMode.toLowerCase()) {
      case 'walking':
        return ('Walk', Icons.directions_walk_rounded);
      case 'running':
        return ('Run', Icons.directions_run_rounded);
      case 'cycling':
        return ('Cycle', Icons.directions_bike_rounded);
      default:
        return ('Ride', Icons.directions_bus_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (modeLabel, modeIcon) = _mode;
    final avg = durationMinutes > 0
        ? (distanceKm / (durationMinutes / 60)).toStringAsFixed(1)
        : '0.0';
    final timeStyle = FigmaText.poppins(20, lineHeight: 28);

    Widget placeRow(String name, LatLng at, String time) => SizedBox(
      height: 32.w,
      child: Row(
        children: [
          Expanded(
            child: ResolvedPlaceLabel(
              placeName: name.isEmpty ? 'Unknown Location' : name,
              lat: at.latitude,
              lng: at.longitude,
              showDot: false,
              textStyle: FigmaText.poppins(20, lineHeight: 28),
            ),
          ),
          SizedBox(width: 12.w),
          Text(time, style: timeStyle),
        ],
      ),
    );

    Widget badge(IconData icon) => Container(
      width: 32.w,
      height: 32.w,
      decoration: BoxDecoration(
        color: _slate,
        borderRadius: BorderRadius.circular(10.w),
      ),
      child: Icon(icon, size: 18.w, color: Colors.white),
    );

    final startTime = _parse(trip.startTime);
    final endTime = _parse(trip.endTime);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _clock(trip.startTime, endOfTrip: false),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                child: Text('-', style: FigmaText.poppins(20, lineHeight: 30)),
              ),
              _clock(trip.endTime, endOfTrip: true),
            ],
          ),
        ),
        SizedBox(height: 28.w),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 32.w,
                child: Column(
                  children: [
                    badge(_placeIcon(trip.startPlace)),
                    Expanded(
                      child: Container(width: 1.5.w, color: _line),
                    ),
                    Container(
                      width: 24.w,
                      height: 24.w,
                      decoration: BoxDecoration(
                        color: _line,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.w),
                      ),
                      child: Icon(modeIcon, size: 12.w, color: Colors.white),
                    ),
                    Expanded(
                      child: Container(width: 1.5.w, color: _line),
                    ),
                    badge(_placeIcon(trip.endPlace)),
                  ],
                ),
              ),
              SizedBox(width: 28.w),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: 51.w - 24.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      placeRow(
                        trip.startPlace,
                        trip.startLocation,
                        startTime == null
                            ? ''
                            : DateFormat('HH:mm').format(startTime),
                      ),
                      SizedBox(height: 12.w),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(20.w),
                        decoration: BoxDecoration(
                          color: Color(0xFFEEF0F4),
                          borderRadius: BorderRadius.circular(20.w),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              modeLabel,
                              style: FigmaText.poppins(20, lineHeight: 28),
                            ),
                            SizedBox(height: 12.w),
                            Text(
                              '${distanceKm.toStringAsFixed(1)}km  ($durationMinutes'
                              'min)',
                              style: FigmaText.poppins(
                                14,
                                lineHeight: 20,
                                color: Color(0xFF0F1320),
                              ),
                            ),
                            SizedBox(height: 8.w),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12.w,
                                vertical: 6.w,
                              ),
                              decoration: BoxDecoration(
                                color: Color(0xFFE6F0FE),
                                borderRadius: BorderRadius.circular(8.w),
                              ),
                              child: Text(
                                'avg speed - $avg km/h',
                                style: FigmaText.poppins(
                                  14,
                                  lineHeight: 20,
                                  color: FigmaColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 22.w),
                      placeRow(
                        trip.endPlace,
                        trip.endLocation,
                        _ongoing
                            ? 'Now'
                            : (endTime == null
                                  ? ''
                                  : DateFormat('HH:mm').format(endTime)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
