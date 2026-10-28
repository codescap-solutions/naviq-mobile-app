import 'package:child_track/core/services/maps_proxy_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GeocodingService {
  final MapsProxyService _maps = MapsProxyService();

  // Reverse geocoding: Get address from coordinates
  Future<String?> getAddressFromCoordinates(LatLng location) =>
      _maps.reverseGeocode(location);

  // Place search using Text Search
  Future<List<PlaceSearchResult>> searchPlaces(String query) async {
    final results = await _maps.search(query);
    return results
        .map(
          (r) => PlaceSearchResult(
            name: r['name'] as String? ?? '',
            address: r['address'] as String? ?? '',
            latitude: (r['lat'] as num? ?? 0).toDouble(),
            longitude: (r['lng'] as num? ?? 0).toDouble(),
          ),
        )
        .toList();
  }
}

class PlaceSearchResult {
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  PlaceSearchResult({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  LatLng get location => LatLng(latitude, longitude);
}
