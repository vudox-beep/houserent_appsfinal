import 'dart:ui';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/app_logo.dart';
import '../widgets/home_image_banner.dart';
import '../widgets/home_sliding_banner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../utils/legal_navigation.dart';
import '../screens/legal_document_screen.dart';
import '../widgets/skeleton_loader.dart';
import 'driver/driver_dashboard.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _publicNotifBadgeCountKey =
      'public_admin_notifications_badge_v1';
  bool _isLoggedIn = false;
  String _userName = '';
  String _userRole = '';

  int _selectedIndex = 0;
  List<dynamic> _properties = [];
  bool _isLoading = true;
  String _appVersionLabel = 'Version --';
  int _publicNotifBadgeCount = 0;
  int _houseHuntBadgeCount = 0;
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<HomeSlidingBannerState> _bannerKey =
      GlobalKey<HomeSlidingBannerState>();
  final GlobalKey<HomeImageBannerState> _imageBannerKey =
      GlobalKey<HomeImageBannerState>();

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _loadProperties();
    _loadAppVersion();
    _loadPublicNotificationBadgeCount();
    _refreshPublicNotificationBadgeCount();
    _loadHouseHuntBadgeCount();
    _maybeShowWhatsNewPopup();
  }

  Future<void> _maybeShowWhatsNewPopup() async {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      const key = 'whats_new_seen_v2026_08_21';
      if (prefs.getBool(key) == true) return;
      await prefs.setBool(key, true);
      if (!mounted) return;
      _showWhatsNewPopup();
    });
  }

  Future<void> _showWhatsNewPopup() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Icon/Image
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC107).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.campaign_rounded,
                    color: Color(0xFFFFC107),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  'What’s New',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome to HouseRent Africa!',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 24),
                // Items
                _buildWhatsNewItem(
                  icon: Icons.map_outlined,
                  title: 'Map View Search',
                  description:
                      'Explore listings on the map and find homes by location.',
                  isDark: isDark,
                ),
                const SizedBox(height: 16),
                _buildWhatsNewItem(
                  icon: Icons.storefront_outlined,
                  title: 'Zed Bine',
                  description:
                      'Sell your phones and promote your business or services.',
                  isDark: isDark,
                ),
                const SizedBox(height: 16),
                _buildWhatsNewItem(
                  icon: Icons.check_circle_outline,
                  title: 'For Landlords',
                  description:
                      'Please mark a listing as "Rented" once it has been taken.',
                  isDark: isDark,
                ),
                const SizedBox(height: 24),
                // Footer text
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.waving_hand_rounded,
                          color: Colors.amber.shade600, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Kulibe ndiwe — to our Kombi Area community in Zambia: you are welcome.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.black87,
                            height: 1.4,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Got it!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWhatsNewItem({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: const Color(0xFFFFC107),
            size: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _loadHouseHuntBadgeCount() async {
    final count = await ApiService.fetchTenantRequestsCount();
    if (!mounted) return;
    setState(() {
      _houseHuntBadgeCount = count;
    });
  }

  Future<void> _loadPublicNotificationBadgeCount() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_publicNotifBadgeCountKey) ?? 0;
    if (!mounted) return;
    setState(() {
      _publicNotifBadgeCount = count;
    });
  }

  Future<void> _refreshPublicNotificationBadgeCount() async {
    final count =
        await NotificationService.refreshPublicNotificationBadgeCount();
    if (!mounted) return;
    setState(() {
      _publicNotifBadgeCount = count;
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersionLabel = 'Version ${info.version}';
      });
    } catch (_) {}
  }

  Future<void> _handleRefresh() async {
    await Future.wait([
      _loadProperties(shuffle: true),
      _bannerKey.currentState?.reload() ?? Future<void>.value(),
      _imageBannerKey.currentState?.reload() ?? Future<void>.value(),
    ]);
  }

  Future<void> _loadProperties({bool shuffle = false}) async {
    try {
      final properties = await ApiService.fetchProperties();

      // Hide properties whose dealer subscription is inactive/expired (defensive frontend filter).
      final now = DateTime.now();
      final zedBineTypes = ['salon', 'gadget', 'mechanic', 'other_service'];

      final filtered = properties.where((p) {
        final type = (p['property_type'] ?? p['type'] ?? '')
            .toString()
            .toLowerCase();

        // Filter out Zed Bine properties from the home screen
        if (zedBineTypes.contains(type)) return false;

        final status =
            (p['dealer_subscription_status'] ??
                    p['subscription_status'] ??
                    p['dealer_status'] ??
                    '')
                .toString()
                .toLowerCase();
        final expiryRaw =
            p['dealer_subscription_expiry'] ?? p['subscription_expiry'];
        DateTime? expiry;
        if (expiryRaw is String &&
            expiryRaw.isNotEmpty &&
            expiryRaw != '0000-00-00 00:00:00') {
          try {
            expiry = DateTime.parse(expiryRaw);
          } catch (_) {}
        }

        final isActiveStatus = status.isEmpty || status == 'active';
        final isNotExpired = expiry == null || !expiry.isBefore(now);
        return isActiveStatus && isNotExpired;
      }).toList();

      if (shuffle) {
        filtered.shuffle();
      }

      if (mounted) {
        setState(() {
          _properties = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<dynamic> _latestProperties() {
    // If it has been shuffled via refresh, return as is.
    // We can detect if it's shuffled by just skipping the sort if we want the "exchange" to reflect.
    // However, to ensure the exchange actually happens on refresh, we'll just return `_properties` directly here.
    return _properties;
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final role = prefs.getString('role');

    if (token != null && token.isNotEmpty) {
      // Temporarily set isLoggedIn to true immediately so the UI responds faster,
      // even if the profile fetch takes a second.
      if (mounted) {
        setState(() {
          _isLoggedIn = true;
          // Ensure role defaults to tenant if null to prevent redirect issues
          _userRole = (role != null && role.isNotEmpty) ? role : 'tenant';
        });
      }

      try {
        final profile = await ApiService.getProfile();
        if (mounted) {
          setState(() {
            _userName = profile['name'] ?? 'User';
            // Overwrite role if API returns it, just in case
            if (profile['role'] != null) {
              _userRole = profile['role'];
            }
          });
        }
      } catch (e) {
        // Token might be invalid or expired
        if (mounted) {
          setState(() {
            _isLoggedIn = false;
          });
        }
      }
    }
  }

  void _navigateToDashboard() {
    if (_userRole == 'dealer') {
      context.go('/dealer-dashboard');
    } else if (_userRole == 'driver') {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DriverDashboard()),
        (_) => false,
      );
    } else {
      context.go('/tenant-dashboard');
    }
  }

  void _showLoginRequiredPopup() {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Login Required',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            'Please login to view and save your favorite properties.',
            style: TextStyle(
              height: 1.4,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Not now',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.go('/login');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Login',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _onItemTapped(int index) {
    if (index == 0) {
      // Home tab clicked
      setState(() {
        _selectedIndex = index;
      });
    } else if (index == 1) {
      // Saved clicked
      if (_isLoggedIn) {
        if (_userRole == 'tenant' || _userRole == 'user' || _userRole.isEmpty) {
          try {
            context.go('/tenant-dashboard', extra: {'tab': 4});
          } catch (_) {}
        } else if (_userRole == 'dealer') {
          context.go('/dealer-dashboard');
        } else if (_userRole == 'driver') {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const DriverDashboard()),
            (_) => false,
          );
        }
      } else {
        _showLoginRequiredPopup();
      }
    } else if (index == 2) {
      if (_isLoggedIn) {
        context.push('/tenant-requests');
      } else {
        _showLoginRequiredPopup();
      }
    } else if (index == 3) {
      if (_isLoggedIn) {
        context.go('/public-notifications');
      } else {
        _showLoginRequiredPopup();
      }
    } else if (index == 4) {
      // Profile clicked
      if (_isLoggedIn) {
        if (_userRole == 'dealer') {
          context.go('/dealer-dashboard');
        } else if (_userRole == 'driver') {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const DriverDashboard()),
            (_) => false,
          );
        } else {
          context.go('/tenant-dashboard', extra: {'tab': 3});
        }
      } else {
        context.go('/login');
      }
    }
  }

  void _submitHomeSearch() {
    final raw = _searchController.text.trim();
    if (raw.isEmpty) {
      context.go('/search-results');
      return;
    }
    context.go('/search-results?location=${Uri.encodeComponent(raw)}');
  }

  Future<void> _openNearMeMap() async {
    if (!mounted) return;

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final allow = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Find homes near you',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            content: Text(
              'Allow location access so we can show nearby rentals on the map and sort them by distance.',
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Allow location',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );

        if (allow == true) {
          permission = await Geolocator.requestPermission();
        }
      }

      if (!mounted) return;

      if (permission == LocationPermission.deniedForever) {
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
              'Location is turned off for HouseRent. Enable it in Settings to see homes near you.',
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
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
          await Geolocator.openAppSettings();
        }
      } else if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location denied. You can still browse all homes on the map.',
            ),
          ),
        );
      } else {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Turn on GPS to see homes closest to you.'),
            ),
          );
        }
      }
    }

    if (mounted) context.push('/near-me');
  }

  Future<void> _showProtectCommunityDialog() async {
    const supportEmail = 'chisalaluckyk5@gmail.com';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final muted = isDark ? Colors.white70 : const Color(0xFF5F6368);
    final titleColor = isDark ? Colors.white : const Color(0xFF111827);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Material(
            color: surface,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFC107),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          size: 30,
                          color: Color(0xFFC62828),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Protect Our Community',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF3E2723),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Report fake listings or scammers',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    children: [
                      Text(
                        'Spotted something suspicious? Email us with details, screenshots, and the listing link so we can act fast.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF242424)
                              : const Color(0xFFF8F8F8),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark
                                ? Colors.white10
                                : const Color(0xFFE8E8E8),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Support email',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: muted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              supportEmail,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: titleColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final uri = Uri(
                              scheme: 'mailto',
                              path: supportEmail,
                              queryParameters: {
                                'subject': 'Report fake listing / scam',
                              },
                            );
                            await launchUrl(uri);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC107),
                            foregroundColor: const Color(0xFF3E2723),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.email_rounded, size: 20),
                          label: const Text(
                            'Email us',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              const ClipboardData(text: supportEmail),
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Email copied'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: titleColor,
                            side: BorderSide(
                              color: isDark
                                  ? const Color(0xFFFFC107).withValues(
                                      alpha: 0.65,
                                    )
                                  : const Color(0xFFD4A017),
                              width: 1.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text(
                            'Copy email',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(
                          'Close',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String desc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242424) : const Color(0xFFF7F7F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFFC107),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF3E2723), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF5F6368),
                    fontSize: 12.8,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationIcon({required bool active, Color? iconColor}) {
    final icon = Icon(
      active ? Icons.notifications : Icons.notifications_none,
      color: iconColor,
    );
    if (_publicNotifBadgeCount <= 0) return icon;

    final badgeText = _publicNotifBadgeCount > 99
        ? '99+'
        : _publicNotifBadgeCount.toString();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -8,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
            child: Text(
              badgeText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHouseHuntIcon({required bool active, Color? iconColor}) {
    final icon = Icon(
      active ? Icons.campaign : Icons.campaign_outlined,
      color: iconColor,
    );
    if (_houseHuntBadgeCount <= 0) return icon;

    final badgeText = _houseHuntBadgeCount > 99
        ? '99+'
        : _houseHuntBadgeCount.toString();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -8,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
            child: Text(
              badgeText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: AppBrand(
          textColor: isDark ? const Color(0xFFFFC107) : Colors.white,
        ),
        elevation: 0,
        backgroundColor: isDark
            ? const Color(0xFF1E1E1E)
            : const Color(
                0xFFFFC107,
              ), // Use dark mode color or the primary button yellow
        centerTitle: false,
        actions: [
          if (_isLoggedIn)
            Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: TextButton.icon(
                onPressed: _navigateToDashboard,
                icon: Icon(
                  Icons.person,
                  color: isDark ? const Color(0xFFFFC107) : Colors.white,
                ),
                label: Text(
                  'Hi, ${_userName.split(' ').first}',
                  style: TextStyle(
                    color: isDark ? const Color(0xFFFFC107) : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: PopupMenuButton<String>(
                icon: Icon(
                  Icons.menu_rounded,
                  color: isDark ? const Color(0xFFFFC107) : Colors.white,
                ),
                color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                offset: const Offset(0, 50),
                onSelected: (value) async {
                  if (value == 'login') {
                    context.go('/login');
                  } else if (value == 'signup') {
                    context.go('/register');
                  } else if (value == 'dashboard') {
                    _navigateToDashboard();
                  } else if (value == 'theme') {
                    final nextMode = appThemeNotifier.value == ThemeMode.dark
                        ? ThemeMode.light
                        : ThemeMode.dark;
                    setAppThemeMode(nextMode);
                  } else if (value == 'share') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Share functionality coming soon'),
                      ),
                    );
                  } else if (value == 'privacy') {
                    openLegalDocument(
                      context,
                      type: LegalDocumentType.privacy,
                    );
                  }
                },
                itemBuilder: (BuildContext context) => [
                  if (_isLoggedIn)
                    PopupMenuItem(
                      value: 'dashboard',
                      child: Row(
                        children: [
                          Icon(
                            Icons.dashboard,
                            size: 20,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Dashboard',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    PopupMenuItem(
                      value: 'login',
                      child: Row(
                        children: [
                          Icon(
                            Icons.login,
                            size: 20,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Login',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'signup',
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_add,
                            size: 20,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Sign Up',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'theme',
                    child: Row(
                      children: [
                        Icon(
                          isDark ? Icons.light_mode : Icons.dark_mode,
                          size: 20,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isDark ? 'Light Mode' : 'Dark Mode',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(
                          Icons.share,
                          size: 20,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Share App',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'privacy',
                    child: Row(
                      children: [
                        Icon(
                          Icons.privacy_tip_outlined,
                          size: 20,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Privacy Policy',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          HomeSlidingBanner(key: _bannerKey),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _handleRefresh,
              color: const Color(0xFFFFC107),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
              // Hero Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(
                  top: 80,
                  bottom: 0,
                ), // Removed horizontal padding and bottom padding to let slider touch edges
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF9C4), // Fallback color
                  image: DecorationImage(
                    image: const NetworkImage(
                      'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?q=80&w=2070&auto=format&fit=crop',
                    ), // Modern real estate image
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.5),
                      BlendMode.darken,
                    ), // Dark overlay for text readability
                  ),
                ),
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Find Your Perfect Home in Zambia',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Discover apartments, houses, and properties for rent across Zambia and the continent.',
                        style: TextStyle(fontSize: 18, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _openNearMeMap,
                          borderRadius: BorderRadius.circular(999),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC107),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.near_me,
                                    size: 15,
                                    color: Colors.black87,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Near Me',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black87,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        width: 600,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2C)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          onSubmitted: (_) => _submitHomeSearch(),
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search by location...',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF2C2C2C)
                                : Colors.white,
                            suffixIcon: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.tune,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                    ),
                                    onPressed: () {
                                      context.go('/advanced-search');
                                    },
                                    tooltip: 'Advanced Search',
                                  ),
                                  ElevatedButton(
                                    onPressed: _submitHomeSearch,
                                    style: ElevatedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Search'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 40,
                    ), // Increased spacing before slider
                    // Category Slider touching the edges
                    SizedBox(
                      width: double.infinity,
                      height: 54, // Slightly taller for better touch target
                      child: Builder(
                        builder: (context) {
                          final categories = [
                            'Zed Bine',
                            'For Rent',
                            'For Sale',
                            'Boarding Houses',
                            'Apartment',
                            'Wedding Lodges',
                            'Studios',
                            'Land for Sale',
                          ];

                          // Optionally merge with dynamically found categories if needed
                          final dynamicCats = _properties
                              .map(
                                (p) => (p['property_type'] ?? p['type'] ?? '')
                                    .toString(),
                              )
                              .where(
                                (e) =>
                                    e.trim().isNotEmpty &&
                                    !categories.contains(e),
                              )
                              .toSet()
                              .toList();

                          categories.addAll(dynamicCats);
                          return ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            scrollDirection: Axis.horizontal,
                            itemCount: categories.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final label = categories[index];
                              return InkWell(
                                onTap: () {
                                  if (label == 'Zed Bine') {
                                    context.push('/zed-bine');
                                    return;
                                  }
                                  String paramType = '';
                                  String paramPurpose = '';

                                  if (label == 'Boarding Houses') {
                                    paramType = 'boarding_house';
                                  } else if (label == 'Wedding Lodges') {
                                    paramType = 'wedding_lodge';
                                  } else if (label == 'For Rent') {
                                    paramPurpose = 'rent';
                                  } else if (label == 'For Sale') {
                                    paramPurpose = 'sale';
                                  } else if (label == 'Land for Sale') {
                                    paramType = 'land';
                                    paramPurpose = 'sale';
                                  } else if (label == 'Apartment') {
                                    paramType = 'apartment';
                                  } else if (label == 'Studios') {
                                    paramType = 'studio';
                                  } else {
                                    paramType = label.toLowerCase().replaceAll(
                                      ' ',
                                      '_',
                                    );
                                  }

                                  String query = '';
                                  if (paramType.isNotEmpty) {
                                    query += 'type=$paramType';
                                  }
                                  if (paramPurpose.isNotEmpty) {
                                    if (query.isNotEmpty) query += '&';
                                    query += 'purpose=$paramPurpose';
                                  }

                                  context.go(
                                    '/search-results${query.isNotEmpty ? '?$query' : ''}',
                                  );
                                },
                                borderRadius: BorderRadius.circular(24),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 10,
                                      sigmaY: 10,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(
                                          0.3,
                                        ), // Dark translucent glass effect
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.2),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (label == 'Zed Bine')
                                            const Icon(
                                              Icons.handyman,
                                              size: 16,
                                              color: Color(0xFFFFC107),
                                            )
                                          else
                                            const Icon(
                                              Icons.category_outlined,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                          const SizedBox(width: 8),
                                          Text(
                                            label,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: label == 'Zed Bine'
                                                  ? const Color(0xFFFFC107)
                                                  : Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Video Walkthrough CTA (compact, close to listings)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF121212), Color(0xFF2B2B2B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC107).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.ondemand_video,
                        color: Color(0xFFFFC107),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'House Reels',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Watch listings in short videos',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => context.push('/video-walkthroughs'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC107),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 34),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Watch'),
                    ),
                  ],
                ),
              ),

              // Featured Properties Section
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0, right: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Featured Properties',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                context.go('/search-results?featured=1'),
                            child: const Text(
                              'View All',
                              style: TextStyle(
                                color: Color(0xFFFFC107),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isLoading)
                      const SkeletonPropertyCarousel(height: 310)
                    else if (_properties
                        .where((p) => p['is_featured']?.toString() == '1')
                        .isEmpty)
                      const SizedBox(
                        height: 100,
                        child: Center(
                          child: Text('No featured properties available'),
                        ),
                      )
                    else
                      SizedBox(
                        height: 310, // Matching the height for consistency
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                          ), // Touch edge a bit
                          itemCount: _properties
                              .where((p) => p['is_featured']?.toString() == '1')
                              .length,
                          itemBuilder: (context, index) {
                            final featuredProps = _properties
                                .where(
                                  (p) => p['is_featured']?.toString() == '1',
                                )
                                .toList();

                            return Container(
                              width:
                                  MediaQuery.of(context).size.width * 0.75 > 320
                                  ? 320 // Max width for larger screens
                                  : MediaQuery.of(context).size.width *
                                        0.75, // Make cards wider (75% of screen width)
                              margin: const EdgeInsets.only(
                                right: 16.0,
                                bottom: 8.0,
                              ), // Tighter margin
                              child: PropertyCard(
                                property: featuredProps[index],
                                isFeatured: true,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),

              // Latest Listings Section
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0, right: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Latest Listings',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.go('/search-results'),
                            child: const Text(
                              'View All',
                              style: TextStyle(
                                color: Color(0xFFFFC107),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isLoading)
                      const SkeletonPropertyCarousel(height: 310)
                    else if (_properties.isEmpty)
                      const SizedBox(
                        height: 280,
                        child: Center(child: Text('No properties available')),
                      )
                    else
                      Builder(
                        builder: (context) {
                          final latestProps = _latestProperties();
                          final latestCount = latestProps.length > 5
                              ? 5
                              : latestProps.length;
                          return SizedBox(
                            height:
                                310, // Increased height to prevent content overflow in neat design
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              itemCount: latestCount,
                              itemBuilder: (context, index) {
                                return Container(
                                  width:
                                      MediaQuery.of(context).size.width * 0.75 >
                                          320
                                      ? 320
                                      : MediaQuery.of(context).size.width *
                                            0.75, // Make cards wider (75% of screen width)
                                  margin: const EdgeInsets.only(
                                    right: 16.0,
                                    bottom: 8.0,
                                  ), // increased margin for breathing room
                                  child: PropertyCard(
                                    property: latestProps[index],
                                    isFeatured: false,
                                    showNewBadge: true,
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),

              // Boarding Houses Section
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0, right: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Boarding Houses',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.go(
                              '/search-results?type=boarding_house',
                            ),
                            child: const Text(
                              'View All',
                              style: TextStyle(
                                color: Color(0xFFFFC107),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isLoading)
                      const SkeletonPropertyCarousel(height: 310)
                    else if (_properties
                        .where(
                          (p) =>
                              p['property_type']?.toString().toLowerCase() ==
                              'boarding_house',
                        )
                        .isEmpty)
                      const SizedBox(
                        height: 100,
                        child: Center(
                          child: Text('No boarding houses available'),
                        ),
                      )
                    else
                      SizedBox(
                        height: 310, // Matching the height for consistency
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          itemCount: _properties
                              .where(
                                (p) =>
                                    p['property_type']
                                        ?.toString()
                                        .toLowerCase() ==
                                    'boarding_house',
                              )
                              .length,
                          itemBuilder: (context, index) {
                            final boardingProps = _properties
                                .where(
                                  (p) =>
                                      p['property_type']
                                          ?.toString()
                                          .toLowerCase() ==
                                      'boarding_house',
                                )
                                .toList();

                            return Container(
                              width:
                                  MediaQuery.of(context).size.width * 0.75 > 320
                                  ? 320
                                  : MediaQuery.of(context).size.width * 0.75,
                              margin: const EdgeInsets.only(
                                right: 16.0,
                                bottom: 8.0,
                              ),
                              child: PropertyCard(
                                property: boardingProps[index],
                                isFeatured: false,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),

              // Why Choose Us
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? Colors.white10 : const Color(0xFFE8E8E8),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? const [Color(0xFF2A2110), Color(0xFF1E1E1E)]
                              : const [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC107)
                                  .withValues(alpha: isDark ? 0.22 : 0.45),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'WHY CHOOSE US',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: isDark
                                    ? const Color(0xFFFFC107)
                                    : const Color(0xFF5A3D31),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Built for finding homes in Zambia',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Trusted listings, direct contact, and support when you need it.',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF5F6368),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                      child: Column(
                        children: [
                          _buildFeatureItem(
                            Icons.verified_rounded,
                            'Verified listings',
                            'Properties are reviewed so you can search with confidence.',
                          ),
                          const SizedBox(height: 10),
                          _buildFeatureItem(
                            Icons.chat_rounded,
                            'Direct contact',
                            'Reach landlords and agents without hidden middleman fees.',
                          ),
                          const SizedBox(height: 10),
                          _buildFeatureItem(
                            Icons.map_rounded,
                            'Wide coverage',
                            'Homes and services across Zambia and beyond.',
                          ),
                          const SizedBox(height: 10),
                          _buildFeatureItem(
                            Icons.support_agent_rounded,
                            'Dedicated support',
                            'Our team is ready to help when you get stuck.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Landlord Registration Banner
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 16.0,
                ),
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: DecorationImage(
                    image: const NetworkImage(
                      'https://images.unsplash.com/photo-1560518883-ce09059eeffa?q=80&w=1973&auto=format&fit=crop',
                    ), // Nice house exterior
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.65),
                      BlendMode.darken,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Are you a Landlord?',
                      style: TextStyle(
                        color: Color(0xFFFFC107), // Yellow text
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'List your properties and reach thousands of potential tenants across Zambia and Africa.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => context.go('/register'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC107),
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Register Now',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Referral Promo Banner (Moved below Landlord Registration Banner)
              GestureDetector(
                onTap: () {
                  if (_isLoggedIn) {
                    if (_userRole == 'dealer') {
                      context.go(
                        '/dealer-dashboard',
                      ); // Navigate to dealer dashboard, they can click referral tab
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Referral program is for dealers. Upgrade your account!',
                          ),
                        ),
                      );
                    }
                  } else {
                    context.go('/login');
                  }
                },
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFF9800)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.group_add_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Refer & Earn 30%!',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Invite others to HouseRent Africa and earn 30% commission.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),

              // Report Fake Listing Banner
              GestureDetector(
                onTap: _showProtectCommunityDialog,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(20.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      border: Border.all(
                        color: isDark
                            ? Colors.red.withOpacity(0.3)
                            : Colors.red.shade100,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.red.withOpacity(0.1)
                                : Colors.red.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.gpp_bad_outlined,
                            size: 28,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Protect Our Community',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Spotted a fake listing or scammer? Report them immediately.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey.shade700,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.red,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              HomeImageBanner(key: _imageBannerKey),
              // Footer
              Container(
                width: double.infinity,
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 40,
                  horizontal: 20,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.real_estate_agent,
                          color: isDark ? Colors.white : Colors.black87,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'HouseRent Africa',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            fontSize: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Find Your Perfect Home in Zambia & Africa',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey.shade600,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Divider(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '© ${DateTime.now().year} HouseRent Africa. Created by HouseRenta Technologies.',
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.grey.shade500,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _appVersionLabel,
                      style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey.shade400,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          const BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            activeIcon: Icon(Icons.favorite),
            label: 'Saved',
          ),
          BottomNavigationBarItem(
            icon: _buildHouseHuntIcon(active: false),
            activeIcon: _buildHouseHuntIcon(active: true),
            label: 'House Request',
          ),
          BottomNavigationBarItem(
            icon: _buildNotificationIcon(active: false),
            activeIcon: _buildNotificationIcon(active: true),
            label: 'Alerts',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        elevation: 16,
      ),
    );
  }
}

class PropertyCard extends StatelessWidget {
  final Map<String, dynamic> property;
  final bool isFeatured;
  final bool showNewBadge;

  const PropertyCard({
    super.key,
    required this.property,
    this.isFeatured = false,
    this.showNewBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Dynamically calculate width to fit 2 cards per row with some spacing
    // Increased the card width to make them wider on the home screen
    final screenWidth = MediaQuery.of(context).size.width;
    // Less margin means wider cards. We reduce the deducted padding from 48+16 to just 32.
    final cardWidth = screenWidth < 600 ? (screenWidth - 32) / 2 : 320.0;

    final id = property['id']?.toString() ?? '1';
    final title = property['title'] ?? 'Unknown Property';
    final location = property['city'] != null && property['country'] != null
        ? '${property['city']}, ${property['country']}'
        : (property['location'] ?? 'Unknown Location');
    final currency = property['currency'] ?? 'ZMW';
    final price = property['price']?.toString() ?? '0';
    final type = (property['property_type']?.toString() ?? 'House').trim();
    final typeLower = type.toLowerCase();

    final bool isService =
        typeLower.contains('wedding') ||
        typeLower.contains('studio') ||
        typeLower.contains('lodge') ||
        typeLower.contains('studies') ||
        typeLower.contains('restaurant');
    final String purposeKey = _purposeKey(property, typeLower);
    final String purposeBadge = _purposeBadgeText(purposeKey);
    final Color purposeBadgeColor = _purposeBadgeColor(purposeKey);
    final bool isNewListing = showNewBadge || _isNewListing(property);

    final beds = property['bedrooms']?.toString() ?? '';
    final baths = property['bathrooms']?.toString() ?? '';
    final size =
        property['size_sqm']?.toString() ?? property['size']?.toString() ?? '';
    final rooms = property['rooms']?.toString() ?? '';
    final capacity = property['capacity']?.toString() ?? '';
    final eventType = property['event_type']?.toString() ?? '';
    final peoplePerRoom = property['people_per_room']?.toString() ?? '';

    // Get first image if available
    String? imageUrl;

    // The new API structure returns 'main_image' with the fully formatted URL
    if (property['main_image'] != null &&
        property['main_image'].toString().isNotEmpty) {
      String mainImg = property['main_image'].toString().trim();
      // Remove any literal backticks the API might accidentally include
      mainImg = mainImg.replaceAll('`', '').trim();
      imageUrl = mainImg;
    }
    // Fallback for older API structure
    else if (property['images'] != null && property['images'].isNotEmpty) {
      var firstImage = property['images'][0];
      if (firstImage is Map && firstImage['url'] != null) {
        String urlStr = firstImage['url'].toString().trim();
        urlStr = urlStr.replaceAll('`', '').trim();
        imageUrl = urlStr;
      } else if (firstImage is String) {
        String imagePath = firstImage.trim();
        imagePath = imagePath.replaceAll('`', '').trim();

        if (imagePath.startsWith('http')) {
          imageUrl = imagePath;
        } else {
          if (imagePath.startsWith('/')) {
            imagePath = imagePath.substring(1);
          }
          if (imagePath.startsWith('assets/')) {
            imageUrl = 'https://houseforrent.site/$imagePath';
          } else if (imagePath.startsWith('uploads/')) {
            imageUrl = 'https://houseforrent.site/php_backend/api/$imagePath';
          } else {
            if (!imagePath.startsWith('assets/')) {
              imageUrl = 'https://houseforrent.site/assets/$imagePath';
            } else {
              imageUrl = 'https://houseforrent.site/$imagePath';
            }
          }
        }
      }
    }

    return GestureDetector(
      onTap: () {
        context.push('/property/$id');
      },
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.only(
          bottom: 0,
        ), // Removed right margin to let ListView padding handle it
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey.shade200,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image Section
                  Container(
                    height:
                        160, // Increased image height slightly for better proportion
                    width: double.infinity,
                    decoration: BoxDecoration(color: Colors.grey.shade200),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imageUrl != null)
                          Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                                  child: Icon(
                                    Icons.image,
                                    size: 40,
                                    color: Colors.black26,
                                  ),
                                ),
                          )
                        else
                          const Center(
                            child: Icon(
                              Icons.image,
                              size: 40,
                              color: Colors.black26,
                            ),
                          ),

                        // Gradient overlay at bottom of image for contrast
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withOpacity(0.4),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),

                        Positioned(
                          top: 12,
                          right: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (isNewListing)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade600,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Text(
                                    'NEW',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                      color: Colors.white,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              if (isFeatured)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors
                                        .black87, // Black badge for featured
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(
                                        Icons.star,
                                        color: Color(0xFFFFC107),
                                        size: 12,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'FEATURED',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 9,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: purposeBadgeColor,
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  purposeBadge,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Details Section
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14.0,
                        vertical: 10.0,
                      ), // Reduced vertical padding
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                        height: 1.2,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4), // Reduced spacing
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    size: 14,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      location,
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.grey.shade600,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4), // Reduced spacing
                              Text(
                                (isService && purposeKey == 'service')
                                    ? '$currency $price per service'
                                    : '$currency $price',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: isDark
                                      ? const Color(0xFFFFD700)
                                      : const Color(0xFF5A3D31),
                                ), // Slightly smaller price
                              ),
                            ],
                          ),

                          // Divider line
                          Divider(
                            color: isDark
                                ? Colors.white12
                                : Colors.grey.shade200,
                            height: 12,
                            thickness: 1,
                          ), // Reduced height
                          // Amenities row at bottom
                          SizedBox(
                            height: 20, // Reduced height
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              children: [
                                if (typeLower == 'apartment' ||
                                    typeLower == 'house') ...[
                                  if (beds.isNotEmpty && beds != '0')
                                    _buildProfessionalAmenity(
                                      context,
                                      Icons.bed_outlined,
                                      '$beds Beds',
                                    ),
                                  if (beds.isNotEmpty && beds != '0')
                                    const SizedBox(width: 12),
                                  if (baths.isNotEmpty && baths != '0')
                                    _buildProfessionalAmenity(
                                      context,
                                      Icons.bathtub_outlined,
                                      '$baths Baths',
                                    ),
                                  if (baths.isNotEmpty && baths != '0')
                                    const SizedBox(width: 12),
                                ] else if (typeLower.contains('boarding')) ...[
                                  if (capacity.isNotEmpty && capacity != '0')
                                    _buildProfessionalAmenity(
                                      context,
                                      Icons.group_outlined,
                                      'Cap: $capacity',
                                    ),
                                  if (capacity.isNotEmpty && capacity != '0')
                                    const SizedBox(width: 12),
                                  if (peoplePerRoom.isNotEmpty &&
                                      peoplePerRoom != '0')
                                    _buildProfessionalAmenity(
                                      context,
                                      Icons.person_outline,
                                      '$peoplePerRoom/Room',
                                    ),
                                  if (peoplePerRoom.isNotEmpty &&
                                      peoplePerRoom != '0')
                                    const SizedBox(width: 12),
                                ] else if (typeLower.contains('wedding') ||
                                    typeLower.contains('studio')) ...[
                                  if (capacity.isNotEmpty && capacity != '0')
                                    _buildProfessionalAmenity(
                                      context,
                                      Icons.groups_outlined,
                                      'Cap: $capacity',
                                    ),
                                  if (capacity.isNotEmpty && capacity != '0')
                                    const SizedBox(width: 12),
                                  if (eventType.isNotEmpty)
                                    _buildProfessionalAmenity(
                                      context,
                                      Icons.event_outlined,
                                      eventType,
                                    ),
                                  if (eventType.isNotEmpty)
                                    const SizedBox(width: 12),
                                ] else if (typeLower == 'salon') ...[
                                  _buildProfessionalAmenity(
                                    context,
                                    Icons.face_retouching_natural,
                                    'Salon & Beauty',
                                  ),
                                  const SizedBox(width: 12),
                                ] else if (typeLower == 'gadget' ||
                                    typeLower == 'mechanic') ...[
                                  _buildProfessionalAmenity(
                                    context,
                                    Icons.devices,
                                    'Repairs',
                                  ),
                                  const SizedBox(width: 12),
                                ] else if (typeLower == 'other_service') ...[
                                  _buildProfessionalAmenity(
                                    context,
                                    Icons.handyman,
                                    'Service',
                                  ),
                                  const SizedBox(width: 12),
                                ] else ...[
                                  if (rooms.isNotEmpty && rooms != '0')
                                    _buildProfessionalAmenity(
                                      context,
                                      Icons.door_front_door_outlined,
                                      '$rooms Rooms',
                                    ),
                                  if (rooms.isNotEmpty && rooms != '0')
                                    const SizedBox(width: 12),
                                ],
                                if (size.isNotEmpty && size != '0')
                                  _buildProfessionalAmenity(
                                    context,
                                    Icons.square_foot_outlined,
                                    '${size}m²',
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if ([
                'taken',
                'rented',
                'sold',
              ].contains(property['status']?.toString().toLowerCase() ?? ''))
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
                      child: Container(
                        color: Colors.white.withOpacity(0.3),
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade700.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Text(
                            purposeKey == 'sale' ? 'SOLD' : 'RENTED',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
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

  Widget _buildProfessionalAmenity(
    BuildContext context,
    IconData icon,
    String text,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Colors.white54 : Colors.grey.shade600,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _purposeKey(Map<String, dynamic> property, String typeLower) {
    final rawPurpose =
        (property['purpose'] ?? property['listing_purpose'] ?? '')
            .toString()
            .toLowerCase()
            .trim();

    if (rawPurpose.contains('sale') || rawPurpose == 'sell') return 'sale';
    if (rawPurpose.contains('service')) return 'service';
    if (rawPurpose.contains('auction')) return 'auction';
    if (rawPurpose.contains('lease')) return 'lease';
    if (rawPurpose.contains('rent')) {
      final bool serviceType =
          typeLower.contains('wedding') ||
          typeLower.contains('studio') ||
          typeLower.contains('lodge') ||
          typeLower.contains('studies') ||
          typeLower.contains('restaurant') ||
          typeLower == 'salon' ||
          typeLower == 'gadget' ||
          typeLower == 'mechanic' ||
          typeLower == 'other_service';
      return serviceType ? 'service' : 'rent';
    }

    if (typeLower.contains('land')) return 'sale';
    return 'rent';
  }

  String _purposeBadgeText(String purposeKey) {
    switch (purposeKey) {
      case 'sale':
        return 'FOR SALE';
      case 'service':
        return 'SERVICE';
      case 'auction':
        return 'AUCTION';
      case 'lease':
        return 'FOR LEASE';
      default:
        return 'FOR RENT';
    }
  }

  Color _purposeBadgeColor(String purposeKey) {
    switch (purposeKey) {
      case 'sale':
        return const Color(0xFF1E3A8A);
      case 'service':
        return const Color(0xFF6D28D9);
      case 'auction':
        return const Color(0xFFD97706);
      case 'lease':
        return const Color(0xFF059669);
      default:
        return const Color(0xFF0F766E);
    }
  }

  bool _isNewListing(Map<String, dynamic> property) {
    final createdRaw =
        (property['created_at'] ??
                property['date_added'] ??
                property['createdAt'] ??
                '')
            .toString()
            .trim();
    if (createdRaw.isEmpty) return false;

    try {
      final createdAt = DateTime.parse(createdRaw);
      return DateTime.now().difference(createdAt).inDays <= 14;
    } catch (_) {
      return false;
    }
  }
}
