import 'package:flutter/material.dart';
import '../widgets/app_logo.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform, File;
import 'dart:ui' show ImageFilter;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dealer/dealer_payment_webview_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../utils/app_error.dart';
import '../widgets/skeleton_loader.dart';
import '../screens/home_screen.dart';
import 'dealer/dealer_payment_webview_screen.dart';

class PropertyDetailsScreen extends StatefulWidget {
  final int propertyId;
  const PropertyDetailsScreen({super.key, required this.propertyId});

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  static const String _publicNotifBadgeCountKey =
      'public_admin_notifications_badge_v1';
  Map<String, dynamic>? _property;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isLoggedIn = false;
  String _userName = '';
  String _userRole = '';
  bool _isSaved = false;
  int _currentImageIndex = 0;
  late PageController _pageController;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  final _inquiryNameController = TextEditingController();
  final _inquiryEmailController = TextEditingController();
  final _inquiryPhoneController = TextEditingController();
  final _inquiryMessageController = TextEditingController();
  final _landlordReviewController = TextEditingController();
  bool _isSendingInquiry = false;
  int _publicNotifBadgeCount = 0;
  int _houseHuntBadgeCount = 0;
  String _currentUserId = '';
  bool _isLoadingLandlordRating = false;
  bool _isSubmittingLandlordRating = false;
  bool _hasRatedLandlord = false;
  double _selectedLandlordRating = 0;
  double _averageLandlordRating = 0;
  int _totalLandlordRatings = 0;

  bool _hasPaidContactAccess = false;
  bool _isCheckingContactAccess = false;
  String _dynamicPrice = '5.00';

  List<dynamic> _similarProperties = [];
  bool _isLoadingSimilar = false;

