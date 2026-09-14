import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart';

/// Result from Google Directions — polyline plus human-readable ETA/distance.
class DrivingRouteResult {
  const DrivingRouteResult({
    required this.points,
    required this.distanceText,
    required this.durationText,
    required this.distanceMeters,
    this.durationSeconds = 0,
  });

  final List<LatLng> points;
  final String distanceText;
  final String durationText;
  final int distanceMeters;
  final int durationSeconds;
}

/// Road routes from the Google Directions API using the Maps key from
/// house/config/config.php (via the site maps proxy), with the app key as fallback.
class GoogleRoutes {
  static const String _fallbackKey = 'AIzaSyDH0JpnMofvCFnx9byn6TUm_GV6YW9onZU';
  static String? _cachedKey;

  static Future<String> apiKey() async {
    if (_cachedKey != null && _cachedKey!.isNotEmpty) return _cachedKey!;
    final fromServer = (await ApiService.getGoogleMapsApiKey())?.trim() ?? '';
    _cachedKey = fromServer.isNotEmpty ? fromServer : _fallbackKey;
    return _cachedKey!;
  }

  /// Returns the road polyline between two points, or empty when unavailable.
  static Future<List<LatLng>> fetchDrivingRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final details = await fetchDrivingRouteDetails(
      origin: origin,
      destination: destination,
    );
    return details?.points ?? const [];
  }

  /// Full route with distance + duration (Yango-style trip preview).
  /// Uses step polylines so road corners/turns stay sharp, not a smoothed line.
  static Future<DrivingRouteResult?> fetchDrivingRouteDetails({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final key = await apiKey();
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${origin.latitude},${origin.longitude}'
        '&destination=${destination.latitude},${destination.longitude}'
        '&mode=driving&key=$key',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List? ?? [];
      if (data['status'] != 'OK' || routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final leg = (route['legs'] as List?)?.first as Map<String, dynamic>?;
      final dist = leg?['distance'] as Map<String, dynamic>?;
      final dur = leg?['duration'] as Map<String, dynamic>?;

      // Prefer per-step geometry so turns and street corners are visible.
      final points = <LatLng>[];
      final steps = leg?['steps'] as List? ?? [];
      for (final raw in steps) {
        if (raw is! Map) continue;
        final enc = raw['polyline']?['points']?.toString() ?? '';
        if (enc.isEmpty) continue;
        final stepPts = decodePolyline(enc);
        if (stepPts.isEmpty) continue;
        if (points.isNotEmpty &&
            points.last.latitude == stepPts.first.latitude &&
            points.last.longitude == stepPts.first.longitude) {
          points.addAll(stepPts.skip(1));
        } else {
          points.addAll(stepPts);
        }
      }

      if (points.isEmpty) {
        final encoded =
            route['overview_polyline']?['points']?.toString() ?? '';
        points.addAll(decodePolyline(encoded));
      }

      return DrivingRouteResult(
        points: points,
        distanceText: dist?['text']?.toString() ?? '',
        durationText: dur?['text']?.toString() ?? '',
        distanceMeters: (dist?['value'] as num?)?.toInt() ?? 0,
        durationSeconds: (dur?['value'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static List<LatLng> decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      for (final isLng in [false, true]) {
        int result = 0, shift = 0, b;
        do {
          b = encoded.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20);
        final delta = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
        if (isLng) {
          lng += delta;
        } else {
          lat += delta;
        }
      }
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
