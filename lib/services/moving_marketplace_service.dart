import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// REST client for the Laravel moving API (`api/moving-laravel`).
///
/// Routes are under `/api/v1`. Set [baseUrl] to the Laravel `public` URL
/// (no trailing slash), e.g. `https://houseforrent.site/api/moving-laravel/public`.
class MovingMarketplaceService {
  /// Public URL of the Laravel app (document root = `public/`).
  static const String baseUrl =
      'https://houseforrent.site/api/moving-laravel/public';

  /// Must match `API_SHARED_SECRET` in the Laravel `.env`.
  /// Leave empty while the server allows open mode.
  static const String apiSharedSecret = '';

  static String get _apiRoot => '$baseUrl/api/v1';

  static int? _userIdFromJwt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      var normalized = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      final mod = normalized.length % 4;
      if (mod == 1) return null;
      if (mod == 2) normalized += '==';
      if (mod == 3) normalized += '=';
      final payload = jsonDecode(utf8.decode(base64.decode(normalized)));
      if (payload is! Map) return null;
      final exp = payload['exp'];
      if (exp is num && exp < DateTime.now().millisecondsSinceEpoch / 1000) {
        return null;
      }
      final id = payload['id'];
      if (id is int) return id;
      return int.tryParse(id?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  static Future<({String userId, String token})> _resolveSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString('token') ?? '').trim();
    var userId = (prefs.getString('user_id') ?? '').trim();

    if (userId.isEmpty && token.isNotEmpty) {
      final fromJwt = _userIdFromJwt(token);
      if (fromJwt != null && fromJwt > 0) {
        userId = fromJwt.toString();
        await prefs.setString('user_id', userId);
      }
    }

    if (userId.isEmpty && token.isNotEmpty) {
      try {
        final profile = await ApiService.getProfile();
        userId =
            profile['id']?.toString() ??
            profile['user']?['id']?.toString() ??
            '';
        if (userId.isNotEmpty) {
          await prefs.setString('user_id', userId);
        }
      } catch (_) {}
    }

    if (userId.isEmpty) {
      throw Exception('Please log in before using moving bookings.');
    }

