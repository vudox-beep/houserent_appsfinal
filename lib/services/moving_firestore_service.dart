import 'package:cloud_firestore/cloud_firestore.dart';

/// Realtime mirror of Laravel `moving_bookings` rows.
/// Laravel writes via MovingFirestoreSync; the app listens here.
class MovingFirestoreService {
  MovingFirestoreService._();

  static const _collection = 'moving_bookings';

  static Stream<Map<String, dynamic>?> watchBooking(int bookingId) {
    return FirebaseFirestore.instance
        .collection(_collection)
        .doc('$bookingId')
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return fromFirestore(snap.data() ?? const {});
    });
  }

  /// Converts a Firestore doc into the shape used by moving screens.
  static Map<String, dynamic> fromFirestore(Map<String, dynamic> data) {
    final id = int.tryParse('${data['id']}') ?? 0;
    final driverId = '${data['driver_id'] ?? ''}'.trim();
    final driverLat = _asDouble(data['driver_lat']);
    final driverLng = _asDouble(data['driver_lng']);

    Map<String, dynamic>? driver;
    if (driverId.isNotEmpty) {
      driver = {
        'id': int.tryParse(driverId) ?? driverId,
        if (driverLat != null && driverLng != null)
          'location': {
            'latitude': driverLat,
            'longitude': driverLng,
          },
      };
    }

    return {
      'id': id,
      'status': data['status']?.toString() ?? 'open',
      'moving_date': data['moving_date']?.toString(),
      if (data['agreed_amount'] != null)
        'agreed_amount': _asDouble(data['agreed_amount']),
      if (data['tenant_offer'] != null)
        'tenant_offer': _asDouble(data['tenant_offer']),
      'pickup': {
        'address': data['pickup_address']?.toString() ?? '',
        'latitude': _asDouble(data['pickup_lat']) ?? 0,
        'longitude': _asDouble(data['pickup_lng']) ?? 0,
      },
      'dropoff': {
        'address': data['dropoff_address']?.toString() ?? '',
        'latitude': _asDouble(data['dropoff_lat']) ?? 0,
        'longitude': _asDouble(data['dropoff_lng']) ?? 0,
      },
      if (driver != null) 'driver': driver,
      'updated_at': data['updated_at']?.toString(),
    };
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
