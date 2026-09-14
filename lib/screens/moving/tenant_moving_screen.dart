import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show Factory, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/google_routes.dart';
import '../../services/moving_firestore_service.dart';
import '../../services/moving_marketplace_service.dart';
import '../../services/moving_trip_notifier.dart';
import '../../theme/yango_map_style.dart';
import '../../widgets/moving_ride_status_panel.dart';
import '../../widgets/place_autocomplete_field.dart';
import '../../widgets/price_beep_overlay.dart';
import '../../widgets/price_offer_countdown.dart';
import '../../widgets/driver_identity_photos.dart';
import '../../widgets/driver_rating_sheet.dart';
import 'moving_booking_detail_screen.dart';
import 'moving_chat_screen.dart';
import 'tenant_my_shifts_screen.dart';
import '../../utils/app_error.dart';

/// Light map with street names kept on.
const String _kUberMapStyle = '''
[
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"simplified"}]},
  {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels","stylers":[{"visibility":"on"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#5f6368"}]},
  {"elementType":"geometry","stylers":[{"color":"#f2f2f2"}]},
  {"featureType":"water","stylers":[{"color":"#c8d7e3"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#e0e0e0"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#5f6368"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#ececec"}]}
]
''';

const Color _kRouteBlack = Color(0xFF14171A);
const Color _kPickupGreen = Color(0xFFFFC107);
const Color _kDropRed = Color(0xFFE53935);
// Bright nav-blue route like the delivery map example.
const Color _kNavRoute = Color(0xFF2F80FF);
const Color _kYangoRoute = Color(0xFFFFCC00);
const Color _kYangoRouteDark = Color(0xFFE6A800);

/// A car/truck cruising on the map (real driver or animated scout).
class _MapCar {
  _MapCar({
    required this.id,
    required this.position,
    required this.heading,
    this.name = 'Driver',
    this.real = false,
    this.viewed = false,
    this.orbitPhase = 0,
    this.orbitRadius = 0.004,
    this.speed = 1,
    this.routeIndex = 0,
    this.followRoute = false,
  });

  final String id;
  LatLng position;
  double heading;
  String name;
  bool real;
  bool viewed; // opened this request
  double orbitPhase;
  double orbitRadius;
  double speed;
  int routeIndex;
  bool followRoute;
}

/// Uber-style tenant page: request a move + see trip status.
class TenantMovingScreen extends StatefulWidget {
  const TenantMovingScreen({super.key, this.resumeTrip});

  /// Optional trip to restore on the map (from My shifts).
  final Map<String, dynamic>? resumeTrip;

  @override
  State<TenantMovingScreen> createState() => _TenantMovingScreenState();
}

