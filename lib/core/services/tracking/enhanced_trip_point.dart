import 'package:child_track/core/utils/location_payload.dart';
import 'package:geolocator/geolocator.dart';

/// Full-fidelity trip point that captures every GPS metadata field.
/// Replaces the sparse {lat, lng, speed, accuracy, ts, battery} payload.
class EnhancedTripPoint {
  final double lat;
  final double lng;
  final double speed; // m/s — 0.0 placeholder when [speedKnown] is false
  /// false = the platform supplied no speed; [speed] is then NOT a measurement
  /// and is left out of the payload (the backend reads that as unknown).
  final bool speedKnown;
  final double accuracy; // horizontal accuracy radius in metres
  final String ts; // ISO 8601 UTC
  final int battery;

  // ── New fields ──────────────────────────────────────────────────────────
  final double bearing; // degrees 0–360 (heading)
  final double altitude; // metres above sea level
  final double speedAccuracy; // m/s accuracy (Android only, 0.0 on iOS)
  final double altitudeAccuracy; // metres (iOS 15+ / Android)
  final double headingAccuracy; // degrees (iOS only, 0.0 on Android)
  final int? floor; // indoor floor (usually null)
  final bool isMocked; // GPS mock detection

  const EnhancedTripPoint({
    required this.lat,
    required this.lng,
    required this.speed,
    this.speedKnown = true,
    required this.accuracy,
    required this.ts,
    required this.battery,
    required this.bearing,
    required this.altitude,
    required this.speedAccuracy,
    required this.altitudeAccuracy,
    required this.headingAccuracy,
    this.floor,
    required this.isMocked,
  });

  /// Build from a Geolocator [Position] + battery level.
  factory EnhancedTripPoint.fromPosition(Position pos, {int battery = 0}) {
    return EnhancedTripPoint(
      lat: pos.latitude,
      lng: pos.longitude,
      speed: knownSpeedMps(pos) ?? 0.0,
      speedKnown: knownSpeedMps(pos) != null,
      accuracy: pos.accuracy,
      ts: pos.timestamp.toUtc().toIso8601String(),
      battery: battery,
      bearing: pos.heading < 0 ? 0.0 : pos.heading,
      altitude: pos.altitude,
      speedAccuracy: pos.speedAccuracy,
      altitudeAccuracy: pos.altitudeAccuracy,
      headingAccuracy: pos.headingAccuracy,
      floor: pos.floor,
      isMocked: pos.isMocked,
    );
  }

  /// Serialise to the trip-tracking API payload.
  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    if (speedKnown) 'speed': speed,
    'speed_known': speedKnown,
    'accuracy': accuracy,
    'ts': ts,
    'battery': battery,
    'bearing': bearing,
    'altitude': altitude,
    'speed_accuracy': speedAccuracy,
    'altitude_accuracy': altitudeAccuracy,
    'heading_accuracy': headingAccuracy,
    if (floor != null) 'floor': floor,
    'is_mocked': isMocked,
  };

  /// Speed in km/h (convenience).
  double get speedKmh => speed * 3.6;
}
