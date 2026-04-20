import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api_service.dart';

const String _backgroundTaskName = 'houserent.notifications.poll';
const String _backgroundTaskUniqueName = 'houserent_notifications_poll_unique';
const String _quickBackgroundTaskName = 'houserent.notifications.quick_poll';
const String _quickBackgroundTaskUniqueName =
    'houserent_notifications_quick_poll_unique';
const String _seenNotificationsKey = 'seen_notification_ids_v1';
const String _seededNotificationsKey = 'seen_notification_ids_seeded_v1';
const String _publicBadgeCountKey = 'public_admin_notifications_badge_v1';
const String _clearedPublicNotificationIdsKey =
    'public_admin_notifications_cleared_ids_v1';

@pragma('vm:entry-point')
void notificationBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await NotificationService.initialize(fromBackground: true);
    await NotificationService.checkAndShowNewNotifications(fromBackground: true);
    return Future.value(true);
  });
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static Timer? _foregroundTimer;
  static bool _isInitialized = false;
  static bool _workManagerInitialized = false;

  static Future<void> initialize({bool fromBackground = false}) async {
    if (_isInitialized && !fromBackground) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(settings);
    await _createAndroidChannel();

    if (!fromBackground) {
      await _requestPermissions();
      await _initializeWorkmanager();
      await checkAndShowNewNotifications(seedOnlyIfFirstRun: true);
      _isInitialized = true;
    }
  }

  static Future<void> startForegroundPolling({
    Duration interval = const Duration(seconds: 30),
  }) async {
    if (_foregroundTimer != null) return;

    await checkAndShowNewNotifications();
    _foregroundTimer = Timer.periodic(interval, (_) async {
      await checkAndShowNewNotifications();
    });
  }

  static void stopForegroundPolling() {
    _foregroundTimer?.cancel();
    _foregroundTimer = null;
  }

  static Future<void> forceCheckNow() async {
    await checkAndShowNewNotifications();
  }

  static Future<void> checkAndShowNewNotifications({
    bool fromBackground = false,
    bool seedOnlyIfFirstRun = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final notifications = <dynamic>[];
      final publicNotifications = <dynamic>[];

      // Logged-in notifications (panel/user scoped)
      if (token.isNotEmpty) {
        try {
          notifications.addAll(await ApiService.fetchNotifications());
        } catch (_) {
          // Keep going; we still try public admin notifications.
        }
      }

      // Public admin notifications (no login required)
      try {
        publicNotifications
            .addAll(await ApiService.fetchPublicAdminNotifications());
        notifications.addAll(publicNotifications);
      } catch (_) {
        // If this also fails, we'll simply skip this cycle.
      }

      if (notifications.isEmpty) return;

      final dedupedById = <String, dynamic>{};
      for (final n in notifications) {
        final id = _extractNotificationId(n);
        if (id.isEmpty) continue;
        dedupedById[id] = n;
      }
      final uniqueNotifications = dedupedById.values.toList();
      if (uniqueNotifications.isEmpty) return;

      final currentIds = uniqueNotifications
          .map((n) => _extractNotificationId(n))
          .where((id) => id.isNotEmpty)
          .toSet();

      final seenIds = await _readSeenIds(prefs);
      final isSeeded = prefs.getBool(_seededNotificationsKey) ?? false;
      final clearedPublicIds = _readClearedPublicIds(prefs);
      await _updatePublicBadgeCountFromList(
        prefs,
        publicNotifications,
        clearedPublicIds: clearedPublicIds,
      );

      if (!isSeeded || seedOnlyIfFirstRun) {
        await _storeSeenIds(prefs, currentIds);
        await prefs.setBool(_seededNotificationsKey, true);
        return;
      }

      final unseen = uniqueNotifications.where((n) {
        if (n is! Map) return false;
        final id = _extractNotificationId(n);
        final body = _extractBody(Map<String, dynamic>.from(n));
        return id.isNotEmpty &&
            !seenIds.contains(id) &&
            !clearedPublicIds.contains(id) &&
            !_isReadNotification(n) &&
            body.isNotEmpty;
      }).toList();

      unseen.sort((a, b) {
        final aDate = _parseDate(a);
        final bDate = _parseDate(b);
        return aDate.compareTo(bDate);
      });

      for (final notif in unseen) {
        await _showLocalNotification(notif);
      }

      final updated = {...seenIds, ...currentIds};
      await _storeSeenIds(prefs, updated);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Notification sync failed (${fromBackground ? "bg" : "fg"}): $e');
      }
    }
  }

  static Future<void> _initializeWorkmanager() async {
    if (_workManagerInitialized) return;
    try {
      await Workmanager().initialize(
        notificationBackgroundDispatcher,
        isInDebugMode: false,
      );

      await Workmanager().registerPeriodicTask(
        _backgroundTaskUniqueName,
        _backgroundTaskName,
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 2),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      // Also schedule a quick one-off background check to reduce delay
      // shortly after app usage/login.
      await Workmanager().registerOneOffTask(
        _quickBackgroundTaskUniqueName,
        _quickBackgroundTaskName,
        initialDelay: const Duration(minutes: 1),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      _workManagerInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Workmanager setup failed: $e');
      }
    }
  }

  static Future<void> scheduleQuickBackgroundCheck() async {
    try {
      await _initializeWorkmanager();
      await Workmanager().registerOneOffTask(
        _quickBackgroundTaskUniqueName,
        _quickBackgroundTaskName,
        initialDelay: const Duration(minutes: 1),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    } catch (_) {}
  }

  static Future<void> _requestPermissions() async {
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> _createAndroidChannel() async {
    const channel = AndroidNotificationChannel(
      'houserent_general_notifications',
      'HouseRent Notifications',
      description: 'Admin and listing alerts',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<void> _showLocalNotification(dynamic notif) async {
    if (notif is! Map) return;
    final n = Map<String, dynamic>.from(notif as Map);
    final idText = _extractNotificationId(n);
    final notifId = int.tryParse(idText) ?? idText.hashCode;

    final title = _extractTitle(n);
    final body = _extractBody(n);
    if (body.isEmpty) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'houserent_general_notifications',
        'HouseRent Notifications',
        channelDescription: 'Admin and listing alerts',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.show(
      notifId,
      title,
      body,
      details,
      payload: jsonEncode({'id': idText}),
    );
  }

  static String _extractTitle(Map<String, dynamic> n) {
    final rawTitle = (n['title'] ?? '').toString().trim();
    if (rawTitle.isNotEmpty) return rawTitle;
    if (_isUploadNotification(n)) return 'New upload available';
    if (_isNewListingNotification(n)) return 'New listing available';
    return 'New admin message';
  }

  static String _extractBody(Map<String, dynamic> n) {
    const candidateKeys = [
      'message',
      'body',
      'description',
      'content',
      'text',
    ];
    for (final key in candidateKeys) {
      final value = (n[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _extractNotificationId(dynamic n) {
    if (n is! Map) return '';
    final map = Map<String, dynamic>.from(n);
    final id = map['id'] ?? map['notification_id'] ?? map['uuid'] ?? '';
    final normalized = id.toString().trim();
    if (normalized.isNotEmpty) return normalized;

    final fallbackKey = [
      (map['type'] ?? map['notification_type'] ?? map['category'] ?? '')
          .toString()
          .trim()
          .toLowerCase(),
      (map['title'] ?? '').toString().trim().toLowerCase(),
      (map['message'] ?? map['body'] ?? map['description'] ?? '')
          .toString()
          .trim()
          .toLowerCase(),
      (map['created_at'] ?? map['date'] ?? '').toString().trim().toLowerCase(),
    ].join('|');

    return fallbackKey.isEmpty ? '' : fallbackKey;
  }

  static bool _isNewListingNotification(Map<String, dynamic> n) {
    final joined = [
      n['type'],
      n['notification_type'],
      n['category'],
      n['title'],
      n['message'],
      n['body'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');

    return joined.contains('listing') ||
        joined.contains('new property') ||
        joined.contains('new listing');
  }

  static bool _isUploadNotification(Map<String, dynamic> n) {
    final joined = [
      n['type'],
      n['notification_type'],
      n['category'],
      n['title'],
      n['message'],
      n['body'],
      n['description'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');

    return joined.contains('upload') ||
        joined.contains('uploaded') ||
        joined.contains('new upload') ||
        joined.contains('proof of payment');
  }

  static bool _isAdminMessageNotification(Map<String, dynamic> n) {
    final joined = [
      n['type'],
      n['notification_type'],
      n['category'],
      n['source'],
      n['title'],
      n['message'],
      n['body'],
      n['description'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');

    return joined.contains('admin') ||
        joined.contains('announcement') ||
        joined.contains('message from admin');
  }

  static bool _isBackgroundEligibleNotification(dynamic notif) {
    if (notif is! Map) return false;
    final map = Map<String, dynamic>.from(notif);
    return _isAdminMessageNotification(map) ||
        _isUploadNotification(map) ||
        _isNewListingNotification(map) ||
        _isDbNotification(map) ||
        _isGenericMessageNotification(map);
  }

  static bool _isDbNotification(Map<String, dynamic> n) {
    final hasContent = _extractBody(n).isNotEmpty;
    final hasDbShape = n.containsKey('target_role') ||
        n.containsKey('created_by') ||
        n.containsKey('notification_id');
    return hasContent && hasDbShape;
  }

  static bool _isGenericMessageNotification(Map<String, dynamic> n) {
    final hasId = _extractNotificationId(n).isNotEmpty;
    final hasTitleOrBody =
        (n['title'] ?? '').toString().trim().isNotEmpty ||
            _extractBody(n).isNotEmpty;
    return hasId && hasTitleOrBody;
  }

  static bool _isReadNotification(dynamic notif) {
    if (notif is! Map) return false;
    final map = Map<String, dynamic>.from(notif);
    final raw = (map['is_read'] ?? '').toString().trim().toLowerCase();
    return raw == '1' || raw == 'true' || raw == 'yes';
  }

  static DateTime _parseDate(dynamic notif) {
    if (notif is! Map) return DateTime.fromMillisecondsSinceEpoch(0);
    final map = Map<String, dynamic>.from(notif);
    final raw = (map['created_at'] ?? map['date'] ?? '').toString().trim();
    return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Future<Set<String>> _readSeenIds(SharedPreferences prefs) async {
    final list = prefs.getStringList(_seenNotificationsKey) ?? const <String>[];
    return list.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  static Future<void> _storeSeenIds(
    SharedPreferences prefs,
    Set<String> ids,
  ) async {
    final trimmed = ids.where((e) => e.trim().isNotEmpty).toList();
    if (trimmed.length > 500) {
      trimmed.removeRange(0, trimmed.length - 500);
    }
    await prefs.setStringList(_seenNotificationsKey, trimmed);
  }

  static Future<int> refreshPublicNotificationBadgeCount() async {
    final prefs = await SharedPreferences.getInstance();
    final clearedIds = _readClearedPublicIds(prefs);
    try {
      final notifications = await ApiService.fetchPublicAdminNotifications();
      return _updatePublicBadgeCountFromList(
        prefs,
        notifications,
        clearedPublicIds: clearedIds,
      );
    } catch (_) {
      return prefs.getInt(_publicBadgeCountKey) ?? 0;
    }
  }

  static Future<int> readPublicNotificationBadgeCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_publicBadgeCountKey) ?? 0;
  }

  static Set<String> _readClearedPublicIds(SharedPreferences prefs) {
    final list =
        prefs.getStringList(_clearedPublicNotificationIdsKey) ?? const <String>[];
    return list.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  static Future<Set<String>> readClearedPublicNotificationIds() async {
    final prefs = await SharedPreferences.getInstance();
    return _readClearedPublicIds(prefs);
  }

  static Future<void> clearAllPublicNotificationsLocally({
    List<dynamic>? notifications,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = _readClearedPublicIds(prefs);

    final source = notifications ?? await ApiService.fetchPublicAdminNotifications();
    final ids = <String>{};
    for (final item in source) {
      final id = _extractNotificationId(item);
      if (id.isNotEmpty) ids.add(id);
    }

    if (ids.isNotEmpty) {
      current.addAll(ids);
      final seen = await _readSeenIds(prefs);
      seen.addAll(ids);
      await _storeSeenIds(prefs, seen);
      await prefs.setStringList(
        _clearedPublicNotificationIdsKey,
        current.toList(),
      );
    }

    await prefs.setInt(_publicBadgeCountKey, 0);
  }

  static Future<int> _updatePublicBadgeCountFromList(
    SharedPreferences prefs,
    List<dynamic> notifications, {
    required Set<String> clearedPublicIds,
  }) async {
    final uniqueIds = <String>{};
    for (final n in notifications) {
      final id = _extractNotificationId(n);
      if (id.isEmpty || clearedPublicIds.contains(id)) continue;
      uniqueIds.add(id);
    }

    final count = uniqueIds.length;
    await prefs.setInt(_publicBadgeCountKey, count);
    return count;
  }
}
