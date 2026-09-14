import 'package:flutter/material.dart';

import '../services/moving_marketplace_service.dart';
import '../utils/app_error.dart';

/// Bottom sheet shown to the tenant right after the driver completes the destination.
Future<bool> showDriverRatingSheet({
  required BuildContext context,
  required int bookingId,
  String driverName = 'your driver',
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) => _DriverRatingSheet(
      bookingId: bookingId,
      driverName: driverName,
    ),
  );
  return result == true;
}

class _DriverRatingSheet extends StatefulWidget {
  const _DriverRatingSheet({
    required this.bookingId,
    required this.driverName,
  });

  final int bookingId;
  final String driverName;

  @override
  State<_DriverRatingSheet> createState() => _DriverRatingSheetState();
}

class _DriverRatingSheetState extends State<_DriverRatingSheet> {
  int _stars = 5;
  bool _busy = false;
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await MovingMarketplaceService.rateDriver(
        bookingId: widget.bookingId,
        rating: _stars,
        comment: _commentCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFFFC107),
                  size: 34,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Rate ${widget.driverName}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your trip is complete. How was this HouseRent Shifts driver?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  final on = star <= _stars;
                  return IconButton(
                    onPressed: _busy ? null : () => setState(() => _stars = star),
                    iconSize: 36,
                    icon: Icon(
                      on ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: const Color(0xFFFFC107),
                    ),
                  );
                }),
              ),
              Text(
                '$_stars / 5',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _commentCtrl,
                maxLines: 3,
                enabled: !_busy,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Optional comment (was the move careful / on time?)',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  filled: true,
                  fillColor:
                      isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.black,
                          ),
                        )
                      : const Text(
                          'Submit rating',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: Text(
                  'Maybe later',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact rating / Premium chip shown to other tenants while booking.
class DriverRatingBadge extends StatelessWidget {
  const DriverRatingBadge({
    super.key,
    required this.rating,
    this.ratingCount = 0,
    this.premium = false,
    this.label,
  });

  final double rating;
  final int ratingCount;
  final bool premium;
  final String? label;

  static DriverRatingBadge? fromDriver(Map<String, dynamic>? driver) {
    if (driver == null) return null;
    final rating = double.tryParse('${driver['rating'] ?? driver['driver_rating']}') ?? 0;
    final count = int.tryParse(
          '${driver['rating_count'] ?? driver['driver_rating_count'] ?? 0}',
        ) ??
        0;
    final premium = driver['premium_rated'] == true ||
        (rating >= 4.5 && count >= 3);
    final label = driver['rating_label']?.toString();
    if (rating <= 0 && count < 1 && (label == null || label.isEmpty)) {
      return null;
    }
    return DriverRatingBadge(
      rating: rating,
      ratingCount: count,
      premium: premium,
      label: label,
    );
  }

  static DriverRatingBadge? fromOffer(Map<String, dynamic> offer) {
    return fromDriver({
      'rating': offer['driver_rating'],
      'rating_count': offer['driver_rating_count'],
      'premium_rated': offer['premium_rated'],
      'rating_label': offer['rating_label'],
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = (label != null && label!.isNotEmpty)
        ? label!
        : (premium
            ? 'Premium · ★ ${rating.toStringAsFixed(rating % 1 == 0 ? 0 : 1)} ($ratingCount)'
            : '★ ${rating.toStringAsFixed(rating % 1 == 0 ? 0 : 1)}${ratingCount > 0 ? ' ($ratingCount)' : ''}');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: premium
            ? const Color(0xFFFFC107).withValues(alpha: 0.18)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: premium
              ? const Color(0xFFFFC107).withValues(alpha: 0.55)
              : Colors.black12,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            premium ? Icons.workspace_premium_rounded : Icons.star_rounded,
            size: 14,
            color: premium ? const Color(0xFFD4A000) : const Color(0xFFFFC107),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: premium ? const Color(0xFFD4A000) : null,
            ),
          ),
        ],
      ),
    );
  }
}