  void _showLoginRequiredPopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Login Required',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        content: const Text(
          'Please login to access this feature.',
          style: TextStyle(height: 1.4, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not now', style: TextStyle(color: Colors.grey)),
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
      ),
    );
  }

  bool _isServiceType(String typeLower) {
    return typeLower.contains('wedding') ||
        typeLower.contains('studio') ||
        typeLower.contains('lodge') ||
        typeLower.contains('studies') ||
        typeLower.contains('restaurant');
  }

  String _purposeKey(Map<String, dynamic> property, String typeLower) {
    final rawPurpose =
        (property['purpose'] ?? property['listing_purpose'] ?? '')
            .toString()
            .toLowerCase()
            .trim();

    if (rawPurpose.contains('sale') || rawPurpose == 'sell') return 'sale';
    if (rawPurpose.contains('service')) return 'service';
    if (rawPurpose.contains('rent')) {
      return _isServiceType(typeLower) ? 'service' : 'rent';
    }
    if (typeLower.contains('land')) return 'sale';
    return 'rent';
  }

  String _purposeLabel(String purposeKey) {
    switch (purposeKey) {
      case 'sale':
        return 'For Sale';
      case 'service':
        return 'Service';
      default:
        return 'For Rent';
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadPublicNotificationBadgeCount();
    _refreshPublicNotificationBadgeCount();
    _loadHouseHuntBadgeCount();
    _checkLoginStatus();
    _fetchPropertyDetails();
    _fetchDynamicPrice();
  }

  Future<void> _fetchDynamicPrice() async {
    try {
      // Create a dummy user ID so the PHP script doesn't fail with "User ID is required"
      final userId = _currentUserId.isNotEmpty ? _currentUserId : 'dummy_user';
      final response = await http.get(
        Uri.parse(
          'https://houseforrent.site/api/tenant_contact_payment.php?action=pay_page&user_id=$userId',
        ),
      );
      if (response.statusCode == 200) {
        final html = response.body;
        // Look for the price in the HTML output: <h1 class="display-4 fw-bold mb-0">ZMW 5.00</h1>
        final regex = RegExp(r'ZMW\s+([\d\.]+)');
        final match = regex.firstMatch(html);
        if (match != null) {
          if (mounted) {
            setState(() {
              _dynamicPrice = match.group(1) ?? '5.00';
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching price: $e');
    }
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

  @override
  void dispose() {
    _pageController.dispose();
    _inquiryNameController.dispose();
    _inquiryEmailController.dispose();
    _inquiryPhoneController.dispose();
    _inquiryMessageController.dispose();
    _landlordReviewController.dispose();
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final role = prefs.getString('role');

    if (token != null && token.isNotEmpty) {
      try {
        final profile = await ApiService.getProfile();
        if (mounted) {
          setState(() {
            _isLoggedIn = true;
            _userName = profile['name'] ?? 'User';
            _userRole = role ?? 'tenant';
            _currentUserId =
                profile['id']?.toString() ??
                profile['user']?['id']?.toString() ??
                '';
          });
          _checkFavoriteStatus();
          _loadLandlordRatingSummary();
          if (_userRole != 'dealer' && _userRole != 'admin') {
            _checkContactAccessStatus();
          } else {
            setState(() {
              _hasPaidContactAccess = true; // Dealers/admins don't pay
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoggedIn = false;
          });
        }
      }
    }
  }

  Future<void> _checkFavoriteStatus() async {
    if (!_isLoggedIn) return;
    final isSaved = await ApiService.checkFavorite(
      widget.propertyId.toString(),
    );
    if (mounted) {
      setState(() {
        _isSaved = isSaved;
      });
    }
  }

  Future<void> _checkContactAccessStatus() async {
    if (!_isLoggedIn || _currentUserId.isEmpty) return;

    setState(() {
      _isCheckingContactAccess = true;
    });

    try {
      final response = await http.post(
        Uri.parse('https://houseforrent.site/api/tenant_contact_payment.php'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'action': 'get_status', 'user_id': _currentUserId},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['has_paid'] == true) {
          if (mounted) {
            setState(() {
              _hasPaidContactAccess = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking contact access: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingContactAccess = false;
        });
      }
    }
  }

  String _normalizeZmPhone(String input) {
    var cleaned = input.replaceAll(RegExp(r'[^0-9]'), '');

    if (cleaned.startsWith('00')) {
      cleaned = cleaned.substring(2);
    }

    if (cleaned.length == 12 && cleaned.startsWith('260')) {
      return cleaned;
    }

    if (cleaned.startsWith('0') && cleaned.length == 10) {
      cleaned = '260${cleaned.substring(1)}';
    } else if (cleaned.length == 9 &&
        (cleaned.startsWith('9') ||
            cleaned.startsWith('7') ||
            cleaned.startsWith('5'))) {
      cleaned = '260$cleaned';
    }

    return cleaned;
  }

  bool _isValidZmPhone(String input) {
    final normalized = _normalizeZmPhone(input);
    return RegExp(r'^260(9|7|5)\d{8}$').hasMatch(normalized);
  }

  Future<Map<String, dynamic>> _tenantPaymentRequest({
    required String action,
    required String userId,
    Map<String, dynamic>? extra,
  }) async {
    final url = 'https://houseforrent.site/api/tenant_contact_payment.php';
    final body = <String, dynamic>{
      'action': action,
      'user_id': userId,
      ...?extra,
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {
          'status': 'error',
          'message': 'Server error (${response.statusCode})',
        };
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (e) {
      return {'status': 'error', 'message': 'Network error occurred'};
    }

    return {'status': 'error', 'message': 'Invalid server response'};
  }

  Future<void> _showContactAccessPrompt(VoidCallback onPaidSuccess) async {
    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final dialogBackground = isDark
            ? const Color(0xFF1F1F1F)
            : Colors.white;
        final primaryTextColor = isDark ? Colors.white : Colors.black87;
        final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;
        final feeCardColor = isDark
            ? const Color(0xFF3A3000)
            : const Color(0xFFFFF3CD);

        return AlertDialog(
          backgroundColor: dialogBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Premium Contact Access',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: primaryTextColor,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: feeCardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFC107)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Color(0xFFFFC107)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'One-time fee: ZMW $_dynamicPrice',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: primaryTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Unlock direct contact details for all listings and get premium features forever!',
                style: TextStyle(color: secondaryTextColor, height: 1.4),
              ),
              const SizedBox(height: 12),
              _buildBenefitRow(
                'Direct Call & WhatsApp Access',
                textColor: primaryTextColor,
              ),
              _buildBenefitRow(
                'Early updates of new listings',
                textColor: primaryTextColor,
              ),
              _buildBenefitRow(
                'Premium call services',
                textColor: primaryTextColor,
              ),
              _buildBenefitRow(
                'Pay once for this account, access forever',
                textColor: primaryTextColor,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: secondaryTextColor),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black87,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                _isLoggedIn ? 'Pay Now' : 'Login to Pay',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (proceed == true) {
      if (!_isLoggedIn) {
        if (!mounted) return;
        // Navigate to login and wait for result
        await context.push('/login');

        // When they return, check if they are now logged in
        if (!mounted) return;
        await _checkLoginStatus();

        // If still not logged in, just abort
        if (!_isLoggedIn) return;
      }

      if (!mounted) return;
      final profile = await ApiService.getProfile();
      final phone = profile['phone']?.toString() ?? '';
      final email = profile['email']?.toString() ?? '';
      final name = profile['name']?.toString() ?? '';

      if (!mounted) return;

      final url =
          'https://houseforrent.site/api/tenant_contact_payment.php?action=pay_page&user_id=$_currentUserId&phone=${Uri.encodeComponent(phone)}&email=${Uri.encodeComponent(email)}&name=${Uri.encodeComponent(name)}';

      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (context) => DealerPaymentWebviewScreen(url: url),
            ),
          )
          .then((_) async {
            if (mounted) {
              await _checkContactAccessStatus();
              if (_hasPaidContactAccess) {
                onPaidSuccess();
              }
            }
          });
    }
  }

  Widget _buildBenefitRow(String text, {Color textColor = Colors.black87}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 14, color: textColor)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFavorite() async {
    if (!_isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to save properties')),
      );
      return;
    }

    // Optimistic UI update
    setState(() {
      _isSaved = !_isSaved;
    });

    try {
      final response = await ApiService.toggleFavorite(
        widget.propertyId.toString(),
      );
      if (mounted) {
        setState(() {
          _isSaved = response['is_favorite'] == true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response['message'] ??
                  (_isSaved
                      ? 'Property saved!'
                      : 'Property removed from saved.'),
            ),
          ),
        );
      }
    } catch (e) {
      // Revert state on error
      if (mounted) {
        setState(() {
          _isSaved = !_isSaved;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppError.userMessage(
                e,
                fallback: 'Unable to update saved state.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch phone dialer.')),
        );
      }
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    String digitsOnly = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.startsWith('0')) {
      digitsOnly = '260${digitsOnly.substring(1)}';
    } else if (!digitsOnly.startsWith('260')) {
      digitsOnly = '260$digitsOnly';
    }

    final String normalizedPhone = '+$digitsOnly';
    final String webPhone = digitsOnly;
    final List<Uri> directChatUris = <Uri>[
      Uri.parse('whatsapp://send?phone=$normalizedPhone'),
      Uri.parse('https://api.whatsapp.com/send?phone=$webPhone'),
      Uri.parse('https://wa.me/$webPhone'),
    ];

    for (final uri in directChatUris) {
      try {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return;
      } catch (_) {
        // Keep trying the next URL format.
      }
    }

    // Last fallback: open WhatsApp without forcing a country code/recipient.
    try {
      final launched = await launchUrl(
        Uri.parse('whatsapp://send?text=Hello'),
        mode: LaunchMode.externalApplication,
      );
      if (launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp opened. Select the contact to continue.'),
          ),
        );
        return;
      }
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not launch WhatsApp. Is it installed?'),
        ),
      );
    }
  }

  Future<void> _submitInquiry() async {
    final name = _inquiryNameController.text.trim();
    final email = _inquiryEmailController.text.trim();
    final phone = _inquiryPhoneController.text.trim();
    final message = _inquiryMessageController.text.trim();

    if (name.isEmpty || email.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name, Email, and Message are required')),
      );
      return;
    }

    setState(() {
      _isSendingInquiry = true;
    });

    try {
      final response = await ApiService.sendPropertyInquiry({
        'property_id': widget.propertyId.toString(),
        'dealer_id': _property!['dealer_id']?.toString() ?? '',
        'name': name,
        'email': email,
        'phone': phone,
        'message': message,
      });

      if (mounted) {
        if (response['status'] == 'success') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Inquiry sent successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _inquiryNameController.clear();
          _inquiryEmailController.clear();
          _inquiryPhoneController.clear();
          _inquiryMessageController.clear();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Failed to send inquiry'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppError.userMessage(
                e,
                fallback: 'Unable to send inquiry. Please try again.',
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingInquiry = false;
        });
      }
    }
  }

  void _showReportForm() {
    String? selectedReason;
    final TextEditingController detailsController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10.0,
                      offset: Offset(0.0, 10.0),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.report_problem_rounded,
                          color: Colors.red.shade700,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Report Property',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F2041),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please let us know why you are reporting this listing. Your report will be kept confidential.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Reason for reporting',
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFFFC107),
                            ),
                          ),
                        ),
                        value: selectedReason,
                        items: const [
                          DropdownMenuItem(
                            value: 'scam',
                            child: Text(
                              'It looks like a scam',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'fake',
                            child: Text(
                              'Fake images or details',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'unavailable',
                            child: Text(
                              'Property is no longer available',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'inappropriate',
                            child: Text(
                              'Inappropriate content',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text(
                              'Other reason',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            selectedReason = val;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: detailsController,
                        decoration: InputDecoration(
                          labelText: 'Additional details (optional)',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFFFC107),
                            ),
                          ),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Report submitted successfully. We will investigate this shortly.',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Submit',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
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
  }

  void _showCalculator() {
    showDialog(
      context: context,
      builder: (context) {
        double amount =
            double.tryParse(_property!['price']?.toString() ?? '0') ?? 0;
        int months = 1;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text(
                'Rent Calculator',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Monthly Rent: ${_property!['currency'] ?? 'ZMW'} $amount',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Months to pay: '),
                      Expanded(
                        child: Slider(
                          value: months.toDouble(),
                          min: 1,
                          max: 12,
                          divisions: 11,
                          label: months.toString(),
                          activeColor: const Color(0xFFFFC107),
                          onChanged: (val) {
                            setState(() {
                              months = val.toInt();
                            });
                          },
                        ),
                      ),
                      Text(
                        '$months',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Estimated:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${_property!['currency'] ?? 'ZMW'} ${(amount * months).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Color(0xFF5A3D31),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showInquiryForm() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Send Inquiry',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Your Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  controller: TextEditingController(
                    text:
                        'Hi, I am interested in ${_property!['title']}. Please contact me.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black87,
              ),
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Inquiry sent successfully! The landlord will contact you soon.',
                    ),
                  ),
                );
              },
              child: const Text('Send Message'),
            ),
          ],
        );
      },
    );
  }

  void _navigateToDashboard() {
    if (_userRole == 'dealer') {
      context.go('/dealer-dashboard');
    } else {
      context.go('/tenant-dashboard');
    }
  }

  Future<void> _fetchPropertyDetails() async {
    try {
      final details = await ApiService.fetchPropertyDetails(
        widget.propertyId.toString(),
      );
      if (mounted) {
        setState(() {
          _property = details;
          _isLoading = false;
        });
        _loadLandlordRatingSummary();
        _fetchSimilarProperties();

        final videoUrl = _property!['video_url']?.toString();
        if (videoUrl != null && videoUrl.trim().isNotEmpty) {
          _initializeVideoPlayer(videoUrl);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AppError.userMessage(
            e,
            fallback: 'Unable to load property details.',
          );
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchSimilarProperties() async {
    if (_property == null) return;

    setState(() {
      _isLoadingSimilar = true;
    });

    try {
      final properties = await ApiService.fetchProperties();

      // Filter logic: same city OR same property type, excluding current property
      final currentCity = _property!['city']?.toString().toLowerCase() ?? '';
      final currentType =
          _property!['property_type']?.toString().toLowerCase() ?? '';
      final currentId = _property!['id']?.toString() ?? '';

      final zedBineTypes = ['salon', 'gadget', 'mechanic', 'other_service'];

      final similar = properties.where((p) {
        if (p['id']?.toString() == currentId) return false; // exclude self

        final pCity = p['city']?.toString().toLowerCase() ?? '';
        final pType = (p['property_type'] ?? p['type'] ?? '')
            .toString()
            .toLowerCase();

        if (zedBineTypes.contains(pType)) return false; // exclude zed bine

        return (pCity == currentCity || pType == currentType);
      }).toList();

      // Sort to randomize or take latest
      similar.shuffle();

      if (mounted) {
        setState(() {
          _similarProperties = similar.take(6).toList(); // Show up to 6
          _isLoadingSimilar = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSimilar = false;
        });
      }
    }
  }

  Future<void> _loadLandlordRatingSummary() async {
    if (_property == null) return;
    final dealerId = _property!['dealer_id']?.toString() ?? '';
    final propertyId = _property!['id']?.toString() ?? '';
    if (dealerId.isEmpty || propertyId.isEmpty) return;

    setState(() {
      _isLoadingLandlordRating = true;
    });

    try {
      final response = await ApiService.fetchLandlordRatingSummary(
        dealerId: dealerId,
        propertyId: propertyId,
      );
      final data = Map<String, dynamic>.from(response['data'] ?? {});
      final myRating = data['my_rating'];

      if (mounted) {
        setState(() {
          _averageLandlordRating =
              double.tryParse(data['average_rating']?.toString() ?? '0') ?? 0;
          _totalLandlordRatings =
              int.tryParse(data['total_ratings']?.toString() ?? '0') ?? 0;
          if (myRating is Map) {
            final parsedRating =
                double.tryParse(myRating['rating']?.toString() ?? '0') ?? 0;
            _selectedLandlordRating = parsedRating;
            _hasRatedLandlord = parsedRating > 0;
            _landlordReviewController.text = (myRating['review'] ?? '')
                .toString();
          } else {
            _selectedLandlordRating = 0;
            _hasRatedLandlord = false;
            _landlordReviewController.clear();
          }
        });
      }
    } catch (_) {
      // Optional enhancement - keep UI quiet if rating API is temporarily unavailable.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLandlordRating = false;
        });
      }
    }
  }

  Future<void> _submitLandlordRating() async {
    if (_property == null) return;
    if (!_isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to rate the landlord')),
      );
      return;
    }
    if (_selectedLandlordRating < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a rating from 1 to 5 stars'),
        ),
      );
      return;
    }

    final dealerId = _property!['dealer_id']?.toString() ?? '';
    final propertyId = _property!['id']?.toString() ?? '';
    if (dealerId.isEmpty || propertyId.isEmpty) return;

    setState(() {
      _isSubmittingLandlordRating = true;
    });

    try {
      await ApiService.submitLandlordRating(
        dealerId: dealerId,
        propertyId: propertyId,
        rating: _selectedLandlordRating.round(),
        review: _landlordReviewController.text,
      );
      if (mounted) {
        await _loadLandlordRatingSummary();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks, your rating was saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppError.userMessage(
                e,
                fallback: 'Could not save rating. Try again.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingLandlordRating = false;
        });
      }
    }
  }

  Future<void> _initializeVideoPlayer(String url) async {
    String processedUrl = url;
    if (!processedUrl.startsWith('http')) {
      if (processedUrl.startsWith('/'))
        processedUrl = processedUrl.substring(1);
      if (processedUrl.startsWith('assets/')) {
        processedUrl = 'https://houseforrent.site/$processedUrl';
      } else if (processedUrl.startsWith('uploads/')) {
        processedUrl =
            'https://houseforrent.site/php_backend/api/$processedUrl';
      } else {
        processedUrl = 'https://houseforrent.site/assets/$processedUrl';
      }
    }

    _videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(processedUrl),
    );
    try {
      await _videoPlayerController!.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: false,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      print('Video initialization failed: $e');
    }
  }

  void _openFullScreenGallery(List<String> images, int initialIndex) {
    int localIndex = initialIndex;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.black,
              insetPadding: EdgeInsets.zero,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: PageController(initialPage: initialIndex),
                    itemCount: images.length,
                    onPageChanged: (index) {
                      setDialogState(() {
                        localIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      return InteractiveViewer(
                        panEnabled: true,
                        minScale: 0.5,
                        maxScale: 4,
                        child: Image.network(
                          images[index],
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                                child: Icon(Icons.error, color: Colors.white),
                              ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 40,
                    right: 20,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 30,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  if (images.length > 1)
                    Positioned(
                      top: 40,
                      left: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${localIndex + 1} / ${images.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _shareProperty(List<String> images) async {
    if (_property == null) return;

    final title = _property!['title'] ?? 'Property';
    final currency = _property!['currency'] ?? 'ZMW';
    final price = _property!['price']?.toString() ?? '0';
    final location = _property!['city'] != null && _property!['country'] != null
        ? '${_property!['city']}, ${_property!['country']}'
        : (_property!['location'] ?? 'Unknown Location');

    final encodedId = base64Encode(
      utf8.encode(widget.propertyId.toString()),
    ).replaceAll('=', '');
    final url = 'https://houseforrent.site/property_details?id=$encodedId';
    final appDownloadUrl =
        'https://play.google.com/store/apps/details?id=com.houserent.africa';
    final imageUrl = images.isNotEmpty ? images.first : 'No image available';

    final shareText =
        'Check out this property: $title\nLocation: $location\nPrice: $currency $price\n\nImage:\n$imageUrl\n\nView details about this property here:\n$url\n\nDownload HouseRent Africa on Playstore for more amazing properties:\n$appDownloadUrl';

    if (images.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(images.first));
        if (response.statusCode == 200) {
          final directory = await getTemporaryDirectory();
          final filePath = '${directory.path}/shared_property_image.png';
          final file = File(filePath);
          await file.writeAsBytes(response.bodyBytes);

          await Share.shareXFiles(
            [XFile(filePath)],
            text: shareText,
            subject: 'Check out this property: $title',
          );
          return;
        }
      } catch (e) {
        debugPrint('Error downloading image for sharing: $e');
      }
    }

    // Fallback to text only if no images or download fails
    Share.share(shareText, subject: 'Check out this property: $title');
  }

  Future<void> _shareToWhatsApp(List<String> images) async {
    if (_property == null) return;

    final title = _property!['title'] ?? 'Property';
    final currency = _property!['currency'] ?? 'ZMW';
    final price = _property!['price']?.toString() ?? '0';
    final location = _property!['city'] != null && _property!['country'] != null
        ? '${_property!['city']}, ${_property!['country']}'
        : (_property!['location'] ?? 'Unknown Location');

    final encodedId = base64Encode(
      utf8.encode(widget.propertyId.toString()),
    ).replaceAll('=', '');
    final url = 'https://houseforrent.site/property_details?id=$encodedId';
    final appDownloadUrl =
        'https://play.google.com/store/apps/details?id=com.houserent.africa';

    final shareText =
        '*Check out this property: $title*\n📍 Location: $location\n💰 Price: $currency $price\n\n🔗 View details about this property here:\n$url\n\n📱 Download HouseRent Africa on Playstore for more amazing properties:\n$appDownloadUrl';

    if (images.isNotEmpty) {
      try {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Preparing image for WhatsApp...')),
          );
        }
        final response = await http.get(Uri.parse(images.first));
        if (response.statusCode == 200) {
          final directory = await getTemporaryDirectory();
          final filePath = '${directory.path}/shared_property_image.png';
          final file = File(filePath);
          await file.writeAsBytes(response.bodyBytes);

          await Share.shareXFiles(
            [XFile(filePath)],
            text: shareText,
            subject: 'Check out this property: $title',
          );
          return;
        }
      } catch (e) {
        debugPrint('Error downloading image for sharing: $e');
      }

    }

    // Fallback to text only if no images or download fails
    final whatsappUrl = Uri.parse(
      'whatsapp://send?text=${Uri.encodeComponent(shareText)}',
    );

    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not launch WhatsApp. Is it installed?'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not launch WhatsApp. Is it installed?'),
          ),
        );
      }
    }
  }

  Widget _buildDetailsSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFFFC107),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            SkeletonBox(
              height: 320,
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            SizedBox(height: 16),
            SkeletonBox(height: 24, width: 260),
            SizedBox(height: 10),
            SkeletonBox(height: 18, width: 140),
            SizedBox(height: 8),
            SkeletonBox(height: 16, width: 180),
            SizedBox(height: 20),
            SkeletonBox(
              height: 110,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            SizedBox(height: 14),
            SkeletonBox(
              height: 110,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            SizedBox(height: 14),
            SkeletonBox(
              height: 140,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            SizedBox(height: 14),
            SkeletonBox(
              height: 220,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            activeIcon: Icon(Icons.favorite),
            label: 'Saved',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.campaign_outlined),
            activeIcon: Icon(Icons.campaign),
            label: 'House Request',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_none),
            activeIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        currentIndex: 0,
        selectedItemColor: const Color(0xFFFFC107),
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return _buildDetailsSkeleton();
    }

    if (_property == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: isDark
              ? const Color(0xFF1E1E1E)
              : const Color(0xFFFFC107),
        ),
        body: const Center(child: Text('Property not found')),
      );
    }

    // Map over images to get valid URLs
    final List<String> images = [];

    String processUrl(String raw) {
      String imageUrl = raw.replaceAll('`', '').trim();
      if (!imageUrl.startsWith('http')) {
        if (imageUrl.startsWith('/')) imageUrl = imageUrl.substring(1);
        if (imageUrl.startsWith('assets/')) {
          imageUrl = 'https://houseforrent.site/$imageUrl';
        } else if (imageUrl.startsWith('uploads/')) {
          imageUrl = 'https://houseforrent.site/php_backend/api/$imageUrl';
        } else {
          imageUrl = 'https://houseforrent.site/assets/$imageUrl';
        }
      }
      return imageUrl;
    }

    if (_property!['main_image'] != null &&
        _property!['main_image'].toString().trim().isNotEmpty) {
      images.add(processUrl(_property!['main_image'].toString()));
    }

    if (_property!['images'] != null) {
      for (var img in _property!['images']) {
        String rawUrl = '';
        if (img is Map && img['url'] != null) {
          rawUrl = img['url'].toString();
        } else if (img is String) {
          rawUrl = img;
        }
        if (rawUrl.trim().isNotEmpty) {
          String pUrl = processUrl(rawUrl);
          if (!images.contains(pUrl)) {
            images.add(pUrl);
          }
        }
      }
    }
    final hasImages = images.isNotEmpty;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFFFC107),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? const Color(0xFFFFC107) : Colors.white,
          ),
          onPressed: () => context.pop(),
        ),
        title: GestureDetector(
          onTap: () => context.go('/home'),
          child: AppBrand(
            textColor: isDark ? const Color(0xFFFFC107) : Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: _buildNotificationIcon(
              active: false,
              iconColor: isDark ? const Color(0xFFFFC107) : Colors.white,
            ),
            tooltip: 'Notifications',
            onPressed: () {
              context.go('/public-notifications');
            },
          ),
          if (_isLoggedIn)
            Builder(
              builder: (context) {
                final isNarrow = MediaQuery.of(context).size.width < 430;
                final firstName = _userName.split(' ').first;
                if (isNarrow) {
                  return IconButton(
                    icon: Icon(
                      Icons.person,
                      color: isDark ? const Color(0xFFFFC107) : Colors.white,
                    ),
                    tooltip: 'Dashboard',
                    onPressed: _navigateToDashboard,
                  );
                }
                return TextButton.icon(
                  onPressed: _navigateToDashboard,
                  icon: Icon(
                    Icons.person,
                    color: isDark ? const Color(0xFFFFC107) : Colors.white,
                  ),
                  label: Text(
                    'Hi, ${firstName.length > 10 ? '${firstName.substring(0, 10)}…' : firstName}',
                    style: TextStyle(
                      color: isDark ? const Color(0xFFFFC107) : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          IconButton(
            icon: Icon(
              _isSaved ? Icons.favorite : Icons.favorite_border,
              color: _isSaved
                  ? Colors.red
                  : (isDark ? const Color(0xFFFFC107) : Colors.white),
            ),
            onPressed: _toggleFavorite,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Gallery Section
            Container(
              height: 280,
              width: double.infinity,
              color: Colors.black,
              child: hasImages
                  ? Stack(
                      children: [
                        PageView.builder(
                          controller: _pageController,
                          itemCount: images.length,
                          onPageChanged: (index) {
                            setState(() {
                              _currentImageIndex = index;
                            });
                          },
                          itemBuilder: (context, index) {
                            return GestureDetector(
                              onTap: () =>
                                  _openFullScreenGallery(images, index),
                              child: Image.network(
                                images[index],
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Center(
                                      child: Icon(
                                        Icons.image,
                                        size: 100,
                                        color: Colors.white24,
                                      ),
                                    ),
                              ),
                            );
                          },
                        ),

                        if (['taken', 'rented', 'sold'].contains(
                          _property!['status']?.toString().toLowerCase() ?? '',
                        ))
                          Positioned.fill(
                            child: ClipRRect(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 5.0,
                                  sigmaY: 5.0,
                                ),
                                child: Container(
                                  color: Colors.white.withOpacity(0.3),
                                  alignment: Alignment.center,
                                  child: Builder(
                                    builder: (context) {
                                      final pType =
                                          (_property!['property_type']
                                                      ?.toString() ??
                                                  '')
                                              .toLowerCase();
                                      final purposeKey = _purposeKey(
                                        _property!,
                                        pType,
                                      );
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade700
                                              .withOpacity(0.9),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.3,
                                              ),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          purposeKey == 'sale'
                                              ? 'SOLD'
                                              : 'RENTED',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Top Left Status Badge (Removed since we have a center badge now)
                        if (!['taken', 'rented', 'sold'].contains(
                          _property!['status']?.toString().toLowerCase() ??
                              'available',
                        ))
                          Positioned(
                            top: 16,
                            left: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade800,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                (_property!['status'] ?? 'Available')
                                    .toString()
                                    .toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),

                        // Bottom Left Price Badge
                        Positioned(
                          bottom: 16,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade800,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Builder(
                              builder: (context) {
                                final pType =
                                    (_property!['property_type']?.toString() ??
                                            '')
                                        .toLowerCase();
                                final purposeKey = _purposeKey(
                                  _property!,
                                  pType,
                                );
                                final suffix = purposeKey == 'service'
                                    ? ' per service'
                                    : (purposeKey == 'rent' ? '/month' : '');
                                return Text(
                                  '${_property!['currency'] ?? 'ZMW'} ${_property!['price'] ?? '0'}$suffix',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // Thumbnails on the right
                        if (images.length > 1)
                          Positioned(
                            right: 16,
                            top: 16,
                            bottom: 16,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (
                                  int i = 0;
                                  i <
                                      (images.length > 4
                                          ? 3
                                          : images.length - 1);
                                  i++
                                )
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8.0),
                                    child: GestureDetector(
                                      onTap: () {
                                        _pageController.animateToPage(
                                          i + 1,
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          curve: Curves.easeInOut,
                                        );
                                      },
                                      child: Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.5,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          image: DecorationImage(
                                            image: NetworkImage(images[i + 1]),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (images.length > 4)
                                  GestureDetector(
                                    onTap: () {
                                      _openFullScreenGallery(images, 4);
                                    },
                                    child: Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                        image: DecorationImage(
                                          image: NetworkImage(images[4]),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.6),
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '+${images.length - 4}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    )
                  : const Center(
                      child: Icon(
                        Icons.image,
                        size: 100,
                        color: Colors.white24,
                      ),
                    ),
            ),

            // Content Section
            Padding(
              padding:
                  EdgeInsets.zero, // Removed padding so it touches the edges
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Determine if the screen is wide enough for a row layout, otherwise use a column
                  final isWideScreen = constraints.maxWidth > 900;

                  final title = _property!['title'] ?? 'Unknown Property';
                  final ref =
                      '#${_property!['id']?.toString().padLeft(6, '0') ?? '000000'}';
                  // Purpose moves down below typeLower
                  final location =
                      _property!['city'] != null &&
                          _property!['country'] != null
                      ? '${_property!['city']}, ${_property!['country']}'
                      : (_property!['location'] ?? 'Unknown Location');
                  final beds = _property!['bedrooms']?.toString() ?? '';
                  final baths = _property!['bathrooms']?.toString() ?? '';
                  final size =
                      _property!['size_sqm']?.toString() ??
                      _property!['size']?.toString() ??
                      '';
                  final type =
                      (_property!['property_type']?.toString() ?? 'House')
                          .trim();
                  final typeLower = type.toLowerCase();
                  final purposeKey = _purposeKey(_property!, typeLower);
                  final purpose = _purposeLabel(purposeKey);
                  final isService = purposeKey == 'service';

                  final rooms = _property!['rooms']?.toString() ?? '';
                  final capacity = _property!['capacity']?.toString() ?? '';
                  final eventType = _property!['event_type']?.toString() ?? '';
                  final peoplePerRoom =
                      _property!['people_per_room']?.toString() ?? '';
                  final description =
                      _property!['description'] ?? 'No description provided.';
                  final amenitiesStr =
                      _property!['amenities']?.toString() ?? '';
                  final amenities = amenitiesStr.isNotEmpty
                      ? amenitiesStr.split(',').map((e) => e.trim()).toList()
                      : [];
                  final currency = _property!['currency'] ?? 'ZMW';
                  final price = _property!['price']?.toString() ?? '0';

                  final mainContent = Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      // Removed border radius and borders so it touches edges cleanly on mobile
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.blue.withOpacity(0.2)
                                    : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.blue.withOpacity(0.5)
                                      : Colors.blue.shade100,
                                ),
                              ),
                              child: Text(
                                purpose,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.lightBlueAccent
                                      : Colors.blue,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              'Ref: $ref',
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F2041),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                location,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        Text(
                          'Overview',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F2041),
                          ),
                        ),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, boxConstraints) {
                            final cardWidth =
                                (boxConstraints.maxWidth - 16) / 3;
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (typeLower == 'apartment' ||
                                    typeLower == 'house') ...[
                                  if (beds.isNotEmpty && beds != '0')
                                    SizedBox(
                                      width: cardWidth,
                                      child: _FeatureCard(
                                        icon: Icons.bed,
                                        label: '$beds Bed',
                                      ),
                                    ),
                                  if (baths.isNotEmpty && baths != '0')
                                    SizedBox(
                                      width: cardWidth,
                                      child: _FeatureCard(
                                        icon: Icons.bathtub,
                                        label: '$baths Bath',
                                      ),
                                    ),
                                ] else if (typeLower.contains('boarding')) ...[
                                  if (capacity.isNotEmpty && capacity != '0')
                                    SizedBox(
                                      width: cardWidth,
                                      child: _FeatureCard(
                                        icon: Icons.group,
                                        label: 'Cap: $capacity',
                                      ),
                                    ),
                                  if (peoplePerRoom.isNotEmpty &&
                                      peoplePerRoom != '0')
                                    SizedBox(
                                      width: cardWidth,
                                      child: _FeatureCard(
                                        icon: Icons.person,
                                        label: '$peoplePerRoom/Rm',
                                      ),
                                    ),
                                ] else if (typeLower.contains('wedding') ||
                                    typeLower.contains('studio')) ...[
                                  if (capacity.isNotEmpty && capacity != '0')
                                    SizedBox(
                                      width: cardWidth,
                                      child: _FeatureCard(
                                        icon: Icons.groups,
                                        label: 'Cap: $capacity',
                                      ),
                                    ),
                                  if (eventType.isNotEmpty)
                                    SizedBox(
                                      width: cardWidth,
                                      child: _FeatureCard(
                                        icon: Icons.event,
                                        label: eventType,
                                      ),
                                    ),
                                ] else ...[
                                  if (rooms.isNotEmpty && rooms != '0')
                                    SizedBox(
                                      width: cardWidth,
                                      child: _FeatureCard(
                                        icon: Icons.door_front_door,
                                        label: '$rooms Rooms',
                                      ),
                                    ),
                                ],
                                if (size.isNotEmpty && size != '0')
                                  SizedBox(
                                    width: cardWidth,
                                    child: _FeatureCard(
                                      icon: Icons.square_foot,
                                      label: '${size}m²',
                                    ),
                                  ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _FeatureCard(
                                    icon: Icons.home,
                                    label: type,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 32),
                        const Divider(),
                        const SizedBox(height: 32),

                        Text(
                          'Description',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F2041),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.6,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),

                        const SizedBox(height: 32),
                        const Divider(),
                        const SizedBox(height: 32),

                        if (amenities.isNotEmpty) ...[
                          Text(
                            'Amenities',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F2041),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: amenities
                                .map((a) => _buildAmenityChip(a))
                                .toList(),
                          ),
                        ],

                        if (_chewieController != null) ...[
                          const SizedBox(height: 32),
                          const Divider(),
                          const SizedBox(height: 32),
                          Text(
                            'Property Video',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color:
                                  Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color ??
                                  const Color(0xFF0F2041),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            height: 250,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.black,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Chewie(controller: _chewieController!),
                            ),
                          ),
                        ],

                        const SizedBox(height: 40),
                      ],
                    ),
                  );

                  final sidebarContent = Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: isDark
                                        ? Colors.red.shade400
                                        : Colors.red.shade700,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Caution',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? Colors.red.shade300
                                                : Colors.red.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Do not make any payments before verifying the property in person. For your safety, make sure to go with at least two people. If you find this listing to be fake, please report it immediately.',
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.red.shade200
                                                : Colors.red.shade900,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        InkWell(
                                          onTap: _showReportForm,
                                          child: Text(
                                            'Report Property',
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.red.shade300
                                                  : Colors.red.shade700,
                                              fontWeight: FontWeight.bold,
                                              decoration:
                                                  TextDecoration.underline,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Listing Owner',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white54 : Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildOwnerCard(),
                            const SizedBox(height: 16),
                            _buildLandlordRatingCard(),
                            const SizedBox(height: 20),
                            Text(
                              'Price',
                              style: TextStyle(
                                fontSize: 16,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.end,
                              children: [
                                Text(
                                  '$currency $price',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFFC107),
                                  ),
                                ),
                                if (purposeKey == 'service')
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 6.0,
                                      left: 4.0,
                                    ),
                                    child: Text(
                                      'per service',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black54,
                                        fontSize: 16,
                                      ),
                                    ),
                                  )
                                else if (purposeKey == 'rent')
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 6.0,
                                      left: 4.0,
                                    ),
                                    child: Text(
                                      '/ month',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black54,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 32),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 50,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        if (!_hasPaidContactAccess) {
                                          _showContactAccessPrompt(() {
                                            final dealerPhone =
                                                _property!['dealer_phone']
                                                    ?.toString() ??
                                                _property!['dealer']?['phone']
                                                    ?.toString() ??
                                                '';
                                            _makePhoneCall(dealerPhone);
                                          });
                                        } else {
                                          final dealerPhone =
                                              _property!['dealer_phone']
                                                  ?.toString() ??
                                              _property!['dealer']?['phone']
                                                  ?.toString() ??
                                              '';
                                          _makePhoneCall(dealerPhone);
                                        }
                                      },
                                      icon: const Icon(Icons.phone, size: 20),
                                      label: const Text(
                                        'Call',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFFFC107,
                                        ), // Yellow
                                        foregroundColor: Colors.black87,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SizedBox(
                                    height: 50,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        if (!_hasPaidContactAccess) {
                                          _showContactAccessPrompt(() {
                                            final dealerPhone =
                                                _property!['dealer_phone']
                                                    ?.toString() ??
                                                _property!['dealer']?['phone']
                                                    ?.toString() ??
                                                '';
                                            _openWhatsApp(dealerPhone);
                                          });
                                        } else {
                                          final dealerPhone =
                                              _property!['dealer_phone']
                                                  ?.toString() ??
                                              _property!['dealer']?['phone']
                                                  ?.toString() ??
                                              '';
                                          _openWhatsApp(dealerPhone);
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.chat,
                                        size: 20,
                                      ), // generic chat icon representing whatsapp
                                      label: const Text(
                                        'WhatsApp',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF25D366,
                                        ), // WhatsApp Green
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: () => _shareToWhatsApp(images),
                                icon: const Icon(
                                  Icons.share,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  'Share to WhatsApp',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF25D366),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: _toggleFavorite,
                                icon: Icon(
                                  _isSaved
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 22,
                                ),
                                label: Text(
                                  _isSaved ? 'Saved' : 'Save Property',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  backgroundColor: _isSaved
                                      ? (isDark
                                          ? const Color(0xFF3A1F24)
                                          : const Color(0xFFFFEBEE))
                                      : (isDark
                                          ? const Color(0xFF2A2A2A)
                                          : const Color(0xFFF7F7F8)),
                                  foregroundColor: _isSaved
                                      ? (isDark
                                          ? const Color(0xFFFF8A80)
                                          : Colors.red.shade700)
                                      : (isDark
                                          ? Colors.white
                                          : Colors.black87),
                                  side: BorderSide(
                                    color: _isSaved
                                        ? (isDark
                                            ? const Color(0xFFFF8A80)
                                                .withValues(alpha: 0.45)
                                            : Colors.red.shade200)
                                        : (isDark
                                            ? Colors.white12
                                            : Colors.grey.shade300),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Inquiry Form (Collapsible Drop Box)
                      Builder(
                        builder: (context) {
                          final fieldFill = isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey.shade50;
                          final fieldBorder = OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.white12
                                  : Colors.transparent,
                            ),
                          );
                          final fieldFocused = OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFFFFC107),
                              width: 1.4,
                            ),
                          );
                          final fieldText = isDark
                              ? Colors.white
                              : Colors.black87;
                          final fieldHint = isDark
                              ? Colors.white38
                              : Colors.black38;

                          InputDecoration inquiryField(String hint) {
                            return InputDecoration(
                              hintText: hint,
                              hintStyle: TextStyle(
                                color: fieldHint,
                                fontWeight: FontWeight.w500,
                              ),
                              filled: true,
                              fillColor: fieldFill,
                              border: fieldBorder,
                              enabledBorder: fieldBorder,
                              focusedBorder: fieldFocused,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            );
                          }

                          return Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1E1E1E)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white12
                                    : Colors.grey.shade200,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: isDark ? 0.25 : 0.02,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                                splashColor: const Color(0xFFFFC107)
                                    .withValues(alpha: 0.12),
                                highlightColor: const Color(0xFFFFC107)
                                    .withValues(alpha: 0.06),
                              ),
                              child: ExpansionTile(
                                collapsedIconColor: isDark
                                    ? Colors.white54
                                    : Colors.black45,
                                iconColor: const Color(0xFFFFC107),
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 8,
                                ),
                                title: Text(
                                  'Request Details',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1F2937),
                                  ),
                                ),
                                subtitle: Text(
                                  'Send a message to the landlord',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black54,
                                  ),
                                ),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFC107)
                                        .withValues(alpha: isDark ? 0.22 : 0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.mail_outline,
                                    color: isDark
                                        ? const Color(0xFFFFC107)
                                        : const Color(0xFF5A3D31),
                                  ),
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      4,
                                      20,
                                      20,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Divider(
                                          height: 1,
                                          color: isDark
                                              ? Colors.white12
                                              : Colors.grey.shade200,
                                        ),
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: _inquiryNameController,
                                          style: TextStyle(
                                            color: fieldText,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          cursorColor: const Color(0xFFFFC107),
                                          decoration: inquiryField('Your Name'),
                                        ),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                          controller: _inquiryEmailController,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          style: TextStyle(
                                            color: fieldText,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          cursorColor: const Color(0xFFFFC107),
                                          decoration: inquiryField(
                                            'Email Address',
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                          controller: _inquiryPhoneController,
                                          keyboardType: TextInputType.phone,
                                          style: TextStyle(
                                            color: fieldText,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          cursorColor: const Color(0xFFFFC107),
                                          decoration: inquiryField(
                                            'Phone Number',
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        TextFormField(
                                          controller: _inquiryMessageController,
                                          maxLines: 4,
                                          style: TextStyle(
                                            color: fieldText,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          cursorColor: const Color(0xFFFFC107),
                                          decoration: inquiryField(
                                            'I am interested in this property...',
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 50,
                                          child: StatefulBuilder(
                                            builder: (context, setStateButton) {
                                              return ElevatedButton(
                                                onPressed: _isSendingInquiry
                                                    ? null
                                                    : () async {
                                                        setStateButton(
                                                          () =>
                                                              _isSendingInquiry =
                                                                  true,
                                                        );
                                                        await _submitInquiry();
                                                        if (mounted) {
                                                          setStateButton(
                                                            () =>
                                                                _isSendingInquiry =
                                                                    false,
                                                          );
                                                        }
                                                      },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      const Color(0xFFFFC107),
                                                  foregroundColor:
                                                      Colors.black87,
                                                  disabledBackgroundColor:
                                                      isDark
                                                      ? const Color(0xFF333333)
                                                      : Colors.grey.shade300,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  elevation: 0,
                                                ),
                                                child: _isSendingInquiry
                                                    ? const SizedBox(
                                                        height: 20,
                                                        width: 20,
                                                        child:
                                                            CircularProgressIndicator(
                                                              color: Colors
                                                                  .black87,
                                                              strokeWidth: 2,
                                                            ),
                                                      )
                                                    : const Text(
                                                        'Send Inquiry',
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                              );
                                            },
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

                      const SizedBox(height: 24),

                      // Map location preview widget
                      Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child:
                              (!kIsWeb &&
                                  (Platform.isAndroid || Platform.isIOS))
                              ? GoogleMap(
                                  initialCameraPosition: CameraPosition(
                                    target: LatLng(
                                      double.tryParse(
                                            _property!['latitude']
                                                    ?.toString() ??
                                                '-15.3875',
                                          ) ??
                                          -15.3875,
                                      double.tryParse(
                                            _property!['longitude']
                                                    ?.toString() ??
                                                '28.3228',
                                          ) ??
                                          28.3228,
                                    ),
                                    zoom: 14.0,
                                  ),
                                  myLocationEnabled: false,
                                  zoomControlsEnabled: true,
                                  scrollGesturesEnabled: true,
                                  zoomGesturesEnabled: true,
                                  markers: {
                                    Marker(
                                      markerId: const MarkerId(
                                        'property_location',
                                      ),
                                      position: LatLng(
                                        double.tryParse(
                                              _property!['latitude']
                                                      ?.toString() ??
                                                  '-15.3875',
                                            ) ??
                                            -15.3875,
                                        double.tryParse(
                                              _property!['longitude']
                                                      ?.toString() ??
                                                  '28.3228',
                                            ) ??
                                            28.3228,
                                      ),
                                    ),
                                  },
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    image: DecorationImage(
                                      image: NetworkImage(
                                        'https://maps.googleapis.com/maps/api/staticmap?center=${_property!['latitude'] ?? '-15.3875'},${_property!['longitude'] ?? '28.3228'}&zoom=14&size=400x200&markers=color:red%7C${_property!['latitude'] ?? '-15.3875'},${_property!['longitude'] ?? '28.3228'}&key=AIzaSyDH0JpnMofvCFnx9byn6TUm_GV6YW9onZU',
                                      ),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 40),

                      // Similar Properties Section
                      if (_isLoadingSimilar)
                        const Center(child: CircularProgressIndicator())
                      else if (_similarProperties.isNotEmpty) ...[
                        Text(
                          'You might also like...',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color ??
                                const Color(0xFF0F2041),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 310,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _similarProperties.length,
                            itemBuilder: (context, index) {
                              return Container(
                                width:
                                    MediaQuery.of(context).size.width * 0.75 >
                                        320
                                    ? 320
                                    : MediaQuery.of(context).size.width * 0.75,
                                margin: const EdgeInsets.only(
                                  right: 16.0,
                                  bottom: 8.0,
                                ),
                                child: PropertyCard(
                                  property: _similarProperties[index],
                                  isFeatured: false,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  );

                  if (isWideScreen) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: mainContent),
                        const SizedBox(width: 32),
                        Expanded(flex: 1, child: sidebarContent),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        mainContent,
                        const SizedBox(height: 24),
                        sidebarContent,
                      ],
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
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
        currentIndex: 0,
        selectedItemColor: const Color(0xFFFFC107),
        unselectedItemColor:
            Theme.of(context).bottomNavigationBarTheme.unselectedItemColor ??
            Colors.grey,
        backgroundColor:
            Theme.of(context).bottomNavigationBarTheme.backgroundColor ??
            Colors.white,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 0) {
            context.go('/home');
          } else if (index == 1) {
            if (_isLoggedIn) {
              if (_userRole == 'tenant' ||
                  _userRole == 'user' ||
                  _userRole.isEmpty) {
                context.go('/tenant-dashboard', extra: {'tab': 4});
              } else if (_userRole == 'dealer') {
                context.go('/dealer-dashboard');
              }
            } else {
              _showLoginRequiredPopup();
            }
          } else if (index == 2) {
            if (_isLoggedIn) {
              context.go('/tenant-requests');
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
            if (_isLoggedIn) {
              if (_userRole == 'dealer') {
                context.go('/dealer-dashboard');
              } else {
                context.go('/tenant-dashboard', extra: {'tab': 3});
              }
            } else {
              context.go('/login');
            }
          }
        },
      ),
    );
  }

  Widget _buildAmenityChip(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 12),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationIcon({
    required bool active,
    double iconSize = 24,
    Color? iconColor,
  }) {
    final icon = Icon(
      active ? Icons.notifications : Icons.notifications_none,
      color: iconColor,
      size: iconSize,
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

  Widget _buildOwnerCard() {
    if (_property == null) return const SizedBox.shrink();
    final ownerName = (_property!['dealer_name'] ?? 'Listing owner').toString();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFFFC107).withOpacity(0.25),
                child: const Icon(Icons.person, color: Color(0xFFFFC107)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ownerName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Landlord Rating Summary
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade300,
              ),
            ),
            child: Row(
              children: [
                // Stars
                ...List.generate(
                  5,
                  (index) => Icon(
                    index < _averageLandlordRating.round()
                        ? Icons.star
                        : Icons.star_border,
                    color: const Color(0xFFFFC107),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                // Rating value and count
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _averageLandlordRating > 0
                          ? '${_averageLandlordRating.toStringAsFixed(1)}'
                          : 'Not rated',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark
                            ? const Color(0xFFFFC107)
                            : const Color(0xFF5A3D31),
                      ),
                    ),
                    if (_totalLandlordRatings > 0)
                      Text(
                        '${_totalLandlordRatings} ${_totalLandlordRatings == 1 ? 'rating' : 'ratings'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandlordRatingCard() {
    if (_property == null) return const SizedBox.shrink();
    final dealerId = _property!['dealer_id']?.toString() ?? '';
    final isOwnerViewingOwnListing =
        _isLoggedIn && _currentUserId.isNotEmpty && _currentUserId == dealerId;
    final canRate = _isLoggedIn && !isOwnerViewingOwnListing;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rate Landlord',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          if (_isLoadingLandlordRating)
            const LinearProgressIndicator(minHeight: 2)
          else
            Row(
              children: [
                ...List.generate(
                  5,
                  (index) => Icon(
                    index < _averageLandlordRating.round()
                        ? Icons.star
                        : Icons.star_border,
                    color: const Color(0xFFFFC107),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _totalLandlordRatings > 0
                      ? '${_averageLandlordRating.toStringAsFixed(1)} ($_totalLandlordRatings)'
                      : 'Not rated yet',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          const SizedBox(height: 12),
          if (canRate)
            Text(
              _hasRatedLandlord
                  ? 'You have already rated this landlord.'
                  : 'You have not rated this landlord yet.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          if (canRate) const SizedBox(height: 8),
          if (!canRate)
            Text(
              _isLoggedIn
                  ? 'You cannot rate your own listing.'
                  : 'Login to rate this landlord.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            )
          else ...[
            Row(
              children: List.generate(5, (index) {
                final star = index + 1;
                return IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedLandlordRating = star.toDouble();
                    });
                  },
                  icon: Icon(
                    star <= _selectedLandlordRating
                        ? Icons.star
                        : Icons.star_border,
                    color: const Color(0xFFFFC107),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  padding: const EdgeInsets.all(0),
                  visualDensity: VisualDensity.compact,
                );
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _landlordReviewController,
              maxLines: 2,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Write a short review (optional)',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1E1E1E)
                    : Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmittingLandlordRating
                    ? null
                    : _submitLandlordRating,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107),
                  foregroundColor: Colors.black87,
                ),
                child: _isSubmittingLandlordRating
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black87,
                        ),
                      )
                    : const Text('Submit Rating'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureCard({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFFFFC107), size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
