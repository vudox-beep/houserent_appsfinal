import 'package:flutter/material.dart';

import '../services/moving_marketplace_service.dart';

/// Shows the driver’s profile photo to the booking tenant (not ID documents).
/// Licence / NRC stay admin-only; tenants only see face/profile + verified badge.
class DriverIdentityPhotos extends StatelessWidget {
  const DriverIdentityPhotos({
    super.key,
    required this.driver,
    this.compact = false,
  });

  final Map<String, dynamic> driver;
  final bool compact;

  static String profileUrlOf(Map<String, dynamic>? driver) {
    if (driver == null) return '';
    final photo = (driver['photo_url'] ?? driver['avatar_url'] ?? '').toString().trim();
    if (photo.isEmpty) {
      return MovingMarketplaceService.driverAvatarUrl(
        name: driver['name']?.toString(),
      );
    }
    if (photo.startsWith('http://') || photo.startsWith('https://')) {
      return photo;
    }
    return 'https://houseforrent.site/${photo.replaceFirst(RegExp(r'^/+'), '')}';
  }

  /// Kept for call sites — documents are never exposed to tenants anymore.
  static List<Map<String, dynamic>> photosOf(Map<String, dynamic>? driver) {
    return const [];
  }

  static bool isVerified(Map<String, dynamic>? driver) {
    if (driver == null) return false;
    if (driver['identity_verified'] == true) return true;
    final identity = driver['identity'];
    return identity is Map && identity['verified'] == true;
  }

  static Future<void> openProfile(
    BuildContext context, {
    required String url,
    required String name,
  }) async {
    if (url.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name.isEmpty ? 'Driver' : name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              AspectRatio(
                aspectRatio: 1,
                child: InteractiveViewer(
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final verified = isVerified(driver);
    final name = (driver['name'] ?? 'Driver').toString();
    final url = profileUrlOf(driver);
    final size = compact ? 64.0 : 96.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (verified) ...[
              Icon(
                Icons.verified_rounded,
                size: compact ? 16 : 18,
                color: Colors.green,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              verified ? 'ID verified · profile photo' : 'Driver profile',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: compact ? 12.5 : 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: InkWell(
            onTap: () => openProfile(context, url: url, name: name),
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: size / 2,
                  backgroundColor: const Color(0xFFFFC107),
                  backgroundImage: NetworkImage(url),
                ),
                if (verified)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified_rounded,
                        color: Colors.green,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
