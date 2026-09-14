import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/moving_marketplace_service.dart';
import '../../services/moving_trip_notifier.dart';
import '../../theme/yango_map_style.dart';

class _NavStep {
  const _NavStep({
    required this.end,
    required this.instruction,
    required this.distanceMeters,
    this.maneuver,
  });
  final LatLng end;
  final String instruction;
  final int distanceMeters;
  final String? maneuver;
}

/// In-app navigation — same dark Yango map (street names) as the live map.
///
/// Routes with the Google Directions API using the Maps key stored in the
/// site config (`php_backend/api/maps.php`), falling back to the app key.
class DriverNavScreen extends StatefulWidget {
  const DriverNavScreen({
    super.key,
    required this.destination,
    required this.destinationLabel,
    this.clientName,
    this.clientPhone,
    this.initialPosition,
    this.bookingId,
    this.reportArrival = false,
    this.autoStartNavigation = false,
    this.nextDestination,
    this.nextDestinationLabel,
  });

  final LatLng destination;
  final String destinationLabel;
  final String? clientName;
  final String? clientPhone;
  /// Last known driver GPS from the live map — avoids cold GPS timeouts.
  final LatLng? initialPosition;
  /// When set + [reportArrival], GPS arrival updates the booking for the client.
  final int? bookingId;
  final bool reportArrival;
  /// Start turn-by-turn + voice as soon as the route is ready.
  final bool autoStartNavigation;
  /// After arriving at [destination], auto-continue here (e.g. pickup → drop-off).
  final LatLng? nextDestination;
  final String? nextDestinationLabel;

  @override
  State<DriverNavScreen> createState() => _DriverNavScreenState();
}

