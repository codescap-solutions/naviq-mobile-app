import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../di/injector.dart';
import '../utils/app_logger.dart';
import 'api_endpoints.dart';
import 'dio_client.dart';

/// Place search, address lookup and driving routes go through our server: the Maps
/// key bundled in the app is Android/iOS-restricted, which these REST APIs can't
/// satisfy. Every method returns an empty/null result on failure, never throws.
class MapsProxyService {
  DioClient get _dio => injector<DioClient>();

  Future<dynamic> _get(String path, Map<String, dynamic> query) async {
    try {
      final response = await _dio.get(path, queryParameters: query);
      final body = response.data;
      if (body is Map && body['is_success'] == true) return body['data'];
    } catch (e) {
      AppLogger.error('MapsProxyService $path: $e');
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> autocomplete(
    String input, {
    String? session,
  }) async {
    final data = await _get(ApiEndpoints.mapsAutocomplete, {
      'input': input,
      if (session != null) 'session': session,
    });
    return data is List ? data.cast<Map<String, dynamic>>() : [];
  }

  Future<LatLng?> placeLocation(String placeId, {String? session}) async {
    final data = await _get(ApiEndpoints.mapsPlace, {
      'place_id': placeId,
      if (session != null) 'session': session,
    });
    if (data is! Map) return null;
    return LatLng(
      (data['lat'] as num).toDouble(),
      (data['lng'] as num).toDouble(),
    );
  }

  Future<List<Map<String, dynamic>>> search(String query) async {
    final data = await _get(ApiEndpoints.mapsSearch, {'query': query});
    return data is List ? data.cast<Map<String, dynamic>>() : [];
  }

  Future<String?> reverseGeocode(LatLng point) async {
    final data = await _get(ApiEndpoints.mapsGeocode, {
      'lat': point.latitude,
      'lng': point.longitude,
    });
    return data is Map ? data['address'] as String? : null;
  }

  Future<List<LatLng>> drivingRoute(LatLng from, LatLng to) async {
    final data = await _get(ApiEndpoints.mapsRoute, {
      'origin_lat': from.latitude,
      'origin_lng': from.longitude,
      'dest_lat': to.latitude,
      'dest_lng': to.longitude,
    });
    final encoded = data is Map ? data['polyline'] as String? : null;
    if (encoded == null || encoded.isEmpty) return [];
    return PolylinePoints.decodePolyline(
      encoded,
    ).map((p) => LatLng(p.latitude, p.longitude)).toList();
  }
}
