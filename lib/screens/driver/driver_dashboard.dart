import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/firebase_messaging_service.dart';
import '../../services/google_routes.dart';
import '../../services/moving_marketplace_service.dart';
import '../../services/moving_trip_notifier.dart';
import '../../theme/yango_map_style.dart';
import '../../widgets/moving_ride_status_panel.dart';
import '../../widgets/price_beep_overlay.dart';
import '../../widgets/price_offer_countdown.dart';
import '../../widgets/skeleton_loader.dart';
import '../moving/moving_booking_detail_screen.dart';
import '../moving/moving_chat_screen.dart';
import 'driver_buy_tokens_sheet.dart';
import 'driver_identity_verification_screen.dart';
import 'driver_nav_screen.dart';
import '../../utils/app_error.dart';
import '../../utils/moving_roles.dart';

/// Uber-style driver panel with live map of available moving requests.
class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard>
    with SingleTickerProviderStateMixin {
  static const LatLng _fallback = LatLng(-15.4167, 28.2833);
  static const Color _uberBlack = Color(0xFF000000);
  static const Color _uberGreen = Color(0xFFFFC107);
  static const Color _accent = Color(0xFFFFC107);

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _driverName = 'Driver';
  /// e.g. "2 tok K20 · 3 tok K50 · 5 tok K89" from token API.
  String _tokenPriceHint = '2 tok K20 · 3 tok K50 · 5 tok K89';
  LatLng _driverLatLng = _fallback;
  bool _hasGps = false;
  double _heading = 0;
  bool _follow3D = false; // Uber-style chase camera (tilt + bearing)
  StreamSubscription<Position>? _posSub;
  int _selectedIndex = 0;
  int _tab = 0; // 0 = Home dashboard, 1 = Live map
  bool _ridePanelMinimized = false;

  /// After sending a new price: big beep pulse on the map while waiting.
  bool _priceSentFlash = false;
  int? _waitingPriceBookingId;
  double? _waitingPriceAmount;
  DateTime? _waitingPriceEnds;
  late final AnimationController _beepPulse;
  Timer? _beepTimer;
  Timer? _priceWaitPoll;

  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  final Map<String, List<LatLng>> _routeCache = {};
  final Set<String> _routeLoading = {};
  final Map<String, BitmapDescriptor> _pricePins = {};
  BitmapDescriptor? _driverIcon;
  BitmapDescriptor? _dropIcon;

  Timer? _pollTimer;
  Timer? _locationTimer;
  Timer? _gpsRebuildTimer;
  bool _overlaysDirty = false;
  int _overlayGen = 0;
  bool _selectingRequest = false;

  /// Track open request ids so new ones can pop up on the map.
  final Set<String> _knownRequestIds = {};
  bool _seededRequestIds = false;
  bool _requestPopupOpen = false;

  final _vehicleTypeCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _beepPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _bootstrap();
    _pollTimer = Timer.periodic(const Duration(seconds: 18), (_) {
      if (mounted && _tab == 1) _loadBookings(silent: true);
    });
  }

  @override
  void dispose() {
    _stopPriceWaitOnMap(refresh: false);
    _beepPulse.dispose();
    _pollTimer?.cancel();
    _locationTimer?.cancel();
    _gpsRebuildTimer?.cancel();
    _posSub?.cancel();
    _mapController?.dispose();
    _vehicleTypeCtrl.dispose();
    _capacityCtrl.dispose();
    _plateCtrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  bool get _isWaitingPrice =>
      _waitingPriceBookingId != null && _waitingPriceAmount != null;

  /// Show SENT, then beep + big pulse on the map until accept / timeout.
  Future<void> _startPriceWaitOnMap({
    required int bookingId,
    required double amount,
  }) async {
    _stopPriceWaitOnMap(refresh: false);
    setState(() {
      _tab = 1;
      _ridePanelMinimized = true;
      _priceSentFlash = true;
      _waitingPriceBookingId = bookingId;
      _waitingPriceAmount = amount;
      _waitingPriceEnds = DateTime.now().add(const Duration(seconds: 30));
    });

    // Quick "SENT" flash, then keep waiting UI.
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _priceSentFlash = false);
    });

    _beepPulse.repeat();
    _playBeep();
    _beepTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!_isWaitingPrice) return;
      _playBeep();
    });

    _priceWaitPoll = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_isWaitingPrice || !mounted) return;
      final ends = _waitingPriceEnds;
      if (ends != null && DateTime.now().isAfter(ends)) {
        _finishPriceWait(accepted: false);
        return;
      }
      try {
        final b =
            await MovingMarketplaceService.getBooking(_waitingPriceBookingId!);
        final a = double.tryParse('${b['agreed_amount']}');
        if (a != null && (a - amount).abs() < 0.5) {
          _finishPriceWait(accepted: true);
        }
      } catch (_) {}
      // Countdown text is driven by _beepPulse — no setState (avoids map refresh).
    });
  }

  void _playBeep() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.click);
  }

  void _finishPriceWait({required bool accepted}) {
    final amount = _waitingPriceAmount ?? 0;
    _stopPriceWaitOnMap(refresh: true);
    if (!mounted) return;
    showPriceOfferResult(
      context: context,
      kind: accepted
          ? PriceOfferResultKind.accepted
          : PriceOfferResultKind.noResponse,
      amount: amount,
      title: accepted ? 'Client accepted' : 'No response',
      subtitle: accepted
          ? 'Fare updated for this trip.'
          : 'You can send another price anytime.',
      primaryLabel: accepted ? 'Continue' : 'Send again',
    );
  }

  void _stopPriceWaitOnMap({required bool refresh}) {
    _beepTimer?.cancel();
    _beepTimer = null;
    _priceWaitPoll?.cancel();
    _priceWaitPoll = null;
    if (_beepPulse.isAnimating) _beepPulse.stop();
    if (!mounted) return;
    setState(() {
      _waitingPriceBookingId = null;
      _waitingPriceAmount = null;
      _waitingPriceEnds = null;
      _priceSentFlash = false;
    });
    if (refresh) _refreshAll();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _driverName = prefs.getString('user_name') ?? 'Driver';
    await _buildIcons();
    await _resolveGps();
    _startGpsStream();
    // Load token prices from API so UI matches Lenco checkout amounts.
    unawaited(_loadTokenPriceHint());
    await _refreshAll();
  }

  Future<void> _loadTokenPriceHint() async {
    final packages = await fetchDriverTokenPackages();
    if (!mounted || packages.isEmpty) return;
    setState(() {
      _tokenPriceHint = packages
          .map((p) {
            final price = p.price == p.price.roundToDouble()
                ? 'K${p.price.toInt()}'
                : 'K${p.price.toStringAsFixed(2)}';
            return '${p.tokens} tok $price';
          })
          .join(' · ');
    });
  }

  /// Live GPS — throttled so the map doesn't rebuild every few metres.
  void _startGpsStream() {
    if (kIsWeb) return;
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 18,
      ),
    ).listen(
      (pos) {
        if (!mounted) return;
        _driverLatLng = LatLng(pos.latitude, pos.longitude);
        _hasGps = true;
        if (pos.heading >= 0) _heading = pos.heading;
        // Debounce marker rebuilds — avoid jank / crashes on rapid GPS ticks.
        // Live rides: slower updates so taps/pans don't fight the map platform view.
        final live = _selectedBooking != null && _canNavigate(_selectedBooking!);
        _gpsRebuildTimer?.cancel();
        _gpsRebuildTimer = Timer(
          Duration(milliseconds: live ? 1400 : 450),
          () {
            if (!mounted || _tab != 1) return;
            _rebuildMapOverlays(light: true);
            if (_follow3D) _chaseCamera(animate: false);
          },
        );
      },
      onError: (_) {},
    );
  }

  /// Uber-style 3D chase cam: tilted, zoomed in, rotated to the direction
  /// the driver is travelling.
  Future<void> _chaseCamera({bool animate = true}) async {
    final controller = _mapController;
    if (controller == null || !_hasGps) return;
    final update = CameraUpdate.newCameraPosition(
      CameraPosition(
        target: _driverLatLng,
        zoom: 16.4,
        tilt: 0,
        bearing: _heading,
      ),
    );
    try {
      if (animate) {
        await controller.animateCamera(update);
      } else {
        await controller.moveCamera(update);
      }
    } catch (_) {}
  }

  Future<void> _buildIcons() async {
    _dropIcon = await _circleMarker(
      fill: _uberBlack,
      ring: Colors.white,
      glyph: Icons.flag_rounded,
      glyphColor: Colors.white,
      size: 84,
    );
    _driverIcon = await _circleMarker(
      fill: const Color(0xFF276EF1),
      ring: Colors.white,
      glyph: Icons.local_shipping_rounded,
      glyphColor: Colors.white,
    );
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _circleMarker({
    required Color fill,
    required Color ring,
    required IconData glyph,
    required Color glyphColor,
    double size = 96,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final radius = size * 0.33;

    canvas.drawCircle(
      center.translate(0, 2),
      radius + 2,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(center, radius, Paint()..color = fill);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(glyph.codePoint),
        style: TextStyle(
          fontSize: size * 0.35,
          fontFamily: glyph.fontFamily,
          package: glyph.fontPackage,
          color: glyphColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
  }

  /// Uber-style price tag pin (dark pill with the fare + pointer tail).
  Future<BitmapDescriptor> _pricePinFor(String label, {bool selected = false}) async {
    final key = '$label|$selected';
    final cached = _pricePins[key];
    if (cached != null) return cached;

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w900,
          color: selected ? Colors.black : _accent,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final w = math.max(tp.width + 44, 72.0);
    const pillH = 54.0;
    const tail = 14.0;
    final h = pillH + tail + 10;
    final pillColor = selected ? _accent : const Color(0xFF14171A);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 4, w, pillH),
      const Radius.circular(27),
    );

    canvas.drawRRect(
      rrect.shift(const Offset(0, 4)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(rrect, Paint()..color = pillColor);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );

    final tailPath = Path()
      ..moveTo(w / 2 - 11, pillH + 2)
      ..lineTo(w / 2 + 11, pillH + 2)
      ..lineTo(w / 2, pillH + tail + 2)
      ..close();
    canvas.drawPath(tailPath, Paint()..color = pillColor);

    tp.paint(canvas, Offset((w - tp.width) / 2, 4 + (pillH - tp.height) / 2));

    final image =
        await recorder.endRecording().toImage(w.ceil(), h.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final pin = BitmapDescriptor.bytes(bytes!.buffer.asUint8List());
    _pricePins[key] = pin;
    return pin;
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

      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          setState(() {
            _driverLatLng = LatLng(last.latitude, last.longitude);
            _hasGps = true;
          });
        }
      } catch (_) {}

      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
        if (!mounted) return;
        setState(() {
          _driverLatLng = LatLng(pos.latitude, pos.longitude);
          _hasGps = true;
        });
        return;
      } catch (_) {}

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 16),
        ),
      );
      if (!mounted) return;
      setState(() {
        _driverLatLng = LatLng(pos.latitude, pos.longitude);
        _hasGps = true;
      });
    } catch (_) {}
  }

  Future<void> _refreshAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Map<String, dynamic>? profile;
      List<Map<String, dynamic>> bookings = [];
      String? err;

      try {
        profile = await MovingMarketplaceService.getDriverMe();
      } catch (e) {
        err = AppError.userMessage(e);
      }

      try {
        bookings = await MovingMarketplaceService.listBookings();
      } catch (e) {
        err ??= AppError.userMessage(e);
      }

      if (!mounted) return;
      if (profile != null) _applyProfile(profile);
      setState(() {
        _bookings = bookings;
        _loading = false;
        // Full-screen error only when profile cannot load.
        _error = profile == null ? err : null;
        if (_selectedIndex >= _feedRequests.length) {
          _selectedIndex = 0;
        }
      });
      if (err != null && profile != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
      }
      await _rebuildMapOverlays();
      _syncLocationTracking();
      _fitMap();
      // Seed known ids on full refresh so only later polls pop up as "new".
      if (!_seededRequestIds) {
        _knownRequestIds
          ..clear()
          ..addAll(_openRequests.map((b) => b['id'].toString()));
        _seededRequestIds = true;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.userMessage(e);
        _loading = false;
      });
    }
  }

  void _applyProfile(Map<String, dynamic> profile) {
    _profile = profile;
    _vehicleTypeCtrl.text = (profile['vehicle_type'] ?? '').toString();
    _capacityCtrl.text = (profile['vehicle_capacity'] ?? '').toString();
    _plateCtrl.text = (profile['vehicle_plate'] ?? '').toString();
    _areaCtrl.text = (profile['service_area'] ?? '').toString();
    if ((profile['name'] ?? '').toString().isNotEmpty) {
      _driverName = profile['name'].toString();
    }
  }

  Future<void> _loadBookings({bool silent = false}) async {
    try {
      final bookings = await MovingMarketplaceService.listBookings();
      if (!mounted) return;
      final previousOpen = Set<String>.from(_knownRequestIds);
      final prevLiveId = _selectedBooking?['id']?.toString();
      final prevLiveStatus = _selectedBooking?['status']?.toString();
      final wasLive =
          _selectedBooking != null && _canNavigate(_selectedBooking!);
      setState(() {
        _bookings = bookings;
        _error = null;
        if (_selectedIndex >= _feedRequests.length) {
          _selectedIndex = math.max(0, _feedRequests.length - 1);
        }
      });
      final selected = _selectedBooking;
      final stillSameLive = silent &&
          wasLive &&
          selected != null &&
          _canNavigate(selected) &&
          selected['id']?.toString() == prevLiveId &&
          selected['status']?.toString() == prevLiveStatus;
      // During ride in progress, silent polls must NOT rebuild/refocus the map
      // — that felt like a crash/refresh when the driver tapped or panned.
      if (!stillSameLive) {
        await _rebuildMapOverlays();
        await _focusSelected(animate: false);
      }
      _detectNewIncomingRequests(previousOpen);
      // Trip start / arrival alerts (deduped) for the active job only.
      Map<String, dynamic>? live = _selectedBooking;
      if (live == null || !_canNavigate(live)) {
        live = null;
        for (final b in bookings) {
          if (_canNavigate(b)) {
            live = b;
            break;
          }
        }
      }
      if (live != null) {
        unawaited(
          MovingTripNotifier.handleBookingStatus(live, isDriver: true),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppError.userMessage(e))),
        );
      }
    }
  }

  String? _offerPriceLabel(Map<String, dynamic> booking) {
    final raw = booking['tenant_offer'] ?? booking['estimated_price'];
    final n = raw is num ? raw : num.tryParse('$raw');
    if (n == null) return null;
    return 'K ${n.round()}';
  }

  void _detectNewIncomingRequests(Set<String> previousOpen) {
    final open = _openRequests;
    final ids = open.map((b) => b['id'].toString()).toSet();

    if (!_seededRequestIds) {
      _knownRequestIds
        ..clear()
        ..addAll(ids);
      _seededRequestIds = true;
      return;
    }

    final newcomers = open
        .where((b) => !previousOpen.contains(b['id'].toString()))
        .toList();
    _knownRequestIds
      ..clear()
      ..addAll(ids);

    if (newcomers.isEmpty || !mounted) return;

    // Jump to the live map and pop the newest request up.
    final newest = newcomers.first;
    final idx =
        _feedRequests.indexWhere((b) => b['id'].toString() == newest['id'].toString());
    setState(() {
      _tab = 1;
      if (idx >= 0) _selectedIndex = idx;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showIncomingRequestPopup(newest);
    });
  }

  Future<void> _showIncomingRequestPopup(Map<String, dynamic> booking) async {
    if (!mounted || _requestPopupOpen) return;
    _requestPopupOpen = true;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final price = _offerPriceLabel(booking) ?? 'New move';
    final name = _tenantName(booking);
    final pickup = _addressOf(booking['pickup'], 'Pickup on map');
    final dropoff = _addressOf(booking['dropoff'], 'Destination on map');
    final km = booking['distance_km'];
    final when = [
      if ((booking['moving_date'] ?? '').toString().isNotEmpty)
        booking['moving_date'].toString(),
      if ((booking['moving_time'] ?? '').toString().isNotEmpty)
        booking['moving_time'].toString(),
    ].join(' · ');

    // Focus map on this request's pickup.
    final idx =
        _feedRequests.indexWhere((b) => b['id'].toString() == booking['id'].toString());
    if (idx >= 0) await _onSelectRequest(idx, animatePage: true);

    if (!mounted) {
      _requestPopupOpen = false;
      return;
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Incoming request',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, anim, secondary) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
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
                            color: _accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'NEW REQUEST',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              color: Color(0xFF9A7400),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          price,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                            color: _uberGreen,
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
                        color: isDark ? Colors.white : _uberBlack,
                      ),
                    ),
                    if (when.isNotEmpty)
                      Text(
                        when,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    const SizedBox(height: 10),
                    _popupRouteLine(
                      color: const Color(0xFF276EF1),
                      label: 'PICKUP',
                      value: pickup,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 6),
                    _popupRouteLine(
                      color: _uberBlack,
                      label: 'DESTINATION',
                      value: dropoff,
                      isDark: isDark,
                    ),
                    if (km != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '$km km trip',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  isDark ? Colors.white70 : Colors.black87,
                              side: BorderSide(
                                color: isDark
                                    ? Colors.white24
                                    : const Color(0xFFE0E0E0),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              minimumSize: const Size(0, 46),
                            ),
                            child: const Text(
                              'Dismiss',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _slideAcceptBooking(booking);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _uberGreen,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              minimumSize: const Size(0, 46),
                            ),
                            child: const Text(
                              'Accept',
                              style: TextStyle(fontWeight: FontWeight.w900),
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
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.2),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );

    _requestPopupOpen = false;
  }

  Widget _popupRouteLine({
    required Color color,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: label == 'DESTINATION' ? BoxShape.rectangle : BoxShape.circle,
            borderRadius:
                label == 'DESTINATION' ? BorderRadius.circular(2) : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: isDark ? Colors.white : _uberBlack,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool get _isAvailable =>
      (_profile?['availability_status']?.toString() ?? '') == 'available';

  int get _tokens =>
      int.tryParse(_profile?['booking_tokens']?.toString() ?? '0') ?? 0;

  String get _profilePhotoUrl {
    final raw =
        (_profile?['photo_url'] ?? _profile?['avatar_url'] ?? '').toString().trim();
    if (raw.isEmpty || raw.contains('ui-avatars.com')) return '';
    return MovingMarketplaceService.driverAvatarUrl(
      name: _driverName,
      photoUrl: raw,
    );
  }

  Future<void> _uploadProfilePhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || path.isEmpty) return;

    setState(() => _busy = true);
    try {
      final data =
          await MovingMarketplaceService.uploadDriverProfilePhoto(path);
      if (!mounted) return;
      setState(() {
        _profile = {
          ...?_profile,
          'photo_url': data['photo_url'],
          'avatar_url': data['avatar_url'] ?? data['photo_url'],
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Profile photo updated. Tenants will see this photo — not your ID documents.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> get _openRequests => _bookings
      .where((b) => (b['status']?.toString() ?? '') == 'open')
      .toList();

  List<Map<String, dynamic>> get _activeJobs => _bookings
      .where((b) {
        final s = (b['status']?.toString() ?? '');
        return s == 'accepted' || s == 'in_progress' || s == 'completed';
      })
      .toList();

  /// Live accepted / in-progress jobs the driver can access and start.
  List<Map<String, dynamic>> get _liveJobs => _bookings
      .where((b) {
        final s = (b['status']?.toString() ?? '');
        return s == 'accepted' || s == 'in_progress' || s == 'arrived';
      })
      .toList();

  List<Map<String, dynamic>> get _feedRequests =>
      [..._openRequests, ..._activeJobs];

  Map<String, dynamic>? get _selectedBooking {
    final list = _feedRequests;
    if (list.isEmpty) return null;
    final i = _selectedIndex.clamp(0, list.length - 1);
    return list[i];
  }

  /// Rejects missing/zero/out-of-range coordinates. A (0,0) pickup would
  /// otherwise make the camera zoom out to the whole of Africa.
  LatLng? _validLatLng(dynamic latRaw, dynamic lngRaw) {
    final lat = double.tryParse(latRaw?.toString() ?? '');
    final lng = double.tryParse(lngRaw?.toString() ?? '');
    if (lat == null || lng == null) return null;
    if (lat.abs() < 0.0001 && lng.abs() < 0.0001) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return LatLng(lat, lng);
  }

  LatLng? _pickupOf(Map<String, dynamic> booking) {
    final pickup = booking['pickup'];
    if (pickup is! Map) return null;
    return _validLatLng(pickup['latitude'], pickup['longitude']);
  }

  LatLng? _dropoffOf(Map<String, dynamic> booking) {
    final drop = booking['dropoff'];
    if (drop is! Map) return null;
    return _validLatLng(drop['latitude'], drop['longitude']);
  }

  String _tenantName(Map<String, dynamic> booking) {
    final tenant = booking['tenant'];
    if (tenant is Map && (tenant['name'] ?? '').toString().isNotEmpty) {
      return tenant['name'].toString();
    }
    return 'Client';
  }

  String _phoneOf(Map<String, dynamic> booking) {
    final direct = (booking['contact_phone'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final tenant = booking['tenant'];
    if (tenant is Map) {
      final phone = (tenant['phone'] ?? '').toString().trim();
      if (phone.isNotEmpty) return phone;
    }
    return '';
  }

  String _addressOf(dynamic place, String fallback) {
    if (place is! Map) return fallback;
    final address = (place['address'] ?? '').toString().trim();
    return address.isEmpty ? fallback : address;
  }

  Future<void> _callPhone(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return;
    final uri = Uri.parse('tel:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  double get _earnings =>
      double.tryParse(_profile?['total_earnings']?.toString() ?? '0') ?? 0;

  int get _jobsCompleted =>
      int.tryParse(_profile?['jobs_completed']?.toString() ?? '0') ?? 0;

  /// Turn-by-turn navigation stays locked until the job is accepted
  /// (client accepted price → Start ride → navigate).
  bool _canNavigate(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? '').toString();
    return status == 'accepted' ||
        status == 'in_progress' ||
        status == 'arrived';
  }

  Future<void> _startRide(Map<String, dynamic> booking) async {
    final id = int.tryParse(booking['id']?.toString() ?? '');
    if (id == null) return;
    final status = (booking['status'] ?? '').toString();

    setState(() => _busy = true);
    try {
      Map<String, dynamic> updated = booking;
      if (status == 'accepted') {
        updated = await MovingMarketplaceService.startRide(id);
        if (!mounted) return;
        // Merge into local list so UI flips to in_progress.
        setState(() {
          final i = _bookings.indexWhere((b) => b['id']?.toString() == '$id');
          if (i >= 0) {
            _bookings[i] = {..._bookings[i], ...updated, 'status': 'in_progress'};
          }
        });
        unawaited(
          MovingTripNotifier.tripStarted(
            bookingId: id,
            forDriver: true,
            otherName: _tenantName(updated),
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride started — navigate to pickup.')),
        );
      }
      if (!mounted) return;
      await _navigateTo(updated);
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeRide(Map<String, dynamic> booking) async {
    final id = int.tryParse(booking['id']?.toString() ?? '');
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete move?'),
        content: const Text(
          'Mark this move as finished. The client can then rate you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await MovingMarketplaceService.completeBooking(id);
      unawaited(MovingTripNotifier.watchBooking(null));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Move completed.')),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelRide(Map<String, dynamic> booking) async {
    final id = int.tryParse(booking['id']?.toString() ?? '');
    if (id == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Cancel ride?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'This ends the trip for you and the client. You can’t undo this.',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep ride'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Cancel ride',
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

    setState(() => _busy = true);
    try {
      await MovingMarketplaceService.cancelBooking(id);
      if (!mounted) return;
      _stopPriceWaitOnMap(refresh: false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride cancelled.')),
      );
      await _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Navigate: your live GPS → client's pickup or destination.
  /// No price negotiation — fare is already agreed when accepted / in progress.
  Future<void> _navigateTo(Map<String, dynamic> booking) async {
    if (!_canNavigate(booking)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Navigation unlocks after the client accepts. Then tap Continue.',
          ),
        ),
      );
      return;
    }

    final pickup = _pickupOf(booking);
    final dropoff = _dropoffOf(booking);
    if (pickup == null && dropoff == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No map location on this request yet.')),
      );
      return;
    }

    // Always refresh your location first — route origin is YOUR GPS.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Getting your location…'),
        duration: Duration(seconds: 2),
      ),
    );
    await _resolveGps();
    if (!mounted) return;
    if (!_hasGps) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Turn on GPS / location, then tap Navigate again.',
          ),
        ),
      );
      return;
    }

    final agreed = double.tryParse('${booking['agreed_amount']}');
    final status = (booking['status'] ?? '').toString();
    // After start: go to client's destination. Before: go to client pickup.
    var selected = (status == 'in_progress' || status == 'arrived')
        ? (dropoff != null ? 'dropoff' : 'pickup')
        : (pickup != null ? 'pickup' : 'dropoff');

    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            Widget destTile({
              required String id,
              required IconData icon,
              required Color iconColor,
              required String title,
              required String subtitle,
            }) {
              final active = selected == id;
              return Material(
                color: active
                    ? const Color(0xFFFFC107).withValues(alpha: 0.14)
                    : const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setSheet(() => selected = id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: iconColor),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          active
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: active
                              ? const Color(0xFFFFC107)
                              : Colors.white38,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Navigate',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      agreed != null
                          ? 'From your location → client · K ${agreed.toStringAsFixed(0)}'
                          : 'From your location → client stop',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (pickup != null)
                      destTile(
                        id: 'pickup',
                        icon: Icons.radio_button_checked,
                        iconColor: const Color(0xFF2F80FF),
                        title: 'Client pickup',
                        subtitle:
                            _addressOf(booking['pickup'], 'Pickup point'),
                      ),
                    if (pickup != null && dropoff != null)
                      const SizedBox(height: 10),
                    if (dropoff != null)
                      destTile(
                        id: 'dropoff',
                        icon: Icons.flag_rounded,
                        iconColor: Colors.white70,
                        title: 'Client destination',
                        subtitle:
                            _addressOf(booking['dropoff'], 'Drop-off point'),
                      ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(sheetCtx, selected),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFC107),
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.navigation_rounded),
                        label: const Text(
                          'Continue',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
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

    if (choice == null || !mounted) return;

    LatLng target;
    String label;
    LatLng? next;
    String? nextLabel;
    var reportArrival = false;
    var autoStart = false;
    if (choice == 'dropoff' && dropoff != null) {
      target = dropoff;
      label = _addressOf(booking['dropoff'], 'Client destination');
      reportArrival = true;
      autoStart = true;
    } else if (pickup != null) {
      target = pickup;
      label = _addressOf(booking['pickup'], 'Client pickup');
      next = dropoff;
      nextLabel = dropoff != null
          ? _addressOf(booking['dropoff'], 'Client destination')
          : null;
      autoStart = true;
    } else {
      target = dropoff!;
      label = _addressOf(booking['dropoff'], 'Client destination');
      reportArrival = true;
      autoStart = true;
    }

    final bookingId = int.tryParse('${booking['id']}');
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverNavScreen(
          destination: target,
          destinationLabel: label,
          clientName: _tenantName(booking),
          clientPhone: _phoneOf(booking),
          // Seed with live driver GPS; nav will refresh and route from here.
          initialPosition: _hasGps ? _driverLatLng : null,
          bookingId: bookingId,
          reportArrival: reportArrival || next != null,
          autoStartNavigation: autoStart,
          nextDestination: next,
          nextDestinationLabel: nextLabel,
        ),
      ),
    );
  }

  /// When both accept the same price → start ride + nav to pickup (voice on).
  /// At pickup, nav auto-continues to destination.
  Future<void> _autoStartNavAfterAccept(Map<String, dynamic> booking) async {
    final id = int.tryParse('${booking['id']}');
    if (id == null) return;
    var trip = Map<String, dynamic>.from(booking);
    final status = (trip['status'] ?? '').toString();
    if (status == 'accepted') {
      try {
        trip = await MovingMarketplaceService.startRide(id);
        if (mounted) {
          setState(() {
            final i =
                _bookings.indexWhere((b) => b['id']?.toString() == '$id');
            if (i >= 0) {
              _bookings[i] = {
                ..._bookings[i],
                ...trip,
                'status': 'in_progress',
              };
            }
          });
        }
        unawaited(
          MovingTripNotifier.tripStarted(
            bookingId: id,
            forDriver: true,
            otherName: _tenantName(trip),
          ),
        );
      } catch (_) {
        // Still try to navigate even if start-ride fails (already started).
      }
    }

    final pickup = _pickupOf(trip) ?? _pickupOf(booking);
    final dropoff = _dropoffOf(trip) ?? _dropoffOf(booking);
    if (pickup == null) {
      if (mounted) await _navigateTo(trip);
      return;
    }
    if (!_hasGps) await _resolveGps();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverNavScreen(
          destination: pickup,
          destinationLabel: _addressOf(trip['pickup'] ?? booking['pickup'], 'Client pickup'),
          clientName: _tenantName(trip),
          clientPhone: _phoneOf(trip),
          initialPosition: _hasGps ? _driverLatLng : null,
          bookingId: id,
          reportArrival: dropoff != null,
          autoStartNavigation: true,
          nextDestination: dropoff,
          nextDestinationLabel: dropoff != null
              ? _addressOf(trip['dropoff'] ?? booking['dropoff'], 'Client destination')
              : null,
        ),
      ),
    );
    if (mounted) await _refreshAll();
  }

  Widget _priceStepBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: const Color(0xFF2A2A2A),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }

  Future<void> _onSelectRequest(int index, {bool animatePage = false}) async {
    if (index < 0 || index >= _feedRequests.length) return;
    // Same live trip already selected — tapping the map/marker must NOT
    // rebuild GoogleMap (that was flashing/crashing during ride in progress).
    if (index == _selectedIndex) {
      final status = (_feedRequests[index]['status'] ?? '').toString();
      if (status == 'accepted' ||
          status == 'in_progress' ||
          status == 'arrived') {
        if (_ridePanelMinimized && mounted) {
          setState(() => _ridePanelMinimized = false);
        }
        return;
      }
      return;
    }
    if (_selectingRequest) return;
    _selectingRequest = true;
    try {
      setState(() {
        _selectedIndex = index;
        _follow3D = false;
        _ridePanelMinimized = false;
      });
      final booking = _feedRequests[index];
      final status = (booking['status'] ?? '').toString();
      final bid = int.tryParse('${booking['id']}');
      // Tell the tenant who opened their request.
      if (status == 'open' && bid != null) {
        unawaited(MovingMarketplaceService.markBookingViewed(bid));
      }
      await _rebuildMapOverlays();
      await _focusSelected(animate: true);
    } finally {
      _selectingRequest = false;
    }
  }

  Future<void> _focusSelected({required bool animate}) async {
    final booking = _selectedBooking;
    final controller = _mapController;
    if (booking == null || controller == null) return;

    final points = <LatLng>[];
    final pickup = _pickupOf(booking);
    final dropoff = _dropoffOf(booking);
    if (pickup != null) points.add(pickup);
    if (dropoff != null) points.add(dropoff);
    // Only include the driver if reasonably close, so a far-away GPS fix
    // never zooms the camera out to continent level.
    if (_hasGps && pickup != null) {
      final km = Geolocator.distanceBetween(
            _driverLatLng.latitude,
            _driverLatLng.longitude,
            pickup.latitude,
            pickup.longitude,
          ) /
          1000;
      if (km < 120) points.add(_driverLatLng);
    } else if (_hasGps && points.isEmpty) {
      points.add(_driverLatLng);
    }
    if (points.isEmpty) return;

    try {
      if (points.length == 1) {
        final update = CameraUpdate.newCameraPosition(
          CameraPosition(target: points.first, zoom: 14.2),
        );
        if (animate) {
          await controller.animateCamera(update);
        } else {
          await controller.moveCamera(update);
        }
        return;
      }

      var minLat = points.first.latitude;
      var maxLat = points.first.latitude;
      var minLng = points.first.longitude;
      var maxLng = points.first.longitude;
      for (final p in points) {
        minLat = math.min(minLat, p.latitude);
        maxLat = math.max(maxLat, p.latitude);
        minLng = math.min(minLng, p.longitude);
        maxLng = math.max(maxLng, p.longitude);
      }
      final update = CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        90,
      );
      if (animate) {
        await controller.animateCamera(update);
      } else {
        await controller.moveCamera(update);
      }
    } catch (_) {}
  }

  /// Rebuild markers/polylines. [light] = GPS-only refresh (skip pin redraw cost).
  Future<void> _rebuildMapOverlays({bool light = false}) async {
    if (_overlaysDirty && light) return;
    final selected = _selectedBooking;
    final selectedId = selected?['id']?.toString();
    final liveSelected = selected != null && _canNavigate(selected);

    // During a live ride, only nudge the driver pin — full Set rebuilds were
    // refreshing/crashing the map when the driver tapped it.
    if (light && liveSelected && _markers.isNotEmpty && _hasGps) {
      if (!mounted) return;
      setState(() {
        _markers = {
          for (final m in _markers)
            if (m.markerId.value == 'driver_me')
              m.copyWith(
                positionParam: _driverLatLng,
                rotationParam: _heading,
              )
            else
              m,
        };
      });
      return;
    }

    final gen = ++_overlayGen;
    _overlaysDirty = true;
    final markers = <Marker>{};
    final polylines = <Polyline>{};

    if (_hasGps) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver_me'),
          position: _driverLatLng,
          icon: _driverIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          flat: true,
          rotation: _heading,
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(title: 'You'),
          zIndexInt: 10,
          // Don't consume taps on the driver pin during a live ride.
          consumeTapEvents: !liveSelected,
        ),
      );
    }

    // Cap pins on the map — too many custom bitmaps cause jank/crashes.
    // Hide open-request pins while a live ride is selected (less tap noise).
    final open = liveSelected ? <Map<String, dynamic>>[] : _openRequests.take(8).toList();
    for (final b in open) {
      final pos = _pickupOf(b) ?? _dropoffOf(b);
      if (pos == null) continue;
      final id = b['id'].toString();
      final name = _tenantName(b);
      final isSelected = id == selectedId;
      final priceLabel = _offerPriceLabel(b);

      BitmapDescriptor icon;
      if (isSelected && priceLabel != null) {
        icon = await _pricePinFor(priceLabel, selected: true);
      } else if (isSelected) {
        icon = await _pricePinFor('NEW', selected: true);
      } else {
        icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
      }
      if (gen != _overlayGen) return;

      markers.add(
        Marker(
          markerId: MarkerId('req_$id'),
          position: pos,
          icon: icon,
          anchor: const Offset(0.5, 1),
          infoWindow: InfoWindow(
            title: priceLabel ?? 'New request',
            snippet: name,
          ),
          onTap: () {
            final idx =
                _feedRequests.indexWhere((x) => x['id'].toString() == id);
            if (idx >= 0) _onSelectRequest(idx, animatePage: true);
          },
          zIndexInt: isSelected ? 8 : 5,
        ),
      );
    }

    for (final b in _liveJobs.take(4)) {
      final pos = _pickupOf(b);
      if (pos == null) continue;
      final id = b['id'].toString();
      final st = (b['status']?.toString() ?? '');
      final started = st == 'in_progress' || st == 'arrived';
      final isSelectedLive = liveSelected && id == selectedId;
      markers.add(
        Marker(
          markerId: MarkerId('job_$id'),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            started ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: _tenantName(b),
            snippet: started ? 'Ride in progress' : 'Accepted trip',
          ),
          onTap: isSelectedLive
              ? null
              : () {
                  final idx = _feedRequests
                      .indexWhere((x) => x['id'].toString() == id);
                  if (idx >= 0) _onSelectRequest(idx, animatePage: true);
                },
          // Let map taps pass through on the active ride pin.
          consumeTapEvents: !isSelectedLive,
        ),
      );
    }

    if (selected != null) {
      final pickup = _pickupOf(selected);
      final dropoff = _dropoffOf(selected);
      if (dropoff != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('selected_drop'),
            position: dropoff,
            icon: _dropIcon ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: 'Destination',
              snippet: _addressOf(selected['dropoff'], 'Drop-off'),
            ),
            zIndexInt: 9,
            // Destination pin must not re-trigger heavy map rebuilds.
            consumeTapEvents: false,
          ),
        );
      }
      if (pickup != null && dropoff != null) {
        final road = _routeCache[selectedId];
        if (road != null && road.isNotEmpty) {
          polylines.add(
            Polyline(
              polylineId: const PolylineId('selected_route'),
              points: road,
              color: const Color(0xFF2F80FF),
              width: 5,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          );
        } else {
          polylines.add(
            Polyline(
              polylineId: const PolylineId('selected_route'),
              points: [pickup, dropoff],
              color: const Color(0xFF2F80FF).withValues(alpha: 0.55),
              width: 4,
              patterns: [PatternItem.dash(18), PatternItem.gap(12)],
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          );
          if (!light) _loadRoadRoute(selected);
        }
      }
    }

    if (!mounted || gen != _overlayGen) {
      if (gen == _overlayGen) _overlaysDirty = false;
      return;
    }
    setState(() {
      _markers = markers;
      _polylines = polylines;
    });
    _overlaysDirty = false;
  }

  /// Fetches the road polyline for a booking once and redraws when ready.
  Future<void> _loadRoadRoute(Map<String, dynamic> booking) async {
    final id = booking['id'].toString();
    if (_routeCache.containsKey(id) || _routeLoading.contains(id)) return;
    final pickup = _pickupOf(booking);
    final dropoff = _dropoffOf(booking);
    if (pickup == null || dropoff == null) return;
    _routeLoading.add(id);
    try {
      final points = await GoogleRoutes.fetchDrivingRoute(
        origin: pickup,
        destination: dropoff,
      );
      if (points.isNotEmpty) {
        _routeCache[id] = points;
        if (mounted && _selectedBooking?['id']?.toString() == id) {
          await _rebuildMapOverlays();
        }
      }
    } finally {
      _routeLoading.remove(id);
    }
  }

  Future<void> _fitMap() async {
    if (_feedRequests.isNotEmpty) {
      await _focusSelected(animate: true);
      return;
    }
    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _driverLatLng,
          zoom: 16,
          tilt: 45,
          bearing: _heading,
        ),
      ),
    );
  }

  void _syncLocationTracking() {
    _locationTimer?.cancel();
    if (!_isAvailable) return;
    _pushLocation();
    _locationTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _pushLocation();
    });
  }

  Future<void> _pushLocation() async {
    try {
      await _resolveGps();
      if (!_hasGps) return;
      await MovingMarketplaceService.updateDriverLocation(
        latitude: _driverLatLng.latitude,
        longitude: _driverLatLng.longitude,
      );
      await _rebuildMapOverlays();
    } catch (_) {}
  }

  String get _identityStatus =>
      (_profile?['identity_status'] ?? 'unverified').toString().toLowerCase();

  /// True once the server returns identity fields (SQL + API deployed).
  bool get _identityGateReady =>
      _profile != null &&
      (_profile!.containsKey('identity_status') ||
          _profile!.containsKey('can_work') ||
          _profile!.containsKey('identity_verified'));

  bool get _canWork {
    if (!_identityGateReady) return true;
    if (_profile?['can_work'] == true) return true;
    return _identityStatus == 'verified';
  }

  String get _identityMessage {
    final msg = (_profile?['identity_message'] ?? '').toString().trim();
    if (msg.isNotEmpty) return msg;
    switch (_identityStatus) {
      case 'pending':
        return 'Your licence / NRC was submitted. Please check back within 1 to 24 hours.';
      case 'rejected':
        return 'Your documents were rejected. Upload clear photos of your driver’s licence or NRC (front and back) again.';
      default:
        return 'Upload your driver’s licence or NRC (front and back) to unlock the driver dashboard, go online, and accept jobs.';
    }
  }

  Future<void> _openIdentityVerification() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const DriverIdentityVerificationScreen(),
      ),
    );
    if (!mounted) return;
    await _refreshAll();
  }

  /// Full-page lock until admin verifies the driver (dealer-style).
  Widget _buildIdentityLock(bool isDark) {
    final pending = _identityStatus == 'pending';
    final rejected = _identityStatus == 'rejected';
    final title = pending
        ? 'Waiting for approval'
        : (rejected ? 'Verification rejected' : 'Verify to use driver app');
    final icon = pending
        ? Icons.hourglass_top_rounded
        : (rejected ? Icons.cancel_rounded : Icons.badge_outlined);
    final iconColor = pending
        ? Colors.orange
        : (rejected ? Colors.red : const Color(0xFFFFC107));

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: _logout,
                    tooltip: 'Log out',
                    icon: Icon(
                      Icons.logout_rounded,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 48, color: iconColor),
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : _uberBlack,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _identityMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 28),
                if (pending) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      'Your documents are under review.\n'
                      'You cannot view or change them until admin approves or rejects.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Colors.orange.shade200
                            : Colors.orange.shade900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _refreshAll,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text(
                        'Refresh status',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _openIdentityVerification,
                      icon: Icon(
                        rejected
                            ? Icons.upload_file_rounded
                            : Icons.verified_user_outlined,
                      ),
                      label: Text(
                        rejected
                            ? 'Re-upload licence / NRC'
                            : 'Upload licence or NRC',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleAvailability(bool value) async {
    if (value && !_canWork) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Verify your ID first'),
          content: Text(
            _identityStatus == 'pending'
                ? 'Your documents are pending approval. You can go online after verification.'
                : 'Upload your driver’s licence or NRC (front and back) before going online.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Verify now'),
            ),
          ],
        ),
      );
      if (go == true && mounted) await _openIdentityVerification();
      return;
    }

    setState(() => _busy = true);
    try {
      final status = await MovingMarketplaceService.setAvailability(value);
      if (!mounted) return;
      setState(() {
        _profile = {...?_profile, 'availability_status': status};
      });
      _syncLocationTracking();
    } catch (e) {
      if (!mounted) return;
      final msg = AppError.userMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (msg.toLowerCase().contains('verif') ||
          msg.toLowerCase().contains('identity') ||
          msg.toLowerCase().contains('licence') ||
          msg.toLowerCase().contains('nrc')) {
        await _openIdentityVerification();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _slideAcceptBooking(Map<String, dynamic> booking) async {
    final status = (booking['status'] ?? 'open').toString();
    final unlocked = booking['unlocked'] == true;
    final id = int.tryParse(booking['id'].toString());
    if (id == null) return;

    // Already on a live trip — open details.
    if (status == 'accepted' ||
        status == 'in_progress' ||
        status == 'arrived') {
      await _openBooking(booking);
      return;
    }

    // Unlocked but still open — jump straight to map negotiation.
    if (unlocked && status == 'open') {
      await _focusBookingOnMap(booking);
      if (mounted) await _openNegotiateOnMap(booking);
      return;
    }

    if (!_canWork) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_identityMessage),
          action: SnackBarAction(
            label: 'Verify ID',
            onPressed: _openIdentityVerification,
          ),
        ),
      );
      await _openIdentityVerification();
      return;
    }

    if (!_isAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Turn Online first — then you can accept move requests.',
          ),
        ),
      );
      return;
    }

    if (_tokens < 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'You need at least 1 booking token to accept a request.',
          ),
          action: SnackBarAction(
            label: 'Buy tokens',
            onPressed: _buyTokens,
          ),
        ),
      );
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);
    try {
      await MovingMarketplaceService.unlockBooking(id);
      if (!mounted) return;
      await _loadBookings(silent: true);
      if (!mounted) return;
      final fresh = _feedRequests.firstWhere(
        (b) => b['id'].toString() == id.toString(),
        orElse: () => {...booking, 'unlocked': true},
      );
      await _focusBookingOnMap(fresh);
      if (!mounted) return;
      // Negotiation opens on the map with +/- (not the detail screen).
      await _openNegotiateOnMap(fresh);
    } catch (e) {
      if (!mounted) return;
      final msg = AppError.userMessage(e);
      final needIdentity = msg.toLowerCase().contains('verif') ||
          msg.toLowerCase().contains('identity') ||
          msg.toLowerCase().contains('licence') ||
          msg.toLowerCase().contains('nrc');
      final needTokens = msg.toLowerCase().contains('token');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          action: needTokens
              ? SnackBarAction(
                  label: 'Buy tokens',
                  onPressed: _buyTokens,
                )
              : (needIdentity
                  ? SnackBarAction(
                      label: 'Verify ID',
                      onPressed: _openIdentityVerification,
                    )
                  : null),
        ),
      );
      if (needIdentity) {
        await _openIdentityVerification();
      } else if (needTokens) {
        await _buyTokens();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _focusBookingOnMap(Map<String, dynamic> booking) async {
    if (!mounted) return;
    setState(() => _tab = 1);
    final idx = _feedRequests
        .indexWhere((b) => b['id'].toString() == booking['id'].toString());
    if (idx >= 0) {
      await _onSelectRequest(idx, animatePage: true);
    } else {
      await _rebuildMapOverlays();
      await _focusSelected(animate: true);
    }
  }

  /// On-map price sheet: − / + then send → serious waiting popup bar.
  /// Only while the request is still open — not after accept / in progress.
  Future<void> _openNegotiateOnMap(Map<String, dynamic> booking) async {
    final status = (booking['status'] ?? '').toString();
    if (status == 'accepted' ||
        status == 'in_progress' ||
        status == 'arrived') {
      // Fare already locked — go to navigate instead.
      if (mounted) await _navigateTo(booking);
      return;
    }

    final bookingId = int.tryParse(booking['id']?.toString() ?? '');
    if (bookingId == null || !mounted) return;

    final baseline = double.tryParse('${booking['agreed_amount']}') ??
        double.tryParse('${booking['tenant_offer']}') ??
        double.tryParse('${booking['estimated_price']}') ??
        MovingMarketplaceService.minFare;
    var price = math.max(
      MovingMarketplaceService.minFare,
      (baseline / 5).round() * 5.0,
    );
    var sending = false;

    final sent = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Set your price',
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
                      'Furniture move · min K ${MovingMarketplaceService.minFare.toStringAsFixed(0)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _priceStepBtn(
                          Icons.remove_rounded,
                          () => setSheet(() {
                            price = (price - 1).clamp(
                              MovingMarketplaceService.minFare,
                              1000000.0,
                            );
                          }),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'K ${price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Color(0xFFFFC107),
                              fontWeight: FontWeight.w900,
                              fontSize: 40,
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                        _priceStepBtn(
                          Icons.add_rounded,
                          () => setSheet(() => price += 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Client asked · K ${baseline.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: sending
                            ? null
                            : () async {
                                setSheet(() => sending = true);
                                try {
                                  await MovingMarketplaceService.submitOffer(
                                    bookingId: bookingId,
                                    amount: price,
                                  );
                                  if (sheetCtx.mounted) {
                                    Navigator.pop(sheetCtx, price);
                                  }
                                } catch (e) {
                                  if (sheetCtx.mounted) {
                                    setSheet(() => sending = false);
                                  }
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        e
                                            .toString()
                                            .replaceFirst('Exception: ', ''),
                                      ),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFC107),
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: const Color(0xFF333333),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          sending ? 'Sending…' : 'Send price to client',
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
            );
          },
        );
      },
    );

    if (sent == null || !mounted) return;
    await _waitForClientOnPrice(
      bookingId: bookingId,
      amount: sent,
    );
  }

  /// Serious top popup bar with loading while the client responds.
  Future<void> _waitForClientOnPrice({
    required int bookingId,
    required double amount,
  }) async {
    if (!mounted) return;
    _stopPriceWaitOnMap(refresh: false);
    setState(() {
      _tab = 1;
      _ridePanelMinimized = true;
      _priceSentFlash = true;
      _waitingPriceBookingId = bookingId;
      _waitingPriceAmount = amount;
      _waitingPriceEnds = DateTime.now().add(const Duration(seconds: 30));
    });
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && _waitingPriceBookingId == bookingId) {
        setState(() => _priceSentFlash = false);
      }
    });
    _beepPulse.repeat();
    _playBeep();
    _beepTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!_isWaitingPrice) return;
      _playBeep();
    });

    final accepted = await showPriceOfferCountdown(
      context: context,
      title: 'Waiting for client',
      subtitle: 'Price offer sent · respond within 30s',
      amount: amount,
      waitingOnly: true,
      duration: const Duration(seconds: 30),
      checkAccepted: () => _pollPriceOfferStatus(
        bookingId: bookingId,
        amount: amount,
      ),
    );

    _stopPriceWaitOnMap(refresh: false);
    if (!mounted) return;
    if (accepted == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Client accepted — starting navigation & voice'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      await _refreshAll();
      if (!mounted) return;
      Map<String, dynamic>? fresh;
      for (final b in _bookings) {
        if (b['id']?.toString() == '$bookingId') {
          fresh = b;
          break;
        }
      }
      fresh ??= {'id': bookingId, 'status': 'accepted', 'agreed_amount': amount};
      await _autoStartNavAfterAccept(fresh);
    } else if (accepted == false) {
      final counter = await _findPendingTenantOffer(bookingId);
      if (counter != null && mounted) {
        final agreed = await _promptTenantCounterAccept(bookingId, counter);
        if (agreed == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Price agreed — starting navigation'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          await _refreshAll();
          if (!mounted) return;
          Map<String, dynamic>? fresh;
          for (final b in _bookings) {
            if (b['id']?.toString() == '$bookingId') {
              fresh = b;
              break;
            }
          }
          fresh ??= {
            'id': bookingId,
            'status': 'accepted',
            'agreed_amount': counter['amount'],
          };
          await _autoStartNavAfterAccept(fresh);
          return;
        }
      }
      await showPriceOfferResult(
        context: context,
        kind: PriceOfferResultKind.declined,
        amount: amount,
        title: 'Client declined',
        subtitle: 'They kept the current fare. Try another price.',
        primaryLabel: 'Send again',
      );
      if (mounted) await _loadBookings(silent: true);
    } else {
      final counter = await _findPendingTenantOffer(bookingId);
      if (counter != null && mounted) {
        final agreed = await _promptTenantCounterAccept(bookingId, counter);
        if (agreed == true) {
          await _refreshAll();
          if (!mounted) return;
          Map<String, dynamic>? fresh;
          for (final b in _bookings) {
            if (b['id']?.toString() == '$bookingId') {
              fresh = b;
              break;
            }
          }
          fresh ??= {
            'id': bookingId,
            'status': 'accepted',
            'agreed_amount': counter['amount'],
          };
          await _autoStartNavAfterAccept(fresh);
          return;
        }
      }
      await showPriceOfferResult(
        context: context,
        kind: PriceOfferResultKind.noResponse,
        amount: amount,
        title: 'No response',
        subtitle: 'Client didn’t reply in time. Send another price anytime.',
        primaryLabel: 'Got it',
      );
      if (mounted) await _loadBookings(silent: true);
    }
  }

  /// `true` accepted · `false` declined · `null` still waiting.
  Future<bool?> _pollPriceOfferStatus({
    required int bookingId,
    required double amount,
  }) async {
    try {
      final offers =
          await MovingMarketplaceService.listOffers(bookingId: bookingId);
      Map<String, dynamic>? match;
      for (final o in offers.reversed) {
        final a = double.tryParse('${o['amount']}');
        if (a == null || (a - amount).abs() >= 0.5) continue;
        final role = (o['sender_role'] ?? '').toString().toLowerCase();
        final sender = o['sender_id']?.toString();
        final driver = o['driver_id']?.toString();
        final fromDriver =
            role == 'driver' || (sender != null && sender == driver);
        if (!fromDriver) continue;
        match = o;
        break;
      }
      if (match != null) {
        final st = (match['status'] ?? '').toString().toLowerCase();
        if (st == 'accepted') return true;
        if (st == 'rejected') {
          // Tenant may have countered — that rejects the driver's pending offer.
          if (_pendingTenantOfferInList(offers) != null) return null;
          return false;
        }
      }

      final b = await MovingMarketplaceService.getBooking(bookingId);
      if ((b['status'] ?? '').toString() == 'accepted') return true;
      final agreed = double.tryParse('${b['agreed_amount']}');
      if (agreed != null && (agreed - amount).abs() < 0.5) return true;
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _pendingTenantOfferInList(
    List<Map<String, dynamic>> offers,
  ) {
    for (final o in offers.reversed) {
      if ((o['status'] ?? '').toString().toLowerCase() != 'pending') continue;
      final role = (o['sender_role'] ?? '').toString();
      final sender = o['sender_id']?.toString();
      final driver = o['driver_id']?.toString();
      if (MovingRoles.isTenant(role) ||
          (sender != null && driver != null && sender != driver)) {
        return o;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _findPendingTenantOffer(int bookingId) async {
    try {
      final offers =
          await MovingMarketplaceService.listOffers(bookingId: bookingId);
      return _pendingTenantOfferInList(offers);
    } catch (_) {
      return null;
    }
  }

  Future<bool?> _promptTenantCounterAccept(
    int bookingId,
    Map<String, dynamic> offer,
  ) async {
    final offerId = int.tryParse(offer['id']?.toString() ?? '');
    final amount = double.tryParse('${offer['amount']}') ?? 0;
    if (offerId == null || amount <= 0 || !mounted) return null;

    final accepted = await showPriceOfferCountdown(
      context: context,
      title: 'Client counter-offer',
      subtitle: 'Accept their price to start the shift',
      amount: amount,
      acceptLabel: 'Accept',
      declineLabel: 'Decline',
    );
    if (accepted != true || !mounted) return accepted;

    await MovingMarketplaceService.acceptOffer(
      bookingId: bookingId,
      offerId: offerId,
    );
    return true;
  }

  Future<void> _openBooking(Map<String, dynamic> booking) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MovingBookingDetailScreen(
          bookingId: int.parse(booking['id'].toString()),
          isDriver: true,
        ),
      ),
    );
    _loadBookings(silent: true);
    try {
      final profile = await MovingMarketplaceService.getDriverMe();
      if (mounted) {
        setState(() => _applyProfile(profile));
      }
    } catch (_) {}
  }

  void _openChat(Map<String, dynamic> booking) {
    final id = int.tryParse(booking['id']?.toString() ?? '');
    if (id == null) return;
    final name = _tenantName(booking);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MovingChatScreen(
          bookingId: id,
          isDriver: true,
          peerName: name.isNotEmpty ? name : 'Client',
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    setState(() => _busy = true);
    try {
      final updated = await MovingMarketplaceService.updateDriverProfile(
        vehicleType: _vehicleTypeCtrl.text.trim(),
        vehicleCapacity: _capacityCtrl.text.trim(),
        vehiclePlate: _plateCtrl.text.trim(),
        serviceArea: _areaCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _profile = {...?_profile, ...updated});
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle details saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    await FirebaseMessagingService.unregisterCurrentDevice();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('role');
    await prefs.remove('user_id');
    if (mounted) context.go('/login');
  }

  void _openProfileSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            18 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Vehicle & service area',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _vehicleTypeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle type',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _capacityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Capacity',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _plateCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Number plate',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _areaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Service area',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14171A),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Save',
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
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locked = !_loading && _error == null && !_canWork;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF4F4F5),
      body: _loading
          ? const SkeletonDriverDashboard()
          : _error != null
              ? _buildError(isDark)
              : locked
                  ? _buildIdentityLock(isDark)
                  : _tab == 0
                      ? _buildHomeTab(isDark)
                      : _buildMapTab(isDark),
      // Hide Home/Map until the driver is verified.
      bottomNavigationBar: _loading || _error != null
          ? _buildSkeletonBottomNav(isDark)
          : locked
              ? null
              : _buildBottomNav(isDark),
    );
  }

  Widget _buildSkeletonBottomNav(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161616) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(
              2,
              (_) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SkeletonBox(
                    width: 54,
                    height: 28,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  const SizedBox(height: 6),
                  const SkeletonBox(height: 10, width: 36),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161616) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              _navItem(0, Icons.dashboard_rounded, 'Home', isDark),
              _navItem(1, Icons.map_rounded, 'Map', isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label, bool isDark) {
    final selected = _tab == index;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _tab = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? _accent.withValues(alpha: 0.22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: selected
                      ? (isDark ? _accent : _uberBlack)
                      : (isDark ? Colors.white38 : Colors.black38),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  color: selected
                      ? (isDark ? Colors.white : _uberBlack)
                      : (isDark ? Colors.white38 : Colors.black38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Home dashboard tab ────────────────────────────────────────────────────

  Widget _buildHomeTab(bool isDark) {
    final activeJob = _liveJobs.isEmpty ? null : _liveJobs.first;

    return SafeArea(
      child: RefreshIndicator(
        color: _accent,
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                InkWell(
                  onTap: _busy ? null : _uploadProfilePhoto,
                  borderRadius: BorderRadius.circular(999),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: _uberBlack,
                        backgroundImage: _profilePhotoUrl.isNotEmpty
                            ? NetworkImage(_profilePhotoUrl)
                            : null,
                        child: _profilePhotoUrl.isEmpty
                            ? Text(
                                _driverName.isNotEmpty
                                    ? _driverName[0].toUpperCase()
                                    : 'D',
                                style: const TextStyle(
                                  color: _accent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: _accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF121212)
                                  : Colors.white,
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 12,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hi, ${_driverName.split(' ').first}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 19,
                          letterSpacing: -0.4,
                          color: isDark ? Colors.white : _uberBlack,
                        ),
                      ),
                      Text(
                        _isAvailable
                            ? 'You are online'
                            : 'You are offline',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _isAvailable
                              ? _uberGreen
                              : (isDark ? Colors.white38 : Colors.black38),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isAvailable,
                  activeThumbColor: _accent,
                  onChanged: _busy ? null : _toggleAvailability,
                ),
                IconButton(
                  onPressed: _logout,
                  icon: Icon(
                    Icons.logout_rounded,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (!_canWork) ...[
              Material(
                color: _identityStatus == 'pending'
                    ? Colors.orange.withValues(alpha: isDark ? 0.18 : 0.12)
                    : _accent.withValues(alpha: isDark ? 0.18 : 0.14),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: _openIdentityVerification,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          _identityStatus == 'pending'
                              ? Icons.hourglass_top_rounded
                              : Icons.badge_outlined,
                          color: _identityStatus == 'pending'
                              ? Colors.orange
                              : _accent,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _identityStatus == 'pending'
                                    ? 'ID pending approval'
                                    : (_identityStatus == 'rejected'
                                        ? 'ID rejected — re-upload'
                                        : 'Verify licence or NRC'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? Colors.white : _uberBlack,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Required before going online or unlocking jobs',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Earnings hero card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _uberBlack,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL EARNINGS',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'K ${_earnings.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 34,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _heroStat(Icons.check_circle_rounded,
                          '$_jobsCompleted moves done'),
                      const SizedBox(width: 16),
                      _heroStat(Icons.star_rounded,
                          '${_profile?['rating'] ?? 0} (${_profile?['rating_count'] ?? 0})'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Tokens + open requests row
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    isDark: isDark,
                    icon: Icons.token_rounded,
                    iconColor: _accent,
                    title: '$_tokens',
                    subtitle: 'Tokens · tap to buy',
                    onTap: _buyTokens,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    isDark: isDark,
                    icon: Icons.inventory_2_rounded,
                    iconColor: const Color(0xFF276EF1),
                    title: '${_openRequests.length}',
                    subtitle: 'Open requests',
                    onTap: () => setState(() => _tab = 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Active trip
            if (activeJob != null) ...[
              Text(
                'Current trip',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: isDark ? Colors.white : _uberBlack,
                ),
              ),
              const SizedBox(height: 10),
              _activeTripCard(activeJob, isDark),
              const SizedBox(height: 18),
            ],

            // Go to map CTA
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => setState(() => _tab = 1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.map_rounded),
                label: const Text(
                  'Open live map',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _openProfileSheet,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: isDark ? Colors.white24 : const Color(0xFFDDDDDD),
                  ),
                  foregroundColor: isDark ? Colors.white : _uberBlack,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text(
                  'Vehicle & service area',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _openIdentityVerification,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: _canWork
                        ? Colors.green.withValues(alpha: 0.7)
                        : (isDark ? Colors.white24 : const Color(0xFFDDDDDD)),
                  ),
                  foregroundColor: _canWork
                      ? Colors.green
                      : (isDark ? Colors.white : _uberBlack),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: Icon(
                  _canWork ? Icons.verified_rounded : Icons.badge_outlined,
                ),
                label: Text(
                  _canWork
                      ? 'ID verified'
                      : (_identityStatus == 'pending'
                          ? 'ID pending review'
                          : 'Verify licence / NRC'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _buyTokens,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFFC107)),
                  foregroundColor: const Color(0xFFFFC107),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.add_card_rounded),
                label: Text(
                  _tokenPriceHint.isEmpty
                      ? 'Buy tokens'
                      : 'Buy tokens · $_tokenPriceHint',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _buyTokens() async {
    final paid = await showDriverBuyTokensSheet(context);
    if (!mounted) return;
    await _refreshAll();
    if (!mounted) return;
    if (paid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tokens updated · $_tokens left')),
      );
    }
  }

  Widget _heroStat(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: _accent, size: 16),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: isDark ? const Color(0xFF1C1C1C) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  letterSpacing: -0.5,
                  color: isDark ? Colors.white : _uberBlack,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activeTripCard(Map<String, dynamic> booking, bool isDark) {
    final status = (booking['status'] ?? '').toString();
    final canComplete = status == 'accepted' ||
        status == 'in_progress' ||
        status == 'arrived';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: _liveRidePanel(booking, forMap: false),
        ),
        if (canComplete) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : () => _completeRide(booking),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black,
                disabledBackgroundColor: const Color(0xFF333333),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.check_circle_rounded, size: 22),
              label: const Text(
                'Complete',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Yango-style sheet for accepted / in-progress jobs (client-facing info).
  Widget _liveRidePanel(Map<String, dynamic> booking, {required bool forMap}) {
    final name = _tenantName(booking);
    final phone = _phoneOf(booking);
    final pickup = _addressOf(booking['pickup'], 'Pickup on map');
    final dropoff = _addressOf(booking['dropoff'], 'Destination');
    final amount = (booking['agreed_amount'] ?? '').toString();
    final status = (booking['status'] ?? '').toString();
    final started = status == 'in_progress' || status == 'arrived';
    final canComplete = status == 'accepted' ||
        status == 'in_progress' ||
        status == 'arrived';
    final items = (booking['items'] ?? '').toString();

    return MovingRideStatusPanel(
      headline: started ? 'Ride in progress' : 'Head to the client',
      subtitle: started ? dropoff : pickup,
      personName: name,
      vehicleLabel: items.isNotEmpty && items != 'null'
          ? (items.length > 42 ? '${items.substring(0, 42)}…' : items)
          : 'Moving client',
      amountLabel:
          amount.isNotEmpty && amount != 'null' ? 'Agreed · K $amount' : null,
      contactLabel: 'Contact client',
      safetyLabel: 'Trip',
      onContact: phone.isNotEmpty ? () => _callPhone(phone) : null,
      onSafety: () => _openBooking(booking),
      onNotes: () => _openChat(booking),
      notesHint: 'HouseRent Africa ride chat…',
      onNavigate: _busy ? null : () => _navigateTo(booking),
      navigateLabel: 'Navigate to',
      onPrimary: _busy ? null : () => _startRide(booking),
      primaryLabel: started ? 'Continue' : 'Start',
      primaryIcon: Icons.play_arrow_rounded,
      onSecondary: canComplete
          ? (_busy ? null : () => _completeRide(booking))
          : null,
      secondaryLabel: canComplete ? 'Complete' : null,
      onCancel: _busy ? null : () => _cancelRide(booking),
      cancelLabel: 'Cancel',
      compact: forMap,
      minimized: forMap ? _ridePanelMinimized : false,
      onMinimize: forMap
          ? () => setState(() => _ridePanelMinimized = !_ridePanelMinimized)
          : null,
    );
  }

  // ── Live map tab ──────────────────────────────────────────────────────────

  Widget _buildMapTab(bool isDark) {
    final selected = _selectedBooking;
    final liveSelected = selected != null && _canNavigate(selected);
    final sheetH = liveSelected
        ? (_ridePanelMinimized ? 78.0 : 360.0)
        : 220.0;
    // Keep GoogleMap padding STABLE during a live ride. Changing padding on
    // every minimize/expand was refreshing/crashing the map on tap.
    final mapBottomPad = liveSelected ? 96.0 : 228.0;

    return Stack(
      children: [
        RepaintBoundary(
          child: GoogleMap(
            key: const ValueKey('driver_live_map'),
            initialCameraPosition: CameraPosition(
              target: _driverLatLng,
              zoom: 15.2,
              tilt: 0,
            ),
            style: kYangoMapStyle,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            buildingsEnabled: false,
            indoorViewEnabled: false,
            trafficEnabled: false,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: false,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
            markers: _markers,
            circles: const <Circle>{},
            polylines: _polylines,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 72,
              bottom: mapBottomPad,
            ),
            onMapCreated: (c) async {
              _mapController = c;
              await _rebuildMapOverlays();
              await _fitMap();
            },
            onTap: (_) {
              // Soft toggle of the ride sheet — no overlay rebuild.
              if (!liveSelected) return;
              setState(() => _ridePanelMinimized = !_ridePanelMinimized);
            },
            onCameraMoveStarted: () {
              if (!_follow3D) return;
              // Avoid setState during gesture when possible — just clear flag.
              _follow3D = false;
              // FAB active state updates on next natural rebuild only.
            },
          ),
        ),
        // Minimal FABs only.
        Positioned(
          right: 12,
          bottom: sheetH + 12,
          child: Column(
            children: [
              _mapFab(
                isDark: true,
                icon: Icons.my_location_rounded,
                active: _follow3D,
                tooltip: 'My location',
                onTap: () {
                  setState(() => _follow3D = true);
                  _chaseCamera();
                },
              ),
              const SizedBox(height: 10),
              _mapFab(
                isDark: true,
                icon: Icons.fit_screen_rounded,
                active: false,
                tooltip: 'Fit route',
                onTap: () {
                  _follow3D = false;
                  _fitMap();
                },
              ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _buildCompactTopBar(),
          ),
        ),
        // Big beep / SENT wait overlay on the map after sending a price.
        if (_isWaitingPrice || _priceSentFlash)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: sheetH,
            child: PriceBeepOverlay(
              pulse: _beepPulse,
              amount: _waitingPriceAmount ?? 0,
              secondsLeft: _waitingPriceEnds == null
                  ? 30
                  : _waitingPriceEnds!
                      .difference(DateTime.now())
                      .inSeconds
                      .clamp(0, 30),
              sentFlash: _priceSentFlash,
              bannerSent: 'Price sent to client',
              bannerWaiting: 'Waiting for client',
              onCancel: _isWaitingPrice
                  ? () => _finishPriceWait(accepted: false)
                  : null,
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildBottomSheet(isDark),
        ),
      ],
    );
  }

  /// Slim top bar — keeps the map readable like the Yango screenshot.
  Widget _buildCompactTopBar() {
    return Material(
      color: const Color(0xE61A1A1A),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _isAvailable ? _uberGreen : Colors.white38,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isAvailable
                    ? '${_openRequests.length} nearby request${_openRequests.length == 1 ? '' : 's'}'
                    : 'You are offline',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            Switch(
              value: _isAvailable,
              activeThumbColor: _accent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: _busy ? null : _toggleAvailability,
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapFab({
    required bool isDark,
    required IconData icon,
    required bool active,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final bg = active
        ? _accent
        : (isDark ? const Color(0xFF1E1E1E) : Colors.white);
    final fg = active
        ? Colors.black
        : (isDark ? Colors.white : Colors.black87);
    return Material(
      color: bg,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black45,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, color: fg, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.black45),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Upload the latest api/moving-laravel files, then confirm '
              'https://houseforrent.site/api/moving-laravel/public/api/health works.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refreshAll,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black87,
              ),
              child: const Text('Retry'),
            ),
            TextButton(onPressed: _logout, child: const Text('Logout')),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSheet(bool isDark) {
    final requests = _feedRequests;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final selected = _selectedBooking;
    final liveSelected = selected != null && _canNavigate(selected);

    if (liveSelected) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: 400 + bottomPad),
        child: SingleChildScrollView(
          child: _liveRidePanel(selected, forMap: true),
        ),
      );
    }

    // Compact dark sheet — one request at a time, map stays dominant.
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + (bottomPad > 0 ? 0 : 4)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              if (!_isAvailable)
                _offlineBanner(isDark)
              else if (requests.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'Waiting for a move request…',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Text(
                      'Incoming · ${requests.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    if (requests.length > 1) ...[
                      _sheetNavBtn(
                        Icons.chevron_left_rounded,
                        _selectedIndex > 0
                            ? () => _onSelectRequest(
                                  _selectedIndex - 1,
                                  animatePage: true,
                                )
                            : null,
                      ),
                      Text(
                        '${_selectedIndex + 1}/${requests.length}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      _sheetNavBtn(
                        Icons.chevron_right_rounded,
                        _selectedIndex < requests.length - 1
                            ? () => _onSelectRequest(
                                  _selectedIndex + 1,
                                  animatePage: true,
                                )
                            : null,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                _neatRequestCard(requests[_selectedIndex.clamp(0, requests.length - 1)]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetNavBtn(IconData icon, VoidCallback? onTap) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onTap,
      icon: Icon(
        icon,
        color: onTap == null ? Colors.white24 : Colors.white70,
      ),
    );
  }

  Widget _offlineBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        'Go online to receive moving requests.',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.white70,
        ),
      ),
    );
  }

  /// Neat single-request card — no elastic animation, minimal chrome.
  Widget _neatRequestCard(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? 'open').toString();
    final unlocked = booking['unlocked'] == true;
    final name = _tenantName(booking);
    final pickup = _addressOf(booking['pickup'], 'Pickup');
    final dropoff = _addressOf(booking['dropoff'], 'Drop-off');
    final price = _offerPriceLabel(booking);
    final km = booking['distance_km'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF2A2A2A),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'C',
                style: const TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
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
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    [
                      if (price != null) price,
                      if (km != null) '$km km',
                    ].join(' · '),
                    style: const TextStyle(
                      color: Color(0xFFFFC107),
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _slimAddr(Icons.radio_button_checked, pickup, const Color(0xFF2F80FF)),
        const SizedBox(height: 6),
        _slimAddr(Icons.flag_rounded, dropoff, Colors.white54),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _busy ? null : () => _slideAcceptBooking(booking),
            style: ElevatedButton.styleFrom(
              backgroundColor: status == 'accepted' ||
                      status == 'in_progress' ||
                      status == 'arrived'
                  ? const Color(0xFF2F80FF)
                  : _uberGreen,
              foregroundColor: status == 'accepted' ||
                      status == 'in_progress' ||
                      status == 'arrived'
                  ? Colors.white
                  : Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              status == 'accepted' ||
                      status == 'in_progress' ||
                      status == 'arrived'
                  ? 'Open trip'
                  : unlocked
                      ? 'Set price'
                      : 'Accept request',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }

  Widget _slimAddr(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