class _DriverNavScreenState extends State<DriverNavScreen>
    with TickerProviderStateMixin {
  static const String _fallbackKey = 'AIzaSyDH0JpnMofvCFnx9byn6TUm_GV6YW9onZU';
  static const Color _accent = Color(0xFFFFC107);
  static const Color _routeBlue = Color(0xFF2F80FF);
  static const Color _green = Color(0xFFFFC107);
  static const Color _sheet = Color(0xFF1A1A1A);

  GoogleMapController? _map;
  StreamSubscription<Position>? _gps;
  final FlutterTts _tts = FlutterTts();
  AnimationController? _moveAnim;

  LatLng? _me;
  LatLng? _prevMe;
  LatLng? _displayPos; // smoothed arrow position (shows motion)
  double _heading = 0;
  double _animFromHeading = 0;
  double _displayHeading = 0;
  double _speedMps = 0;
  BitmapDescriptor? _navArrow;
  List<LatLng> _route = [];
  List<_NavStep> _steps = [];
  final List<LatLng> _trail = [];
  String _distanceText = '';
  String _durationText = '';
  int _durationSeconds = 0;
  DateTime? _etaFetchedAt;
  String _instruction = 'Fetching route…';
  bool _loading = true;
  bool _navigating = false;
  bool _voiceOn = true;
  bool _ttsReady = false;
  bool _speaking = false;
  int _speakGen = 0;
  String? _error;
  String? _apiKey;
  String _lastSpoken = '';
  bool _saidApproaching = false;
  bool _saidSoon = false;
  bool _saidArrived = false;
  bool _startupVoiceDone = false;
  bool _autoStarted = false;
  late LatLng _dest;
  late String _destLabel;
  LatLng? _nextDest;
  String? _nextLabel;
  bool _reportArrival = false;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCam = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSpeakAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _voiceInit;
  Timer? _etaTick;

  @override
  void initState() {
    super.initState();
    _dest = widget.destination;
    _destLabel = widget.destinationLabel;
    _nextDest = widget.nextDestination;
    _nextLabel = widget.nextDestinationLabel;
    // Only notify API arrival on the final leg (destination).
    _reportArrival = widget.reportArrival && widget.nextDestination == null;
    _moveAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addListener(_onMoveTick);
    _voiceInit = _initVoice();
    _buildNavArrow();
    _etaTick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _durationSeconds > 0) setState(() {});
    });
    _start();
  }

  String get _remainingLabel {
    if (_durationSeconds <= 0) {
      return _durationText.isEmpty ? '—' : _durationText;
    }
    final fetched = _etaFetchedAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(fetched).inSeconds;
    final left = (_durationSeconds - elapsed).clamp(0, _durationSeconds);
    if (left <= 45) return 'Arriving now';
    final mins = (left / 60).ceil();
    return '$mins min left';
  }

  void _onMoveTick() {
    final from = _prevMe;
    final to = _me;
    if (from == null || to == null || !_navigating) return;
    final t = Curves.easeOut.transform(_moveAnim!.value);
    final lat = from.latitude + (to.latitude - from.latitude) * t;
    final lng = from.longitude + (to.longitude - from.longitude) * t;
    // Smooth heading shortest-path lerp from anim start → target.
    var dH = _heading - _animFromHeading;
    while (dH > 180) {
      dH -= 360;
    }
    while (dH < -180) {
      dH += 360;
    }
    final nextHeading = (_animFromHeading + dH * t + 360) % 360;
    final nextPos = LatLng(lat, lng);
    if (!mounted) return;
    setState(() {
      _displayPos = nextPos;
      _displayHeading = nextHeading;
    });
  }

  Future<void> _initVoice() async {
    try {
      try {
        await _tts.setSharedInstance(true);
      } catch (_) {}
      // Prefer Google TTS package name only (avoid breaking init with bad values).
      try {
        final engines = await _tts.getEngines;
        if (engines is List) {
          final names = engines.map((e) => e.toString()).toList();
          final google = names.firstWhere(
            (e) => e.contains('com.google.android.tts') ||
                e.toLowerCase().contains('google'),
            orElse: () => '',
          );
          if (google.isNotEmpty && google.contains('.')) {
            await _tts.setEngine(google);
          }
        }
      } catch (_) {}
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(false);
      try {
        await _tts.setQueueMode(1); // QUEUE_FLUSH
      } catch (_) {}
      // Android: use navigation guidance stream (media/nav volume).
      try {
        await _tts.setAudioAttributesForNavigation();
      } catch (_) {}
      try {
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions
                .interruptSpokenAudioAndMixWithOthers,
          ],
          IosTextToSpeechAudioMode.voicePrompt,
        );
      } catch (_) {}
      _tts.setStartHandler(() => _speaking = true);
      _tts.setCompletionHandler(() => _speaking = false);
      _tts.setCancelHandler(() => _speaking = false);
      _tts.setErrorHandler((_) => _speaking = false);
      _ttsReady = true;
    } catch (_) {
      _ttsReady = false;
    }
  }

  Future<bool> _ensureVoice() async {
    if (_ttsReady) return true;
    try {
      await (_voiceInit ?? _initVoice()).timeout(const Duration(seconds: 5));
    } catch (_) {
      await _initVoice();
    }
    return _ttsReady;
  }

  Future<void> _speak(String raw, {bool force = false}) async {
    if (!_voiceOn) return;
    await _ensureVoice();
    if (!mounted || !_ttsReady) return;

    final text = _speechClean(raw);
    if (text.isEmpty) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastSpeakAt).inMilliseconds < 800) return;
    if (!force &&
        text == _lastSpoken &&
        now.difference(_lastSpeakAt).inSeconds < 8) {
      return;
    }

    _speakGen++;
    final gen = _speakGen;
    _lastSpoken = text;
    _lastSpeakAt = now;
    try {
      // Re-assert nav audio + volume every speak (Android can drop attributes).
      try {
        await _tts.setAudioAttributesForNavigation();
        await _tts.setVolume(1.0);
      } catch (_) {}
      // Do NOT stop before first words — stop can kill start speech on Android.
      if (_speaking) {
        await _tts.stop();
        await Future.delayed(const Duration(milliseconds: 80));
      }
      if (gen != _speakGen || !_voiceOn) return;
      // focus: true requests audio focus on Android (critical for audible prompts).
      final result = await _tts.speak(text, focus: true);
      if (result == 0 || result == false) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (gen != _speakGen || !_voiceOn) return;
        await _tts.speak(text, focus: true);
      }
    } catch (_) {
      try {
        await _tts.setLanguage('en-US');
        await _tts.setVolume(1.0);
        await _tts.setAudioAttributesForNavigation();
        await _tts.speak(text, focus: true);
      } catch (_) {}
    }
  }

  /// Always speaks as soon as Start navigation is pressed.
  Future<void> _speakNavigationStart() async {
    if (mounted) setState(() => _voiceOn = true);
    _startupVoiceDone = false;
    _saidApproaching = false;
    _saidSoon = false;

    await _ensureVoice();
    if (!mounted || !_navigating) return;

    final first =
        _steps.isNotEmpty ? _speechClean(_steps.first.instruction) : '';
    final dest = _shortPlace(_destLabel);

    // Short first line that ALWAYS plays (media / navigation volume).
    final line = first.isNotEmpty
        ? 'Navigation started. $first'
        : (dest.isEmpty
            ? 'Navigation started. Follow the blue route.'
            : 'Navigation started. Head to $dest.');

    await _speak(line, force: true);
    // Cold TTS on Android often drops the first utterance — retry once.
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted && _navigating && _voiceOn && !_speaking) {
      await _speak(line, force: true);
    }

    if (mounted && _navigating) _startupVoiceDone = true;
  }

  static String _shortPlace(String label) {
    var t = label.trim().replaceAll('…', '').replaceAll('...', '');
    if (t.length > 40) t = t.substring(0, 40);
    return t;
  }

  static String _speechClean(String input) {
    var t = input
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('Destination will be on the', 'Destination on the')
        .replaceAll('Continue onto', 'Continue on')
        .replaceAll('Continue straight onto', 'Continue straight on')
        .replaceAll('Head ', 'Go ')
        .trim();
    t = t.replaceAllMapped(
      RegExp(r'\b(\d+)\s*m\b', caseSensitive: false),
      (m) => '${m[1]} meters',
    );
    t = t.replaceAllMapped(
      RegExp(r'\b(\d+(?:\.\d+)?)\s*km\b', caseSensitive: false),
      (m) => '${m[1]} kilometers',
    );
    // Keep prompts short for clearer TTS.
    if (t.length > 120) {
      final cut = t.indexOf(',', 60);
      if (cut > 40) t = t.substring(0, cut);
    }
    return t;
  }

  String _distancePhrase(int meters) {
    if (meters >= 1000) {
      final km = (meters / 1000).toStringAsFixed(meters >= 2000 ? 0 : 1);
      return '$km kilometers';
    }
    if (meters >= 100) {
      return '${(meters / 50).round() * 50} meters';
    }
    return '$meters meters';
  }

  /// Nav chevron (points up; marker rotation = heading) + motion wake.
  Future<void> _buildNavArrow() async {
    const size = 128.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final c = Offset(size / 2, size / 2);

    // Soft ground shadow.
    canvas.drawCircle(
      Offset(c.dx, c.dy + 6),
      30,
      Paint()..color = Colors.black.withValues(alpha: 0.32),
    );

    // Motion wake behind the arrow (shows you're moving).
    final wake = Path()
      ..moveTo(c.dx, c.dy + 10)
      ..lineTo(c.dx + 20, c.dy + 42)
      ..lineTo(c.dx, c.dy + 32)
      ..lineTo(c.dx - 20, c.dy + 42)
      ..close();
    canvas.drawPath(
      wake,
      Paint()
        ..color = const Color(0xFFFFC107).withValues(alpha: 0.38)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    // Outer ring.
    canvas.drawCircle(c, 34, Paint()..color = Colors.white);
    canvas.drawCircle(c, 30, Paint()..color = const Color(0xFF14171A));

    // Chevron / arrow nose pointing north (up).
    final arrow = Path()
      ..moveTo(c.dx, c.dy - 26)
      ..lineTo(c.dx + 20, c.dy + 14)
      ..lineTo(c.dx + 7, c.dy + 14)
      ..lineTo(c.dx + 7, c.dy + 24)
      ..lineTo(c.dx - 7, c.dy + 24)
      ..lineTo(c.dx - 7, c.dy + 14)
      ..lineTo(c.dx - 20, c.dy + 14)
      ..close();

    canvas.drawPath(
      arrow,
      Paint()
        ..color = const Color(0xFFFFC107)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      arrow,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..isAntiAlias = true,
    );

    // Small white tip highlight.
    canvas.drawCircle(
      Offset(c.dx, c.dy - 12),
      3.6,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted || bytes == null) return;
    setState(() {
      _navArrow = BitmapDescriptor.bytes(bytes.buffer.asUint8List());
    });
  }

  @override
  void dispose() {
    _gps?.cancel();
    _etaTick?.cancel();
    _moveAnim?.dispose();
    _tts.stop();
    _map?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    // Seed immediately from the live map so nav never sits on a blank error.
    if (widget.initialPosition != null) {
      _me = widget.initialPosition;
    }

    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        // Still allow route from last known / initial seed.
        final seeded = await _resolvePosition(allowSeedOnly: true);
        if (seeded == null) {
          if (!mounted) return;
          setState(() {
            _error =
                'Turn on location / GPS, then tap Retry.';
            _loading = false;
          });
          return;
        }
      } else {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          final seeded = await _resolvePosition(allowSeedOnly: true);
          if (seeded == null) {
            if (!mounted) return;
            setState(() {
              _error = 'Location permission is needed for navigation.';
              _loading = false;
            });
            return;
          }
        } else {
          await _resolvePosition(allowSeedOnly: false);
        }
      }

      if (_me == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Could not get your GPS position. Tap Retry.';
          _loading = false;
        });
        return;
      }

      _apiKey = await ApiService.getGoogleMapsApiKey() ?? _fallbackKey;
      if (mounted) setState(() {}); // show map while route loads
      await _fetchRoute();
    } catch (_) {
      if (_me != null) {
        _apiKey ??= await ApiService.getGoogleMapsApiKey() ?? _fallbackKey;
        await _fetchRoute();
        return;
      }
      if (mounted) {
        setState(() {
          _error = 'Could not get your GPS position. Tap Retry.';
          _loading = false;
        });
      }
    }
  }

  /// Tries last-known → current (medium) → current (high) → stream, then seed.
  Future<LatLng?> _resolvePosition({required bool allowSeedOnly}) async {
    // 1) Cached fix (fast).
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _me = LatLng(last.latitude, last.longitude);
        if (last.heading >= 0) _heading = last.heading;
        if (allowSeedOnly) return _me;
      }
    } catch (_) {}

    if (allowSeedOnly) {
      return _me ?? widget.initialPosition;
    }

    // 2) Medium accuracy with short timeout (works indoors better).
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _me = LatLng(pos.latitude, pos.longitude);
      if (pos.heading >= 0) _heading = pos.heading;
      return _me;
    } catch (_) {}

    // 3) High accuracy, longer wait.
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      _me = LatLng(pos.latitude, pos.longitude);
      if (pos.heading >= 0) _heading = pos.heading;
      return _me;
    } catch (_) {}

    // 4) First stream event.
    try {
      final pos = await Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).first.timeout(const Duration(seconds: 12));
      _me = LatLng(pos.latitude, pos.longitude);
      if (pos.heading >= 0) _heading = pos.heading;
      return _me;
    } catch (_) {}

    // 5) Seed from live map / last known already stored.
    return _me ?? widget.initialPosition;
  }

  Future<void> _fetchRoute() async {
    final me = _me;
    if (me == null) return;
    try {
      final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${me.latitude},${me.longitude}'
        '&destination=${_dest.latitude},${_dest.longitude}'
        '&mode=driving&key=${_apiKey ?? _fallbackKey}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = data['routes'] as List? ?? [];
      if (data['status'] != 'OK' || routes.isEmpty) {
        throw Exception(data['error_message'] ?? 'No route found');
      }
      final route = routes.first as Map<String, dynamic>;
      final leg = (route['legs'] as List).first as Map<String, dynamic>;
      final steps = leg['steps'] as List? ?? [];
      final parsedSteps = <_NavStep>[];
      for (final raw in steps) {
        final s = raw as Map<String, dynamic>;
        final end = s['end_location'];
        if (end is! Map) continue;
        final lat = double.tryParse('${end['lat']}');
        final lng = double.tryParse('${end['lng']}');
        if (lat == null || lng == null) continue;
        final distVal = int.tryParse('${s['distance']?['value']}') ?? 0;
        parsedSteps.add(
          _NavStep(
            end: LatLng(lat, lng),
            instruction: _stripHtml(
              s['html_instructions']?.toString() ?? 'Continue',
            ),
            distanceMeters: distVal,
            maneuver: s['maneuver']?.toString(),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _route = _decodePolyline(
          route['overview_polyline']?['points']?.toString() ?? '',
        );
        _steps = parsedSteps;
        _saidApproaching = false;
        _saidSoon = false;
        _distanceText = leg['distance']?['text']?.toString() ?? '';
        _durationText = leg['duration']?['text']?.toString() ?? '';
        _durationSeconds =
            int.tryParse('${leg['duration']?['value']}') ?? 0;
        _etaFetchedAt = DateTime.now();
        _instruction = parsedSteps.isEmpty
            ? 'Head to $_destLabel'
            : parsedSteps.first.instruction;
        _loading = false;
        _error = null;
      });
      if (!_navigating) {
        await _fitRoute();
        // Auto-start turn-by-turn + voice after price accept / leg switch.
        if (widget.autoStartNavigation && !_autoStarted && _me != null) {
          _autoStarted = true;
          _toggleNavigation();
        }
      } else if (_me != null) {
        await _chaseNavCamera(_me!, bearing: _heading, force: true);
        if (parsedSteps.isNotEmpty) {
          await _speak(parsedSteps.first.instruction, force: true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Keep any old route; show error only when we have nothing to draw.
        _error = _route.isEmpty
            ? 'Directions unavailable. You can still open Google Maps.'
            : null;
      });
    }
  }

  static String _stripHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static List<LatLng> _decodePolyline(String encoded) {
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

  double _distanceMeters(LatLng a, LatLng b) =>
      Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);

  Future<void> _fitRoute() async {
    final map = _map;
    if (map == null) return;
    final points = [..._route, if (_me != null) _me!, _dest];
    if (points.isEmpty) return;
    var minLat = points.first.latitude, maxLat = points.first.latitude;
    var minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    try {
      await map.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          70,
        ),
      );
    } catch (_) {}
  }

  Future<void> _reportArrivalIfNeeded() async {
    final id = widget.bookingId;
    if (id == null || !_reportArrival) {
      return;
    }
    try {
      await MovingMarketplaceService.markArrived(id);
    } catch (_) {}
    await MovingTripNotifier.arrivedAtDestination(
      bookingId: id,
      forDriver: true,
      placeLabel: _destLabel,
    );
  }

  /// Pickup reached → auto-start navigation to client destination + voice.
  Future<void> _advanceToNextLegOrFinish() async {
    final next = _nextDest;
    final nextLabel = _nextLabel;
    if (next != null && nextLabel != null) {
      await _speak(
        'You have arrived at pickup. Starting navigation to destination.',
        force: true,
      );
      setState(() {
        _dest = next;
        _destLabel = nextLabel;
        _nextDest = null;
        _nextLabel = null;
        _reportArrival = true;
        _saidArrived = false;
        _saidApproaching = false;
        _saidSoon = false;
        _startupVoiceDone = false;
        _autoStarted = false;
        _instruction = 'Routing to destination…';
        _loading = true;
        _route = [];
        _steps = [];
      });
      await _fetchRoute();
      if (mounted && !_navigating && _me != null) {
        _autoStarted = true;
        _toggleNavigation();
      } else if (mounted && _navigating) {
        unawaited(_speakNavigationStart());
      }
      return;
    }

    setState(() {
      _navigating = false;
      _instruction = 'You have arrived at $_destLabel';
    });
    await _speak('You have arrived at $_destLabel', force: true);
    unawaited(_reportArrivalIfNeeded());
    _resetOverviewCamera();
  }

  /// Stop turn-by-turn follow only — stay on this map (do not pop).
  void _cancelNavigation() {
    if (!_navigating) return;
    _gps?.cancel();
    _gps = null;
    _speakGen++;
    _tts.stop();
    setState(() {
      _navigating = false;
      _startupVoiceDone = false;
    });
    // Flat overview of the route; user keeps exploring the map.
    _resetOverviewCamera();
  }

  Future<void> _resetOverviewCamera() async {
    try {
      await _map?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _me ?? _dest,
            zoom: 15.2,
            bearing: 0,
            tilt: 0,
          ),
        ),
      );
    } catch (_) {}
    await _fitRoute();
  }

  void _toggleNavigation() {
    if (_navigating) {
      _cancelNavigation();
      return;
    }
    setState(() {
      _navigating = true;
      _voiceOn = true; // always talk when starting
      _saidApproaching = false;
      _saidSoon = false;
      _saidArrived = false;
      _startupVoiceDone = false;
      _displayPos = _me;
      _displayHeading = _heading;
      _trail
        ..clear()
        ..addAll([if (_me != null) _me!]);
    });
    // Immediate street-level follow when navigation starts.
    if (_me != null) {
      _chaseNavCamera(_me!, bearing: _heading, force: true);
    }
    _gps = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen(_onPosition);

    // Speak right away on Start navigation (media volume).
    unawaited(_speakNavigationStart());
  }

  /// Close zoom + look-ahead; snappy follow while the arrow moves.
  Future<void> _chaseNavCamera(
    LatLng me, {
    required double bearing,
    bool force = false,
  }) async {
    final now = DateTime.now();
    if (!force && now.difference(_lastCam).inMilliseconds < 160) return;
    _lastCam = now;

    final b = bearing >= 0 ? bearing : 0.0;
    // Look ahead so the arrow sits lower and the road slides past (shows motion).
    final rad = b * math.pi / 180;
    final ahead = LatLng(
      me.latitude + (0.00048 * math.cos(rad)),
      me.longitude + (0.00048 * math.sin(rad)),
    );

    final update = CameraUpdate.newCameraPosition(
      CameraPosition(
        target: ahead,
        zoom: 18.2,
        bearing: b,
        tilt: 55,
      ),
    );

    try {
      if (force) {
        await _map?.animateCamera(update);
      } else {
        // moveCamera tracks GPS without laggy animate queues.
        await _map?.moveCamera(update);
      }
    } catch (_) {}
  }

  void _updateStepInstruction(LatLng me) {
    if (_steps.isEmpty) return;
    // Let the start phrase finish before turn prompts.
    if (!_startupVoiceDone) return;

    // Drop passed steps; keep the next useful instruction.
    var advanced = false;
    while (_steps.length > 1 && _distanceMeters(me, _steps.first.end) < 28) {
      _steps.removeAt(0);
      advanced = true;
      _saidApproaching = false;
      _saidSoon = false;
    }

    final step = _steps.first;
    final metersToEnd = _distanceMeters(me, step.end).round();
    final next = _speechClean(step.instruction);

    if (next != _instruction && mounted) {
      setState(() => _instruction = step.instruction);
    }

    // New step — one clear line only.
    if (advanced) {
      unawaited(_speak(next, force: true));
      return;
    }

    // Pre-turn prompts (once each) — skip if we just spoke.
    if (_speaking) return;
    if (!_saidSoon && metersToEnd <= 180 && metersToEnd > 70) {
      _saidSoon = true;
      unawaited(
        _speak('In ${_distancePhrase(metersToEnd)}, $next', force: true),
      );
    } else if (!_saidApproaching && metersToEnd <= 70) {
      _saidApproaching = true;
      unawaited(_speak('Now $next', force: true));
    }
  }

  double _resolveHeading(Position pos, LatLng me) {
    // Prefer course-over-ground once moving; else fall back to path bearing.
    if (pos.heading >= 0 && pos.speed > 1.0) return pos.heading;
    final prev = _prevMe;
    if (prev != null && _distanceMeters(prev, me) > 2.5) {
      return Geolocator.bearingBetween(
        prev.latitude,
        prev.longitude,
        me.latitude,
        me.longitude,
      );
    }
    if (pos.heading >= 0) return pos.heading;
    return _heading;
  }

  Future<void> _onPosition(Position pos) async {
    final me = LatLng(pos.latitude, pos.longitude);
    final bearing = _resolveHeading(pos, me);
    _speedMps = pos.speed.isFinite && pos.speed > 0 ? pos.speed : _speedMps;

    // Smooth motion: animate arrow from last display → new GPS.
    _prevMe = _displayPos ?? _me ?? me;
    _animFromHeading = _displayHeading;
    _me = me;
    _heading = (bearing + 360) % 360;

    // Motion trail so you can see you're moving.
    if (_trail.isEmpty || _distanceMeters(_trail.last, me) > 2.5) {
      _trail.add(me);
      if (_trail.length > 22) _trail.removeAt(0);
    }

    _moveAnim
      ?..duration = Duration(
        milliseconds: (_speedMps > 8 ? 420 : 750),
      )
      ..forward(from: 0);

    // Arrived at current stop (pickup or destination)?
    if (_distanceMeters(me, _dest) < 45) {
      if (!_saidArrived) {
        _saidArrived = true;
        // Keep GPS stream if we still have a next leg.
        if (_nextDest == null) {
          _gps?.cancel();
          _gps = null;
        }
        unawaited(_advanceToNextLegOrFinish());
      }
      return;
    }

    _updateStepInstruction(me);

    // Off-route check: reroute if > 60 m from the polyline (throttled).
    if (_route.isNotEmpty) {
      var nearest = double.infinity;
      for (final p in _route) {
        final d = _distanceMeters(me, p);
        if (d < nearest) nearest = d;
      }
      if (nearest > 60 &&
          DateTime.now().difference(_lastReroute).inSeconds > 12) {
        _lastReroute = DateTime.now();
        _fetchRoute();
      }
    }

    // Camera slightly behind so the arrow visibly slides forward.
    await _chaseNavCamera(me, bearing: _heading);
  }

  Widget _navFab({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Material(
      color: active ? _accent : const Color(0xFF2A2A2A),
      elevation: 4,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(
            icon,
            color: active ? Colors.black : Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }

  Future<void> _openGoogleMapsApp() async {
    final d = _dest;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${d.latitude},${d.longitude}&travelmode=driving',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _call() async {
    final phone =
        (widget.clientPhone ?? '').replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.isEmpty) return;
    await launchUrl(Uri.parse('tel:$phone'));
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    const sheetH = 168.0;

    return PopScope(
      canPop: !_navigating,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _navigating) _cancelNavigation();
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_me != null)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _me!,
                zoom: _navigating ? 18.4 : 15.2,
                tilt: _navigating ? 52 : 0,
                bearing: _navigating ? _heading : 0,
              ),
              // Brighter street labels while navigating; same dark base otherwise.
              style: _navigating ? kYangoNavMapStyle : kYangoMapStyle,
              // Custom arrow while navigating; system blue dot otherwise.
              myLocationEnabled: !_navigating,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: true,
              indoorViewEnabled: false,
              trafficEnabled: false,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              minMaxZoomPreference: _navigating
                  ? const MinMaxZoomPreference(16.8, 20)
                  : const MinMaxZoomPreference(3, 20),
              markers: {
                Marker(
                  markerId: const MarkerId('nav_dest'),
                  position: _dest,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
                  infoWindow: InfoWindow(title: _destLabel),
                ),
                if (_navigating)
                  Marker(
                    markerId: const MarkerId('nav_arrow'),
                    position: _displayPos ?? _me!,
                    icon: _navArrow ??
                        BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueYellow,
                        ),
                    rotation: _displayHeading,
                    flat: true,
                    anchor: const Offset(0.5, 0.55),
                    zIndexInt: 20,
                    consumeTapEvents: true,
                  ),
              },
              polylines: {
                if (_route.isNotEmpty)
                  Polyline(
                    polylineId: const PolylineId('nav_route'),
                    points: _route,
                    color: _routeBlue,
                    width: 6,
                    startCap: Cap.roundCap,
                    endCap: Cap.roundCap,
                    jointType: JointType.round,
                  ),
                if (_navigating && _trail.length >= 2)
                  Polyline(
                    polylineId: const PolylineId('nav_trail'),
                    points: List<LatLng>.from(_trail),
                    color: const Color(0xFFFFC107).withValues(alpha: 0.75),
                    width: 4,
                    startCap: Cap.roundCap,
                    endCap: Cap.roundCap,
                    jointType: JointType.round,
                  ),
              },
              padding: EdgeInsets.only(top: topPad + 88, bottom: sheetH + 8),
              onMapCreated: (c) {
                _map = c;
                if (_route.isNotEmpty) _fitRoute();
              },
            )
          else
            Center(
              child: _loading
                  ? const CircularProgressIndicator(color: _accent)
                  : Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error ?? 'Waiting for GPS…',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _start,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Retry GPS',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

          // Top turn instruction — compact dark bar (matches live map).
          Positioned(
            top: topPad + 10,
            left: 12,
            right: 12,
            child: Material(
              color: _sheet,
              elevation: 6,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: const BoxDecoration(
                        color: _routeBlue,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _navigating && _voiceOn
                            ? Icons.record_voice_over_rounded
                            : Icons.navigation_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _loading ? 'Fetching route…' : _instruction,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _navigating
                                ? (_voiceOn
                                    ? 'Voice on · ${_destLabel}'
                                    : 'Voice muted · ${_destLabel}')
                                : _destLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Neat FABs — voice + location + fit.
          Positioned(
            right: 12,
            bottom: sheetH + 14,
            child: Column(
              children: [
                _navFab(
                  icon: _voiceOn
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded,
                  active: _voiceOn,
                  onTap: () async {
                    final next = !_voiceOn;
                    setState(() => _voiceOn = next);
                    if (!next) {
                      await _tts.stop();
                    } else if (_navigating && _instruction.isNotEmpty) {
                      await _speak(_instruction, force: true);
                    }
                  },
                ),
                const SizedBox(height: 10),
                _navFab(
                  icon: Icons.my_location_rounded,
                  active: _navigating,
                  onTap: () {
                    if (_me == null) return;
                    if (!_navigating) _toggleNavigation();
                    _chaseNavCamera(_me!, bearing: _heading, force: true);
                  },
                ),
                const SizedBox(height: 10),
                _navFab(
                  icon: Icons.fit_screen_rounded,
                  onTap: () {
                    // Overview only — cancel follow, keep this map open.
                    if (_navigating) {
                      _cancelNavigation();
                    } else {
                      _fitRoute();
                    }
                  },
                ),
                const SizedBox(height: 10),
                _navFab(
                  icon: Icons.map_outlined,
                  onTap: _openGoogleMapsApp,
                ),
              ],
            ),
          ),

          // Dark bottom sheet — ETA + start/end (matches ride panel).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                16,
                12 + MediaQuery.of(context).padding.bottom,
              ),
              decoration: const BoxDecoration(
                color: _sheet,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFFF8A80),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _loading ? null : _start,
                            child: const Text(
                              'Retry GPS',
                              style: TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _remainingLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              [
                                if (_distanceText.isNotEmpty) _distanceText,
                                if ((widget.clientName ?? '').isNotEmpty)
                                  widget.clientName!,
                              ].join(' · '),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if ((widget.clientPhone ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Material(
                            color: _green.withValues(alpha: 0.18),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _call,
                              child: const Padding(
                                padding: EdgeInsets.all(12),
                                child: Icon(
                                  Icons.phone_rounded,
                                  color: _green,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed:
                          _loading || _me == null ? null : _toggleNavigation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _navigating ? const Color(0xFFE53935) : _accent,
                        foregroundColor:
                            _navigating ? Colors.white : Colors.black,
                        disabledBackgroundColor: const Color(0xFF333333),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: Icon(
                        _navigating
                            ? Icons.close_rounded
                            : Icons.navigation_rounded,
                      ),
                      label: Text(
                        _navigating ? 'Cancel navigation' : 'Start navigation',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}