class _TenantMovingScreenState extends State<TenantMovingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _radar;
  PlaceSelection? _pickup;
  PlaceSelection? _dropoff;
  // Uber-style defaults: move today, right now — user can still reschedule.
  DateTime _movingDate = DateTime.now();
  TimeOfDay _movingTime = TimeOfDay.now();
  final _itemsCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _fareScrollCtrl = ScrollController();
  final _itemsFocus = FocusNode();
  bool _submitting = false;

  // Trip preview map (like Uber's booking map).
  GoogleMapController? _tripMapCtrl;
  List<LatLng> _routePts = [];
  String _routeDistText = '';
  String _routeDurText = '';
  double? _offerPrice; // tenant's own fare offer (defaults to the estimate)

  // Yango-style fly-through navigation along the road route.
  bool _routeFlying = false;
  Timer? _flyTimer;
  int _flyStep = 0;
  List<LatLng> _flySamples = [];

  // Booking that was just posted from the map — we stay on the map and show
  // the searching/offers panel instead of leaving the screen.
  Map<String, dynamic>? _activeTrip;

  // Fare panel stays minimized (aside) until the user taps Expand.
  bool _panelCollapsed = true;
  LatLng _mapCenter = const LatLng(-15.4167, 28.2833); // Lusaka fallback
  bool _hasGps = false;
  bool _locatingPickup = false;
  bool _loadingTrips = true;
  String? _error;
  List<Map<String, dynamic>> _trips = [];

  // Live driver offers per open booking (like Uber's "drivers responding").
  Timer? _offerTimer;
  Timer? _nearbyTimer;
  final Map<int, List<Map<String, dynamic>>> _driverOffers = {};
  final Set<int> _seenOfferIds = {};
  final Set<int> _acceptedPopupShown = {};
  final Set<int> _ratingPromptShown = {};
  bool _offerSheetOpen = false;
  bool _responsePopupOpen = false;
  bool _ratingPromptOpen = false;

  /// Incoming driver price — same SENT/BEEP map design as the driver app.
  late final AnimationController _beepPulse;
  Timer? _beepTimer;
  bool _priceBeepActive = false;
  /// Driver-bid style pulse while waiting for driver prices (Shift map only).
  bool _searchWaitingPulse = false;
  int _carTickSkip = 0;
  bool _priceIncomingFlash = false;
  double? _incomingPriceAmount;
  DateTime? _incomingPriceEnds;

  /// Live assigned-driver tracking on the client map.
  Timer? _liveTrackTimer;
  StreamSubscription<Map<String, dynamic>?>? _firestoreSub;
  int? _firestoreWatchId;
  LatLng? _liveDriverPos;
  LatLng? _prevLiveDriverPos;
  LatLng? _displayDriverPos; // smoothed (driver-map feel)
  double _liveDriverHeading = 0;
  double _displayDriverHeading = 0;
  double _animFromHeading = 0;
  AnimationController? _driverSmooth;
  bool _clientCamFollow = true; // pan map → pause; recenter → resume
  bool _programmaticCam = false; // ignore onCameraMoveStarted from our chase
  String _liveEtaLabel = '';
  int _liveEtaSeconds = 0;
  DateTime? _liveEtaFetchedAt;
  DateTime _lastEtaFetch = DateTime.fromMillisecondsSinceEpoch(0);
  final FlutterTts _clientTts = FlutterTts();
  bool _clientVoiceReady = false;
  bool _saidAcceptVoice = false;
  bool _saidStartVoice = false;

  // Uber-style moving cars on the map while searching.
  late final AnimationController _carAnim;
  BitmapDescriptor? _truckIcon;
  BitmapDescriptor? _navArrowIcon;
  BitmapDescriptor? _viewedArrowIcon;
  BitmapDescriptor? _pickupPin;
  BitmapDescriptor? _dropPin;
  BitmapDescriptor? _cornerPin;
  final List<_MapCar> _cars = [];
  List<LatLng> _routeCorners = [];
  List<Map<String, dynamic>> _nearbyDrivers = [];
  /// Live: drivers who opened the request but have not sent a price.
  List<Map<String, dynamic>> _bookingViewers = [];
  int _seenTotal = 0;
  int _respondedCount = 0;
  Timer? _viewersTimer;
  bool _searching3d = false;
  bool _previewDrivers = false;

  @override
  void initState() {
    super.initState();
    _radar = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
    _beepPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _carAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 50),
    )..addListener(_tickCars);
    _driverSmooth = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(_onDriverSmoothTick);
    _buildTruckIcon();
    _buildNavArrowIcon();
    _buildViewedArrowIcon();
    _buildRoutePins();
    _buildCornerPin();
    _loadPhone();
    _loadTrips();
    _resolveGps();
    // Faster while rides are live so renegotiation prices pop up quickly.
    _offerTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _pollDriverOffers();
    });
    _itemsFocus.addListener(() {
      if (_itemsFocus.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_fareScrollCtrl.hasClients) return;
          _fareScrollCtrl.animateTo(
            _fareScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        });
      }
    });
    final resume = widget.resumeTrip;
    if (resume != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resumeTripOnMap(resume);
      });
    }
  }

  /// Phone comes straight from the account — no manual typing.
  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    var phone = prefs.getString('phone') ?? '';
    if (phone.isEmpty) {
      try {
        final profile = await ApiService.getProfile();
        phone = (profile['user']?['phone'] ?? profile['phone'] ?? '')
            .toString()
            .trim();
        if (phone.isNotEmpty) await prefs.setString('phone', phone);
      } catch (_) {}
    }
    if (mounted) setState(() => _phoneCtrl.text = phone);
  }

  Future<void> _resolveGps() async {
    try {
      if (kIsWeb) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      setState(() {
        _mapCenter = LatLng(pos.latitude, pos.longitude);
        _hasGps = true;
      });
      if (_pickup == null && _dropoff == null) {
        _tripMapCtrl?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _mapCenter, zoom: 14.5),
          ),
        );
      }
    } catch (_) {}
  }

  /// One-tap Uber-style pickup at the tenant's GPS position.
  Future<void> _useMyLocationAsPickup() async {
    setState(() => _locatingPickup = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied.');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      // Turn GPS into a readable street address so the driver knows the spot.
      final address = await ApiService.reverseGeocode(
        pos.latitude,
        pos.longitude,
      );
      if (!mounted) return;
      _setPickup(PlaceSelection(
        address: address ?? 'My current location',
        placeId: '',
        latitude: pos.latitude,
        longitude: pos.longitude,
      ));
      setState(() {
        _mapCenter = LatLng(pos.latitude, pos.longitude);
        _hasGps = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get your location. Type the pickup instead.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locatingPickup = false);
    }
  }

  /// Uber-style row that opens the search popup.
  Widget _placeRow({required bool isPickup, required bool isDark}) {
    final sel = isPickup ? _pickup : _dropoff;
    final hint = isPickup ? 'Pickup location' : 'Drop-off location';
    return InkWell(
      onTap: () => _openPlaceSearch(isPickup: isPickup),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
        child: Row(
          children: [
            Icon(
              isPickup ? Icons.radio_button_checked : Icons.location_on,
              size: 20,
              color: isPickup ? const Color(0xFFFFC107) : Colors.redAccent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                sel?.address ?? hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  color: sel == null
                      ? (isDark ? Colors.white38 : Colors.black38)
                      : (isDark ? Colors.white : Colors.black87),
                ),
              ),
            ),
            if (isPickup && _locatingPickup)
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFFC107),
                ),
              )
            else
              Icon(
                Icons.search_rounded,
                size: 18,
                color: isDark ? Colors.white38 : Colors.black26,
              ),
          ],
        ),
      ),
    );
  }

  /// Full popup search with autocomplete; sits above the keyboard.
  Future<void> _openPlaceSearch({required bool isPickup}) async {
    final result = await showModalBottomSheet<PlaceSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlaceSearchSheet(
        title: isPickup ? 'Set pickup' : 'Set drop-off',
        hint: isPickup
            ? 'Search pickup location'
            : 'Search drop-off location',
        biasLat: _hasGps ? _mapCenter.latitude : null,
        biasLng: _hasGps ? _mapCenter.longitude : null,
        showUseMyLocation: isPickup,
      ),
    );
    if (result == null || !mounted) return;
    if (result.placeId == '__gps__') {
      await _useMyLocationAsPickup();
      return;
    }
    if (isPickup) {
      _setPickup(result);
    } else {
      _setDropoff(result);
    }
  }

  void _setPickup(PlaceSelection p) {
    _stopRouteNavigation();
    _stopPreviewDrivers();
    setState(() {
      _pickup = p;
      _routePts = [];
      _routeCorners = [];
      _routeDistText = '';
      _routeDurText = '';
      _offerPrice = null;
      _panelCollapsed = true; // stay aside until Expand is tapped
    });
    _updateTripRoute();
  }

  void _setDropoff(PlaceSelection p) {
    _stopRouteNavigation();
    _stopPreviewDrivers();
    setState(() {
      _dropoff = p;
      _routePts = [];
      _routeCorners = [];
      _routeDistText = '';
      _routeDurText = '';
      _offerPrice = null;
      _panelCollapsed = true; // stay aside until Expand is tapped
    });
    _updateTripRoute();
  }

  /// Draws the real road route, then centers the full path responsively.
  Future<void> _updateTripRoute({bool forLive = false}) async {
    final p = _pickup;
    final d = _dropoff;
    if (p == null || d == null) return;

    final result = await GoogleRoutes.fetchDrivingRouteDetails(
      origin: LatLng(p.latitude, p.longitude),
      destination: LatLng(d.latitude, d.longitude),
    );
    if (!mounted) return;
    if (result == null || result.points.isEmpty) return;

    setState(() {
      _routePts = result.points;
      _routeDistText = result.distanceText;
      _routeDurText = result.durationText;
      _routeCorners = _detectRouteCorners(result.points);
      if (!forLive) {
        _panelCollapsed = true; // Duration | Distance bar while planning
      }
    });

    if (!forLive) {
      _buildFlySamples();
      _startPreviewDrivers();
      await _fitRouteBounds(animated: true);
    }
  }

  void _syncPlacesFromBooking(Map<String, dynamic> booking) {
    final p = booking['pickup'];
    final d = booking['dropoff'];
    if (p is Map) {
      final lat = double.tryParse('${p['latitude']}');
      final lng = double.tryParse('${p['longitude']}');
      if (lat != null && lng != null) {
        _pickup = PlaceSelection(
          address: (p['address'] ?? _pickup?.address ?? 'Pickup').toString(),
          latitude: lat,
          longitude: lng,
          placeId: (p['place_id'] ?? _pickup?.placeId ?? '').toString(),
        );
      }
    }
    if (d is Map) {
      final lat = double.tryParse('${d['latitude']}');
      final lng = double.tryParse('${d['longitude']}');
      if (lat != null && lng != null) {
        _dropoff = PlaceSelection(
          address: (d['address'] ?? _dropoff?.address ?? 'Destination').toString(),
          latitude: lat,
          longitude: lng,
          placeId: (d['place_id'] ?? _dropoff?.placeId ?? '').toString(),
        );
      }
    }
  }

  /// Keep the road route on the client map once accepted / trip started.
  Future<void> _ensureLiveTripRoute({Map<String, dynamic>? booking}) async {
    final b = booking ?? _activeTrip;
    if (b != null) _syncPlacesFromBooking(b);
    if (_pickup == null || _dropoff == null) return;
    if (_routePts.length >= 2) return;
    await _updateTripRoute(forLive: true);
  }

  /// Sharp turns on the road route (bearing change) — shown as corner dots.
  List<LatLng> _detectRouteCorners(List<LatLng> pts) {
    if (pts.length < 3) return const [];
    final corners = <LatLng>[];
    for (var i = 1; i < pts.length - 1; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final c = pts[i + 1];
      final b1 = _bearingBetween(a, b);
      final b2 = _bearingBetween(b, c);
      var delta = (b2 - b1).abs();
      if (delta > 180) delta = 360 - delta;
      // Real street corners / turns — ignore tiny wiggles.
      if (delta >= 28) {
        // Skip points that are too close to the previous corner.
        if (corners.isEmpty ||
            Geolocator.distanceBetween(
                  corners.last.latitude,
                  corners.last.longitude,
                  b.latitude,
                  b.longitude,
                ) >
                55) {
          corners.add(b);
        }
      }
    }
    // Cap so the map stays readable.
    if (corners.length <= 18) return corners;
    final step = (corners.length / 18).ceil();
    return [
      for (var i = 0; i < corners.length; i += step) corners[i],
    ];
  }

  /// Smooth auto-focus: pans to the route, then eases into city/district zoom.
  Future<void> _fitRouteBounds({bool animated = true}) async {
    final controller = _tripMapCtrl;
    if (controller == null) return;

    final points = _mapFocusPoints();
    if (points.isEmpty) return;

    var minLat = points.first.latitude, maxLat = points.first.latitude;
    var minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Keep a city-block minimum span so short trips still show streets.
    if ((maxLat - minLat).abs() < 0.003) {
      minLat -= 0.0035;
      maxLat += 0.0035;
    }
    if ((maxLng - minLng).abs() < 0.003) {
      minLng -= 0.0035;
      maxLng += 0.0035;
    }

    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final size = MediaQuery.of(context).size;
    final topPad = _activeTrip != null
        ? 28.0
        : (MediaQuery.of(context).padding.top + 88);
    final bottomPad = (_panelCollapsed || _activeTrip != null)
        ? 130.0
        : size.height * 0.36;

    final latSpan = (maxLat - minLat).abs() * 1.12;
    final lngSpan = (maxLng - minLng).abs() * 1.12;
    var zoom = _zoomForSpan(
      latSpan: latSpan,
      lngSpan: lngSpan,
      mapWidth: size.width,
      mapHeight: size.height - topPad - bottomPad,
      padding: 36,
      tilt: 0,
    );

    // City / district band — never province-level.
    zoom = zoom.clamp(12.8, 16.2);

    try {
      if (!animated) {
        await controller.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: center, zoom: zoom, tilt: 0, bearing: 0),
          ),
        );
        return;
      }

      // Step 1 — glide to route center at a soft mid zoom.
      final midZoom = (zoom - 1.1).clamp(12.5, 15.0);
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: center, zoom: midZoom, tilt: 0, bearing: 0),
        ),
      );
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted || _tripMapCtrl == null) return;

      // Step 2 — ease into the final city/district focus.
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: center, zoom: zoom, tilt: 0, bearing: 0),
        ),
      );
    } catch (_) {
      try {
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: center, zoom: 14.2),
          ),
        );
      } catch (_) {}
    }
  }

  void _buildFlySamples() {
    if (_routePts.length <= 2) {
      _flySamples = List.from(_routePts);
      return;
    }
    const target = 55;
    final step = math.max(1, (_routePts.length / target).floor());
    _flySamples = [
      for (var i = 0; i < _routePts.length; i += step) _routePts[i],
      _routePts.last,
    ];
  }

  double _bearingBetween(LatLng from, LatLng to) {
    final dLat = to.latitude - from.latitude;
    final dLng = to.longitude - from.longitude;
    if (dLat.abs() < 1e-9 && dLng.abs() < 1e-9) return _tripBearing();
    return (math.atan2(dLng, dLat) * 180 / math.pi + 360) % 360;
  }

  /// Yango-style 360 camera: high tilt, zoomed in, aligned with the road.
  Future<void> _fitYangoCamera({bool atStart = false, int? step}) async {
    final controller = _tripMapCtrl;
    if (controller == null || _routePts.isEmpty) return;

    final idx = step ?? (atStart ? 0 : _routePts.length ~/ 2);
    final safeIdx = idx.clamp(0, _routePts.length - 1);
    final target = _routePts[safeIdx];
    final nextIdx = math.min(safeIdx + 1, _routePts.length - 1);
    final bearing = _bearingBetween(target, _routePts[nextIdx]);

    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: 17.4,
            tilt: 67,
            bearing: bearing,
          ),
        ),
      );
    } catch (_) {}
  }

  /// Animates the camera along the road route (Yango navigate preview).
  void _startRouteNavigation() {
    if (_flySamples.length < 2 || _tripMapCtrl == null) return;
    _stopRouteNavigation();
    setState(() {
      _routeFlying = true;
      _panelCollapsed = true;
      _flyStep = 0;
    });
    _fitYangoCamera(atStart: true);

    _flyTimer = Timer.periodic(const Duration(milliseconds: 110), (_) async {
      if (!mounted || !_routeFlying) return;
      if (_flyStep >= _flySamples.length) {
        _stopRouteNavigation();
        await _fitRouteBounds(animated: true);
        return;
      }

      final from = _flySamples[_flyStep];
      final to = _flySamples[math.min(_flyStep + 1, _flySamples.length - 1)];
      final bearing = _bearingBetween(from, to);

      try {
        await _tripMapCtrl?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: from,
              zoom: 17.6,
              tilt: 68,
              bearing: bearing,
            ),
          ),
        );
      } catch (_) {}

      _flyStep++;
    });
  }

  void _stopRouteNavigation() {
    _flyTimer?.cancel();
    _flyTimer = null;
    if (mounted) setState(() => _routeFlying = false);
  }

  /// All points that should stay visible (route, trucks, endpoints).
  List<LatLng> _mapFocusPoints() {
    final points = <LatLng>[
      if (_pickup != null) LatLng(_pickup!.latitude, _pickup!.longitude),
      if (_dropoff != null) LatLng(_dropoff!.latitude, _dropoff!.longitude),
      ..._routePts,
    ];
    if (_searching3d) {
      for (final car in _cars) {
        points.add(car.position);
      }
    }
    return points;
  }

  /// Bearing along the trip (pickup → drop-off) for a nicer 3D angle.
  double _tripBearing() {
    final p = _pickup;
    final d = _dropoff;
    if (p == null || d == null) return 0;
    final dLat = d.latitude - p.latitude;
    final dLng = d.longitude - p.longitude;
    if (dLat.abs() < 1e-9 && dLng.abs() < 1e-9) return 0;
    return (math.atan2(dLng, dLat) * 180 / math.pi + 360) % 360;
  }

  /// Zoom level that fits a lat/lng span inside the visible map area.
  double _zoomForSpan({
    required double latSpan,
    required double lngSpan,
    required double mapWidth,
    required double mapHeight,
    required double padding,
    required double tilt,
  }) {
    const world = 256.0;
    latSpan = latSpan.clamp(0.0005, 90);
    lngSpan = lngSpan.clamp(0.0005, 180);

    double latRad(double lat) {
      final s = math.sin(lat * math.pi / 180);
      return math.log((1 + s) / (1 - s)) / 2;
    }

    final latFraction =
        ((latRad(latSpan / 2 + 0.001) - latRad(-latSpan / 2 - 0.001)) / math.pi)
            .abs()
            .clamp(0.001, 1.0);
    final lngFraction = (lngSpan / 360).clamp(0.001, 1.0);

    final h = (mapHeight - padding * 2).clamp(100, mapHeight);
    final w = (mapWidth - padding * 2).clamp(100, mapWidth);

    final latZoom = math.log(h / world / latFraction) / math.ln2;
    final lngZoom = math.log(w / world / lngFraction) / math.ln2;
    var zoom = math.min(latZoom, lngZoom);

    // Tilted cameras need a slightly wider view so buildings + route fit.
    if (tilt > 0) zoom -= (tilt / 60) * 1.4;
    // Floor at city/district (~12.8), never province (~10–11).
    return zoom.clamp(12.8, 18.0);
  }

  /// Smart camera: flat bounds overview (example style) or 3D search chase.
  Future<void> _fitMapCamera({
    bool preview3d = false,
    bool searching = false,
    bool yangoOverview = false,
  }) async {
    final controller = _tripMapCtrl;
    if (controller == null) return;

    // Flat responsive overview — matches the delivery-nav screenshot.
    if (!searching && !preview3d && !_searching3d) {
      await _fitRouteBounds(animated: true);
      return;
    }
    if (yangoOverview && !searching) {
      await _fitRouteBounds(animated: true);
      return;
    }

    final points = _mapFocusPoints();
    final size = MediaQuery.of(context).size;
    final topPad = searching ? 24.0 : 130.0;
    final bottomPad = (_panelCollapsed || searching || _activeTrip != null)
        ? 120.0
        : size.height * 0.36;
    final sidePad = 48.0;

    final use3d = searching || preview3d || _searching3d;
    final tilt = searching ? 62.0 : (use3d ? 48.0 : 0.0);
    final bearing = use3d ? _tripBearing() : 0.0;

    try {
      if (points.isEmpty) {
        if (_hasGps) {
          await controller.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: _mapCenter,
                zoom: 14.5,
                tilt: tilt,
                bearing: bearing,
              ),
            ),
          );
        }
        return;
      }

      var minLat = points.first.latitude, maxLat = points.first.latitude;
      var minLng = points.first.longitude, maxLng = points.first.longitude;
      for (final p in points) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }

      if (searching) {
        const m = 0.004;
        minLat -= m;
        maxLat += m;
        minLng -= m;
        maxLng += m;
      }

      final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
      final latSpan = (maxLat - minLat).abs();
      final lngSpan = (maxLng - minLng).abs();
      final zoom = _zoomForSpan(
        latSpan: latSpan < 0.002 ? 0.008 : latSpan * 1.18,
        lngSpan: lngSpan < 0.002 ? 0.008 : lngSpan * 1.18,
        mapWidth: size.width,
        mapHeight: size.height,
        padding: sidePad + (topPad + bottomPad) / 4,
        tilt: tilt,
      );

      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: center,
            zoom: zoom,
            tilt: tilt,
            bearing: bearing,
          ),
        ),
      );
    } catch (_) {
      await _fitRouteBounds(animated: true);
    }
  }

  Future<void> _loadTrips() async {
    setState(() {
      _loadingTrips = true;
      _error = null;
    });
    try {
      final trips = await MovingMarketplaceService.listBookings();
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _loadingTrips = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.userMessage(e);
        _loadingTrips = false;
      });
    }
  }

  @override
  void dispose() {
    _stopPriceBeep();
    _searchWaitingPulse = false;
    _liveTrackTimer?.cancel();
    _firestoreSub?.cancel();
    _offerTimer?.cancel();
    _nearbyTimer?.cancel();
    _viewersTimer?.cancel();
    _flyTimer?.cancel();
    _clientTts.stop();
    _driverSmooth?.dispose();
    _carAnim.dispose();
    _radar.dispose();
    _beepPulse.dispose();
    _itemsCtrl.dispose();
    _phoneCtrl.dispose();
    _fareScrollCtrl.dispose();
    _itemsFocus.dispose();
    _tripMapCtrl?.dispose();
    super.dispose();
  }

  bool get _isLiveRide {
    final s = (_activeTrip?['status'] ?? '').toString();
    return s == 'accepted' || s == 'in_progress' || s == 'arrived';
  }

  String get _remainingEtaDisplay {
    if (_liveEtaSeconds <= 0) return _liveEtaLabel;
    final fetched = _liveEtaFetchedAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(fetched).inSeconds;
    final left = (_liveEtaSeconds - elapsed).clamp(0, _liveEtaSeconds);
    if (left <= 45) return 'Arriving now';
    final mins = (left / 60).ceil();
    return '$mins min left';
  }

  Future<void> _ensureClientVoice() async {
    if (_clientVoiceReady) return;
    try {
      await _clientTts.setLanguage('en-US');
      await _clientTts.setSpeechRate(0.48);
      await _clientTts.setVolume(1.0);
      try {
        await _clientTts.setAudioAttributesForNavigation();
      } catch (_) {}
      _clientVoiceReady = true;
    } catch (_) {
      _clientVoiceReady = false;
    }
  }

  Future<void> _speakClient(String text) async {
    if (text.trim().isEmpty) return;
    await _ensureClientVoice();
    if (!_clientVoiceReady) return;
    try {
      await _clientTts.speak(text, focus: true);
    } catch (_) {
      try {
        await _clientTts.speak(text);
      } catch (_) {}
    }
  }

  /// Remaining time until driver reaches pickup (accepted) or destination (started).
  Future<void> _refreshLiveEta({bool force = false}) async {
    if (!_isLiveRide) return;
    final driver = _liveDriverPos;
    if (driver == null) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastEtaFetch).inSeconds < 22) return;
    _lastEtaFetch = now;

    final status = (_activeTrip?['status'] ?? '').toString();
    LatLng? target;
    if (status == 'in_progress' || status == 'arrived') {
      if (_dropoff != null) {
        target = LatLng(_dropoff!.latitude, _dropoff!.longitude);
      }
    } else if (_pickup != null) {
      target = LatLng(_pickup!.latitude, _pickup!.longitude);
    }
    if (target == null) return;

    final result = await GoogleRoutes.fetchDrivingRouteDetails(
      origin: driver,
      destination: target,
    );
    if (!mounted || result == null) return;
    setState(() {
      _liveEtaSeconds = result.durationSeconds;
      _liveEtaFetchedAt = DateTime.now();
      _liveEtaLabel = result.durationText;
    });
  }

  void _syncLiveDriverTracking() {
    if (!_isLiveRide) {
      _liveTrackTimer?.cancel();
      _liveTrackTimer = null;
      _liveDriverPos = null;
      _prevLiveDriverPos = null;
      _displayDriverPos = null;
      _clientCamFollow = true;
      _syncFirestoreWatch();
      return;
    }
    _updateLiveDriverFromTrip(_activeTrip!);
    _syncFirestoreWatch();
    _liveTrackTimer ??= Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _pollLiveTripTracking();
    });
  }

  void _syncFirestoreWatch() {
    final id = int.tryParse(_activeTrip?['id']?.toString() ?? '');
    if (id == null) {
      _firestoreSub?.cancel();
      _firestoreSub = null;
      _firestoreWatchId = null;
      return;
    }
    final status = (_activeTrip?['status'] ?? '').toString();
    if (status == 'completed' || status == 'cancelled') {
      _firestoreSub?.cancel();
      _firestoreSub = null;
      _firestoreWatchId = null;
      return;
    }
    if (_firestoreWatchId == id && _firestoreSub != null) return;

    _firestoreSub?.cancel();
    _firestoreWatchId = id;
    _firestoreSub = MovingFirestoreService.watchBooking(id).listen(
      (booking) {
        if (!mounted || booking == null) return;
        final st = (booking['status'] ?? '').toString();
        if (st == 'accepted' ||
            st == 'in_progress' ||
            st == 'arrived') {
          unawaited(_applyLiveBookingUpdate(booking));
          _syncLiveDriverTracking();
        } else {
          setState(() => _activeTrip = {...?_activeTrip, ...booking});
        }
      },
      onError: (_) {},
    );
  }

  Future<void> _applyLiveBookingUpdate(Map<String, dynamic> booking) async {
    if (!mounted) return;
    final prevStatus = (_activeTrip?['status'] ?? '').toString();
    setState(() => _activeTrip = {...?_activeTrip, ...booking});
    unawaited(
      MovingTripNotifier.handleBookingStatus(booking, isDriver: false),
    );
    _updateLiveDriverFromTrip(booking);
    _syncPlacesFromBooking(booking);
    final nowStatus = (booking['status'] ?? '').toString();
    final startedNow =
        prevStatus != 'in_progress' && nowStatus == 'in_progress';
    if (_routePts.length < 2 || startedNow) {
      if (startedNow) _routePts = [];
      unawaited(_ensureLiveTripRoute(booking: booking));
    }
    unawaited(_refreshLiveEta(force: startedNow));
    if (startedNow && !_saidStartVoice) {
      _saidStartVoice = true;
      unawaited(
        _speakClient(
          'Your HouseRent Shifts trip has started. '
          '${_remainingEtaDisplay.isNotEmpty && _remainingEtaDisplay != '—' ? 'About $_remainingEtaDisplay to destination.' : ''}',
        ),
      );
    }
    if (mounted) setState(() {});
  }

  void _onDriverSmoothTick() {
    final from = _prevLiveDriverPos;
    final to = _liveDriverPos;
    final anim = _driverSmooth;
    if (from == null || to == null || anim == null || !_isLiveRide) return;
    final t = Curves.easeOut.transform(anim.value);
    final lat = from.latitude + (to.latitude - from.latitude) * t;
    final lng = from.longitude + (to.longitude - from.longitude) * t;
    var dH = _liveDriverHeading - _animFromHeading;
    while (dH > 180) {
      dH -= 360;
    }
    while (dH < -180) {
      dH += 360;
    }
    if (!mounted) return;
    setState(() {
      _displayDriverPos = LatLng(lat, lng);
      _displayDriverHeading = (_animFromHeading + dH * t + 360) % 360;
    });
    // Chase with smoothed position (moveCamera — no laggy animate queue).
    unawaited(
      _followLiveDriverCamera(
        pos: _displayDriverPos,
        bearing: _displayDriverHeading,
      ),
    );
  }

  Future<void> _pollLiveTripTracking() async {
    final id = int.tryParse(_activeTrip?['id']?.toString() ?? '');
    if (id == null || !_isLiveRide) return;
    try {
      final booking = await MovingMarketplaceService.getBooking(id);
      if (!mounted) return;
      await _applyLiveBookingUpdate(booking);
    } catch (_) {}
  }

  void _updateLiveDriverFromTrip(Map<String, dynamic> trip) {
    final driver = trip['driver'];
    if (driver is! Map) return;
    final loc = driver['location'];
    if (loc is! Map) return;
    final lat = double.tryParse('${loc['latitude']}');
    final lng = double.tryParse('${loc['longitude']}');
    if (lat == null || lng == null) return;
    if (lat.abs() < 0.0001 && lng.abs() < 0.0001) return;
    final next = LatLng(lat, lng);
    if (_liveDriverPos != null) {
      final moved = Geolocator.distanceBetween(
        _liveDriverPos!.latitude,
        _liveDriverPos!.longitude,
        next.latitude,
        next.longitude,
      );
      if (moved > 3) {
        _liveDriverHeading = Geolocator.bearingBetween(
          _liveDriverPos!.latitude,
          _liveDriverPos!.longitude,
          next.latitude,
          next.longitude,
        );
      }
    }
    final movedEnough = _liveDriverPos == null ||
        Geolocator.distanceBetween(
              _liveDriverPos!.latitude,
              _liveDriverPos!.longitude,
              next.latitude,
              next.longitude,
            ) >
            4;
    _prevLiveDriverPos = _displayDriverPos ?? _liveDriverPos ?? next;
    _animFromHeading = _displayDriverHeading;
    _liveDriverPos = next;
    if (_displayDriverPos == null) {
      _displayDriverPos = next;
      _displayDriverHeading = _liveDriverHeading;
    }
    if (!mounted) return;
    setState(() {});
    if (movedEnough || _displayDriverPos == next) {
      _driverSmooth
        ?..duration = const Duration(milliseconds: 1100)
        ..forward(from: 0);
      unawaited(_refreshLiveEta());
    }
  }

  DateTime _lastLiveCam = DateTime.fromMillisecondsSinceEpoch(0);

  /// Driver-nav style chase: close zoom, tilt, look-ahead, moveCamera (smooth).
  Future<void> _followLiveDriverCamera({
    bool force = false,
    LatLng? pos,
    double? bearing,
  }) async {
    final ctrl = _tripMapCtrl;
    final driver = pos ?? _displayDriverPos ?? _liveDriverPos;
    if (ctrl == null || driver == null || !_isLiveRide) return;
    if (!_clientCamFollow && !force) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastLiveCam).inMilliseconds < 160) return;
    _lastLiveCam = now;

    final b = bearing ?? _displayDriverHeading;
    final heading = b >= 0 ? b : 0.0;
    final rad = heading * math.pi / 180;
    // Look ahead so the truck sits lower and the road slides past.
    final ahead = LatLng(
      driver.latitude + (0.00042 * math.cos(rad)),
      driver.longitude + (0.00042 * math.sin(rad)),
    );

    final update = CameraUpdate.newCameraPosition(
      CameraPosition(
        target: ahead,
        zoom: 17.85,
        bearing: heading,
        tilt: 48,
      ),
    );

    _programmaticCam = true;
    try {
      if (force) {
        _clientCamFollow = true;
        await ctrl.animateCamera(update);
      } else {
        await ctrl.moveCamera(update);
      }
    } catch (_) {
    } finally {
      // Let the platform fire move-started for our update, then clear.
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        _programmaticCam = false;
      });
    }
  }

  void _playBeep() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);
  }

  void _startPriceBeep(double amount) {
    _stopPriceBeep();
    if (!mounted) return;
    setState(() {
      _searchWaitingPulse = false;
      _priceBeepActive = true;
      _priceIncomingFlash = true;
      _incomingPriceAmount = amount;
      _incomingPriceEnds = DateTime.now().add(const Duration(seconds: 30));
      _panelCollapsed = true;
    });
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && _priceBeepActive) {
        setState(() => _priceIncomingFlash = false);
      }
    });
    _beepPulse.repeat();
    _playBeep();
    _beepTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!_priceBeepActive) return;
      _playBeep();
    });
  }

  Future<void> _openMyShifts() async {
    final trip = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => const TenantMyShiftsScreen(returnTripToCaller: true),
      ),
    );
    if (!mounted) return;
    await _loadTrips();
    if (trip != null && mounted) {
      await _resumeTripOnMap(trip);
    }
  }

  void _stopPriceBeep({bool resumeSearchPulse = false}) {
    _beepTimer?.cancel();
    _beepTimer = null;
    if (_beepPulse.isAnimating) _beepPulse.stop();
    if (!mounted) return;
    setState(() {
      _priceBeepActive = false;
      _priceIncomingFlash = false;
      _incomingPriceAmount = null;
      _incomingPriceEnds = null;
    });
    if (resumeSearchPulse) {
      final st = (_activeTrip?['status'] ?? '').toString();
      if (_searching3d && st == 'open') {
        _startSearchWaitingPulse();
      }
    }
  }

  /// Uber-style pickup (green car pin) and destination (red car pin).
  Future<void> _buildRoutePins() async {
    _pickupPin = await _drawCarPin(_kPickupGreen);
    _dropPin = await _drawCarPin(_kDropRed);
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _drawCarPin(Color ring) async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);
    const radius = 18.0;

    canvas.drawCircle(
      center.translate(0, 2),
      radius + 5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(center, radius, Paint()..color = ring);
    canvas.drawCircle(
      center,
      radius - 2.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center.translate(0, 1), width: 16, height: 10),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(body, Paint()..color = Colors.white);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center.translate(0, -4), width: 10, height: 6),
        const Radius.circular(1.5),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );

    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  /// Small white/blue disc marking a street corner / turn on the route.
  Future<void> _buildCornerPin() async {
    const size = 48.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);
    canvas.drawCircle(
      center,
      7,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      center,
      7,
      Paint()
        ..color = _kNavRoute
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(center, 2.5, Paint()..color = _kNavRoute);
    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted || bytes == null) return;
    setState(() {
      _cornerPin = BitmapDescriptor.bytes(bytes.buffer.asUint8List());
    });
  }

  /// Nav-blue road route with sharp corner joints + turn markers.
  Set<Polyline> _uberRoutePolylines() {
    final lines = <Polyline>{};
    List<LatLng> pts;
    bool loading;

    if (_routePts.isNotEmpty) {
      pts = _routePts;
      loading = false;
    } else if (_pickup != null && _dropoff != null) {
      pts = [
        LatLng(_pickup!.latitude, _pickup!.longitude),
        LatLng(_dropoff!.latitude, _dropoff!.longitude),
      ];
      loading = true;
    } else {
      return lines;
    }

    if (loading) {
      lines.add(
        Polyline(
          polylineId: const PolylineId('trip_loading'),
          points: pts,
          color: _kNavRoute.withValues(alpha: 0.35),
          width: 5,
          patterns: [PatternItem.dash(20), PatternItem.gap(12)],
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
      return lines;
    }

    // Outer dark edge so corners read clearly on the night map.
    lines.add(
      Polyline(
        polylineId: const PolylineId('trip_halo'),
        points: pts,
        color: const Color(0xFF0B1F4A),
        width: 14,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.bevel,
        zIndex: 1,
      ),
    );
    // Main blue road body — miter joints keep street corners crisp.
    lines.add(
      Polyline(
        polylineId: const PolylineId('trip'),
        points: pts,
        color: _kNavRoute,
        width: 8,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.bevel,
        zIndex: 2,
      ),
    );
    // Light centerline so turns stand out vs a flat blob.
    lines.add(
      Polyline(
        polylineId: const PolylineId('trip_center'),
        points: pts,
        color: Colors.white.withValues(alpha: 0.55),
        width: 2,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.bevel,
        zIndex: 3,
      ),
    );
    return lines;
  }

  /// Yellow nav arrow (same idea as driver nav) for the live assigned mover.
  Future<void> _buildNavArrowIcon() async {
    _navArrowIcon = await _drawHeadingArrow(
      fill: const Color(0xFFFFC107),
      ring: Colors.white,
    );
    if (mounted) setState(() {});
  }

  /// Second arrow — green tip for drivers who have viewed the request.
  Future<void> _buildViewedArrowIcon() async {
    _viewedArrowIcon = await _drawHeadingArrow(
      fill: const Color(0xFF00C853),
      ring: const Color(0xFFFFC107),
    );
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _drawHeadingArrow({
    required Color fill,
    required Color ring,
  }) async {
    const size = 120.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final c = Offset(size / 2, size / 2);

    canvas.drawCircle(
      Offset(c.dx, c.dy + 5),
      28,
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );
    final wake = Path()
      ..moveTo(c.dx, c.dy + 8)
      ..lineTo(c.dx + 18, c.dy + 38)
      ..lineTo(c.dx, c.dy + 28)
      ..lineTo(c.dx - 18, c.dy + 38)
      ..close();
    canvas.drawPath(
      wake,
      Paint()..color = fill.withValues(alpha: 0.35),
    );
    canvas.drawCircle(c, 32, Paint()..color = ring);
    canvas.drawCircle(c, 28, Paint()..color = const Color(0xFF14171A));
    final arrow = Path()
      ..moveTo(c.dx, c.dy - 24)
      ..lineTo(c.dx + 18, c.dy + 12)
      ..lineTo(c.dx + 6, c.dy + 12)
      ..lineTo(c.dx + 6, c.dy + 22)
      ..lineTo(c.dx - 6, c.dy + 22)
      ..lineTo(c.dx - 6, c.dy + 12)
      ..lineTo(c.dx - 18, c.dy + 12)
      ..close();
    canvas.drawPath(arrow, Paint()..color = fill);
    canvas.drawPath(
      arrow,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  /// Flat truck icon that rotates with heading (Uber-style on the map).
  Future<void> _buildTruckIcon() async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);

    // Soft shadow under the truck.
    canvas.drawCircle(
      center.translate(0, 4),
      18,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Cab (front) — drawn pointing "up" so rotation = heading.
    final cab = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center.translate(0, -10), width: 22, height: 18),
      const Radius.circular(4),
    );
    canvas.drawRRect(cab, Paint()..color = const Color(0xFF14171A));

    // Cargo bed.
    final bed = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center.translate(0, 8), width: 28, height: 28),
      const Radius.circular(5),
    );
    canvas.drawRRect(bed, Paint()..color = const Color(0xFFFFC107));
    canvas.drawRRect(
      bed,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Windshield hint.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center.translate(0, -12), width: 14, height: 8),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF276EF1),
    );

    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted || bytes == null) return;
    setState(() {
      _truckIcon = BitmapDescriptor.bytes(bytes.buffer.asUint8List());
    });
  }

  /// Drop into 3D search mode — same bid-wait pulse vibe as the driver map.
  Future<void> _startSearchingOnMap() async {
    final pickup = _pickup;
    if (pickup == null) return;

    final center = LatLng(pickup.latitude, pickup.longitude);
    setState(() {
      _searching3d = true;
      _previewDrivers = true;
      _panelCollapsed = true;
      _spawnMovingDrivers(center);
    });
    _startSearchWaitingPulse();

    _carAnim.repeat();
    _nearbyTimer?.cancel();
    _nearbyTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _pollNearbyDrivers();
    });
    await _pollNearbyDrivers();

    // One smooth 3D fit (do not re-fit on every nearby poll — that janks the map).
    await _fitMapCamera(searching: true);
    _viewersTimer?.cancel();
    _viewersTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _pollBookingViewers();
    });
    unawaited(_pollBookingViewers());
  }

  void _startSearchWaitingPulse() {
    if (_priceBeepActive) return;
    if (!_beepPulse.isAnimating) _beepPulse.repeat();
    if (mounted) setState(() => _searchWaitingPulse = true);
  }

  void _stopSearchWaitingPulse() {
    if (!_searchWaitingPulse) return;
    if (!_priceBeepActive && _beepPulse.isAnimating) _beepPulse.stop();
    if (mounted) setState(() => _searchWaitingPulse = false);
  }

  /// Restore map session from a booking (My trips → Show on map).
  Future<void> _resumeTripOnMap(Map<String, dynamic> trip) async {
    PlaceSelection? pickup;
    PlaceSelection? dropoff;
    final p = trip['pickup'];
    final d = trip['dropoff'];
    if (p is Map) {
      final lat = double.tryParse('${p['latitude']}');
      final lng = double.tryParse('${p['longitude']}');
      if (lat != null && lng != null) {
        pickup = PlaceSelection(
          address: (p['address'] ?? 'Pickup').toString(),
          latitude: lat,
          longitude: lng,
          placeId: (p['place_id'] ?? '').toString(),
        );
      }
    }
    if (d is Map) {
      final lat = double.tryParse('${d['latitude']}');
      final lng = double.tryParse('${d['longitude']}');
      if (lat != null && lng != null) {
        dropoff = PlaceSelection(
          address: (d['address'] ?? 'Drop-off').toString(),
          latitude: lat,
          longitude: lng,
          placeId: (d['place_id'] ?? '').toString(),
        );
      }
    }

    setState(() {
      _activeTrip = trip;
      _panelCollapsed = true;
      if (pickup != null) _pickup = pickup;
      if (dropoff != null) _dropoff = dropoff;
    });
    _syncFirestoreWatch();

    if (pickup != null && dropoff != null) {
      await _updateTripRoute();
    }
    final st = (trip['status'] ?? '').toString();
    if (st == 'accepted' || st == 'in_progress' || st == 'arrived') {
      _stopSearchingOnMap();
      _syncLiveDriverTracking();
      await _pollLiveTripTracking();
    } else {
      await _startSearchingOnMap();
    }
  }

  void _stopSearchingOnMap() {
    _nearbyTimer?.cancel();
    _viewersTimer?.cancel();
    _viewersTimer = null;
    _stopPreviewDrivers();
    _stopSearchWaitingPulse();
    if (!mounted) return;
    setState(() {
      _searching3d = false;
      _nearbyDrivers = [];
      _bookingViewers = [];
      _seenTotal = 0;
      _respondedCount = 0;
    });
  }

  /// Drivers start moving as soon as the road route is ready (preview + search).
  void _startPreviewDrivers() {
    final pickup = _pickup;
    if (pickup == null || _routePts.length < 2) return;
    final center = LatLng(pickup.latitude, pickup.longitude);
    setState(() {
      _previewDrivers = true;
      _spawnMovingDrivers(center);
    });
    if (!_carAnim.isAnimating) _carAnim.repeat();
    _nearbyTimer?.cancel();
    _nearbyTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _pollNearbyDrivers();
    });
    _pollNearbyDrivers();
  }

  void _stopPreviewDrivers() {
    if (!_searching3d) {
      _nearbyTimer?.cancel();
      _carAnim.stop();
    }
    setState(() {
      _previewDrivers = false;
      if (!_searching3d) _cars.clear();
    });
  }

  /// Seed trucks that drive along the road route (and a few near pickup).
  void _spawnMovingDrivers(LatLng center) {
    final rnd = math.Random(center.latitude.hashCode ^ center.longitude.hashCode);
    final keepReal = _cars.where((c) => c.real).toList();
    _cars
      ..clear()
      ..addAll(keepReal);

    final routeLen = _routePts.length;
    final alongCount = routeLen > 8 ? 3 : 2;
    for (var i = 0; i < alongCount; i++) {
      final idx = ((i + 1) * routeLen / (alongCount + 1)).floor().clamp(0, routeLen - 2);
      final from = _routePts[idx];
      final to = _routePts[idx + 1];
      _cars.add(
        _MapCar(
          id: 'route_$i',
          position: from,
          heading: _bearingBetween(from, to),
          name: 'Driver nearby',
          real: false,
          followRoute: true,
          routeIndex: idx,
          speed: 0.9 + rnd.nextDouble() * 0.8,
        ),
      );
    }

    // A couple of orbiting movers around pickup (Uber-style availability).
    for (var i = 0; i < 2; i++) {
      final phase = (i / 2) * math.pi * 2 + rnd.nextDouble();
      final radius = 0.0022 + rnd.nextDouble() * 0.0028;
      _cars.add(
        _MapCar(
          id: 'scout_$i',
          position: _orbitPoint(center, phase, radius),
          heading: (phase * 180 / math.pi + 90) % 360,
          name: 'Nearby mover',
          real: false,
          followRoute: false,
          orbitPhase: phase,
          orbitRadius: radius,
          speed: 0.7 + rnd.nextDouble() * 0.6,
        ),
      );
    }
  }

  LatLng _orbitPoint(LatLng center, double phase, double radius) {
    // Stretch longitude a bit so the orbit looks round on the map.
    final latFactor = math.cos(center.latitude * math.pi / 180).abs().clamp(0.4, 1.0);
    return LatLng(
      center.latitude + math.sin(phase) * radius,
      center.longitude + math.cos(phase) * radius / latFactor,
    );
  }

  void _tickCars() {
    if ((!_searching3d && !_previewDrivers) || !mounted) return;
    var moved = false;

    for (final car in _cars) {
      if (car.real) continue;

      if (car.followRoute && _routePts.length > 2) {
        // Advance along the road polyline so cars follow street corners.
        final step = math.max(1, (1.2 * car.speed).round());
        car.routeIndex = (car.routeIndex + step) % (_routePts.length - 1);
        final from = _routePts[car.routeIndex];
        final to = _routePts[car.routeIndex + 1];
        car.position = from;
        car.heading = _bearingBetween(from, to);
        moved = true;
        continue;
      }

      if (_pickup == null) continue;
      final center = LatLng(_pickup!.latitude, _pickup!.longitude);
      car.orbitPhase += 0.012 * car.speed;
      final next = _orbitPoint(center, car.orbitPhase, car.orbitRadius);
      final dLat = next.latitude - car.position.latitude;
      final dLng = next.longitude - car.position.longitude;
      if (dLat.abs() > 1e-9 || dLng.abs() > 1e-9) {
        car.heading = (math.atan2(dLng, dLat) * 180 / math.pi + 360) % 360;
      }
      car.position = next;
      moved = true;
    }
    // Rebuild ~every 150ms so the map stays smooth (50ms setState was janky).
    if (!moved) return;
    _carTickSkip = (_carTickSkip + 1) % 3;
    if (_carTickSkip == 0) setState(() {});
  }

  Future<void> _pollNearbyDrivers() async {
    final pickup = _pickup;
    if (pickup == null) return;
    if (!_previewDrivers && _activeTrip == null) return;
    try {
      final list = await MovingMarketplaceService.listNearbyDrivers(
        lat: pickup.latitude,
        lng: pickup.longitude,
      );
      if (!mounted) return;
      final viewedIds = {
        for (final v in _bookingViewers)
          int.tryParse('${v['id']}') ?? -1,
      }..remove(-1);
      setState(() {
        _nearbyDrivers = list;
        _cars.removeWhere((c) => c.real);
        for (final d in list) {
          final lat = double.tryParse('${d['latitude']}');
          final lng = double.tryParse('${d['longitude']}');
          if (lat == null || lng == null) continue;
          final id = int.tryParse('${d['id']}') ?? 0;
          _cars.add(
            _MapCar(
              id: 'drv_$id',
              position: LatLng(lat, lng),
              heading: 0,
              name: (d['name'] ?? 'Driver').toString(),
              real: true,
              viewed: viewedIds.contains(id),
            ),
          );
        }
        // Keep animated scouts unless we have plenty of live drivers.
        if (list.length >= 4) {
          _cars.removeWhere((c) => !c.real);
        }
      });
      // Don't re-fit camera here — causes zoom jumps while searching.
    } catch (_) {}
  }

  Future<void> _pollBookingViewers() async {
    final trip = _activeTrip;
    if (trip == null) return;
    final status = (trip['status'] ?? '').toString();
    if (status != 'open') {
      if (_bookingViewers.isNotEmpty && mounted) {
        setState(() {
          _bookingViewers = [];
          _seenTotal = 0;
          _respondedCount = 0;
        });
      }
      return;
    }
    final id = int.tryParse('${trip['id']}');
    if (id == null) return;
    try {
      final data = await MovingMarketplaceService.listBookingViews(id);
      if (!mounted) return;
      var viewers = (data['viewers'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // Client backup: drop anyone who already has a pending price on this trip.
      final offerDriverIds = {
        for (final o in (_driverOffers[id] ?? []))
          int.tryParse('${o['driver_id']}') ?? -1,
      }..remove(-1);
      viewers = viewers.where((v) {
        final did = int.tryParse('${v['id']}') ?? -1;
        final responded = v['responded'] == true || v['responded'] == 1;
        return !responded && !offerDriverIds.contains(did);
      }).toList();

      setState(() {
        _bookingViewers = viewers;
        _seenTotal = int.tryParse('${data['seen_total']}') ?? viewers.length;
        _respondedCount =
            int.tryParse('${data['responded_count']}') ?? offerDriverIds.length;
        final viewedIds = {
          for (final v in viewers) int.tryParse('${v['id']}') ?? -1,
        }..remove(-1);
        for (final car in _cars) {
          if (!car.real) continue;
          final cid = int.tryParse(car.id.replaceFirst('drv_', '')) ?? -1;
          car.viewed = viewedIds.contains(cid);
        }
      });
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _openTrips => _trips
      .where((t) => (t['status'] ?? '').toString() == 'open')
      .toList();

  List<Map<String, dynamic>> get _liveTrips => _trips
      .where((t) {
        final s = (t['status'] ?? '').toString();
        return s == 'accepted' || s == 'in_progress' || s == 'arrived';
      })
      .toList();

  /// Polls offers on open + live bookings; pops price alerts on the map.
  Future<void> _pollDriverOffers() async {
    // Keep trip list fresh so My trips + active map stay in sync.
    try {
      final trips = await MovingMarketplaceService.listBookings();
      if (mounted) {
        setState(() => _trips = trips);
        _syncActiveTripFromList(trips);
      }
    } catch (_) {}

    // Open bookings only — price negotiation closes once accepted / in progress.
    for (final trip in _openTrips.take(3)) {
      await _pollOffersForTrip(trip, renegotiate: false);
    }
    if (_activeTrip != null &&
        (_activeTrip!['status'] ?? '').toString() == 'open') {
      await _pollBookingViewers();
    }
  }

  Future<void> _pollOffersForTrip(
    Map<String, dynamic> trip, {
    required bool renegotiate,
  }) async {
    final id = int.tryParse(trip['id'].toString());
    if (id == null) return;
    try {
      final offers = await MovingMarketplaceService.listOffers(bookingId: id);
      final driverOffers = offers.where((o) {
        final status = (o['status'] ?? '').toString().toLowerCase();
        if (status != 'pending') return false;
        final role = (o['sender_role'] ?? '').toString().toLowerCase();
        // Driver-sent offers (role may be missing on older API payloads).
        if (role == 'driver') return true;
        final sender = o['sender_id']?.toString();
        final driver = o['driver_id']?.toString();
        return sender != null && sender == driver;
      }).toList();
      if (!mounted) return;
      setState(() => _driverOffers[id] = driverOffers);

      final newOnes = driverOffers.where((o) {
        final oid = int.tryParse(o['id'].toString()) ?? -1;
        return oid > 0 && !_seenOfferIds.contains(oid);
      }).toList();
      if (newOnes.isEmpty || !mounted) return;

      // Don't mark as seen until we can actually show the popup — otherwise a
      // busy sheet swallows the new price and it never appears again.
      if (_responsePopupOpen) return;
      if (!renegotiate && _offerSheetOpen) return;

      final offer = newOnes.first;
      final oid = int.tryParse(offer['id'].toString()) ?? -1;
      if (oid > 0) _seenOfferIds.add(oid);

      if (renegotiate) {
        // Close trip/offers sheet so the countdown is visible on top.
        if (_offerSheetOpen && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          _offerSheetOpen = false;
        }
        await _showLivePriceCountdown(trip, offer);
      } else {
        await _showDriverRespondedPopup(trip, offer);
      }
    } catch (_) {}
  }

  /// New fare during an active ride — map BEEP + countdown (same as driver).
  Future<void> _showLivePriceCountdown(
    Map<String, dynamic> trip,
    Map<String, dynamic> offer,
  ) async {
    if (!mounted || _responsePopupOpen) return;
    _responsePopupOpen = true;
    final bookingId = int.tryParse(trip['id'].toString()) ?? 0;
    final offerId = int.tryParse(offer['id'].toString()) ?? 0;
    final amount = double.tryParse('${offer['amount']}') ?? 0;
    final name =
        (offer['driver_name'] ?? offer['sender_name'] ?? 'Driver').toString();
    final avatar = MovingMarketplaceService.driverAvatarUrl(
      name: name,
      photoUrl: (offer['avatar_url'] ?? offer['photo_url'] ?? '').toString(),
    );

    if (!mounted || bookingId <= 0 || offerId <= 0) {
      _responsePopupOpen = false;
      return;
    }

    // Same map pulse / beep design as the driver waiting screen.
    _startPriceBeep(amount);

    final accepted = await showPriceOfferCountdown(
      context: context,
      title: 'New price from $name',
      subtitle: 'Accept within 30 seconds',
      amount: amount,
      acceptLabel: 'Accept',
      declineLabel: 'Keep fare',
      imageUrl: avatar,
    );

    // Resume SEARCH pulse if they decline / time out (still open).
    _stopPriceBeep(resumeSearchPulse: accepted != true);
    if (!mounted) {
      _responsePopupOpen = false;
      return;
    }

    try {
      if (accepted == true) {
        await _acceptLivePriceNeat(
          trip: trip,
          bookingId: bookingId,
          offerId: offerId,
          amount: amount,
          driverName: name,
        );
      } else if (accepted == false) {
        try {
          await MovingMarketplaceService.rejectOffer(
            bookingId: bookingId,
            offerId: offerId,
          );
        } catch (_) {}
        if (!mounted) return;
        await showPriceOfferResult(
          context: context,
          kind: PriceOfferResultKind.keptFare,
          amount: amount,
          title: 'Keeping current fare',
          subtitle: 'Driver’s new price was declined.',
          primaryLabel: 'OK',
        );
      } else {
        // Timed out / dismissed — no response.
        try {
          await MovingMarketplaceService.rejectOffer(
            bookingId: bookingId,
            offerId: offerId,
          );
        } catch (_) {}
        if (!mounted) return;
        await showPriceOfferResult(
          context: context,
          kind: PriceOfferResultKind.noResponse,
          amount: amount,
          title: 'No response',
          subtitle: 'Time ran out — current fare stays the same.',
          primaryLabel: 'OK',
        );
      }
      if (mounted) await _loadTrips();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppError.userMessage(e)),
          ),
        );
      }
    } finally {
      _responsePopupOpen = false;
    }
  }

  /// Accept driver’s renegotiated fare — optimistic UI + recover if API flakes.
  Future<void> _acceptLivePriceNeat({
    required Map<String, dynamic> trip,
    required int bookingId,
    required int offerId,
    required double amount,
    required String driverName,
  }) async {
    // Optimistic update so the panel doesn’t fall back to the old fare.
    if (mounted) {
      setState(() {
        _activeTrip = {
          ...trip,
          ...?_activeTrip,
          'agreed_amount': amount,
        };
        _panelCollapsed = false;
      });
    }

    Map<String, dynamic> updated = {};
    var ok = false;
    try {
      updated = await MovingMarketplaceService.acceptOffer(
        bookingId: bookingId,
        offerId: offerId,
      );
      ok = true;
    } catch (_) {
      // Server may have accepted already (driver already saw it) — verify.
      try {
        final fresh = await MovingMarketplaceService.getBooking(bookingId);
        final agreed = double.tryParse('${fresh['agreed_amount']}');
        if (agreed != null && (agreed - amount).abs() < 0.5) {
          updated = fresh;
          ok = true;
        }
      } catch (_) {}
    }

    if (!mounted) return;

    if (ok) {
      setState(() {
        _activeTrip = {
          ...trip,
          ...?_activeTrip,
          ...updated,
          'agreed_amount':
              double.tryParse('${updated['agreed_amount']}') ?? amount,
          if (updated['driver'] is Map) 'driver': updated['driver'],
          if (updated['pickup'] is Map) 'pickup': updated['pickup'],
          if (updated['dropoff'] is Map) 'dropoff': updated['dropoff'],
          if (updated['status'] != null) 'status': updated['status'],
        };
      });
      await showPriceOfferResult(
        context: context,
        kind: PriceOfferResultKind.accepted,
        amount: amount,
        title: 'Price accepted',
        subtitle: 'Fare updated with $driverName.',
        primaryLabel: 'Continue',
      );
      return;
    }

    // True failure — restore prior trip snapshot.
    if (mounted) {
      setState(() => _activeTrip = trip);
      await showPriceOfferResult(
        context: context,
        kind: PriceOfferResultKind.declined,
        amount: amount,
        title: 'Couldn’t update fare',
        subtitle: 'Please try accepting again if the offer is still open.',
        primaryLabel: 'OK',
      );
    }
  }

  void _syncActiveTripFromList(List<Map<String, dynamic>> trips) {
    final active = _activeTrip;
    if (active == null) return;
    final id = active['id']?.toString();
    if (id == null) return;
    Map<String, dynamic>? match;
    for (final t in trips) {
      if (t['id']?.toString() == id) {
        match = t;
        break;
      }
    }
    if (match == null) return;
    final was = (active['status'] ?? '').toString();
    final now = (match['status'] ?? '').toString();
    setState(() => _activeTrip = match);
    _syncLiveDriverTracking();
    if (now == 'accepted' || now == 'in_progress' || now == 'arrived') {
      unawaited(_ensureLiveTripRoute(booking: match));
    }
    if (was != 'accepted' &&
        now == 'accepted' &&
        !_acceptedPopupShown.contains(int.tryParse(id) ?? -1)) {
      final updated = match;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAcceptedPopup(updated);
      });
    }
    // Driver marked destination complete → ask tenant to rate.
    if (now == 'completed' &&
        (was != 'completed' || match['can_rate'] == true) &&
        match['has_rated'] != true) {
      final updated = match;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_promptRateDriver(updated));
      });
    }
  }

  Future<void> _promptRateDriver(Map<String, dynamic> trip) async {
    if (!mounted || _ratingPromptOpen) return;
    final bookingId = int.tryParse(trip['id']?.toString() ?? '') ?? 0;
    if (bookingId < 1 || _ratingPromptShown.contains(bookingId)) return;
    if (trip['has_rated'] == true || trip['can_rate'] == false) return;

    _ratingPromptShown.add(bookingId);
    _ratingPromptOpen = true;
    final driver = trip['driver'] is Map
        ? Map<String, dynamic>.from(trip['driver'] as Map)
        : <String, dynamic>{};
    final name = (driver['name'] ?? 'your driver').toString();
    try {
      final rated = await showDriverRatingSheet(
        context: context,
        bookingId: bookingId,
        driverName: name,
      );
      if (!mounted) return;
      if (rated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for rating your driver.')),
        );
        await _loadTrips();
        if (mounted) {
          setState(() {
            _activeTrip = null;
            _panelCollapsed = false;
          });
        }
      }
    } finally {
      _ratingPromptOpen = false;
    }
  }

  /// Top popup when a driver responds with a price — map session stays open.
  Future<void> _showDriverRespondedPopup(
    Map<String, dynamic> trip,
    Map<String, dynamic> offer,
  ) async {
    if (!mounted || _responsePopupOpen) return;
    _responsePopupOpen = true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name =
        (offer['driver_name'] ?? offer['sender_name'] ?? 'Driver').toString();
    final amount = (offer['amount'] ?? '').toString();
    final vehicle = (offer['vehicle_type'] ?? '').toString();
    final bookingId = int.tryParse(trip['id'].toString()) ?? 0;

    // Keep this trip as the active map session.
    setState(() {
      _activeTrip = trip;
      _panelCollapsed = true;
    });

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Driver responded',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim, secondary) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFC107).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'DRIVER RESPONDED',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: Color(0xFFFFC107),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'K $amount',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            color: Color(0xFFFFC107),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    if (vehicle.isNotEmpty)
                      Text(
                        vehicle,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Later',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showDriverOffersSheet(trip);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFC107),
                              foregroundColor: Colors.black,
                              elevation: 0,
                              minimumSize: const Size(0, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              bookingId > 0 &&
                                      (_driverOffers[bookingId]?.length ?? 0) > 1
                                  ? 'View offers'
                                  : 'Review',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secondary, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.18),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );

    _responsePopupOpen = false;
  }

  /// Popup when a move is accepted — keeps the map session open.
  Future<void> _showAcceptedPopup(Map<String, dynamic> trip) async {
    if (!mounted) return;
    final id = int.tryParse(trip['id'].toString()) ?? -1;
    if (id > 0) {
      _acceptedPopupShown.add(id);
      unawaited(MovingTripNotifier.watchBooking(id));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final driver = trip['driver'] is Map
        ? Map<String, dynamic>.from(trip['driver'] as Map)
        : <String, dynamic>{};
    final driverName = (driver['name'] ?? 'Your driver').toString();
    final plate = (driver['vehicle_plate'] ?? '').toString();
    final vehicle = (driver['vehicle_type'] ?? '').toString();
    final phone = (driver['phone'] ?? trip['contact_phone'] ?? '').toString();
    final amount = (trip['agreed_amount'] ?? '').toString();

    setState(() {
      _activeTrip = trip;
      _panelCollapsed = false;
      _searching3d = false;
    });
    _stopSearchingOnMap();
    _syncPlacesFromBooking(trip);
    _syncLiveDriverTracking();
    unawaited(_ensureLiveTripRoute(booking: trip));
    unawaited(_refreshLiveEta(force: true));
    if (!_saidAcceptVoice) {
      _saidAcceptVoice = true;
      // Same moment both accept price → client auto voice + live tracking.
      unawaited(Future<void>(() async {
        await Future.delayed(const Duration(milliseconds: 600));
        await _refreshLiveEta(force: true);
        final eta = _remainingEtaDisplay;
        await _speakClient(
          eta.isNotEmpty && eta != '—'
              ? 'Price accepted. Your HouseRent Shifts driver is on the way. $eta.'
              : 'Price accepted. Your HouseRent Shifts driver is on the way.',
        );
      }));
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Move accepted',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, anim, secondary) {
        return SafeArea(
          child: Align(
            alignment: Alignment.center,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 22),
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC107).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Color(0xFFFFC107),
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Move accepted!',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      amount.isNotEmpty
                          ? '$driverName · K $amount'
                          : driverName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    if (vehicle.isNotEmpty || plate.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        [vehicle, if (plate.isNotEmpty) plate].join(' · '),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    DriverIdentityPhotos(driver: driver, compact: true),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        phone,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Color(0xFF276EF1),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14171A),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Stay on map',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openMyShifts();
                      },
                      child: const Text(
                        'View in My shifts',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, secondary, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
  }

  /// Pop-up: trip status (pickup, drop-off, price, ETA) + driver offers.
  Future<void> _showDriverOffersSheet(Map<String, dynamic> trip) async {
    final bookingId = int.tryParse(trip['id'].toString());
    if (bookingId == null || _offerSheetOpen) return;
    _offerSheetOpen = true;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final pickupAddr = _addressFromTrip(trip['pickup'], _pickup?.address);
    final dropAddr = _addressFromTrip(trip['dropoff'], _dropoff?.address);
    final price = trip['tenant_offer'] ??
        trip['estimated_price'] ??
        (_offerPrice?.toStringAsFixed(0));
    final eta = _routeDurText.isNotEmpty
        ? _routeDurText
        : (trip['duration_text'] ?? trip['eta'] ?? '').toString();
    final dist = _routeDistText.isNotEmpty
        ? _routeDistText
        : (_tripKm != null
            ? '${_tripKm!.toStringAsFixed(1)} km'
            : (trip['distance_text'] ?? '').toString());
    final when =
        '${trip['moving_date'] ?? _dateLabel} · ${trip['moving_time'] ?? _timeLabel}';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheet) {
            final offers = _driverOffers[bookingId] ?? [];
            final maxH = MediaQuery.of(sheetContext).size.height * 0.82;
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white24
                                : const Color(0xFFE2E2E2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        offers.isEmpty ? 'Trip status' : 'Driver offers',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _statusSummaryCard(
                        isDark: isDark,
                        pickup: pickupAddr,
                        dropoff: dropAddr,
                        price: price?.toString(),
                        eta: eta,
                        distance: dist,
                        when: when,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        offers.isEmpty
                            ? 'Waiting for driver prices…'
                            : '${offers.length} driver${offers.length == 1 ? '' : 's'} responding',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (offers.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: _radarBadge(36)),
                        )
                      else
                        ...[
                          for (var i = 0; i < offers.length; i++) ...[
                            if (i > 0) const SizedBox(height: 10),
                            _offerTile(
                              offers[i],
                              bookingId,
                              isDark,
                              setSheet,
                            ),
                          ],
                        ],
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Close'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    _offerSheetOpen = false;
  }

  String _addressFromTrip(dynamic raw, String? fallback) {
    if (raw is Map) {
      final a = (raw['address'] ?? raw['name'] ?? '').toString().trim();
      if (a.isNotEmpty) return a;
    }
    final s = (raw ?? '').toString().trim();
    if (s.isNotEmpty && !s.startsWith('{')) return s;
    return (fallback ?? '—').trim().isEmpty ? '—' : (fallback ?? '—');
  }

  Widget _statusSummaryCard({
    required bool isDark,
    required String pickup,
    required String dropoff,
    required String? price,
    required String eta,
    required String distance,
    required String when,
  }) {
    Widget row(IconData icon, String label, String value, {Color? accent}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: accent ?? const Color(0xFFFFC107)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value.isEmpty ? '—' : value,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242424) : const Color(0xFFF7F7F8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFECECEC),
        ),
      ),
      child: Column(
        children: [
          row(Icons.trip_origin_rounded, 'Pickup', pickup,
              accent: _kPickupGreen),
          row(Icons.flag_rounded, 'Destination', dropoff, accent: _kDropRed),
          const Divider(height: 16),
          Row(
            children: [
              Expanded(
                child: row(
                  Icons.payments_rounded,
                  'Your price',
                  price != null && price.isNotEmpty ? 'K $price' : '—',
                ),
              ),
              Expanded(
                child: row(
                  Icons.schedule_rounded,
                  'Time to arrive',
                  eta.isNotEmpty ? eta : '—',
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: row(
                  Icons.straighten_rounded,
                  'Distance',
                  distance.isNotEmpty ? distance : '—',
                ),
              ),
              Expanded(
                child: row(
                  Icons.event_rounded,
                  'Move time',
                  when,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _offerTile(
    Map<String, dynamic> offer,
    int bookingId,
    bool isDark,
    void Function(void Function()) setSheet,
  ) {
    final offerId = int.tryParse(offer['id'].toString()) ?? 0;
    final name = (offer['driver_name'] ?? offer['sender_name'] ?? 'Driver')
        .toString();
    final vehicle = (offer['vehicle_type'] ?? '').toString();
    final amount = (offer['amount'] ?? '').toString();
    final note = (offer['note'] ?? '').toString();
    final ratingBadge = DriverRatingBadge.fromOffer(offer);
    final avatar = MovingMarketplaceService.driverAvatarUrl(
      name: name,
      photoUrl: (offer['avatar_url'] ?? offer['photo_url'] ?? '').toString(),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242424) : const Color(0xFFF7F7F8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ratingBadge?.premium == true
              ? const Color(0xFFFFC107).withValues(alpha: 0.45)
              : (isDark ? Colors.white10 : const Color(0xFFECECEC)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF14171A),
                backgroundImage: NetworkImage(avatar),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    if (vehicle.isNotEmpty)
                      Text(
                        vehicle,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    if (ratingBadge != null) ...[
                      const SizedBox(height: 4),
                      ratingBadge,
                    ],
                  ],
                ),
              ),
              Text(
                'K $amount',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Color(0xFFFFC107),
                ),
              ),
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: Material(
                    color: const Color(0xFF2C2C2E),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        try {
                          await MovingMarketplaceService.rejectOffer(
                            bookingId: bookingId,
                            offerId: offerId,
                          );
                          setSheet(() {
                            _driverOffers[bookingId]?.removeWhere(
                              (o) => o['id'].toString() == offerId.toString(),
                            );
                          });
                        } catch (_) {}
                      },
                      child: const Center(
                        child: Text(
                          'Decline',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PriceTimedAcceptButton(
                  height: 48,
                  onAccept: () async {
                    try {
                      await MovingMarketplaceService.acceptOffer(
                        bookingId: bookingId,
                        offerId: offerId,
                      );
                      if (!mounted) return;
                      Navigator.of(context).pop();
                      await _loadTrips();
                      if (!mounted) return;
                      Map<String, dynamic>? accepted;
                      for (final t in _trips) {
                        if (t['id']?.toString() == '$bookingId') {
                          accepted = t;
                          break;
                        }
                      }
                      accepted ??= {
                        ...?_activeTrip,
                        'id': bookingId,
                        'status': 'accepted',
                        'agreed_amount': amount,
                        'driver': {
                          'name': name,
                          if (vehicle.isNotEmpty) 'vehicle_type': vehicle,
                        },
                      };
                      setState(() {
                        _activeTrip = accepted;
                        _searching3d = true;
                        _panelCollapsed = false;
                        _driverOffers.remove(bookingId);
                      });
                      await _showAcceptedPopup(accepted);
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppError.userMessage(e),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          // Negotiate without typing: +/- steps and quick suggestions.
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => _showCounterSheet(bookingId, offer),
              icon: const Icon(Icons.swap_vert_rounded, size: 17),
              label: const Text(
                'Suggest another price',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF276EF1),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pulsing radar badge — the "searching for drivers" vibe.
  Widget _radarBadge(double size) {
    return AnimatedBuilder(
      animation: _radar,
      builder: (context, _) {
        final t = _radar.value;
        return SizedBox(
          width: size * 2.2,
          height: size * 2.2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size + size * 1.2 * t,
                height: size + size * 1.2 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFFC107)
                        .withValues(alpha: 0.7 * (1 - t)),
                    width: 2,
                  ),
                ),
              ),
              Container(
                width: size,
                height: size,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFC107),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.local_shipping_rounded,
                  size: size * 0.55,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Live strip: drivers who saw the request but have not sent a price.
  Widget _viewersAvatarStrip({required bool dark, required bool compact}) {
    final viewers = _bookingViewers;
    if (viewers.isEmpty) return const SizedBox.shrink();
    final show = viewers.take(compact ? 6 : 10).toList();
    final extra = viewers.length - show.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: compact ? 6 : 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF00C853),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  compact
                      ? 'Seen · not responding · ${viewers.length}'
                          '${_seenTotal > viewers.length ? ' / $_seenTotal seen' : ''}'
                      : 'Live · ${viewers.length} seen, not responding'
                          '${_respondedCount > 0 ? ' · $_respondedCount priced' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 11.5 : 12.5,
                    color: dark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: compact ? 38 : 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: show.length + (extra > 0 ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              if (i >= show.length) {
                return CircleAvatar(
                  radius: compact ? 15 : 18,
                  backgroundColor: const Color(0xFFFFC107),
                  child: Text(
                    '+$extra',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 11 : 12,
                    ),
                  ),
                );
              }
              final v = show[i];
              final name = (v['name'] ?? 'Driver').toString();
              final avatar = (v['avatar_url'] ?? '').toString();
              final vehicle = (v['vehicle_type'] ?? '').toString();
              return Tooltip(
                message: '$name · seen, not responding',
                child: compact
                    ? Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: const Color(0xFF2A2A2A),
                            backgroundImage: avatar.isNotEmpty
                                ? NetworkImage(avatar)
                                : null,
                            child: avatar.isEmpty
                                ? Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : 'D',
                                    style: const TextStyle(
                                      color: Color(0xFFFFC107),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  )
                                : null,
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: const Color(0xFF00C853),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF111111),
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.visibility_rounded,
                                size: 9,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Container(
                        padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
                        decoration: BoxDecoration(
                          color: dark
                              ? Colors.white.withValues(alpha: 0.06)
                              : const Color(0xFFF3F3F3),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFF00C853).withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: const Color(0xFF2A2A2A),
                                  backgroundImage: avatar.isNotEmpty
                                      ? NetworkImage(avatar)
                                      : null,
                                  child: avatar.isEmpty
                                      ? Text(
                                          name.isNotEmpty
                                              ? name[0].toUpperCase()
                                              : 'D',
                                          style: const TextStyle(
                                            color: Color(0xFFFFC107),
                                            fontWeight: FontWeight.w900,
                                          ),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00C853),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: dark
                                            ? const Color(0xFF1A1A1A)
                                            : Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.visibility_rounded,
                                      size: 9,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 110),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                      color: dark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    vehicle.isNotEmpty
                                        ? '$vehicle · seen'
                                        : 'Seen · waiting',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                      color: dark
                                          ? Colors.white54
                                          : Colors.black45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  String get _dateLabel =>
      '${_movingDate.year}-${_movingDate.month.toString().padLeft(2, '0')}-${_movingDate.day.toString().padLeft(2, '0')}';

  String get _timeLabel =>
      '${_movingTime.hour.toString().padLeft(2, '0')}:${_movingTime.minute.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (_pickup == null || _dropoff == null) return;

    // Date/time stay hidden in UI but always sent as "now".
    final now = DateTime.now();
    _movingDate = now;
    _movingTime = TimeOfDay.fromDateTime(now);

    final items = _itemsCtrl.text.trim().isEmpty
        ? 'Household items'
        : _itemsCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    setState(() => _submitting = true);
    try {
      final booking = await MovingMarketplaceService.createBooking(
        pickup: _pickup!.toApiMap(),
        dropoff: _dropoff!.toApiMap(),
        movingDate: _dateLabel,
        movingTime: _timeLabel,
        itemDescription: items,
        contactPhone: phone.isEmpty ? 'N/A' : phone,
        tenantOffer: _currentOffer,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request posted — searching for drivers…'),
        ),
      );
      // Stay on the map: 3D cars cruise while drivers respond with prices.
      setState(() => _activeTrip = booking);
      _syncFirestoreWatch();
      await _startSearchingOnMap();
      await _loadTrips();
      if (mounted) _pollDriverOffers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Local distance/fare preview before booking (server recomputes it).
  double? get _tripKm {
    final p = _pickup;
    final d = _dropoff;
    if (p == null || d == null) return null;
    if (p.latitude.abs() < 0.0001 && p.longitude.abs() < 0.0001) return null;
    if (d.latitude.abs() < 0.0001 && d.longitude.abs() < 0.0001) return null;
    return MovingMarketplaceService.distanceKm(
      lat1: p.latitude,
      lng1: p.longitude,
      lat2: d.latitude,
      lng2: d.longitude,
    );
  }

  double? get _fareEstimate {
    final km = _tripKm;
    return km == null ? null : MovingMarketplaceService.estimateFare(km);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'accepted':
        return const Color(0xFF276EF1);
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'cancelled':
        return Colors.red.shade400;
      default:
        return const Color(0xFFFFC107);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Full-screen map only — My shifts is a separate page (home + floating button).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF14171A),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFF14171A),
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: _buildRequestTab(isDark),
      ),
    );
  }

  Widget _mapChromeButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    Color bg = const Color(0xE61A1A1A),
    Color fg = Colors.white,
  }) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black54,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Tooltip(
            message: tooltip ?? '',
            child: Icon(icon, size: 22, color: fg),
          ),
        ),
      ),
    );
  }

  /// Uber-style booking map: pickup/drop pins + real road route + moving cars.
  Widget _buildTripMap(bool isDark) {
    final markers = <Marker>{};
    if (_pickup != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(_pickup!.latitude, _pickup!.longitude),
          icon: _pickupPin ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: 'Pickup',
            snippet: _pickup!.address,
          ),
          zIndexInt: 4,
        ),
      );
    }
    if (_dropoff != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(_dropoff!.latitude, _dropoff!.longitude),
          icon: _dropPin ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: 'Destination',
            snippet: _dropoff!.address,
          ),
          zIndexInt: 4,
        ),
      );
    }

    final ready = _pickup != null && _dropoff != null;
    final searching = _activeTrip != null;
    final liveStatus = (_activeTrip?['status'] ?? '').toString();
    final liveRide =
        liveStatus == 'accepted' || liveStatus == 'in_progress' || liveStatus == 'arrived';

    // Street-corner markers only while planning/searching (keep live map light).
    if (!liveRide && _cornerPin != null) {
      for (var i = 0; i < _routeCorners.length; i++) {
        markers.add(
          Marker(
            markerId: MarkerId('corner_$i'),
            position: _routeCorners[i],
            icon: _cornerPin!,
            anchor: const Offset(0.5, 0.5),
            zIndexInt: 3,
            consumeTapEvents: false,
          ),
        );
      }
    }

    // Scout cars while searching; viewed drivers get the green arrow.
    if (!liveRide && (_previewDrivers || _searching3d)) {
      for (final car in _cars) {
        final icon = car.viewed
            ? (_viewedArrowIcon ??
                _truckIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ))
            : (_truckIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ));
        markers.add(
          Marker(
            markerId: MarkerId(car.id),
            position: car.position,
            icon: icon,
            flat: true,
            rotation: car.heading,
            anchor: const Offset(0.5, 0.55),
            infoWindow: InfoWindow(
              title: car.name,
              snippet: car.viewed
                  ? 'Seen · not responding'
                  : (car.real
                      ? 'Available nearby'
                      : (car.followRoute
                          ? 'On your route'
                          : 'Looking for jobs')),
            ),
            zIndexInt: car.viewed ? 10 : (car.real ? 8 : 5),
          ),
        );
      }
    }

    final livePos = _displayDriverPos ?? _liveDriverPos;
    if (liveRide && livePos != null) {
      final dName = (_activeTrip?['driver'] is Map)
          ? ((_activeTrip!['driver']['name'] ?? 'Driver').toString())
          : 'Driver';
      markers.add(
        Marker(
          markerId: const MarkerId('live_driver'),
          position: livePos,
          icon: _navArrowIcon ??
              _truckIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueYellow,
              ),
          flat: true,
          rotation: _displayDriverHeading,
          anchor: const Offset(0.5, 0.55),
          infoWindow: InfoWindow(
            title: dName,
            snippet: liveStatus == 'in_progress'
                ? 'On your shift'
                : 'On the way to pickup',
          ),
          zIndexInt: 12,
          consumeTapEvents: false,
        ),
      );
    }

    final searchingOpen = searching && !liveRide;
    // Stable padding only — avoid panel expand/collapse changing GoogleMap pad.
    final topPad = MediaQuery.of(context).padding.top + 52;
    final bottomPad = liveRide || searchingOpen
        ? 96.0
        : ready
            ? 126.0
            : 48.0;
    return RepaintBoundary(
      child: GoogleMap(
        key: const ValueKey('client_shift_map'),
        initialCameraPosition: CameraPosition(
          target: livePos ??
              (_pickup != null
                  ? LatLng(_pickup!.latitude, _pickup!.longitude)
                  : _mapCenter),
          zoom: liveRide
              ? 17.85
              : (searchingOpen ? 15.4 : (_hasGps ? 14.5 : 12)),
          bearing: liveRide
              ? _displayDriverHeading
              : (searchingOpen ? _tripBearing() : 0),
          tilt: liveRide ? 48 : (searchingOpen ? 58 : 0),
        ),
        // Same dark Yango street map as the driver (search + live).
        style: (liveRide || searchingOpen) ? kYangoNavMapStyle : kYangoMapStyle,
        myLocationEnabled: _hasGps && !liveRide,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        compassEnabled: true,
        liteModeEnabled: false,
        buildingsEnabled: true,
        indoorViewEnabled: false,
        trafficEnabled: false,
        // Fully movable: pan / pinch-zoom / rotate / tilt anytime.
        rotateGesturesEnabled: true,
        tiltGesturesEnabled: true,
        scrollGesturesEnabled: true,
        zoomGesturesEnabled: true,
        // Win gesture arena so the map scrolls under floating UI.
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
        },
        minMaxZoomPreference: const MinMaxZoomPreference(3, 21),
        markers: markers,
        circles: searchingOpen && _pickup != null
            ? {
                Circle(
                  circleId: const CircleId('search_ring'),
                  center: LatLng(_pickup!.latitude, _pickup!.longitude),
                  radius: 900,
                  fillColor: const Color(0xFFFFC107).withValues(alpha: 0.08),
                  strokeColor: const Color(0xFFFFC107).withValues(alpha: 0.45),
                  strokeWidth: 2,
                ),
              }
            : {},
        polylines: liveRide ? _liveRoutePolylines() : _uberRoutePolylines(),
        padding: EdgeInsets.only(
          top: topPad,
          bottom: bottomPad,
          left: (liveRide || searchingOpen) ? 16 : 28,
          right: (liveRide || searchingOpen) ? 16 : 28,
        ),
        onTap: (_) {
          if (!_panelCollapsed) {
            _setPanelCollapsed(true);
          }
        },
        onCameraMoveStarted: () {
          if (_routeFlying) _stopRouteNavigation();
          // User panned — pause chase until they tap recenter.
          if (liveRide && !_programmaticCam) _clientCamFollow = false;
        },
        onMapCreated: (c) async {
          _tripMapCtrl = c;
          if (liveRide && livePos != null) {
            await _followLiveDriverCamera(force: true, pos: livePos);
          } else if (searchingOpen) {
            await _fitMapCamera(searching: true);
          } else if (_routePts.isNotEmpty) {
            await _fitRouteBounds(animated: false);
          } else {
            await _fitMapCamera(
              preview3d: false,
              searching: false,
            );
          }
        },
      ),
    );
  }

  /// Road route on live rides (pickup → destination). Fallback while loading.
  Set<Polyline> _liveRoutePolylines() {
    List<LatLng> pts = _routePts;
    var loading = false;
    if (pts.length < 2 && _pickup != null && _dropoff != null) {
      pts = [
        LatLng(_pickup!.latitude, _pickup!.longitude),
        LatLng(_dropoff!.latitude, _dropoff!.longitude),
      ];
      loading = true;
    }
    if (pts.length < 2) return {};

    return {
      Polyline(
        polylineId: const PolylineId('live_route_halo'),
        points: pts,
        color: const Color(0xFF0B1F4A),
        width: 12,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        zIndex: 1,
      ),
      Polyline(
        polylineId: const PolylineId('live_route'),
        points: pts,
        color: _kNavRoute,
        width: 7,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        patterns: loading
            ? [PatternItem.dash(22), PatternItem.gap(12)]
            : const <PatternItem>[],
        zIndex: 2,
      ),
    };
  }

  /// Full-screen map: edge-to-edge GoogleMap + floating chrome (no AppBar/tabs).
  Widget _buildRequestTab(bool isDark) {
    final ready = _pickup != null && _dropoff != null;
    final screenH = MediaQuery.of(context).size.height;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _buildTripMap(isDark)),
        // Buttons only — no full-width bar so the map stays scrollable.
        Positioned(
          top: 0,
          left: 12,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _mapChromeButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Dashboard',
                onTap: () => context.go('/tenant-dashboard'),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _mapChromeButton(
                icon: Icons.receipt_long_rounded,
                tooltip: 'My shifts',
                onTap: _openMyShifts,
                bg: const Color(0xFFFFC107),
                fg: Colors.black,
              ),
            ),
          ),
        ),
        // Floating search card — sized to content so map pans around it.
        if (_activeTrip == null)
          Positioned(
            top: 0,
            left: 12,
            right: 12,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 64),
                child: Material(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  elevation: 6,
                  shadowColor: Colors.black45,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _placeRow(isPickup: true, isDark: isDark),
                        Divider(
                          height: 1,
                          indent: 34,
                          color:
                              isDark ? Colors.white12 : Colors.grey.shade200,
                        ),
                        _placeRow(isPickup: false, isDark: isDark),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        // Fare panel once the route is known; searching panel after posting.
        if (ready || _activeTrip != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedSlide(
              offset: Offset.zero,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              child: _activeTrip != null
                  ? _searchingPanel(isDark)
                  : _farePanel(isDark),
            ),
          ),
        // Pulse is visual only — map stays free to pan/zoom underneath.
        if (_priceBeepActive || _searchWaitingPulse)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: _panelCollapsed ? 118 : 360,
            child: PriceBeepOverlay(
              pulse: _beepPulse,
              amount: _priceBeepActive
                  ? (_incomingPriceAmount ?? 0)
                  : (_currentOffer > 0
                      ? _currentOffer
                      : (double.tryParse(
                              '${_activeTrip?['tenant_offer'] ?? ''}') ??
                          0)),
              secondsLeft: _priceBeepActive
                  ? (_incomingPriceEnds == null
                      ? 30
                      : _incomingPriceEnds!
                          .difference(DateTime.now())
                          .inSeconds
                          .clamp(0, 30))
                  : 0,
              sentFlash: _priceBeepActive && _priceIncomingFlash,
              sentLabel: _priceBeepActive ? 'NEW' : 'POSTED',
              beepLabel: _priceBeepActive ? 'BEEP' : 'SEARCH',
              bannerSent: _priceBeepActive
                  ? 'New price from driver'
                  : 'Request posted',
              bannerWaiting: _priceBeepActive
                  ? 'Respond to new price'
                  : 'Waiting for drivers',
              showAmount: _priceBeepActive || _currentOffer > 0,
              showTimer: _priceBeepActive,
              allowMapGestures: true,
              onCancel: _priceBeepActive
                  ? null
                  : (_submitting ? null : _cancelActiveTrip),
            ),
          ),
        // Yango-style map controls: navigate fly-through + 360 refit.
        if (ready || _activeTrip != null)
          Positioned(
            right: 12,
            bottom: () {
              if (_activeTrip != null) {
                final st = (_activeTrip!['status'] ?? '').toString();
                final live =
                    st == 'accepted' || st == 'in_progress' || st == 'arrived';
                // Stable above the ride sheet (match driver FABs).
                if (live) return _panelCollapsed ? 118.0 : 372.0;
                if (_panelCollapsed) return 118.0;
                return screenH * 0.34 + 14;
              }
              return _panelCollapsed ? 130.0 : screenH * 0.36 + 14;
            }(),
            child: Column(
              children: [
                if (_routePts.length > 2 && _activeTrip == null)
                  Material(
                    color: _routeFlying ? _kYangoRouteDark : _kYangoRoute,
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        if (_routeFlying) {
                          _stopRouteNavigation();
                        } else {
                          _startRouteNavigation();
                        }
                      },
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: Icon(
                          _routeFlying
                              ? Icons.stop_rounded
                              : Icons.navigation_rounded,
                          size: 22,
                          color: _kRouteBlack,
                        ),
                      ),
                    ),
                  ),
                if (_routePts.length > 2 && _activeTrip == null)
                  const SizedBox(height: 10),
                Material(
                  color: const Color(0xFF2A2A2A),
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      _stopRouteNavigation();
                      if (_isLiveRide &&
                          (_displayDriverPos ?? _liveDriverPos) != null) {
                        _clientCamFollow = true;
                        _followLiveDriverCamera(force: true);
                      } else {
                        _fitRouteBounds(animated: true);
                      }
                    },
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: Icon(
                        Icons.my_location_rounded,
                        size: 22,
                        color: _isLiveRide && _clientCamFollow
                            ? const Color(0xFFFFC107)
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Second arrow control — reset north / unlock free rotate.
                Material(
                  color: const Color(0xFF2A2A2A),
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () async {
                      _clientCamFollow = false;
                      final ctrl = _tripMapCtrl;
                      if (ctrl == null) return;
                      try {
                        await ctrl.animateCamera(
                          CameraUpdate.newCameraPosition(
                            CameraPosition(
                              target: _displayDriverPos ??
                                  _liveDriverPos ??
                                  (_pickup != null
                                      ? LatLng(
                                          _pickup!.latitude,
                                          _pickup!.longitude,
                                        )
                                      : _mapCenter),
                              zoom: _isLiveRide ? 16.5 : 15.2,
                              bearing: 0,
                              tilt: _isLiveRide || _searching3d ? 45 : 0,
                            ),
                          ),
                        );
                      } catch (_) {}
                    },
                    child: const SizedBox(
                      width: 46,
                      height: 46,
                      child: Icon(
                        Icons.navigation_rounded,
                        size: 22,
                        color: Color(0xFFFFC107),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  double get _currentOffer {
    final base = _fareEstimate ?? 100;
    return _offerPrice ?? base;
  }

  void _bumpOffer(double delta) {
    setState(() {
      _offerPrice = (_currentOffer + delta)
          .clamp(MovingMarketplaceService.minFare, 1000000.0);
    });
  }

  void _setPanelCollapsed(bool collapsed) {
    if (_panelCollapsed == collapsed) return;
    setState(() => _panelCollapsed = collapsed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isLiveRide) {
        // Don't refit on minimize — keeps the live map steady like driver.
        return;
      }
      if (_activeTrip != null) {
        _fitMapCamera(searching: true);
      } else if (_routePts.isNotEmpty) {
        _fitRouteBounds(animated: true);
      }
    });
  }

  void _togglePanel() => _setPanelCollapsed(!_panelCollapsed);

  /// Shared Expand / Minimize control for the fare sheet.
  Widget _panelToggleButton({required bool collapsed, bool darkBar = false}) {
    final label = collapsed ? 'Expand' : 'Minimize';
    final icon = collapsed
        ? Icons.keyboard_arrow_up_rounded
        : Icons.keyboard_arrow_down_rounded;
    final fg = darkBar ? Colors.white : _kRouteBlack;
    final bg = darkBar
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFF0F0F0);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _togglePanel,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom panel — same dark negotiate look as the driver sheet:
  /// big − / + price, neat "what you are moving", request CTA.
  /// Date/time are hidden here but still sent as "now" on submit.
  Widget _farePanel(bool _) {
    final offer = _currentOffer;
    final estimate = _fareEstimate;

    // Minimized: Duration | Distance + quick request.
    if (_panelCollapsed) {
      final dur = _routeDurText.isNotEmpty ? _routeDurText : '—';
      final dist = _routeDistText.isNotEmpty
          ? _routeDistText
          : (_tripKm != null ? '${_tripKm!.toStringAsFixed(1)} km' : '—');
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Duration',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dur,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Distance',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dist,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _panelToggleButton(collapsed: true, darkBar: true),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'K ${offer.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Color(0xFFFFC107),
                      fontWeight: FontWeight.w900,
                      fontSize: 40,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFC107),
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: const Color(0xFF333333),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.black,
                                ),
                              )
                            : const Text(
                                'Request',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: (MediaQuery.of(context).size.height -
                  MediaQuery.of(context).viewInsets.bottom) *
              0.55,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 22,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SingleChildScrollView(
          controller: _fareScrollCtrl,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 150) {
                    _setPanelCollapsed(true);
                  }
                },
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _panelToggleButton(collapsed: false, darkBar: true),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'HouseRent Shifts',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                MovingMarketplaceService.farePeriodLabel(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.9),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Furniture / rental shifting · min K ${MovingMarketplaceService.minFare.toStringAsFixed(0)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _tripKm != null
                    ? (_routeDurText.isNotEmpty
                        ? '${_tripKm!.toStringAsFixed(1)} km · $_routeDurText'
                        : '${_tripKm!.toStringAsFixed(1)} km trip')
                    : (_routeDistText.isNotEmpty
                        ? '$_routeDistText · $_routeDurText'
                        : 'Trip route'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _stepButton(
                    icon: Icons.remove_rounded,
                    onTap: () => _bumpOffer(-1),
                    isDark: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'K ${offer.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Color(0xFFFFC107),
                        fontWeight: FontWeight.w900,
                        fontSize: 40,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  _stepButton(
                    icon: Icons.add_rounded,
                    onTap: () => _bumpOffer(1),
                    isDark: true,
                  ),
                ],
              ),
              if (estimate != null) ...[
                const SizedBox(height: 6),
                Text(
                  MovingMarketplaceService.isNightRate()
                      ? 'Night suggested · K ${estimate.toStringAsFixed(0)}'
                      : 'Day suggested · K ${estimate.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'What are you moving?',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _itemsCtrl,
                focusNode: _itemsFocus,
                maxLines: 2,
                minLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                cursorColor: const Color(0xFFFFC107),
                textInputAction: TextInputAction.done,
                onTap: () {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (!mounted || !_fareScrollCtrl.hasClients) return;
                    _fareScrollCtrl.animateTo(
                      _fareScrollCtrl.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  });
                },
                decoration: InputDecoration(
                  hintText: 'e.g. 1 bed, sofa, fridge, 6 boxes',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontWeight: FontWeight.w600,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Colors.white10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFFFC107)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: const Color(0xFF333333),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          'Request · K ${offer.toStringAsFixed(0)}',
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
    );
  }

  Future<void> _callDriverPhone(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return;
    final uri = Uri.parse('tel:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _openActiveTripDetails() {
    final id = int.tryParse(_activeTrip?['id']?.toString() ?? '');
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MovingBookingDetailScreen(
          bookingId: id,
          isDriver: false,
        ),
      ),
    );
  }

  void _openActiveTripChat() {
    final trip = _activeTrip;
    final id = int.tryParse(trip?['id']?.toString() ?? '');
    if (id == null) return;
    final driver = trip?['driver'];
    String? name;
    int? driverId;
    if (driver is Map) {
      name = (driver['name'] ?? driver['full_name'] ?? '').toString();
      driverId = int.tryParse(driver['id']?.toString() ?? '');
    }
    name ??= (trip?['driver_name'] ?? '').toString();
    if (name.trim().isEmpty) name = 'Driver';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MovingChatScreen(
          bookingId: id,
          isDriver: false,
          peerName: name,
          driverId: driverId,
        ),
      ),
    );
  }

  Future<void> _cancelActiveTrip() async {
    final trip = _activeTrip;
    final id = int.tryParse(trip?['id']?.toString() ?? '');
    if (id == null || _submitting) return;

    final status = (trip?['status'] ?? 'open').toString();
    final title = status == 'open' ? 'Cancel request?' : 'Cancel ride?';
    final body = status == 'open'
        ? 'Drivers will stop seeing this move request.'
        : 'This ends the trip. You can’t undo this.';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Text(
          body,
          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              status == 'open' ? 'Cancel request' : 'Cancel ride',
              style: TextStyle(
                color: Colors.red.shade300,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await MovingMarketplaceService.cancelBooking(id);
      if (!mounted) return;
      _stopSearchingOnMap();
      _liveTrackTimer?.cancel();
      _liveTrackTimer = null;
      setState(() {
        _activeTrip = null;
        _pickup = null;
        _dropoff = null;
        _routePts = [];
        _routeCorners = [];
        _offerPrice = null;
        _itemsCtrl.clear();
        _panelCollapsed = true;
        _submitting = false;
        _liveDriverPos = null;
        _prevLiveDriverPos = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'open' ? 'Request cancelled.' : 'Ride cancelled.',
          ),
        ),
      );
      await _loadTrips();
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    }
  }

  /// After posting: radar + live count of drivers responding, without ever
  /// leaving the map. Offers pop up automatically from the poll timer.
  /// When accepted, shows a Yango-style driver-arriving sheet.
  Widget _searchingPanel(bool isDark) {
    final trip = _activeTrip!;
    final status = (trip['status'] ?? 'open').toString();
    final accepted = status == 'accepted' || status == 'in_progress' || status == 'arrived';
    final bookingId = int.tryParse(trip['id'].toString()) ?? 0;
    final offers = _driverOffers[bookingId] ?? [];
    final driver = trip['driver'] is Map
        ? Map<String, dynamic>.from(trip['driver'] as Map)
        : <String, dynamic>{};
    final driverName = (driver['name'] ?? 'Driver').toString();
    final agreed = (trip['agreed_amount'] ?? '').toString();
    final vehicle = (driver['vehicle_type'] ?? 'Mover').toString();
    final plate = (driver['vehicle_plate'] ?? '').toString();
    final phone = (driver['phone'] ?? trip['contact_phone'] ?? '').toString();
    final ratingBadge = DriverRatingBadge.fromDriver(driver);
    final ratingLabel = ratingBadge == null
        ? null
        : (ratingBadge.premium
            ? 'Premium · ★ ${ratingBadge.rating.toStringAsFixed(ratingBadge.rating % 1 == 0 ? 0 : 1)}'
            : '★ ${ratingBadge.rating.toStringAsFixed(ratingBadge.rating % 1 == 0 ? 0 : 1)}');

    if (status == 'completed') {
      // Destination done — prompt rating if not already shown.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_promptRateDriver(trip));
      });
    }

    if (accepted) {
      // Collapsed slim bar while ride is live.
      if (_panelCollapsed) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 22,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
          child: SafeArea(
            top: false,
            child: InkWell(
              onTap: () => _setPanelCollapsed(false),
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_shipping_rounded,
                    color: Color(0xFFFFC107),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status == 'arrived'
                              ? 'Driver arrived'
                              : status == 'in_progress'
                                  ? (_remainingEtaDisplay.isNotEmpty &&
                                          _remainingEtaDisplay != '—'
                                      ? 'To destination · $_remainingEtaDisplay'
                                      : 'Shift in progress')
                                  : (_remainingEtaDisplay.isNotEmpty &&
                                          _remainingEtaDisplay != '—'
                                      ? 'Arriving · $_remainingEtaDisplay'
                                      : 'Driver is on the way'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          [
                            driverName,
                            if (plate.isNotEmpty && plate != 'null') plate,
                            if (agreed.isNotEmpty && agreed != 'null')
                              'K $agreed',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _panelToggleButton(collapsed: true, darkBar: true),
                ],
              ),
            ),
          ),
        );
      }

      final pickupAddr = () {
        final p = trip['pickup'];
        if (p is Map) {
          final a = (p['address'] ?? '').toString().trim();
          if (a.isNotEmpty) return a;
        }
        return _pickup?.address;
      }();
      final dropAddr = () {
        final d = trip['dropoff'];
        if (d is Map) {
          final a = (d['address'] ?? '').toString().trim();
          if (a.isNotEmpty) return a;
        }
        return _dropoff?.address;
      }();

      final driverPhoto = () {
        final d = trip['driver'];
        if (d is Map) {
          return MovingMarketplaceService.driverAvatarUrl(
            name: driverName,
            photoUrl: (d['avatar_url'] ?? d['photo_url'] ?? '').toString(),
          );
        }
        return MovingMarketplaceService.driverAvatarUrl(name: driverName);
      }();

      final eta = _remainingEtaDisplay;
      final hasEta = eta.isNotEmpty && eta != '—';
      final headline = status == 'arrived'
          ? (hasEta ? 'Arrived · $eta' : 'Driver arrived at destination')
          : status == 'in_progress'
              ? (hasEta
                  ? 'To destination · $eta'
                  : 'HouseRent Shifts · in progress')
              : (hasEta
                  ? 'Driver arriving · $eta'
                  : 'HouseRent Shifts · driver on the way');
      final vehicleLine =
          vehicle.isNotEmpty && vehicle != 'null' ? vehicle : null;

      return MovingRideStatusPanel(
        headline: headline,
        subtitle: vehicleLine,
        personName: driverName,
        personImageUrl: driverPhoto,
        vehicleLabel: driverName,
        plate: plate.isNotEmpty && plate != 'null' ? plate : null,
        ratingLabel: ratingLabel,
        amountLabel: agreed.isNotEmpty && agreed != 'null'
            ? 'K $agreed'
            : null,
        pickupLabel: pickupAddr,
        dropoffLabel: dropAddr,
        phoneLabel: phone.isNotEmpty && phone != 'null' ? phone : null,
        contactLabel: 'Call',
        safetyLabel: 'Details',
        onContact: phone.isNotEmpty && phone != 'null'
            ? () => _callDriverPhone(phone)
            : null,
        onSafety: _openActiveTripDetails,
        onNotes: _openActiveTripChat,
        notesHint: 'HouseRent Shifts chat…',
        onMinimize: () => _setPanelCollapsed(true),
        onCancel: _submitting ? null : _cancelActiveTrip,
        cancelLabel: 'Cancel shift',
      );
    }

    final seenWaiting = _bookingViewers.length;
    final title = offers.isEmpty
        ? (seenWaiting > 0
            ? '$seenWaiting seen · not responding'
            : (_nearbyDrivers.isEmpty
                ? 'Finding a HouseRent Shifts mover…'
                : '${_nearbyDrivers.length} mover${_nearbyDrivers.length == 1 ? '' : 's'} nearby'))
        : '${offers.length} driver${offers.length == 1 ? '' : 's'} responding'
            '${seenWaiting > 0 ? ' · $seenWaiting still watching' : ''}';
    final subtitle = seenWaiting > 0
        ? (offers.isEmpty
            ? 'Live: green arrows = saw your shift, no price yet'
            : '$_respondedCount priced · $seenWaiting still watching')
        : (trip['tenant_offer'] != null
            ? 'Your offer: K ${trip['tenant_offer']} · HouseRent Shifts'
            : 'Waiting for driver prices · HouseRent Shifts');

    // Minimized: slim status bar — tap Expand (or the bar) to open again.
    if (_panelCollapsed) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _setPanelCollapsed(false),
                      borderRadius: BorderRadius.circular(12),
                      child: Row(
                        children: [
                          _radarBadge(18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _panelToggleButton(collapsed: true, darkBar: true),
                ],
              ),
              if (_bookingViewers.isNotEmpty) ...[
                const SizedBox(height: 8),
                _viewersAvatarStrip(dark: true, compact: true),
              ],
              if (offers.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () => _showDriverOffersSheet(trip),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'View ${offers.length} offer${offers.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 150) {
                  _setPanelCollapsed(true);
                }
              },
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white24
                                : const Color(0xFFE2E2E2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _panelToggleButton(collapsed: false, darkBar: isDark),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _radarBadge(20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
                if (offers.isNotEmpty)
                  Text(
                    'from K ${offers.map((o) => double.tryParse('${o['amount']}') ?? double.infinity).reduce((a, b) => a < b ? a : b).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: Color(0xFFFFC107),
                    ),
                  ),
              ],
            ),
            if (_bookingViewers.isNotEmpty) ...[
              const SizedBox(height: 12),
              _viewersAvatarStrip(dark: isDark, compact: false),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () => _showDriverOffersSheet(trip),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC107),
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: Text(
                        offers.isEmpty ? 'View status' : 'View driver prices',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: _submitting ? null : _cancelActiveTrip,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade300,
                        side: BorderSide(
                          color: Colors.red.shade300.withValues(alpha: 0.45),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: const Text(
                        'Cancel request',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Tenant counter-offer: no typing — just +/- steps and quick suggestions.
  Future<void> _showCounterSheet(
    int bookingId,
    Map<String, dynamic> offer,
  ) async {
    final driverAmt = double.tryParse('${offer['amount']}') ?? 0;
    final driverId = int.tryParse('${offer['driver_id']}');
    final trip = _trips.firstWhere(
      (t) => t['id'].toString() == '$bookingId',
      orElse: () => <String, dynamic>{},
    );
    final myOffer = double.tryParse(
      '${trip['tenant_offer'] ?? trip['estimated_price'] ?? ''}',
    );

    double roundK5(double v) => (v / 5).round() * 5.0;
    final minF = MovingMarketplaceService.minFare;
    final suggestions = <double>{
      if (myOffer != null && myOffer >= minF && myOffer < driverAmt) myOffer,
      if (myOffer != null && myOffer > 0)
        roundK5((driverAmt + myOffer) / 2),
      if (driverAmt > minF + 20) driverAmt - 20,
      if (driverAmt > minF + 10) driverAmt - 10,
    }.where((v) => v >= minF && v < driverAmt).toList()
      ..sort();

    var value = suggestions.isNotEmpty
        ? suggestions.first
        : math.max(minF, driverAmt);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Suggest your price',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Driver asked K ${driverAmt.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _stepButton(
                          icon: Icons.remove_rounded,
                          onTap: () => setSheet(() {
                            value = (value - 1).clamp(
                              MovingMarketplaceService.minFare,
                              1000000.0,
                            );
                          }),
                          isDark: isDark,
                        ),
                        Text(
                          'K ${value.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        _stepButton(
                          icon: Icons.add_rounded,
                          onTap: () => setSheet(() => value += 1),
                          isDark: isDark,
                        ),
                      ],
                    ),
                    if (suggestions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in suggestions)
                            ChoiceChip(
                              label: Text('K ${s.toStringAsFixed(0)}'),
                              selected: value == s,
                              selectedColor: const Color(0xFFFFC107),
                              labelStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5,
                              ),
                              onSelected: (_) => setSheet(() => value = s),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            await MovingMarketplaceService.submitOffer(
                              bookingId: bookingId,
                              amount: value,
                              driverId: driverId,
                            );
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'K ${value.toStringAsFixed(0)} sent to the driver.',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!sheetContext.mounted) return;
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppError.userMessage(e),
                                ),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14171A),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        child: const Text(
                          'Send price to driver',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _stepButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: const Color(0xFF14171A),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: const Color(0xFFFFC107), size: 26),
        ),
      ),
    );
  }

}

