import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import 'api_service.dart';
import 'moving_trip_notifier.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.initialize(fromBackground: true);

  final notification = message.notification;
  final title = notification?.title ?? message.data['title']?.toString();
  final body =
      notification?.body ??
      message.data['body']?.toString() ??
      message.data['message']?.toString();
  if (body == null || body.trim().isEmpty) return;

  final type = message.data['type']?.toString();
  final event = message.data['event']?.toString() ?? '';

  // Legacy all-driver "new booking" pushes — ignore completely.
  if (type == 'moving' && event == 'new_booking') return;

  // Only watch trips for booker↔driver events (offer, accept, start, etc.).
  if (type == 'moving') {
    final bookingId = int.tryParse(message.data['booking_id']?.toString() ?? '');
    if (bookingId != null && bookingId > 0) {
      await MovingTripNotifier.watchBooking(bookingId);
    }
  }

  await NotificationService.showPushNotification(
    id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
    title: title ?? 'HouseRent notification',
    body: body,
    data: message.data,
  );
}

class FirebaseMessagingService {
  FirebaseMessagingService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((message) async {
      final notification = message.notification;
      final title = notification?.title ?? message.data['title']?.toString();
      final body = notification?.body ?? message.data['body']?.toString();
      if (body == null || body.trim().isEmpty) return;

      final type = message.data['type']?.toString();
      final event = message.data['event']?.toString() ?? '';

      if (type == 'moving' && event == 'new_booking') return;

      if (type == 'moving') {
        final bookingId =
            int.tryParse(message.data['booking_id']?.toString() ?? '');
        if (bookingId != null && bookingId > 0) {
          await MovingTripNotifier.watchBooking(bookingId);
        }
      }

      await NotificationService.showPushNotification(
        id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: title ?? 'HouseRent notification',
        body: body,
        data: message.data,
      );
    });

    _messaging.onTokenRefresh.listen((token) async {
      try {
        await ApiService.registerNotificationDevice(token);
      } catch (_) {}
    });

    await syncToken();
    _initialized = true;
  }

  static Future<void> syncToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await ApiService.registerNotificationDevice(token);
      }
    } catch (_) {}
  }

  static Future<void> unregisterCurrentDevice() async {
    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await ApiService.unregisterNotificationDevice(token);
      }
      await _messaging.deleteToken();
    } catch (_) {}
  }
}
