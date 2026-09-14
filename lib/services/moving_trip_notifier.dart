import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'moving_marketplace_service.dart';
import 'notification_service.dart';

/// Trip alerts for HouseRent Shifts (local + background poll). Deduped per event.
/// Alerts only for the booker and the assigned driver — never every driver.
class MovingTripNotifier {
  static const _watchKey = 'moving_watch_booking_id_v1';
  static const _seenPrefix = 'moving_trip_seen_v1_';

  static Timer? _watchTimer;
  static bool _pollInFlight = false;

  /// Keep one active booking id for background checks (cleared on done).
  static Future<void> watchBooking(int? bookingId) async {
    final prefs = await SharedPreferences.getInstance();
    if (bookingId == null || bookingId <= 0) {
      await prefs.remove(_watchKey);
      _stopWatchPoll();
      return;
    }
    await prefs.setInt(_watchKey, bookingId);
    _startWatchPoll();
    // Immediate check so start/arrive aren’t delayed.
    unawaited(pollWatchedBooking());
    // Extra background wake shortly after a live shift is watched.
    unawaited(NotificationService.scheduleQuickBackgroundCheck());
  }

  static Future<int?> watchedBookingId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_watchKey);
  }

  static void _startWatchPoll() {
    if (_watchTimer != null) return;
    // Fast while a live shift is watched (works with app open / warm).
    _watchTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(pollWatchedBooking());
    });
  }

  static void _stopWatchPoll() {
    _watchTimer?.cancel();
    _watchTimer = null;
  }

  /// Resume watch poll after app cold start if a booking is still active.
  static Future<void> resumeWatchIfNeeded() async {
    final id = await watchedBookingId();
    if (id != null) {
      _startWatchPoll();
      await pollWatchedBooking();
    }
  }

  static Future<bool> _already(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_seenPrefix$key') ?? false;
  }

  static Future<void> _mark(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_seenPrefix$key', true);
  }

  /// True when this login is the booker or the assigned driver on the trip.
  static bool isParticipant(
    Map<String, dynamic> booking, {
    required String userId,
    required bool isDriver,
  }) {
    final myId = int.tryParse(userId) ?? 0;
    if (myId <= 0) return false;

    final tenantId = int.tryParse('${booking['tenant_id'] ?? ''}') ??
        int.tryParse(
          '${booking['tenant'] is Map ? (booking['tenant'] as Map)['id'] : ''}',
        ) ??
        0;
    final driverId = int.tryParse('${booking['driver_id'] ?? ''}') ??
        int.tryParse(
          '${booking['driver'] is Map ? (booking['driver'] as Map)['id'] : ''}',
        ) ??
        0;

    if (isDriver) return driverId > 0 && driverId == myId;
    return tenantId > 0 && tenantId == myId;
  }

  /// Show once per booking+event. Safe to call from UI or background.
  static Future<void> notifyOnce({
    required int bookingId,
    required String event,
    required String title,
    required String body,
  }) async {
    final key = '${bookingId}_$event';
    if (await _already(key)) return;

    try {
      await NotificationService.ensureReady();
      await NotificationService.showPushNotification(
        id: 'moving_$key',
        title: title,
        body: body,
        data: {
          'type': 'moving',
          'event': event,
          'booking_id': '$bookingId',
        },
      );
      await _mark(key);
    } catch (_) {}
  }

  static Future<void> tripStarted({
    required int bookingId,
    required bool forDriver,
    String? otherName,
  }) async {
    await watchBooking(bookingId);
    final name = (otherName ?? '').trim();
    if (forDriver) {
      await notifyOnce(
        bookingId: bookingId,
        event: 'started_driver',
        title: 'HouseRent Shifts · trip started',
        body: name.isEmpty
            ? 'Navigate to the client pickup.'
            : 'Trip with $name started — navigate to pickup.',
      );
    } else {
      await notifyOnce(
        bookingId: bookingId,
        event: 'started_client',
        title: 'HouseRent Shifts · trip started',
        body: name.isEmpty
            ? 'Your mover is on the way.'
            : '$name started your shift and is on the way.',
      );
    }
  }

  static Future<void> arrivedAtDestination({
    required int bookingId,
    required bool forDriver,
    String? placeLabel,
  }) async {
    await watchBooking(bookingId);
    final place = (placeLabel ?? 'destination').trim();
    if (forDriver) {
      await notifyOnce(
        bookingId: bookingId,
        event: 'arrived_driver',
        title: 'HouseRent Shifts · arrived',
        body: 'You arrived at $place. You can complete the shift.',
      );
    } else {
      await notifyOnce(
        bookingId: bookingId,
        event: 'arrived_client',
        title: 'HouseRent Shifts · driver arrived',
        body: 'Your mover arrived at $place.',
      );
    }
  }

  /// Apply status transitions from a booking payload (UI poll or background).
  /// Only the booker and that assigned driver get local trip alerts.
  static Future<void> handleBookingStatus(
    Map<String, dynamic> booking, {
    required bool isDriver,
    String? userId,
  }) async {
    final id = int.tryParse('${booking['id']}') ?? 0;
    if (id <= 0) return;

    final prefs = await SharedPreferences.getInstance();
    final myId = (userId ?? prefs.getString('user_id') ?? '').trim();
    if (myId.isEmpty ||
        !isParticipant(booking, userId: myId, isDriver: isDriver)) {
      // Someone else's open request / trip — never alert this device.
      final watched = await watchedBookingId();
      if (watched == id) await watchBooking(null);
      return;
    }

    final status = (booking['status'] ?? '').toString();

    if (status == 'accepted' ||
        status == 'in_progress' ||
        status == 'arrived') {
      await watchBooking(id);
    }
    if (status == 'completed' || status == 'cancelled') {
      await watchBooking(null);
      return;
    }

    if (status == 'in_progress' || status == 'arrived') {
      final other = isDriver
          ? (booking['tenant'] is Map
              ? (booking['tenant']['name'] ?? '').toString()
              : '')
          : (booking['driver'] is Map
              ? (booking['driver']['name'] ?? '').toString()
              : '');
      await tripStarted(
        bookingId: id,
        forDriver: isDriver,
        otherName: other,
      );
    }

    if (status == 'arrived') {
      final drop = booking['dropoff'];
      final place = drop is Map
          ? (drop['address'] ?? 'destination').toString()
          : 'destination';
      await arrivedAtDestination(
        bookingId: id,
        forDriver: isDriver,
        placeLabel: place,
      );
    }
  }

  /// One cheap GET for the watched booking — used by Workmanager / foreground.
  static Future<void> pollWatchedBooking() async {
    if (_pollInFlight) return;
    final id = await watchedBookingId();
    if (id == null) {
      _stopWatchPoll();
      return;
    }
    _pollInFlight = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = (prefs.getString('role') ?? '').toLowerCase();
      final userId = prefs.getString('user_id') ?? '';
      if (userId.isEmpty) return;
      final isDriver = role == 'driver';
      final booking = await MovingMarketplaceService.getBooking(id);
      await handleBookingStatus(
        booking,
        isDriver: isDriver,
        userId: userId,
      );
    } catch (_) {
    } finally {
      _pollInFlight = false;
    }
  }
}
