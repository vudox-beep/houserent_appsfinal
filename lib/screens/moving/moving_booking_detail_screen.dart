import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/moving_marketplace_service.dart';
import '../../utils/moving_roles.dart';
import '../../theme/yango_map_style.dart';
import '../../widgets/driver_identity_photos.dart';
import '../../widgets/driver_rating_sheet.dart';
import '../../widgets/skeleton_loader.dart';
import '../driver/driver_buy_tokens_sheet.dart';
import '../driver/driver_nav_screen.dart';
import '../../utils/app_error.dart';

class MovingBookingDetailScreen extends StatefulWidget {
  const MovingBookingDetailScreen({
    super.key,
    required this.bookingId,
    required this.isDriver,
    this.initialDriverId,
  });

  final int bookingId;
  final bool isDriver;
  final int? initialDriverId;

  @override
  State<MovingBookingDetailScreen> createState() =>
      _MovingBookingDetailScreenState();
}

class _MovingBookingDetailScreenState extends State<MovingBookingDetailScreen> {
  Map<String, dynamic>? _booking;
  List<Map<String, dynamic>> _offers = [];
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int? _conversationDriverId;
  final _offerCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _conversationDriverId = widget.initialDriverId;
    _refresh();
    // Live mode: keep offers and chat fresh without manual refresh.
    _liveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _refreshSilent();
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _offerCtrl.dispose();
    _noteCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  /// Background poll — never shows the loading spinner or clears state.
  Future<void> _refreshSilent() async {
    if (_loading || _busy) return;
    try {
      final booking =
          await MovingMarketplaceService.getBooking(widget.bookingId);
      int? driverId = _conversationDriverId;
      if (!widget.isDriver && booking['driver'] is Map) {
        driverId = int.tryParse(booking['driver']['id']?.toString() ?? '');
      }

      var offers = _offers;
      var messages = _messages;
      if (driverId != null || widget.isDriver) {
        try {
          offers = await MovingMarketplaceService.listOffers(
            bookingId: widget.bookingId,
            driverId: widget.isDriver ? null : driverId,
          );
          messages = await MovingMarketplaceService.listMessages(
            bookingId: widget.bookingId,
            driverId: widget.isDriver ? null : driverId,
          );
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _booking = booking;
        _offers = offers;
        _messages = messages;
        _conversationDriverId = driverId;
      });
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final booking =
          await MovingMarketplaceService.getBooking(widget.bookingId);
      int? driverId = _conversationDriverId;
      if (widget.isDriver) {
        // Conversation is always with this driver.
      } else if (booking['driver'] is Map) {
        driverId = int.tryParse(booking['driver']['id']?.toString() ?? '');
      }
      driverId ??= widget.initialDriverId;

      List<Map<String, dynamic>> offers = [];
      List<Map<String, dynamic>> messages = [];
      if (driverId != null || widget.isDriver) {
        try {
          offers = await MovingMarketplaceService.listOffers(
            bookingId: widget.bookingId,
            driverId: widget.isDriver ? null : driverId,
          );
          messages = await MovingMarketplaceService.listMessages(
            bookingId: widget.bookingId,
            driverId: widget.isDriver ? null : driverId,
          );
        } catch (_) {
          // Not unlocked yet — still show booking summary.
        }
      }

      if (!mounted) return;
      setState(() {
        _booking = booking;
        _offers = offers;
        _messages = messages;
        _conversationDriverId = driverId;
        _loading = false;
      });
      // After destination complete, open rating for the tenant once.
      if (!widget.isDriver &&
          (booking['status'] ?? '') == 'completed' &&
          booking['has_rated'] != true &&
          booking['can_rate'] != false) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final driver = booking['driver'] is Map
              ? Map<String, dynamic>.from(booking['driver'] as Map)
              : <String, dynamic>{};
          final ok = await showDriverRatingSheet(
            context: context,
            bookingId: widget.bookingId,
            driverName: (driver['name'] ?? 'your driver').toString(),
          );
          if (ok && mounted) await _refresh();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.userMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _unlock() async {
    setState(() => _busy = true);
    try {
      await MovingMarketplaceService.unlockBooking(widget.bookingId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request unlocked. You can chat and offer a price.')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      final msg = AppError.userMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      if (widget.isDriver && msg.toLowerCase().contains('token')) {
        final paid = await showDriverBuyTokensSheet(context);
        if (paid && mounted) await _refresh();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitOffer() async {
    final amount = double.tryParse(_offerCtrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid price in ZMW.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await MovingMarketplaceService.submitOffer(
        bookingId: widget.bookingId,
        amount: amount,
        note: _noteCtrl.text.trim(),
        driverId: widget.isDriver ? null : _conversationDriverId,
      );
      _offerCtrl.clear();
      _noteCtrl.clear();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptOffer(int offerId) async {
    setState(() => _busy = true);
    try {
      await MovingMarketplaceService.acceptOffer(
        bookingId: widget.bookingId,
        offerId: offerId,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await MovingMarketplaceService.sendMessage(
        bookingId: widget.bookingId,
        message: text,
        driverId: widget.isDriver ? null : _conversationDriverId,
      );
      _messageCtrl.clear();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startRide() async {
    setState(() => _busy = true);
    try {
      final updated =
          await MovingMarketplaceService.startRide(widget.bookingId);
      if (!mounted) return;
      setState(() => _booking = {...?_booking, ...updated, 'status': 'in_progress'});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride started — open navigation.')),
      );
      await _openNavigation();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openNavigation() async {
    final pickup = _latLngOf(_booking?['pickup']);
    final drop = _latLngOf(_booking?['dropoff']);
    final status = (_booking?['status'] ?? '').toString();
    // Your GPS → client destination when in progress; else → client pickup.
    final LatLng? target = status == 'in_progress'
        ? (drop ?? pickup)
        : (pickup ?? drop);
    if (target == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No map location on this trip.')),
      );
      return;
    }

    LatLng? myPos;
    if (!kIsWeb) {
      try {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) {
            myPos = LatLng(last.latitude, last.longitude);
          }
          try {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: Duration(seconds: 8),
              ),
            );
            myPos = LatLng(pos.latitude, pos.longitude);
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (!mounted) return;
    final toDropoff = status == 'in_progress' && drop != null;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverNavScreen(
          destination: target,
          destinationLabel: toDropoff
              ? _addr(_booking?['dropoff'], 'Client destination')
              : _addr(_booking?['pickup'], 'Client pickup'),
          clientName: (_booking?['tenant']?['name'] ?? 'Client').toString(),
          clientPhone: (_booking?['contact_phone'] ??
                  _booking?['tenant']?['phone'] ??
                  '')
              .toString(),
          initialPosition: myPos,
        ),
      ),
    );
  }

  Future<void> _complete() async {
    setState(() => _busy = true);
    try {
      await MovingMarketplaceService.completeBooking(widget.bookingId);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final status = (_booking?['status'] ?? 'open').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(status == 'open' ? 'Cancel request?' : 'Cancel ride?'),
        content: Text(
          status == 'open'
              ? 'This removes your open moving request.'
              : 'This ends the trip for both sides. You can’t undo this.',
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
                color: Colors.red.shade600,
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
      await MovingMarketplaceService.cancelBooking(widget.bookingId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'open' ? 'Request cancelled.' : 'Ride cancelled.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    await launchUrl(uri);
  }

  InputDecoration _fieldDecoration({
    required bool isDark,
    String? labelText,
    String? hintText,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: isDark ? Colors.white12 : Colors.black12,
      ),
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      labelStyle: TextStyle(
        color: isDark ? Colors.white54 : Colors.black54,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: isDark ? Colors.white38 : Colors.black38,
        fontWeight: FontWeight.w600,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFFC107), width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(widget.isDriver ? 'Job details' : 'Trip details'),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFF14171A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const SkeletonTripDetails()
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _refresh,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC107),
                            foregroundColor: Colors.black,
                          ),
                          child: const Text(
                            'Retry',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildBody(isDark),
    );
  }

  LatLng? _latLngOf(dynamic raw) {
    if (raw is! Map) return null;
    final lat = double.tryParse('${raw['lat'] ?? raw['latitude'] ?? ''}');
    final lng = double.tryParse('${raw['lng'] ?? raw['longitude'] ?? ''}');
    if (lat == null || lng == null) return null;
    if (lat.abs() < 0.0001 && lng.abs() < 0.0001) return null;
    return LatLng(lat, lng);
  }

  Widget _routeMapPreview({
    required LatLng? pickup,
    required LatLng? dropoff,
  }) {
    if (pickup == null && dropoff == null) return const SizedBox.shrink();
    final center = pickup ?? dropoff!;
    final markers = <Marker>{
      if (pickup != null)
        Marker(
          markerId: const MarkerId('detail_pickup'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      if (dropoff != null)
        Marker(
          markerId: const MarkerId('detail_drop'),
          position: dropoff,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
        ),
    };
    final poly = <Polyline>{
      if (pickup != null && dropoff != null)
        Polyline(
          polylineId: const PolylineId('detail_route'),
          points: [pickup, dropoff],
          color: const Color(0xFF2F80FF),
          width: 4,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 150,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: center, zoom: 13.2),
          style: kYangoMapStyle,
          markers: markers,
          polylines: poly,
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
          buildingsEnabled: false,
          indoorViewEnabled: false,
          trafficEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          scrollGesturesEnabled: false,
          zoomGesturesEnabled: false,
          liteModeEnabled: true,
          onMapCreated: (c) async {
            if (pickup == null || dropoff == null) return;
            try {
              await c.moveCamera(
                CameraUpdate.newLatLngBounds(
                  LatLngBounds(
                    southwest: LatLng(
                      pickup.latitude < dropoff.latitude
                          ? pickup.latitude
                          : dropoff.latitude,
                      pickup.longitude < dropoff.longitude
                          ? pickup.longitude
                          : dropoff.longitude,
                    ),
                    northeast: LatLng(
                      pickup.latitude > dropoff.latitude
                          ? pickup.latitude
                          : dropoff.latitude,
                      pickup.longitude > dropoff.longitude
                          ? pickup.longitude
                          : dropoff.longitude,
                    ),
                  ),
                  48,
                ),
              );
            } catch (_) {}
          },
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    final booking = _booking!;
    final status = (booking['status'] ?? '').toString();
    final unlocked = booking['unlocked'] == true;
    final pickup = booking['pickup'] is Map
        ? (booking['pickup']['address'] ?? '').toString()
        : 'Unlock to see pickup';
    final dropoff = booking['dropoff'] is Map
        ? (booking['dropoff']['address'] ?? '').toString()
        : 'Unlock to see drop-off';
    final items = (booking['items'] ?? '').toString();
    final driver = booking['driver'] is Map
        ? Map<String, dynamic>.from(booking['driver'] as Map)
        : null;
    final tenant = booking['tenant'] is Map
        ? Map<String, dynamic>.from(booking['tenant'] as Map)
        : null;

    final pickupLl = _latLngOf(booking['pickup']);
    final dropoffLl = _latLngOf(booking['dropoff']);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _card(
          isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.replaceAll('_', ' ').toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    color: Color(0xFFFFC107),
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (pickupLl != null || dropoffLl != null) ...[
                const SizedBox(height: 12),
                _routeMapPreview(pickup: pickupLl, dropoff: dropoffLl),
              ],
              const SizedBox(height: 12),
              _line(Icons.radio_button_checked, pickup),
              const SizedBox(height: 8),
              _line(Icons.location_on, dropoff),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(items, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
              ],
              const SizedBox(height: 8),
              Text(
                '${booking['moving_date'] ?? ''} ${booking['moving_time'] ?? ''}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              if (booking['agreed_amount'] != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Agreed: ZMW ${booking['agreed_amount']}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ] else if (booking['estimated_price'] != null) ...[
                const SizedBox(height: 8),
                Text(
                  'System estimate: ZMW ${booking['estimated_price']}'
                  '${booking['distance_km'] != null ? ' · ${booking['distance_km']} km' : ''}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFFC107),
                  ),
                ),
                Text(
                  'Use this as a guide — agree the final price below.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.isDriver && !unlocked && status == 'open') ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _busy ? null : _unlock,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.lock_open),
              label: const Text(
                'Unlock request (1 token)',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
        if ((status == 'open' ||
                status == 'accepted' ||
                status == 'in_progress') &&
            (!widget.isDriver ||
                (widget.isDriver &&
                    (status == 'accepted' || status == 'in_progress')))) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: _busy ? null : _cancel,
            child: Text(
              status == 'open' ? 'Cancel request' : 'Cancel ride',
              style: TextStyle(
                color: Colors.red.shade600,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
        if (driver != null) ...[
          const SizedBox(height: 12),
          _card(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFF14171A),
                      child: Icon(Icons.local_shipping, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (driver['name'] ?? 'Driver').toString(),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          Text(
                            '${driver['vehicle_type'] ?? ''} • ${driver['vehicle_plate'] ?? ''}',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          Builder(
                            builder: (_) {
                              final badge = DriverRatingBadge.fromDriver(driver);
                              if (badge == null) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: badge,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _call(driver['phone']?.toString()),
                      icon: const Icon(Icons.phone, color: Color(0xFF276EF1)),
                    ),
                  ],
                ),
                if (!widget.isDriver) ...[
                  const SizedBox(height: 12),
                  DriverIdentityPhotos(driver: driver),
                ],
              ],
            ),
          ),
        ],
        if (tenant != null && widget.isDriver && unlocked) ...[
          const SizedBox(height: 12),
          _card(
            isDark,
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFFFC107),
                  child: Icon(Icons.person, color: Colors.black87),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    (tenant['name'] ?? 'Tenant').toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _call(
                    (tenant['phone'] ?? booking['contact_phone'])?.toString(),
                  ),
                  icon: const Icon(Icons.phone, color: Color(0xFF276EF1)),
                ),
              ],
            ),
          ),
        ],
        if (unlocked || (!widget.isDriver && _conversationDriverId != null) || status == 'accepted' || status == 'in_progress') ...[
          const SizedBox(height: 16),
          Text(
            'Price negotiation',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          if (_offers.isEmpty)
            Text(
              'No offers yet.',
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
            ),
          ..._offers.map((o) {
            final pending = (o['status'] ?? '') == 'pending';
            final senderRole = (o['sender_role'] ?? '').toString();
            final canAccept = pending &&
                ((widget.isDriver && MovingRoles.isTenant(senderRole)) ||
                    (!widget.isDriver && MovingRoles.isDriver(senderRole)));
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ZMW ${o['amount']} • ${o['sender_name'] ?? senderRole}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        if ((o['note'] ?? '').toString().isNotEmpty)
                          Text(
                            o['note'].toString(),
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        Text(
                          (o['status'] ?? '').toString().toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canAccept)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _acceptOffer(int.parse(o['id'].toString())),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFFC107),
                      ),
                      child: const Text(
                        'Accept',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                ],
              ),
            );
          }),
          if (status == 'open' && (unlocked || !widget.isDriver)) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _offerCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                    cursorColor: const Color(0xFFFFC107),
                    decoration: _fieldDecoration(
                      isDark: isDark,
                      labelText: 'Offer (ZMW)',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _busy ? null : _submitOffer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDark ? const Color(0xFFFFC107) : const Color(0xFF14171A),
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(widget.isDriver ? 'Offer' : 'Counter'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: const Color(0xFFFFC107),
              decoration: _fieldDecoration(
                isDark: isDark,
                labelText: 'Note (optional)',
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Chat',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          ..._messages.map((m) {
            final role = m['sender_role']?.toString();
            final mine = widget.isDriver
                ? MovingRoles.isDriver(role)
                : MovingRoles.isTenant(role);
            return Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                decoration: BoxDecoration(
                  color: mine
                      ? (isDark
                          ? const Color(0xFFFFC107)
                          : const Color(0xFF14171A))
                      : (isDark ? const Color(0xFF2A2A2A) : Colors.white),
                  borderRadius: BorderRadius.circular(14),
                  border: mine
                      ? null
                      : Border.all(
                          color: isDark
                              ? Colors.white10
                              : Colors.black.withValues(alpha: 0.06),
                        ),
                ),
                child: Text(
                  (m['message'] ?? '').toString(),
                  style: TextStyle(
                    color: mine
                        ? (isDark ? Colors.black : Colors.white)
                        : (isDark ? Colors.white : Colors.black87),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageCtrl,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                  cursorColor: const Color(0xFFFFC107),
                  decoration: _fieldDecoration(
                    isDark: isDark,
                    hintText: 'Type a message…',
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy ? null : _sendMessage,
                icon: const Icon(Icons.send, color: Color(0xFFFFC107)),
              ),
            ],
          ),
        ],
        if (widget.isDriver &&
            (status == 'accepted' || status == 'in_progress')) ...[
          const SizedBox(height: 16),
          if (status == 'accepted')
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _startRide,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107),
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 26),
                label: const Text(
                  'Start ride',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            )
          else ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _openNavigation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF14171A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.navigation_rounded),
                label: const Text(
                  'Continue navigation',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _busy ? null : _complete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                ),
                child: const Text(
                  'Mark move complete',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ],
        if (!widget.isDriver &&
            status == 'completed' &&
            booking['has_rated'] != true) ...[
          const SizedBox(height: 16),
          _card(
            isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rate your driver',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Trip complete — share how this move went for other tenants.',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final name =
                                (driver?['name'] ?? 'your driver').toString();
                            final ok = await showDriverRatingSheet(
                              context: context,
                              bookingId: widget.bookingId,
                              driverName: name,
                            );
                            if (ok && mounted) await _refresh();
                          },
                    icon: const Icon(Icons.star_rounded),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    label: const Text(
                      'Rate driver now',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!widget.isDriver &&
            status == 'completed' &&
            booking['has_rated'] == true) ...[
          const SizedBox(height: 16),
          _card(
            isDark,
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 10),
                Text(
                  'Thanks — you already rated this driver.',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _addr(dynamic raw, String fallback) {
    if (raw is Map) {
      final a = (raw['address'] ?? raw['name'] ?? '').toString().trim();
      if (a.isNotEmpty) return a;
    }
    final s = (raw ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  Widget _card(bool isDark, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: child,
    );
  }

  Widget _line(IconData icon, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFFFFC107)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