    return (userId: userId, token: token);
  }

  static Future<Map<String, String>> _headers(
    ({String userId, String token}) session,
  ) async {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-user-id': session.userId,
      if (session.token.isNotEmpty) 'Authorization': 'Bearer ${session.token}',
      if (apiSharedSecret.isNotEmpty) 'x-api-key': apiSharedSecret,
    };
  }

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final session = await _resolveSession();
    final uri = Uri.parse('$_apiRoot$path').replace(queryParameters: query);
    final headers = await _headers(session);
    late http.Response response;

    final payload = <String, dynamic>{
      if (body != null) ...body,
      if (method == 'POST' || method == 'PATCH') 'user_id': session.userId,
    };

    // LiteSpeed on houseforrent.site returns HTML 403 for POST/PATCH with an
    // empty body. Always send at least `{}` so accept/start/cancel reach Laravel.
    final encodedBody =
        (method == 'POST' || method == 'PATCH') ? jsonEncode(payload) : null;

    try {
      switch (method) {
        case 'GET':
          response = await http.get(
            uri.replace(
              queryParameters: {
                ...uri.queryParameters,
                if ((uri.queryParameters['user_id'] ?? '').isEmpty)
                  'user_id': session.userId,
              },
            ),
            headers: headers,
          );
          break;
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: encodedBody,
          );
          break;
        case 'PATCH':
          response = await http.patch(
            uri,
            headers: headers,
            body: encodedBody,
          );
          break;
        default:
          throw Exception('Unsupported method $method');
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('Unsupported')) rethrow;
      if (e is Exception && e.toString().contains('Please log in')) rethrow;
      throw Exception(
        'Could not reach the moving API at $baseUrl. '
        'Is api/moving-laravel deployed and reachable?',
      );
    }

    final trimmed = response.body.trimLeft();
    final looksJson = trimmed.startsWith('{') || trimmed.startsWith('[');
    if (!looksJson) {
      throw Exception(
        'Moving API blocked or unavailable (HTTP ${response.statusCode}). '
        'Try again in a moment.',
      );
    }

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
        'Moving API returned invalid JSON (HTTP ${response.statusCode}).',
      );
    }

    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        decoded['status'] == 'success') {
      return decoded;
    }

    final code = (decoded['code'] ?? '').toString();
    final message = decoded['message']?.toString() ??
        'Moving request failed (HTTP ${response.statusCode}).';
    if (code == 'login_required' || response.statusCode == 401) {
      throw Exception('Please log in before using moving bookings.');
    }

    if (response.statusCode >= 500) {
      final lower = message.toLowerCase();
      if (lower.contains('sqlite') ||
          lower.contains('sqlstate') ||
          lower.contains('no such table')) {
        throw Exception(
          'Moving service database is not configured on the server. '
          'Please try again later.',
        );
      }
    }

    throw Exception(message);
  }

  static Future<Map<String, dynamic>> createBooking({
    required Map<String, dynamic> pickup,
    required Map<String, dynamic> dropoff,
    required String movingDate,
    String? movingTime,
    required String itemDescription,
    required String contactPhone,
    double? tenantOffer,
  }) async {
    final res = await _request(
      'POST',
      '/bookings',
      body: {
        'pickup': pickup,
        'dropoff': dropoff,
        'moving_date': movingDate,
        if (movingTime != null && movingTime.isNotEmpty)
          'moving_time': movingTime,
        'item_description': itemDescription,
        'contact_phone': contactPhone,
        if (tenantOffer != null) 'tenant_offer': tenantOffer,
      },
    );
    return Map<String, dynamic>.from(res['data']?['booking'] ?? {});
  }

  static Future<List<Map<String, dynamic>>> listBookings({
    int page = 1,
    int limit = 30,
  }) async {
    final res = await _request(
      'GET',
      '/bookings',
      query: {'page': '$page', 'limit': '$limit'},
    );
    final list = res['data']?['bookings'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> getBooking(int bookingId) async {
    final res = await _request('GET', '/bookings/$bookingId');
    return Map<String, dynamic>.from(res['data']?['booking'] ?? {});
  }

  /// Driver: record that this open request was opened / looked at.
  static Future<void> markBookingViewed(int bookingId) async {
    try {
      await _request('POST', '/bookings/$bookingId/view');
    } catch (_) {
      // Non-blocking for driver UX.
    }
  }

  /// Tenant: drivers who viewed an open request.
  /// By default only those who have **not** sent a price yet (live watching).
  static Future<Map<String, dynamic>> listBookingViews(
    int bookingId, {
    bool notRespondingOnly = true,
  }) async {
    final res = await _request(
      'GET',
      '/bookings/$bookingId/views',
      query: {
        'not_responding': notRespondingOnly ? '1' : '0',
      },
    );
    final data = res['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {
      'viewers': <Map<String, dynamic>>[],
      'count': 0,
      'seen_not_responding': 0,
      'seen_total': 0,
      'responded_count': 0,
    };
  }

  static Future<Map<String, dynamic>> unlockBooking(int bookingId) async {
    final res = await _request('POST', '/bookings/$bookingId/unlock');
    return Map<String, dynamic>.from(res['data'] ?? {});
  }

  static Future<void> cancelBooking(int bookingId) async {
    await _request('POST', '/bookings/$bookingId/cancel');
  }

  /// Available drivers near a point (for the tenant searching map).
  static Future<List<Map<String, dynamic>>> listNearbyDrivers({
    required double lat,
    required double lng,
    double radiusKm = 15,
  }) async {
    final res = await _request(
      'GET',
      '/drivers/nearby',
      query: {
        'lat': '$lat',
        'lng': '$lng',
        'radius_km': '$radiusKm',
      },
    );
    final list = res['data']?['drivers'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> submitOffer({
    required int bookingId,
    required double amount,
    String? note,
    int? driverId,
  }) async {
    final res = await _request(
      'POST',
      '/bookings/$bookingId/offers',
      body: {
        'amount': amount,
        if (note != null && note.isNotEmpty) 'note': note,
        if (driverId != null) 'driver_id': driverId,
      },
    );
    return Map<String, dynamic>.from(res['data']?['offer'] ?? {});
  }

  static Future<List<Map<String, dynamic>>> listOffers({
    required int bookingId,
    int? driverId,
  }) async {
    final res = await _request(
      'GET',
      '/bookings/$bookingId/offers',
      query: {
        if (driverId != null) 'driver_id': '$driverId',
      },
    );
    final list = res['data']?['offers'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> acceptOffer({
    required int bookingId,
    required int offerId,
  }) async {
    final res = await _request(
      'POST',
      '/bookings/$bookingId/offers/$offerId/accept',
    );
    final data = res['data'];
    if (data is Map && data['booking'] is Map) {
      return Map<String, dynamic>.from(data['booking'] as Map);
    }
    if (data is Map && data['id'] != null) {
      return Map<String, dynamic>.from(data);
    }
    // Fallback — caller can verify via getBooking.
    return <String, dynamic>{'id': bookingId};
  }

  static Future<void> rejectOffer({
    required int bookingId,
    required int offerId,
  }) async {
    await _request('POST', '/bookings/$bookingId/offers/$offerId/reject');
  }

  // ── Furniture / rental shifting fare (must match config/moving.php) ─────
  // Not a taxi — minimum K400. Night (20:00–05:59) costs more than day.

  static const double minFare = 400;
  static const double dayBaseFare = 400;
  static const double dayPerKm = 25;
  static const double nightBaseFare = 500;
  static const double nightPerKm = 35;

  /// True for night furniture-move rates (20:00–05:59 local time).
  static bool isNightRate([DateTime? at]) {
    final h = (at ?? DateTime.now()).hour;
    return h >= 20 || h < 6;
  }

  static double get baseFare => isNightRate() ? nightBaseFare : dayBaseFare;
  static double get perKmRate => isNightRate() ? nightPerKm : dayPerKm;

  static String farePeriodLabel([DateTime? at]) => isNightRate(at)
      ? 'Night rate · furniture move'
      : 'Day rate · furniture move';

  static double distanceKm({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    const earth = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
    return earth * 2 * math.atan2(math.sqrt(a.toDouble()), math.sqrt(1 - a.toDouble()));
  }

  /// Base + per-km, rounded to K5, never below [minFare].
  static double estimateFare(double km, {DateTime? at}) {
    final night = isNightRate(at);
    final base = night ? nightBaseFare : dayBaseFare;
    final perKm = night ? nightPerKm : dayPerKm;
    final raw = ((base + perKm * km) / 5).round() * 5.0;
    return raw < minFare ? minFare : raw;
  }

  /// Yellow avatar URL when the API has no photo yet.
  static String driverAvatarUrl({String? name, String? photoUrl}) {
    var photo = (photoUrl ?? '').trim();
    if (photo.isNotEmpty) {
      if (!photo.startsWith('http://') && !photo.startsWith('https://')) {
        photo = 'https://houseforrent.site/${photo.replaceFirst(RegExp(r'^/+'), '')}';
      }
      return photo;
    }
    final label = (name ?? 'Driver').trim().isEmpty ? 'Driver' : name!.trim();
    return 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(label)}'
        '&background=FFC107&color=111111&size=256&bold=true';
  }

  /// Upload face/profile photo shown to tenants (not licence/NRC).
  static Future<Map<String, dynamic>> uploadDriverProfilePhoto(
    String filePath,
  ) async {
    final endpoints = <(String, String)>[
      ('POST', '/drivers/me/photo'),
      ('POST', '/drivers/me/profile'),
      ('PATCH', '/drivers/me/profile'),
    ];
    Object? lastError;
    for (final entry in endpoints) {
      try {
        final session = await _resolveSession();
        final headers = await _headers(session);
        headers.remove('Content-Type');
        final request = http.MultipartRequest(
          entry.$1,
          Uri.parse('$_apiRoot${entry.$2}'),
        );
        request.headers.addAll(headers);
        request.files.add(await http.MultipartFile.fromPath('photo', filePath));
        final streamed = await request.send();
        final response = await http.Response.fromStream(streamed);
        final trimmed = response.body.trimLeft();
        if (!trimmed.startsWith('{')) {
          throw Exception(
            'Profile photo upload failed (HTTP ${response.statusCode}).',
          );
        }
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final msg = decoded['message']?.toString().toLowerCase() ?? '';
        if (response.statusCode == 404 || msg.contains('could not be found')) {
          throw Exception(decoded['message']?.toString() ?? 'not found');
        }
        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            decoded['status'] == 'error') {
          throw Exception(
            decoded['message']?.toString() ?? 'Profile photo upload failed.',
          );
        }
        return Map<String, dynamic>.from(decoded['data'] as Map? ?? decoded);
      } catch (e) {
        lastError = e;
        final msg = e.toString().toLowerCase();
        if (!msg.contains('could not be found') &&
            !msg.contains('not found') &&
            !msg.contains('http 404')) {
          rethrow;
        }
      }
    }
    throw Exception(
      lastError?.toString().replaceFirst('Exception: ', '') ??
          'Profile photo upload failed.',
    );
  }

  static Future<Map<String, dynamic>> sendMessage({
    required int bookingId,
    required String message,
    int? driverId,
  }) async {
    final res = await _request(
      'POST',
      '/bookings/$bookingId/messages',
      body: {
        'message': message,
        if (driverId != null) 'driver_id': driverId,
      },
    );
    return Map<String, dynamic>.from(res['data']?['message'] ?? {});
  }

  static Future<List<Map<String, dynamic>>> listMessages({
    required int bookingId,
    int? driverId,
    int afterId = 0,
  }) async {
    final res = await _request(
      'GET',
      '/bookings/$bookingId/messages',
      query: {
        if (driverId != null) 'driver_id': '$driverId',
        'after_id': '$afterId',
      },
    );
    final list = res['data']?['messages'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> startRide(int bookingId) async {
    // Prefer start-ride (deployed alias). Fall back to /start for older hosts.
    try {
      final res = await _request('POST', '/bookings/$bookingId/start-ride');
      return Map<String, dynamic>.from(res['data']?['booking'] ?? {});
    } catch (e) {
      final msg = e.toString();
      // Only fall back when the new route is missing on the server.
      if (!msg.contains('did not respond') &&
          !msg.contains('404') &&
          !msg.contains('Not Found') &&
          !msg.contains('could not be found')) {
        rethrow;
      }
      final res = await _request('POST', '/bookings/$bookingId/start');
      return Map<String, dynamic>.from(res['data']?['booking'] ?? {});
    }
  }

  static Future<Map<String, dynamic>> markArrived(int bookingId) async {
    final res = await _request('POST', '/bookings/$bookingId/arrived');
    return Map<String, dynamic>.from(res['data']?['booking'] ?? {});
  }

  static Future<void> completeBooking(int bookingId) async {
    await _request('POST', '/bookings/$bookingId/complete');
  }

  static Future<void> rateDriver({
    required int bookingId,
    required int rating,
    String? comment,
  }) async {
    await _request(
      'POST',
      '/bookings/$bookingId/rating',
      body: {
        'rating': rating,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      },
    );
  }

  static Future<Map<String, dynamic>> getDriverMe() async {
    final res = await _request('GET', '/drivers/me');
    return Map<String, dynamic>.from(res['data']?['driver'] ?? {});
  }

  /// Upload driver’s licence photo OR NRC front + back for verification.
  ///
  /// Tries `/drivers/me/identity` first, then falls back to the existing
  /// `/drivers/me/profile` route (some hosts never picked up the new route).
  static Future<Map<String, dynamic>> uploadDriverIdentity({
    required String docType,
    String? licencePath,
    String? nrcFrontPath,
    String? nrcBackPath,
  }) async {
    final endpoints = <(String, String)>[
      ('POST', '/drivers/me/identity'),
      ('POST', '/drivers/me/upload-docs'),
      ('POST', '/drivers/me/profile'),
      ('PATCH', '/drivers/me/profile'),
    ];

    Object? lastError;
    for (final entry in endpoints) {
      final method = entry.$1;
      final path = entry.$2;
      try {
        return await _sendDriverIdentityMultipart(
          method: method,
          path: path,
          docType: docType,
          licencePath: licencePath,
          nrcFrontPath: nrcFrontPath,
          nrcBackPath: nrcBackPath,
        );
      } catch (e) {
        lastError = e;
        final msg = e.toString().toLowerCase();
        final routeMissing = msg.contains('could not be found') ||
            msg.contains('not found') ||
            msg.contains('http 404');
        if (!routeMissing) rethrow;
      }
    }
    throw Exception(
      lastError?.toString().replaceFirst('Exception: ', '') ??
          'Identity upload failed.',
    );
  }

  static Future<Map<String, dynamic>> _sendDriverIdentityMultipart({
    required String method,
    required String path,
    required String docType,
    String? licencePath,
    String? nrcFrontPath,
    String? nrcBackPath,
  }) async {
    final session = await _resolveSession();
    final headers = await _headers(session);
    headers.remove('Content-Type');
    final request = http.MultipartRequest(
      method,
      Uri.parse('$_apiRoot$path'),
    );
    request.headers.addAll(headers);
    request.fields['doc_type'] = docType;
    if (docType == 'licence' && licencePath != null) {
      request.files.add(
        await http.MultipartFile.fromPath('licence', licencePath),
      );
    }
    if (docType == 'nrc') {
      if (nrcFrontPath != null) {
        request.files.add(
          await http.MultipartFile.fromPath('nrc_front', nrcFrontPath),
        );
      }
      if (nrcBackPath != null) {
        request.files.add(
          await http.MultipartFile.fromPath('nrc_back', nrcBackPath),
        );
      }
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final trimmed = response.body.trimLeft();
    if (!trimmed.startsWith('{')) {
      throw Exception(
        'Identity upload failed (HTTP ${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 404 ||
        (decoded['message']?.toString().toLowerCase().contains('could not be found') ??
            false)) {
      throw Exception(
        decoded['message']?.toString() ??
            'Identity upload failed (HTTP 404).',
      );
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['status'] == 'error') {
      throw Exception(
        decoded['message']?.toString() ?? 'Identity upload failed.',
      );
    }
    return Map<String, dynamic>.from(decoded['data'] as Map? ?? decoded);
  }

  static Future<Map<String, dynamic>> updateDriverProfile({
    required String vehicleType,
    required String vehicleCapacity,
    required String vehiclePlate,
    required String serviceArea,
  }) async {
    final res = await _request(
      'PATCH',
      '/drivers/me/profile',
      body: {
        'vehicle_type': vehicleType,
        'vehicle_capacity': vehicleCapacity,
        'vehicle_plate': vehiclePlate,
        'service_area': serviceArea,
      },
    );
    return Map<String, dynamic>.from(res['data']?['driver'] ?? {});
  }

  static Future<String> setAvailability(bool available) async {
    final res = await _request(
      'PATCH',
      '/drivers/me/availability',
      body: {
        'availability_status': available ? 'available' : 'unavailable',
      },
    );
    return (res['data']?['availability_status'] ??
            (available ? 'available' : 'unavailable'))
        .toString();
  }

  static Future<void> updateDriverLocation({
    required double latitude,
    required double longitude,
  }) async {
    await _request(
      'PATCH',
      '/drivers/me/location',
      body: {'latitude': latitude, 'longitude': longitude},
    );
  }
}
