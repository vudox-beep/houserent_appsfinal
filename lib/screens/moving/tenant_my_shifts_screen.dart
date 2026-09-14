import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/moving_marketplace_service.dart';
import '../../widgets/driver_rating_sheet.dart';
import 'moving_booking_detail_screen.dart';
import '../../utils/app_error.dart';

/// Standalone list of tenant shifts — kept off the live map screen.
class TenantMyShiftsScreen extends StatefulWidget {
  const TenantMyShiftsScreen({
    super.key,
    this.returnTripToCaller = false,
  });

  /// When opened from the map AppBar, pop the selected trip back.
  /// When opened from the home dashboard, push the map with that trip.
  final bool returnTripToCaller;

  @override
  State<TenantMyShiftsScreen> createState() => _TenantMyShiftsScreenState();
}

class _TenantMyShiftsScreenState extends State<TenantMyShiftsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _trips = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trips = await MovingMarketplaceService.listBookings();
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppError.userMessage(e);
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'accepted':
      case 'arrived':
      case 'in_progress':
        return const Color(0xFF276EF1);
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'cancelled':
        return Colors.red.shade400;
      default:
        return const Color(0xFFFFC107);
    }
  }

  Widget _routeLine(IconData icon, String text, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFFFFC107)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text.isEmpty ? 'Location hidden until unlocked' : text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  void _openOnMap(Map<String, dynamic> trip) {
    if (widget.returnTripToCaller) {
      Navigator.of(context).pop(trip);
      return;
    }
    context.push('/moving', extra: trip);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'My shifts',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFF14171A),
        foregroundColor: Colors.white,
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFC107)),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_trips.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 56,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 12),
            const Text(
              'No shifts yet',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Book a HouseRent Shift'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFFFC107),
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _trips.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final trip = _trips[index];
          final status = (trip['status'] ?? 'open').toString();
          final pickup = trip['pickup'] is Map
              ? (trip['pickup']['address'] ?? '').toString()
              : '';
          final dropoff = trip['dropoff'] is Map
              ? (trip['dropoff']['address'] ?? '').toString()
              : '';
          final date = (trip['moving_date'] ?? '').toString();
          final amount = trip['agreed_amount'];
          final driver = trip['driver'] is Map
              ? Map<String, dynamic>.from(trip['driver'] as Map)
              : <String, dynamic>{};
          final driverName = (driver['name'] ?? '').toString();
          final plate = (driver['vehicle_plate'] ?? '').toString();
          final vehicle = (driver['vehicle_type'] ?? '').toString();
          final isLive = status == 'accepted' ||
              status == 'in_progress' ||
              status == 'arrived' ||
              status == 'open';

          return Material(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MovingBookingDetailScreen(
                      bookingId: int.parse(trip['id'].toString()),
                      isDriver: false,
                    ),
                  ),
                );
                _load();
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: _statusColor(status),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          date,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _routeLine(Icons.radio_button_checked, pickup, isDark),
                    Padding(
                      padding: const EdgeInsets.only(left: 9),
                      child: Container(
                        width: 2,
                        height: 14,
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                      ),
                    ),
                    _routeLine(Icons.location_on, dropoff, isDark),
                    if (driverName.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        [
                          driverName,
                          if (vehicle.isNotEmpty) vehicle,
                          if (plate.isNotEmpty) plate,
                        ].join(' · '),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      Builder(
                        builder: (_) {
                          final badge = DriverRatingBadge.fromDriver(driver);
                          if (badge == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: badge,
                          );
                        },
                      ),
                    ],
                    if (amount != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Agreed: K $amount',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                    if (isLive) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: () => _openOnMap(trip),
                          icon: Icon(
                            status == 'open'
                                ? Icons.search_rounded
                                : Icons.map_rounded,
                            size: 18,
                          ),
                          label: Text(
                            status == 'open'
                                ? 'Continue on map'
                                : 'Open on map',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: status == 'open'
                                ? const Color(0xFFFFC107)
                                : const Color(0xFF14171A),
                            foregroundColor:
                                status == 'open' ? Colors.black : Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (status == 'completed' &&
                        trip['has_rated'] != true &&
                        trip['can_rate'] != false) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final id =
                                int.tryParse(trip['id']?.toString() ?? '') ?? 0;
                            if (id < 1) return;
                            final rated = await showDriverRatingSheet(
                              context: context,
                              bookingId: id,
                              driverName:
                                  driverName.isEmpty ? 'your driver' : driverName,
                            );
                            if (rated && mounted) _load();
                          },
                          icon: const Icon(Icons.star_rounded, size: 18),
                          label: const Text(
                            'Rate driver',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC107),
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