/// Full-height popup for typing a place — the sheet rides on top of the
/// keyboard so suggestions are never hidden. Pops with the chosen
/// [PlaceSelection], or a sentinel placeId `__gps__` for "use my location".
class _PlaceSearchSheet extends StatefulWidget {
  const _PlaceSearchSheet({
    required this.title,
    required this.hint,
    this.biasLat,
    this.biasLng,
    this.showUseMyLocation = false,
  });

  final String title;
  final String hint;
  final double? biasLat;
  final double? biasLng;
  final bool showUseMyLocation;

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _predictions = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _predictions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      // Worldwide search biased around the user's GPS; fall back to Zambia
      // for servers still running the older maps proxy.
      var results = await ApiService.autocompleteAddress(
        value.trim(),
        country: '',
        biasLat: widget.biasLat,
        biasLng: widget.biasLng,
      );
      if (results.isEmpty) {
        results = await ApiService.autocompleteAddress(
          value.trim(),
          country: 'zm',
          biasLat: widget.biasLat,
          biasLng: widget.biasLng,
        );
      }
      if (!mounted) return;
      setState(() {
        _predictions = results;
        _loading = false;
      });
    });
  }

  Future<void> _pick(Map<String, dynamic> prediction) async {
    final placeId = (prediction['place_id'] ?? '').toString();
    final description = (prediction['description'] ?? '').toString();
    if (placeId.isEmpty) return;

    setState(() => _loading = true);
    final details = await ApiService.getPlaceDetails(placeId);
    if (!mounted) return;
    setState(() => _loading = false);

    final lat = double.tryParse(details?['lat']?.toString() ?? '');
    final lng = double.tryParse(details?['lng']?.toString() ?? '');
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load that place. Try another.')),
      );
      return;
    }

    Navigator.of(context).pop(
      PlaceSelection(
        address: (details?['address'] ?? description).toString(),
        placeId: placeId,
        latitude: lat,
        longitude: lng,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final height = MediaQuery.of(context).size.height * 0.88;

    return Padding(
      // Rides above the keyboard so the list stays visible while typing.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : const Color(0xFFE2E2E2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: const Color(0xFFFFC107),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFFFC107),
                          ),
                        ),
                      )
                    : null,
                filled: true,
                fillColor:
                    isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white10 : Colors.transparent,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFFFC107)),
                ),
              ),
            ),
            if (widget.showUseMyLocation)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(
                  Icons.my_location_rounded,
                  color: Color(0xFF276EF1),
                  size: 20,
                ),
                title: Text(
                  'Use my current location',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(
                  const PlaceSelection(
                    address: 'My current location',
                    placeId: '__gps__',
                    latitude: 0,
                    longitude: 0,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Expanded(
              child: _predictions.isEmpty
                  ? Center(
                      child: Text(
                        _searchCtrl.text.trim().length < 3
                            ? 'Type at least 3 letters to search'
                            : (_loading ? 'Searching…' : 'No places found'),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: _predictions.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: isDark ? Colors.white12 : Colors.grey.shade200,
                      ),
                      itemBuilder: (context, index) {
                        final p = _predictions[index];
                        return ListTile(
                          leading: Icon(
                            Icons.place_outlined,
                            size: 20,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                          title: Text(
                            (p['description'] ?? '').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          onTap: () => _pick(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
