import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';

class NearMeMapScreen extends StatefulWidget {
  const NearMeMapScreen({super.key});

  @override
  State<NearMeMapScreen> createState() => _NearMeMapScreenState();
}

class _NearMeMapScreenState extends State<NearMeMapScreen>
    with WidgetsBindingObserver {
  static const LatLng _fallbackCenter = LatLng(-15.4167, 28.2833);
  static const String _darkMapStyle = r'''[
    {"elementType":"geometry","stylers":[{"color":"#15191f"}]},
    {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
    {"elementType":"labels.text.fill","stylers":[{"color":"#9ca7b5"}]},
    {"elementType":"labels.text.stroke","stylers":[{"color":"#15191f"}]},
    {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#37404b"}]},
    {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#1b2027"}]},
    {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#182720"}]},
    {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#668174"}]},
    {"featureType":"road","elementType":"geometry","stylers":[{"color":"#292f38"}]},
    {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#11151a"}]},
    {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#b6bec8"}]},
    {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#4b4230"}]},
    {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#2c281f"}]},
    {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#f2cc73"}]},
    {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#20262e"}]},
    {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0b2938"}]},
    {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#638594"}]}
  ]''';

  GoogleMapController? _mapController;
  LatLng _mapCenter = _fallbackCenter;
  bool _usingDeviceLocation = false;
  bool _resolvingLocation = false;
  bool _retryLocationOnResume = false;
  bool _isLoading = true;
  String? _error;

  List<Map<String, dynamic>> _propertiesWithCoords = [];
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  Set<Polyline> _polylines = {};

  Map<String, dynamic>? _routeProperty;
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;
  bool _isFetchingRoute = false;
  String _routeMode = 'driving';
  List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _navPositionSub;
  bool _isNavigating = false;
  DateTime _lastRerouteAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool _radiusEnabled = false;
  double _radiusKm = 10.0;

  final Map<String, BitmapDescriptor> _markerIconCache = {};
  final Map<String, Future<BitmapDescriptor>> _markerIconInFlight = {};

  bool get _canShowInteractiveMap =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navPositionSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _retryLocationOnResume) {
      _retryLocationOnResume = false;
      unawaited(_refreshLocationAfterSettings());
    }
  }

  Future<void> _refreshLocationAfterSettings() async {
    final gotLocation = await _resolveDeviceLocation(requestIfNeeded: false);
    if (!gotLocation || !mounted) return;
    await _rebuildMarkers(useDefaultIcons: true);
    await _moveCameraToUser();
  }

  LatLng? _propertyLatLng(Map<String, dynamic> property) {
    final lat = double.tryParse(property['latitude']?.toString() ?? '');
    final lng = double.tryParse(property['longitude']?.toString() ?? '');
    if (lat == null || lng == null) return null;
    if (lat.isNaN || lng.isNaN) return null;
    if (lat == 0 && lng == 0) return null;
    return LatLng(lat, lng);
  }

  String? _propertyImageUrl(Map<String, dynamic> property) {
    String? imageUrl;
    final mainImage = property['main_image']?.toString().trim();
    if (mainImage != null && mainImage.isNotEmpty) {
      imageUrl = mainImage.replaceAll('`', '').trim();
    } else if (property['images'] != null && property['images'].isNotEmpty) {
      final firstImage = property['images'][0];
      if (firstImage is Map && firstImage['url'] != null) {
        imageUrl = firstImage['url'].toString().replaceAll('`', '').trim();
      } else if (firstImage is String) {
        imageUrl = firstImage.replaceAll('`', '').trim();
      }
    }

    if (imageUrl == null || imageUrl.isEmpty) return null;
    if (imageUrl.startsWith('http')) return imageUrl;

    var imagePath = imageUrl;
    if (imagePath.startsWith('/')) imagePath = imagePath.substring(1);
    if (imagePath.startsWith('assets/')) {
      return 'https://houseforrent.site/$imagePath';
    }
    if (imagePath.startsWith('uploads/')) {
      return 'https://houseforrent.site/php_backend/api/$imagePath';
    }
    return 'https://houseforrent.site/assets/$imagePath';
  }

  bool _isRentableListing(Map<String, dynamic> property) {
    final status = (property['status'] ?? '').toString().toLowerCase();
    if (['taken', 'rented', 'sold'].contains(status)) return false;

    final type = (property['property_type'] ?? property['type'] ?? '')
        .toString()
        .toLowerCase();
    const zedBineTypes = ['salon', 'gadget', 'mechanic', 'other_service'];
    if (zedBineTypes.contains(type)) return false;

    return true;
  }

  Future<bool> _resolveDeviceLocation({bool requestIfNeeded = false}) async {
    if (_resolvingLocation) return false;
    _resolvingLocation = true;
    try {
      return await _resolveDeviceLocationInternal(
        requestIfNeeded: requestIfNeeded,
      );
    } catch (_) {
      return false;
    } finally {
      _resolvingLocation = false;
    }
  }

  Future<bool> _resolveDeviceLocationInternal({
    required bool requestIfNeeded,
  }) async {
    if (!_canShowInteractiveMap) return false;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (requestIfNeeded && mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final turnOn = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Turn on location',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            content: Text(
              'Enable GPS on your device so we can show homes near you.',
              style: TextStyle(
                height: 1.4,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107),
                  foregroundColor: Colors.black87,
                  elevation: 0,
                ),
                child: const Text(
                  'Open settings',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
        if (turnOn == true) {
          _retryLocationOnResume = true;
          await Geolocator.openLocationSettings();
        }
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestIfNeeded) {
      if (!mounted) return false;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final allow = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Allow location access',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            'We use your location to show nearby homes and help you navigate to listings.',
            style: TextStyle(
              height: 1.4,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black87,
                elevation: 0,
              ),
              child: const Text(
                'Allow',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
      if (allow == true) {
        permission = await Geolocator.requestPermission();
      } else {
        return false;
      }
    }

    if (permission == LocationPermission.denied) {
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      if (requestIfNeeded && mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final openSettings = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Location blocked',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            content: Text(
              'Enable location for HouseRent in your phone Settings.',
              style: TextStyle(
                height: 1.4,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107),
                  foregroundColor: Colors.black87,
                  elevation: 0,
                ),
                child: const Text(
                  'Open Settings',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
        if (openSettings == true) {
          _retryLocationOnResume = true;
          await Geolocator.openAppSettings();
        }
      }
      return false;
    }

    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return false;
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      // A fresh GPS fix can time out indoors. A cached device position is still
      // much more useful than silently falling back to the default map center.
      position = await Geolocator.getLastKnownPosition();
    }

    if (position == null || !mounted) return false;
    final resolvedPosition = position;
    setState(() {
      _mapCenter = LatLng(
        resolvedPosition.latitude,
        resolvedPosition.longitude,
      );
      _usingDeviceLocation = true;
    });
    return true;
  }

  Future<void> _init() async {
    _navPositionSub?.cancel();
    _navPositionSub = null;
    setState(() {
      _isLoading = true;
      _error = null;
      _polylines = {};
      _routeProperty = null;
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _isFetchingRoute = false;
      _routePoints = [];
      _isNavigating = false;
    });

    try {
      final raw = await ApiService.fetchProperties();
      final list = <Map<String, dynamic>>[];
      for (final p in raw) {
        if (p is! Map) continue;
        final map = Map<String, dynamic>.from(p);
        if (!_isRentableListing(map)) continue;
        if (_propertyLatLng(map) == null) continue;
        list.add(map);
      }

      LatLng center = _fallbackCenter;
      var usingDeviceLocation = false;

      final gotLocation = await _resolveDeviceLocation(requestIfNeeded: true);
      if (gotLocation) {
        center = _mapCenter;
        usingDeviceLocation = true;
      }

      if (!mounted) return;
      setState(() {
        _mapCenter = center;
        _usingDeviceLocation = usingDeviceLocation;
        _propertiesWithCoords = list;
        _isLoading = false;
      });

      await _rebuildMarkers(useDefaultIcons: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load Near Me map. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    await _fitMapToContent();
  }

  Future<void> _moveCameraToUser() async {
    if (!_usingDeviceLocation) {
      final gotLocation = await _resolveDeviceLocation(requestIfNeeded: true);
      if (gotLocation) {
        await _rebuildMarkers(useDefaultIcons: true);
      }
    }

    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _mapCenter, zoom: 13.5),
      ),
    );
  }

  Future<void> _fitMapToContent() async {
    final controller = _mapController;
    if (controller == null) return;

    final points = <LatLng>[_mapCenter];
    for (final marker in _markers) {
      if (marker.markerId.value == 'me') continue;
      points.add(marker.position);
    }

    if (points.length == 1) {
      await _moveCameraToUser();
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    try {
      await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
    } catch (_) {
      await _moveCameraToUser();
    }
  }

  double _distanceMeters(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }

  Future<BitmapDescriptor> _markerIconFromImageUrl(String url) {
    final cached = _markerIconCache[url];
    if (cached != null) return Future.value(cached);
    final inflight = _markerIconInFlight[url];
    if (inflight != null) return inflight;

    final future = _buildMarkerIcon(url);
    _markerIconInFlight[url] = future;
    return future;
  }

  Future<BitmapDescriptor> _buildMarkerIcon(String url) async {
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        return BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueYellow,
        );
      }

      final bytes = resp.bodyBytes;
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 110,
        targetHeight: 110,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;

      const size = 130.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final center = const Offset(size / 2, size / 2);
      const outerRadius = size / 2;
      const innerRadius = 48.0;

      final shadowPaint = Paint()
        ..color = const Color(0xFF000000).withValues(alpha: 0.18)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8);
      canvas.drawCircle(center.translate(0, 3), outerRadius - 10, shadowPaint);

      final outerPaint = Paint()..color = const Color(0xFFFFC107);
      canvas.drawCircle(center, outerRadius - 12, outerPaint);

      final clipPath = Path()
        ..addOval(Rect.fromCircle(center: center, radius: innerRadius));
      canvas.save();
      canvas.clipPath(clipPath);
      final src = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst = Rect.fromCircle(center: center, radius: innerRadius);
      canvas.drawImageRect(image, src, dst, Paint());
      canvas.restore();

      final ringPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      canvas.drawCircle(center, innerRadius, ringPaint);

      final picture = recorder.endRecording();
      final markerImage = await picture.toImage(size.toInt(), size.toInt());
      final data = await markerImage.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        return BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueYellow,
        );
      }

      final out = data.buffer.asUint8List();
      final desc = BitmapDescriptor.bytes(out);
      _markerIconCache[url] = desc;
      _markerIconInFlight.remove(url);
      return desc;
    } catch (_) {
      _markerIconInFlight.remove(url);
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    }
  }

  Future<BitmapDescriptor> _iconForProperty(
    Map<String, dynamic> property, {
    required bool useDefaultIcons,
  }) async {
    if (useDefaultIcons) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    }
    final url = _propertyImageUrl(property);
    if (url == null || url.isEmpty) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    }
    return _markerIconFromImageUrl(url);
  }

  Future<void> _rebuildMarkers({bool useDefaultIcons = false}) async {
    final radiusMeters = _radiusKm * 1000.0;
    final filtered = _propertiesWithCoords.where((p) {
      if (!_radiusEnabled) return true;
      final latLng = _propertyLatLng(p);
      if (latLng == null) return false;
      return _distanceMeters(_mapCenter, latLng) <= radiusMeters;
    }).toList();

    final markers = <Marker>{};
    if (_usingDeviceLocation) {
      markers.add(
        Marker(
          markerId: const MarkerId('me'),
          position: _mapCenter,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'You are here'),
        ),
      );
    }

    for (final p in filtered) {
      final latLng = _propertyLatLng(p);
      if (latLng == null) continue;
      final id = (p['id'] ?? p['property_id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      final icon = await _iconForProperty(p, useDefaultIcons: useDefaultIcons);
      markers.add(
        Marker(
          markerId: MarkerId('p_$id'),
          position: latLng,
          icon: icon,
          onTap: () => _openPropertySheet(p),
        ),
      );
    }

    final circles = <Circle>{};
    if (_radiusEnabled && _usingDeviceLocation) {
      circles.add(
        Circle(
          circleId: const CircleId('radius'),
          center: _mapCenter,
          radius: radiusMeters,
          fillColor: const Color(0xFFFFC107).withValues(alpha: 0.12),
          strokeColor: const Color(0xFFFFC107).withValues(alpha: 0.65),
          strokeWidth: 2,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _markers = markers;
      _circles = circles;
    });

    if (_mapController != null) {
      await _fitMapToContent();
    }

    if (!useDefaultIcons) return;
    unawaited(_upgradeMarkerIcons(filtered));
  }

  Future<void> _upgradeMarkerIcons(
    List<Map<String, dynamic>> properties,
  ) async {
    for (final p in properties) {
      if (!mounted) return;
      final latLng = _propertyLatLng(p);
      if (latLng == null) continue;
      final id = (p['id'] ?? p['property_id'] ?? '').toString().trim();
      if (id.isEmpty) continue;

      final icon = await _iconForProperty(p, useDefaultIcons: false);
      if (!mounted) return;

      setState(() {
        _markers = {
          ..._markers.where((m) => m.markerId.value != 'p_$id'),
          Marker(
            markerId: MarkerId('p_$id'),
            position: latLng,
            icon: icon,
            onTap: () => _openPropertySheet(p),
          ),
        };
      });
    }
  }

  Future<void> _openPropertySheet(Map<String, dynamic> property) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = _propertyImageUrl(property);
    final id = (property['id'] ?? property['property_id'] ?? '')
        .toString()
        .trim();
    final title = (property['title'] ?? 'Property').toString();
    final location = (property['city'] != null && property['country'] != null)
        ? '${property['city']}, ${property['country']}'
        : (property['location'] ?? '').toString();
    final currency = (property['currency'] ?? 'ZMW').toString();
    final price = (property['price'] ?? '').toString();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: url == null
                        ? Container(
                            color: isDark
                                ? const Color(0xFF2C2C2C)
                                : Colors.grey.shade200,
                            child: Icon(
                              Icons.home,
                              color: isDark ? Colors.white54 : Colors.black45,
                              size: 40,
                            ),
                          )
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => Container(
                              color: isDark
                                  ? const Color(0xFF2C2C2C)
                                  : Colors.grey.shade200,
                              child: Icon(
                                Icons.broken_image,
                                color: isDark ? Colors.white54 : Colors.black45,
                                size: 40,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  location.isEmpty
                      ? '$currency $price'
                      : '$location • $currency $price',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: id.isEmpty
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                this.context.push('/property/$id');
                              },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: isDark
                                ? Colors.white24
                                : Colors.grey.shade300,
                          ),
                          foregroundColor: isDark
                              ? Colors.white
                              : Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.info_outline, size: 18),
                        label: const Text(
                          'Details',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _showRouteOnMap(property);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFC107),
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.directions, size: 18),
                        label: const Text(
                          'Route',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showRouteOnMap(Map<String, dynamic> property) async {
    final dest = _propertyLatLng(property);
    if (dest == null) return;

    if (!_usingDeviceLocation) {
      final gotLocation = await _resolveDeviceLocation(requestIfNeeded: true);
      if (!gotLocation) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Turn on location so we can show the route from where you are.',
              ),
            ),
          );
        }
        return;
      }
      await _rebuildMarkers(useDefaultIcons: true);
    }

    await _navPositionSub?.cancel();
    _navPositionSub = null;

    if (!mounted) return;
    setState(() {
      _isNavigating = false;
      _isFetchingRoute = true;
      _routeProperty = property;
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _polylines = {};
      _routePoints = [];
    });

    final origin = _mapCenter;
    var points = <LatLng>[origin, dest];
    var distance = _distanceMeters(origin, dest);
    double? duration;

    final fetched = await _fetchDrivingRoute(origin, dest);
    if (fetched != null) {
      points = fetched.points;
      distance = fetched.distance;
      duration = fetched.duration;
    }

    if (!mounted) return;
    setState(() {
      _isFetchingRoute = false;
      _routeDistanceMeters = distance;
      _routeDurationSeconds = duration;
      _routePoints = points;
      _polylines = _routePolylinesFor(points);
    });

    await _fitCameraToPoints(points);
  }

  Future<({List<LatLng> points, double distance, double? duration})?>
  _fetchDrivingRoute(LatLng origin, LatLng dest) async {
    try {
      final url =
          'https://router.project-osrm.org/route/v1/driving/'
          '${origin.longitude},${origin.latitude};${dest.longitude},${dest.latitude}'
          '?overview=full&geometries=geojson';
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;

      final data = json.decode(resp.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final coords = geometry?['coordinates'] as List?;
      if (coords == null) return null;

      final parsed = <LatLng>[];
      for (final c in coords) {
        if (c is List && c.length >= 2) {
          parsed.add(
            LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          );
        }
      }
      if (parsed.length < 2) return null;

      return (
        points: parsed,
        distance:
            (route['distance'] as num?)?.toDouble() ??
            _distanceMeters(origin, dest),
        duration: (route['duration'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  Set<Polyline> _routePolylinesFor(List<LatLng> points) {
    // Uber-style route: solid dark line with a light casing (inverted in dark mode).
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = isDark ? Colors.white : const Color(0xFF14171A);
    final casingColor = isDark ? const Color(0xFF14171A) : Colors.white;
    return {
      Polyline(
        polylineId: const PolylineId('route_outline'),
        points: points,
        color: casingColor,
        width: 9,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
      Polyline(
        polylineId: const PolylineId('route'),
        points: points,
        color: lineColor,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
      ),
    };
  }

  double _bearingBetween(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  Future<void> _startInAppNavigation() async {
    if (_routeProperty == null || _routePoints.length < 2) return;

    setState(() => _isNavigating = true);

    await _navPositionSub?.cancel();
    _navPositionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 5,
          ),
        ).listen((position) {
          unawaited(_onNavigationPosition(position));
        });

    final controller = _mapController;
    if (controller != null) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _routePoints.first,
            zoom: 17,
            tilt: 45,
            bearing: _bearingBetween(_routePoints.first, _routePoints[1]),
          ),
        ),
      );
    }
  }

  Future<void> _onNavigationPosition(Position position) async {
    if (!mounted || !_isNavigating) return;

    final current = LatLng(position.latitude, position.longitude);
    final property = _routeProperty;
    final dest = property == null ? null : _propertyLatLng(property);
    if (dest == null) return;

    _mapCenter = current;

    // Arrived when within ~30 meters of the property.
    if (_distanceMeters(current, dest) <= 30) {
      await _navPositionSub?.cancel();
      _navPositionSub = null;
      if (!mounted) return;
      setState(() {
        _isNavigating = false;
        _routeDistanceMeters = 0;
        _routeDurationSeconds = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have arrived at the property.')),
      );
      return;
    }

    var routePoints = _routePoints;

    // Find the closest point of the route to where we are now.
    var nearestIndex = 0;
    var nearestDist = double.infinity;
    for (var i = 0; i < routePoints.length; i++) {
      final d = _distanceMeters(current, routePoints[i]);
      if (d < nearestDist) {
        nearestDist = d;
        nearestIndex = i;
      }
    }

    // Drifted off the route: fetch a fresh one (throttled to every 20s).
    if (nearestDist > 60 &&
        DateTime.now().difference(_lastRerouteAt) >
            const Duration(seconds: 20)) {
      _lastRerouteAt = DateTime.now();
      final fetched = await _fetchDrivingRoute(current, dest);
      if (!mounted || !_isNavigating) return;
      if (fetched != null) {
        routePoints = fetched.points;
        nearestIndex = 0;
      }
    }

    // Keep only the part of the route that is still ahead of us.
    final ahead = <LatLng>[
      current,
      ...routePoints.sublist(
        math.min(nearestIndex + 1, routePoints.length - 1),
      ),
    ];
    var remainingDistance = 0.0;
    for (var i = 0; i < ahead.length - 1; i++) {
      remainingDistance += _distanceMeters(ahead[i], ahead[i + 1]);
    }

    if (!mounted || !_isNavigating) return;
    setState(() {
      _routePoints = ahead;
      _routeDistanceMeters = remainingDistance;
      // ETA is recomputed from the remaining distance while navigating.
      _routeDurationSeconds = null;
      _polylines = _routePolylinesFor(ahead);
      _markers = {
        ..._markers.where((m) => m.markerId.value != 'me'),
        Marker(
          markerId: const MarkerId('me'),
          position: current,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'You are here'),
        ),
      };
    });

    final controller = _mapController;
    if (controller != null) {
      final next = ahead.length > 1 ? ahead[1] : dest;
      final heading = position.heading;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: current,
            zoom: 17,
            tilt: 45,
            bearing: heading.isFinite && heading > 0
                ? heading
                : _bearingBetween(current, next),
          ),
        ),
      );
    }
  }

  Future<void> _stopInAppNavigation() async {
    await _navPositionSub?.cancel();
    _navPositionSub = null;
    if (!mounted) return;
    setState(() => _isNavigating = false);
    await _fitCameraToPoints(_routePoints);
  }

  Future<void> _recenterNavigationCamera() async {
    final controller = _mapController;
    if (controller == null || _routePoints.isEmpty) return;
    final current = _routePoints.first;
    final next = _routePoints.length > 1 ? _routePoints[1] : current;
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: current,
          zoom: 17,
          tilt: 45,
          bearing: _bearingBetween(current, next),
        ),
      ),
    );
  }

  Widget _buildNavigationBanner(bool isDark) {
    final property = _routeProperty;
    if (property == null) return const SizedBox.shrink();
    final title = (property['title'] ?? 'Property').toString();
    final distance = _routeDistanceMeters;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF14171A),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.navigation, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  distance == null ? 'On route' : _formatDistance(distance),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'to $title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            _routeMode == 'walking'
                ? Icons.directions_walk
                : Icons.directions_car_filled,
            color: Colors.white.withValues(alpha: 0.7),
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBottomBar(bool isDark) {
    final eta = _routeEtaSeconds;
    final distance = _routeDistanceMeters;
    final property = _routeProperty;
    final title = (property?['title'] ?? 'Property').toString();

    var etaBig = '--';
    var etaSmall = 'min';
    var arrivalLabel = 'On the way';
    var remainingLabel = '';
    if (eta != null) {
      final mins = (eta / 60).ceil();
      if (mins < 100) {
        etaBig = '$mins';
        etaSmall = 'min';
      } else {
        etaBig = '${(mins / 60).ceil()}';
        etaSmall = 'hr';
      }
      final arrival = DateTime.now().add(Duration(seconds: eta.round()));
      final hh = arrival.hour.toString().padLeft(2, '0');
      final mm = arrival.minute.toString().padLeft(2, '0');
      arrivalLabel = 'Arriving by $hh:$mm';
    }
    if (distance != null) {
      remainingLabel = '${_formatDistance(distance)} remaining';
    }

    final subtleText = isDark ? Colors.white54 : Colors.black45;
    final strongText = isDark ? Colors.white : const Color(0xFF14171A);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
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
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF14171A),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      etaBig,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                    Text(
                      etaSmall,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      arrivalLabel,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: strongText,
                      ),
                    ),
                    if (remainingLabel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        remainingLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: subtleText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Material(
                color: isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade100,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: _recenterNavigationCamera,
                  tooltip: 'Re-center',
                  icon: Icon(Icons.my_location, size: 20, color: strongText),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(
            height: 1,
            color: isDark ? Colors.white12 : Colors.grey.shade200,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.circle, size: 10, color: Color(0xFF276EF1)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Your location',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: subtleText,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 2,
                height: 12,
                color: isDark ? Colors.white24 : Colors.grey.shade300,
              ),
            ),
          ),
          Row(
            children: [
              Container(width: 10, height: 10, color: strongText),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: strongText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _stopInAppNavigation,
              style: TextButton.styleFrom(
                backgroundColor: Colors.red.withValues(alpha: 0.1),
                foregroundColor: Colors.red.shade600,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'End navigation',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fitCameraToPoints(List<LatLng> points) async {
    final controller = _mapController;
    if (controller == null || points.isEmpty) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          90,
        ),
      );
    } catch (_) {}
  }

  void _clearRoute() {
    _navPositionSub?.cancel();
    _navPositionSub = null;
    setState(() {
      _polylines = {};
      _routeProperty = null;
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _isFetchingRoute = false;
      _routePoints = [];
      _isNavigating = false;
    });
    unawaited(_fitMapToContent());
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).ceil();
    if (mins < 60) return '$mins min';
    return '${mins ~/ 60} hr ${mins % 60} min';
  }

  double? get _routeEtaSeconds {
    final distance = _routeDistanceMeters;
    if (distance == null) return null;
    if (_routeMode == 'walking') {
      // Average walking speed of ~5 km/h.
      return distance / 1.35;
    }
    // Prefer the routing service's driving estimate; fall back to ~40 km/h.
    return _routeDurationSeconds ?? distance / 11.1;
  }

  Future<void> _launchExternalNavigation() async {
    final property = _routeProperty;
    if (property == null) return;
    final dest = _propertyLatLng(property);
    if (dest == null) return;

    final origin = '${_mapCenter.latitude},${_mapCenter.longitude}';
    final destination = '${dest.latitude},${dest.longitude}';
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&travelmode=$_routeMode',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the route in Maps.')),
      );
    }
  }

  Widget _buildRouteModeChip({
    required IconData icon,
    required String label,
    required String mode,
    required bool isDark,
  }) {
    final selected = _routeMode == mode;
    return InkWell(
      onTap: () => setState(() => _routeMode = mode),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFFC107)
              : (isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xFFFFC107)
                : (isDark ? Colors.white12 : Colors.grey.shade300),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected
                  ? Colors.black87
                  : (isDark ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected
                    ? Colors.black87
                    : (isDark ? Colors.white70 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteCard(bool isDark) {
    final property = _routeProperty;
    if (property == null) return const SizedBox.shrink();

    final title = (property['title'] ?? 'Property').toString();
    final distance = _routeDistanceMeters;
    final eta = _routeEtaSeconds;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.route,
                  color: Color(0xFFFFC107),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _isFetchingRoute
                          ? 'Finding the best route…'
                          : [
                              if (distance != null) _formatDistance(distance),
                              if (eta != null) _formatDuration(eta),
                            ].join(' • '),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _clearRoute,
                tooltip: 'Clear route',
                icon: Icon(
                  Icons.close,
                  size: 20,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),
          if (_isFetchingRoute) ...[
            const SizedBox(height: 10),
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(999)),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: Color(0xFFFFC107),
                backgroundColor: Colors.transparent,
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _buildRouteModeChip(
                  icon: Icons.directions_car_filled,
                  label: 'Drive',
                  mode: 'driving',
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildRouteModeChip(
                  icon: Icons.directions_walk,
                  label: 'Walk',
                  mode: 'walking',
                  isDark: isDark,
                ),
                const Spacer(),
                IconButton(
                  onPressed: _launchExternalNavigation,
                  tooltip: 'Open in Google Maps',
                  icon: Icon(
                    Icons.map_outlined,
                    size: 20,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _startInAppNavigation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.navigation, size: 16),
                  label: const Text(
                    'Start',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  int get _homeMarkerCount {
    final meMarker = _usingDeviceLocation ? 1 : 0;
    return math.max(0, _markers.length - meMarker);
  }

  Widget _buildUnsupportedMapMessage(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.map_outlined,
              size: 56,
              color: isDark ? Colors.white38 : Colors.black45,
            ),
            const SizedBox(height: 12),
            Text(
              'Near Me map works on Android and iPhone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_propertiesWithCoords.length} homes have map coordinates. Open the app on your phone to explore them.',
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/search-results?view=map'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Browse listings',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyListingsMessage(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.home_work_outlined,
              size: 56,
              color: isDark ? Colors.white38 : Colors.black45,
            ),
            const SizedBox(height: 12),
            Text(
              'No homes with map locations yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/search-results'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Browse all listings',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: const Text('Near Me'),
        backgroundColor: isDark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFFFC107),
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _isLoading || !_canShowInteractiveMap
                ? null
                : _moveCameraToUser,
            icon: const Icon(Icons.my_location),
            tooltip: 'My location',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC107)),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_off,
                      size: 56,
                      color: isDark ? Colors.white38 : Colors.black45,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _init,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC107),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Try again',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : !_canShowInteractiveMap
          ? _buildUnsupportedMapMessage(isDark)
          : _propertiesWithCoords.isEmpty
          ? _buildEmptyListingsMessage(isDark)
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _mapCenter,
                    zoom: 12.5,
                  ),
                  style: _darkMapStyle,
                  trafficEnabled: true,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  markers: _markers,
                  circles: _circles,
                  polylines: _polylines,
                  onMapCreated: _onMapCreated,
                ),
                if (_routeProperty != null && !_isNavigating)
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: _buildRouteCard(isDark),
                  ),
                if (_isNavigating) ...[
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: _buildNavigationBanner(isDark),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: _buildNavigationBottomBar(isDark),
                  ),
                ],
                if (!_usingDeviceLocation && _routeProperty == null)
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: Material(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      elevation: 2,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: () async {
                          final gotLocation = await _resolveDeviceLocation(
                            requestIfNeeded: true,
                          );
                          if (gotLocation) {
                            await _rebuildMarkers(useDefaultIcons: true);
                            await _moveCameraToUser();
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white12
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_searching,
                                color: Color(0xFFFFC107),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Turn on location to find homes near you',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                              ),
                              Text(
                                'Enable',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                  color: isDark
                                      ? const Color(0xFFFFC107)
                                      : const Color(0xFF5A3D31),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_routeProperty == null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white12 : Colors.grey.shade200,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _radiusEnabled
                                    ? 'Radius: ${_radiusKm.toStringAsFixed(_radiusKm < 10 ? 1 : 0)} km'
                                    : 'Showing all mapped homes',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                            Switch(
                              value: _radiusEnabled,
                              activeThumbColor: const Color(0xFFFFC107),
                              onChanged: _usingDeviceLocation
                                  ? (v) async {
                                      setState(() => _radiusEnabled = v);
                                      await _rebuildMarkers(
                                        useDefaultIcons: true,
                                      );
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        if (_radiusEnabled && _usingDeviceLocation) ...[
                          Slider(
                            value: _radiusKm,
                            min: 1,
                            max: 50,
                            divisions: 49,
                            activeColor: const Color(0xFFFFC107),
                            label: '${_radiusKm.toStringAsFixed(0)} km',
                            onChanged: (v) {
                              setState(() => _radiusKm = v);
                            },
                            onChangeEnd: (_) async {
                              await _rebuildMarkers(useDefaultIcons: true);
                            },
                          ),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$_homeMarkerCount homes shown',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                setState(() => _isLoading = true);
                                await _init();
                              },
                              child: Text(
                                'Refresh',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF5A3D31),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
