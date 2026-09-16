import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class HomeBannerItem {
  const HomeBannerItem({
    required this.imageUrl,
    this.title = '',
    this.subtitle = '',
    this.linkUrl = '',
    this.text = '',
  });

  final String imageUrl;
  final String title;
  final String subtitle;
  final String linkUrl;
  final String text;

  bool get hasImage => imageUrl.isNotEmpty;
}

class ApiService {
  // Use the live production server URL
  static String get baseUrl {
    const String productionUrl = 'https://houseforrent.site/php_backend/api';
    return productionUrl;
  }

  static Future<Map<String, dynamic>> uploadVerificationDocument(
    String userId,
    String filePath,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final role = (prefs.getString('role') ?? 'dealer').toLowerCase();

    final endpoint = role == 'agent'
        ? '$baseUrl/agent_company/check_status_agent.php'
        : role == 'company'
            ? '$baseUrl/agent_company/check_status_company.php'
            : '$baseUrl/dealer/check_status.php';

    var request = http.MultipartRequest('POST', Uri.parse(endpoint));
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['action'] = 'upload_verification';
    request.fields['user_id'] = userId;

    request.files.add(await http.MultipartFile.fromPath('document', filePath));

    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);

    Map<String, dynamic> decoded = {};
    try {
      final raw = jsonDecode(response.body);
      if (raw is Map<String, dynamic>) {
        decoded = raw;
      } else if (raw is Map) {
        decoded = Map<String, dynamic>.from(raw);
      }
    } catch (_) {}

    if (response.statusCode == 200) {
      return decoded.isNotEmpty
          ? decoded
          : {'status': 'error', 'message': 'Invalid server response'};
    }

    final msg = decoded['message']?.toString() ?? 'Failed to upload document';
    throw Exception(msg);
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'login',
          'email': email,
          'password': password,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'error') {
          return data;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'token',
          data['user']['token'] ?? data['token'] ?? '',
        );
        await prefs.setString(
          'role',
          (data['user']['role'] ?? data['role'] ?? '').toString().trim(),
        );
        // Cache user_id so other endpoints don't need to re-call getProfile()
        final userId =
            data['user']['id']?.toString() ?? data['id']?.toString() ?? '';
        if (userId.isNotEmpty) await prefs.setString('user_id', userId);
        final userName =
            data['user']['name']?.toString() ?? data['name']?.toString() ?? '';
        if (userName.isNotEmpty) await prefs.setString('user_name', userName);
        final phone =
            data['user']['phone']?.toString() ?? data['phone']?.toString() ?? '';
        if (phone.isNotEmpty) await prefs.setString('phone', phone);
        return data;
      } else {
        throw Exception('Server error');
      }
    } catch (e) {
      throw Exception('Please check your internet connection and try again.');
    }
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/public/send_password_reset.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'forgot_password', 'email': email}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Server error');
      }
    } catch (e) {
      throw Exception('Please check your internet connection and try again.');
    }
  }

  static Future<Map<String, dynamic>> resendVerification(
    String email, {
    String name = 'User',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/public/send_verification.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'name': name}),
      );
      final rawBody = response.body.trim();
      if (rawBody.isEmpty) {
        throw Exception('Server returned an empty response.');
      }
      final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return decoded;
      }
      throw Exception(
        decoded['message']?.toString() ?? 'Failed to resend verification email',
      );
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Please check your internet connection and try again.');
    }
  }

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
    required String role,
    required String phone,
    String referralCode = '',
    String vehicleType = '',
    String vehicleCapacity = '',
    String serviceArea = '',
  }) async {
    // Agent + private company use dedicated APIs (landlord/dealer stays on register.php).
    if (role == 'agent') {
      return registerAgent(
        name: name,
        email: email,
        password: password,
        confirmPassword: confirmPassword,
        phone: phone,
        referralCode: referralCode,
      );
    }
    if (role == 'company') {
      return registerCompany(
        name: name,
        email: email,
        password: password,
        confirmPassword: confirmPassword,
        phone: phone,
        referralCode: referralCode,
      );
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'email': email,
          'password': password,
          'confirm_password': confirmPassword,
          'role': role,
          'phone': phone,
          if (referralCode.trim().isNotEmpty)
            'referral_code': referralCode.trim().toUpperCase(),
          if (vehicleType.trim().isNotEmpty) 'vehicle_type': vehicleType.trim(),
          if (vehicleCapacity.trim().isNotEmpty)
            'vehicle_capacity': vehicleCapacity.trim(),
          if (serviceArea.trim().isNotEmpty) 'service_area': serviceArea.trim(),
        }),
      );
      final rawBody = response.body.trim();
      if (rawBody.isEmpty) {
        throw Exception('Registration is temporarily unavailable. Please try again.');
      }
      final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
      if (response.statusCode == 200 || response.statusCode == 201) {
        return decoded;
      }
      throw Exception(
        decoded['message']?.toString() ?? 'Registration failed',
      );
    } catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('formatexception') ||
          text.contains('clientexception') ||
          text.contains('socketexception') ||
          text.contains('http://') ||
          text.contains('https://') ||
          text.contains('houseforrent.site') ||
          text.contains('php_backend') ||
          text.contains('uri=')) {
        throw Exception('Registration failed. Please try again.');
      }
      if (e is Exception) rethrow;
      throw Exception('Please check your internet connection and try again.');
    }
  }

  static Future<Map<String, dynamic>> registerAgent({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
    required String phone,
    String referralCode = '',
  }) async {
    return _postAgentCompanyRegister(
      '$baseUrl/agent_company/register_agent.php',
      {
        'name': name,
        'email': email,
        'password': password,
        'confirm_password': confirmPassword,
        'phone': phone,
        if (referralCode.trim().isNotEmpty)
          'referral_code': referralCode.trim().toUpperCase(),
      },
    );
  }

  static Future<Map<String, dynamic>> registerCompany({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
    required String phone,
    String referralCode = '',
  }) async {
    return _postAgentCompanyRegister(
      '$baseUrl/agent_company/register_company.php',
      {
        'name': name,
        'email': email,
        'password': password,
        'confirm_password': confirmPassword,
        'phone': phone,
        if (referralCode.trim().isNotEmpty)
          'referral_code': referralCode.trim().toUpperCase(),
      },
    );
  }

  static Future<Map<String, dynamic>> _postAgentCompanyRegister(
    String url,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      final rawBody = response.body.trim();
      if (rawBody.isEmpty) {
        throw Exception('Registration is temporarily unavailable. Please try again.');
      }
      final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
      if (response.statusCode == 200 || response.statusCode == 201) {
        return decoded;
      }
      throw Exception(decoded['message']?.toString() ?? 'Registration failed');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Please check your internet connection and try again.');
    }
  }

  static Future<Map<String, dynamic>> checkAgentStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final response = await http.post(
      Uri.parse('$baseUrl/agent_company/check_status_agent.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to check agent status: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> checkCompanyStatus({
    String action = 'get_status',
    Map<String, dynamic>? extra,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final response = await http.post(
      Uri.parse('$baseUrl/agent_company/check_status_company.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'action': action, ...?extra}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to check company status: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> saveCompanyDetails({
    required String companyName,
    required String companyRegNo,
    required String companyAddress,
    required String companyContact,
  }) async {
    return checkCompanyStatus(
      action: 'save_company_details',
      extra: {
        'company_name': companyName,
        'company_reg_no': companyRegNo,
        'company_address': companyAddress,
        'company_contact': companyContact,
      },
    );
  }

  static Future<Map<String, dynamic>> agentRequestChat({
    required String action,
    Map<String, dynamic>? extra,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final response = await http.post(
      Uri.parse('$baseUrl/agent_company/request_chat.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'action': action, ...?extra}),
    );
    Map<String, dynamic> decoded = {};
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        decoded = body;
      }
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded.isNotEmpty
          ? decoded
          : {'status': 'error', 'message': 'Invalid server response'};
    }

    final msg = decoded['message']?.toString() ??
        'Chat request failed (${response.statusCode})';
    throw Exception(msg);
  }

  static Future<Map<String, dynamic>> checkPanelStatus(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final role = (prefs.getString('role') ?? '').toLowerCase();
    if (role == 'agent') return checkAgentStatus();
    if (role == 'company') return checkCompanyStatus();
    return checkDealerStatus(userId);
  }

  static Future<List<dynamic>> fetchProperties([
    Map<String, String>? queryParams,
  ]) async {
    String queryString = '';
    if (queryParams != null && queryParams.isNotEmpty) {
      // Remove any empty string parameters before building the query string
      final cleanParams = Map<String, String>.from(queryParams)
        ..removeWhere((key, value) => value.trim().isEmpty);

      if (cleanParams.isNotEmpty) {
        // Construct the query string properly avoiding URI encoding breaking the PHP backend GET parsing
        queryString = '?';
        cleanParams.forEach((key, value) {
          queryString += '$key=$value&';
        });
        // Remove trailing '&'
        if (queryString.endsWith('&')) {
          queryString = queryString.substring(0, queryString.length - 1);
        }
      }
    }

    final response = await http.get(
      Uri.parse('$baseUrl/properties/index.php$queryString'),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      // Support the new {"status": "success", "data": [...]} format or fallback to direct array
      final rawList = (decoded is Map && decoded['data'] != null)
          ? decoded['data']
          : decoded;
      if (rawList is! List) return <dynamic>[];
      return rawList.where(_isPubliclyVisibleListing).toList();
    } else {
      throw Exception('Failed to load properties: ${response.statusCode}');
    }
  }

  static bool _isPubliclyVisibleListing(dynamic property) {
    if (property is! Map) return false;
    final p = Map<String, dynamic>.from(property);
    final now = DateTime.now();

    // Any explicit lock flag means we must hide the listing.
    const lockKeys = [
      'is_payment_locked',
      'is_locked',
      'payment_locked',
      'subscription_locked',
      'dealer_locked',
    ];
    for (final key in lockKeys) {
      if (_asBool(_pickAny(p, [key]))) return false;
    }

    // Explicit inactive-like statuses across known backend variants.
    const statusKeys = [
      'dealer_subscription_status',
      'subscription_status',
      'dealer_status',
      'sub_status',
      'plan_status',
      'paid_type',
      'account_type',
      'payment_status',
      'dealer_payment_status',
    ];
    const inactiveTokens = [
      'inactive',
      'expired',
      'suspended',
      'blocked',
      'locked',
      'unpaid',
      'free trial',
      'trial',
      'none',
      'cancelled',
      'canceled',
    ];

    for (final key in statusKeys) {
      final value = _pickAny(p, [key]);
      final normalized = value?.toString().trim().toLowerCase() ?? '';
      if (normalized.isEmpty) continue;
      if (inactiveTokens.any(normalized.contains)) return false;
    }

    // Also check one-level nested dealer/account objects when present.
    const nestedKeys = ['dealer', 'account', 'owner', 'user'];
    for (final nestedKey in nestedKeys) {
      final nested = p[nestedKey];
      if (nested is Map) {
        if (!_isPubliclyVisibleListing(Map<String, dynamic>.from(nested))) {
          return false;
        }
      }
    }

    // Expired subscription/plan should be hidden.
    final expiry = _parseDate(
      _pickAny(p, const [
        'dealer_subscription_expiry',
        'subscription_expiry',
        'plan_expiry',
        'expiry',
        'expiry_date',
        'subscription_end',
      ]),
    );
    if (expiry != null && expiry.isBefore(now)) return false;

    return true;
  }

  static dynamic _pickAny(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      if (map.containsKey(key)) return map[key];
    }
    return null;
  }

  static bool _asBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    final s = value.toString().trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty || raw == '0000-00-00 00:00:00') return null;
    return DateTime.tryParse(raw);
  }

  static Future<Map<String, dynamic>> fetchPropertyDetails(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/properties/index.php?id=$id'),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      // Support the new {"status": "success", "data": [...]} format or fallback to direct object
      if (decoded is Map &&
          decoded['data'] != null &&
          (decoded['data'] as List).isNotEmpty) {
        return decoded['data'][0];
      }
      return decoded;
    } else {
      throw Exception('Failed to load property details');
    }
  }

  // TENANT REQUESTS
  static Future<List<dynamic>> fetchTenantRequests() async {
    final response = await http.post(
      Uri.parse('$baseUrl/public/tenant_requests.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'get_requests'}),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'success') {
        return decoded['data'] ?? [];
      } else {
        throw Exception(decoded['message'] ?? 'Failed to fetch requests');
      }
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<int> fetchTenantRequestsCount() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/public/tenant_requests.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'get_requests_count'}),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['status'] == 'success' && decoded['data'] != null) {
          return int.tryParse(decoded['data']['total']?.toString() ?? '0') ?? 0;
        }
      }
    } catch (_) {}
    return 0;
  }

  static Future<Map<String, dynamic>> addTenantRequest(
    String message,
    String propertyType,
    String location,
    String budget,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/public/tenant_requests.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'add_request',
        'message': message,
        'property_type': propertyType,
        'location': location,
        'budget': budget,
      }),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'success') {
        return decoded['data'] ?? {};
      } else {
        throw Exception(decoded['message'] ?? 'Failed to add request');
      }
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  // TENANT REQUEST COMMENTS
  static Future<List<dynamic>> fetchRequestComments(String requestId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/public/tenant_requests.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'get_comments', 'request_id': requestId}),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'success') {
        return decoded['data'] ?? [];
      } else {
        throw Exception(decoded['message'] ?? 'Failed to fetch comments');
      }
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> addRequestComment(
    String requestId,
    String comment,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/public/tenant_requests.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'add_comment',
        'request_id': requestId,
        'comment': comment,
      }),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'success') {
        return decoded['data'] ?? {};
      } else {
        throw Exception(decoded['message'] ?? 'Failed to add comment');
      }
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  // Tenant favorites
  static Future<Map<String, dynamic>> toggleFavorite(String propertyId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    // We explicitly get the profile to guarantee we send the user_id since the token might not be passing it correctly.
    final profile = await getProfile();
    final userId = profile['id']?.toString() ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/tenant/favorites.php'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': 'Bearer $token',
      },
      body: {'action': 'toggle', 'user_id': userId, 'property_id': propertyId},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to toggle favorite: ${response.statusCode}');
    }
  }

  static Future<bool> checkFavorite(String propertyId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    try {
      final profile = await getProfile();
      final userId = profile['id']?.toString() ?? '';

      final response = await http.post(
        Uri.parse('$baseUrl/tenant/favorites.php'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Bearer $token',
        },
        body: {'action': 'check', 'user_id': userId, 'property_id': propertyId},
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        return decoded['is_favorite'] == true;
      }
    } catch (e) {
      // Ignore errors for unauthenticated users or network issues
    }
    return false;
  }

  static Future<List<dynamic>> fetchMyRentals() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.get(
      Uri.parse('$baseUrl/rentals/my_rentals.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load rentals');
    }
  }

  static Future<List<dynamic>> fetchFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final profile = await getProfile();
    final userId = profile['id']?.toString() ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/tenant/favorites.php'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': 'Bearer $token',
      },
      body: {'action': 'get_all', 'user_id': userId},
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'success') {
        return decoded['data'] ?? [];
      } else {
        throw Exception(decoded['message'] ?? 'Failed to load favorites');
      }
    } else {
      throw Exception('Failed to load favorites');
    }
  }

  static Future<Map<String, dynamic>> sendForgotPasswordEmail(
    String email,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/includes/SimpleMailer.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'forgot_password',
        'email': email,
        'reset_token': (100000 + DateTime.now().millisecondsSinceEpoch % 900000)
            .toString(), // Generate 6 digit code
      }),
    );
    if (response.statusCode == 200) {
      return _decodeJsonObjectSafe(response.body);
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> sendVerificationEmail(
    String email,
    String name,
    String verifyLink,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/includes/SimpleMailer.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'registration_verify',
        'email': email,
        'name': name,
        'verify_link': verifyLink,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> sendPropertyInquiry(
    Map<String, dynamic> inquiryData,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    // Add user_id if logged in, otherwise let it be null
    try {
      final profile = await getProfile();
      inquiryData['user_id'] = profile['id']?.toString();
    } catch (e) {
      // Not logged in, that's fine for public inquiries
    }

    final response = await http.post(
      Uri.parse(
        '$baseUrl/public/send_inquiry',
      ), // Uses the .htaccess redirect without .php
      headers: {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(inquiryData),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
        'Failed to send inquiry. Server responded with ${response.statusCode}',
      );
    }
  }

  static Future<Map<String, dynamic>> fetchLandlordRatingSummary({
    required String dealerId,
    String? propertyId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final query = <String, String>{
      'dealer_id': dealerId,
      if (propertyId != null && propertyId.trim().isNotEmpty)
        'property_id': propertyId,
    };

    final uri = Uri.parse(
      '$baseUrl/public/landlord_ratings.php',
    ).replace(queryParameters: query);

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(response.body);
      if (decoded['status'] == 'success') return decoded;
      throw Exception(decoded['message'] ?? 'Failed to load landlord rating');
    }
    throw Exception('Failed to load landlord rating: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> submitLandlordRating({
    required String dealerId,
    required String propertyId,
    required int rating,
    String review = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/public/landlord_ratings.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'submit_rating',
        'dealer_id': dealerId,
        'property_id': propertyId,
        'rating': rating,
        'review': review.trim(),
      }),
    );

    if (response.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(response.body);
      if (decoded['status'] == 'success') return decoded;
      throw Exception(decoded['message'] ?? 'Failed to submit rating');
    }
    throw Exception('Failed to submit rating: ${response.statusCode}');
  }

  static Future<dynamic> fetchPaymentHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final role = prefs.getString('role') ?? 'tenant';

    if (role == 'dealer') {
      // Get the profile to ensure we have the correct user_id
      final profile = await getProfile();
      final userId = profile['id']?.toString() ?? '';

      final response = await http.post(
        Uri.parse('$baseUrl/dealer/payments/dealer_payment.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'action': 'history', 'user_id': userId}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load payment history');
      }
    } else {
      final endpoint = '$baseUrl/payments/history.php';
      final response = await http.get(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load payment history');
      }
    }
  }

  static Future<Map<String, dynamic>> dealerInitiatePayment(
    String userId,
    String phone,
    String operator,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/dealer/payments/dealer_payments.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'initiate',
        'user_id': userId,
        'phone': phone,
        'operator': operator,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to initiate payment');
    }
  }

  static Future<Map<String, dynamic>> dealerVerifyPayment(
    String userId,
    String reference,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/dealer/payments/dealer_payments.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'verify',
        'user_id': userId,
        'reference': reference,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to verify payment');
    }
  }

  static Future<Map<String, dynamic>> dealerGetSubscriptionStatus(
    String userId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/dealer/payments/dealer_payments.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'get_status', 'user_id': userId}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get subscription status');
    }
  }

  static Future<Map<String, dynamic>> dealerPaymentHistory(
    String userId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/dealer/payments/dealer_payments.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'history', 'user_id': userId}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get payment history');
    }
  }

  static Future<Map<String, dynamic>> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.get(
      Uri.parse('$baseUrl/auth/me.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load profile');
    }
  }

  static Future<Map<String, dynamic>> updateProfile(
    String name,
    String phone,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.put(
      Uri.parse('$baseUrl/auth/me.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'name': name, 'phone': phone}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update profile');
    }
  }

  static Future<Map<String, dynamic>> fetchDealerProperties() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.get(
      Uri.parse('$baseUrl/dealer/properties/index.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return {'status': 'success', 'data': jsonDecode(response.body)};
    } else {
      throw Exception('Failed to load dealer properties');
    }
  }

  static String _absoluteSiteUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    const site = 'https://houseforrent.site';
    if (trimmed.startsWith('/')) return '$site$trimmed';
    return '$site/${trimmed.replaceFirst(RegExp(r'^\\+'), '')}';
  }

  static HomeBannerItem? _parseHomeBannerItem(dynamic item) {
    if (item is String) {
      final text = item.trim();
      if (text.isEmpty) return null;
      return HomeBannerItem(imageUrl: '', text: text);
    }
    if (item is! Map) return null;
    final image = _absoluteSiteUrl(
      (item['image'] ??
              item['image_url'] ??
              item['image_path'] ??
              item['url'] ??
              '')
          .toString(),
    );
    final title = (item['title'] ?? '').toString().trim();
    final subtitle = (item['subtitle'] ?? item['location'] ?? '')
        .toString()
        .trim();
    final text = (item['text'] ?? item['message'] ?? title)
        .toString()
        .trim();
    final link = _absoluteSiteUrl(
      (item['link'] ?? item['link_url'] ?? '').toString(),
    );
    if (image.isEmpty && text.isEmpty) return null;
    return HomeBannerItem(
      imageUrl: image,
      title: title,
      subtitle: subtitle,
      linkUrl: link,
      text: text,
    );
  }

  static List<HomeBannerItem>? _homeBannerCache;
  static DateTime? _homeBannerCacheAt;
  static const Duration _homeBannerCacheTtl = Duration(minutes: 3);

  static Future<List<HomeBannerItem>> fetchHomeBannerItems({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _homeBannerCache != null &&
        _homeBannerCacheAt != null &&
        DateTime.now().difference(_homeBannerCacheAt!) < _homeBannerCacheTtl) {
      return _homeBannerCache!;
    }
    final urls = <String>[
      'https://houseforrent.site/api/home_banners.php',
      '$baseUrl/public/home_banners.php',
    ];
    for (final url in urls) {
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {'Accept': 'application/json'},
        );
        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) continue;
        final data = decoded['data'];
        if (data is! List) continue;
        final items = data
            .map(_parseHomeBannerItem)
            .whereType<HomeBannerItem>()
            .toList();
        if (items.isNotEmpty) {
          _homeBannerCache = items;
          _homeBannerCacheAt = DateTime.now();
          return items;
        }
      } catch (_) {
        continue;
      }
    }
    if (_homeBannerCache != null) return _homeBannerCache!;
    return const <HomeBannerItem>[];
  }

  static Future<List<String>> fetchHomeBanners() async {
    final items = await fetchHomeBannerItems();
    return items
        .where((item) => !item.hasImage)
        .map((item) => item.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
  }

  static Future<Map<String, dynamic>> updatePropertyStatus(
    String propertyId,
    String status,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/properties/update_status.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'property_id': propertyId, 'status': status}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  // Add Property
  static Future<Map<String, dynamic>> createProperty(
    Map<String, dynamic> data,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    // Add action explicitly
    data['action'] = 'create_property';

    final response = await http
        .post(
          Uri.parse('$baseUrl/dealer/properties/add_property.php'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(data),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> updateProperty(
    String propertyId,
    Map<String, dynamic> data,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final payload = Map<String, dynamic>.from(data);
    payload['action'] = 'update_property';
    payload['property_id'] = propertyId;

    final uri = Uri.parse('$baseUrl/dealer/properties/add_property.php');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(response.body);
      if (decoded is Map<String, dynamic> && decoded['status'] == 'success') {
        return decoded;
      }

      final fallbackBody = payload.map(
        (k, v) => MapEntry(k, v?.toString() ?? ''),
      );
      final fallbackResponse = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Bearer $token',
        },
        body: fallbackBody,
      );
      if (fallbackResponse.statusCode == 200) {
        return _decodeJsonObjectSafe(fallbackResponse.body);
      }
      throw Exception('Server error: ${fallbackResponse.statusCode}');
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> deleteProperty(String propertyId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final uri = Uri.parse('$baseUrl/dealer/properties/add_property.php');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'delete_property',
        'property_id': propertyId,
      }),
    );

    if (response.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(response.body);
      if (decoded is Map<String, dynamic> && decoded['status'] == 'success') {
        return decoded;
      }

      final fallbackResponse = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Bearer $token',
        },
        body: {'action': 'delete_property', 'property_id': propertyId},
      );
      if (fallbackResponse.statusCode == 200) {
        return _decodeJsonObjectSafe(fallbackResponse.body);
      }
      throw Exception('Server error: ${fallbackResponse.statusCode}');
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> uploadPropertyImages(
    String propertyId,
    List<String> imagePaths, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (imagePaths.isEmpty) {
      return {'status': 'error', 'message': 'No files provided'};
    }

    // Chunk uploads so large galleries don't hit post_max_size under traffic.
    const chunkSize = 3;
    final allUrls = <String>[];
    final total = imagePaths.length;

    for (var i = 0; i < imagePaths.length; i += chunkSize) {
      final end = (i + chunkSize > imagePaths.length)
          ? imagePaths.length
          : i + chunkSize;
      final chunk = imagePaths.sublist(i, end);
      final result = await _uploadPropertyImagesChunk(propertyId, chunk);
      if (result['status'] != 'success') {
        return result;
      }
      final urls = result['urls'];
      if (urls is List) {
        allUrls.addAll(urls.map((e) => e.toString()));
      }
      onProgress?.call(end, total);
    }

    return {
      'status': 'success',
      'message': '${allUrls.length} files uploaded successfully',
      'urls': allUrls,
    };
  }

  static Future<Map<String, dynamic>> _uploadPropertyImagesChunk(
    String propertyId,
    List<String> imagePaths,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token') ?? '';

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('$baseUrl/dealer/properties/add_property.php'),
        );

        request.headers.addAll({'Authorization': 'Bearer $token'});
        request.fields['action'] = 'upload_property_images';
        request.fields['property_id'] = propertyId;

        for (final path in imagePaths) {
          request.files.add(
            await http.MultipartFile.fromPath('images[]', path),
          );
        }

        final streamedResponse = await request.send().timeout(
          const Duration(seconds: 90),
        );
        final response = await http.Response.fromStream(
          streamedResponse,
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          return _decodeJsonObjectSafe(response.body);
        }
        lastError = Exception('Server error: ${response.statusCode}');
      } catch (e) {
        lastError = e;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
        }
      }
    }
    throw lastError ?? Exception('Upload failed');
  }

  static Future<Map<String, dynamic>> replacePropertyImages(
    String propertyId,
    List<String> imagePaths,
  ) async {
    // Keep replace for callers that need it; prefer chunked uploadPropertyImages
    // for add/edit so concurrent users don't blow POST limits.
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/dealer/properties/add_property.php'),
    );

    request.headers.addAll({'Authorization': 'Bearer $token'});

    request.fields['action'] = 'replace_property_images';
    request.fields['property_id'] = propertyId;

    for (var path in imagePaths) {
      request.files.add(await http.MultipartFile.fromPath('images[]', path));
    }

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 120),
    );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return _decodeJsonObjectSafe(response.body);
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> deletePropertyImage({
    required String propertyId,
    required String imageId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final uri = Uri.parse('$baseUrl/dealer/properties/add_property.php');

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'delete_property_image',
        'property_id': propertyId,
        'image_id': imageId,
      }),
    );

    if (response.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(response.body);
      if (decoded['status'] == 'success') return decoded;

      final fallback = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Bearer $token',
        },
        body: {
          'action': 'delete_property_image',
          'property_id': propertyId,
          'image_id': imageId,
        },
      );
      if (fallback.statusCode == 200) {
        return _decodeJsonObjectSafe(fallback.body);
      }
      throw Exception('Server error: ${fallback.statusCode}');
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  // Tenant Management
  static Future<Map<String, dynamic>> approveTenantPayment(
    dynamic paymentId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final profile = await getProfile();
    final dealerId = profile['id']?.toString() ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/tenants/add_tenant'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'verify_payment',
        'payment_id': paymentId.toString(),
        'dealer_id': dealerId,
        'status': 'approved',
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> fetchDealerTenantsAndActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final profile = await getProfile();
    final dealerId = profile['id']?.toString() ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/tenants/add_tenant'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'action': 'get_tenants', 'dealer_id': dealerId}),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'error') {
        throw Exception(decoded['message'] ?? 'Failed to load tenants data');
      }
      return decoded;
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> fetchDealerTenantRentPayments({
    String status = 'all',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final uri = Uri.parse(
      '$baseUrl/dealer/tenants/dealer_tenant_rent_payments.php',
    ).replace(queryParameters: {'status': status});
    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );

    final decoded = _decodeJsonObjectSafe(response.body);
    if (response.statusCode == 200 && decoded['status'] == 'success') {
      return decoded;
    }
    throw Exception(decoded['message'] ?? 'Failed to load tenant payments');
  }

  static Future<Map<String, dynamic>> addDealerTenantByEmail({
    required String email,
    required String propertyId,
    required String rentAmount,
    required String startDate,
    String endDate = '',
    String roomNumber = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final response = await http.post(
      Uri.parse('$baseUrl/dealer/tenants/dealer_tenant_rent_payments.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'add_tenant_by_email',
        'email': email.trim(),
        'property_id': propertyId,
        'rent_amount': rentAmount,
        'start_date': startDate,
        'end_date': endDate,
        'room_number': roomNumber.trim(),
      }),
    );

    final decoded = _decodeJsonObjectSafe(response.body);
    if ((response.statusCode == 200 || response.statusCode == 201) &&
        decoded['status'] == 'success') {
      return decoded;
    }
    throw Exception(decoded['message'] ?? 'Failed to add tenant');
  }

  static Future<List<Map<String, dynamic>>> fetchRentalLeases() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final response = await http.get(
      Uri.parse('$baseUrl/leases/rental_leases.php?action=list'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    final decoded = _decodeJsonObjectSafe(response.body);
    if (response.statusCode == 200 && decoded['status'] == 'success') {
      final data = decoded['data'];
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return [];
    }
    throw Exception(decoded['message'] ?? 'Failed to load leases');
  }

  static Future<Map<String, dynamic>> fetchRentalLease(String leaseId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final response = await http.get(
      Uri.parse(
        '$baseUrl/leases/rental_leases.php?action=get&lease_id=$leaseId',
      ),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    final decoded = _decodeJsonObjectSafe(response.body);
    if (response.statusCode == 200 && decoded['status'] == 'success') {
      final data = decoded['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
    }
    throw Exception(decoded['message'] ?? 'Failed to load lease');
  }

  static Future<Map<String, dynamic>> createRentalLease({
    required String rentalId,
    double depositAmount = 0,
    bool send = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final response = await http.post(
      Uri.parse('$baseUrl/leases/rental_leases.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'create',
        'rental_id': int.tryParse(rentalId) ?? rentalId,
        'deposit_amount': depositAmount,
        'send': send,
      }),
    );
    final decoded = _decodeJsonObjectSafe(response.body);
    if ((response.statusCode == 200 || response.statusCode == 201) &&
        decoded['status'] == 'success') {
      return decoded;
    }
    throw Exception(decoded['message'] ?? 'Failed to create lease');
  }

  static Future<Map<String, dynamic>> signRentalLease({
    required String leaseId,
    required String signedName,
    required String signatureData,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final response = await http.post(
      Uri.parse('$baseUrl/leases/rental_leases.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'sign',
        'lease_id': int.tryParse(leaseId) ?? leaseId,
        'signed_name': signedName,
        'signature_data': signatureData,
      }),
    );
    final decoded = _decodeJsonObjectSafe(response.body);
    if (response.statusCode == 200 && decoded['status'] == 'success') {
      final data = decoded['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      return decoded;
    }
    throw Exception(decoded['message'] ?? 'Failed to sign lease');
  }

  static Future<Map<String, dynamic>> reviewDealerTenantRentPayment({
    required String paymentId,
    required String status,
    String dealerNotes = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final response = await http.post(
      Uri.parse('$baseUrl/dealer/tenants/dealer_tenant_rent_payments.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'review_payment',
        'payment_id': paymentId,
        'status': status,
        'dealer_notes': dealerNotes.trim(),
      }),
    );

    final decoded = _decodeJsonObjectSafe(response.body);
    if (response.statusCode == 200 && decoded['status'] == 'success') {
      return decoded;
    }
    throw Exception(decoded['message'] ?? 'Failed to review payment');
  }

  static Future<Map<String, dynamic>> fetchTenantRatingSummary(
    String tenantId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final uri = Uri.parse(
      '$baseUrl/dealer/tenants/ratings.php',
    ).replace(queryParameters: {'tenant_id': tenantId});

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(response.body);
      if (decoded['status'] == 'success') return decoded;
      throw Exception(decoded['message'] ?? 'Failed to load tenant rating');
    }
    throw Exception('Server error: ${response.statusCode}');
  }

  static Future<List<Map<String, dynamic>>> fetchDealerTenantRatings() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.get(
      Uri.parse('$baseUrl/dealer/tenants/ratings.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(response.body);
      if (decoded['status'] != 'success') {
        throw Exception(decoded['message'] ?? 'Failed to load tenant ratings');
      }
      final raw = decoded['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return <Map<String, dynamic>>[];
    }

    throw Exception('Server error: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> submitTenantRating({
    required String tenantId,
    required String rentalId,
    required int rating,
    String review = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final payload = <String, dynamic>{
      'tenant_id': tenantId,
      'rating': rating.clamp(1, 5),
      'review': review.trim(),
    };
    if (rentalId.trim().isNotEmpty) {
      payload['rental_id'] = rentalId.trim();
    }

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/tenants/ratings.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(response.body);
      if (decoded['status'] == 'success') return decoded;
      throw Exception(decoded['message'] ?? 'Failed to save tenant rating');
    }
    throw Exception('Server error: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> addTenant(
    Map<String, dynamic> data,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final profile = await getProfile();
    data['dealer_id'] = profile['id']?.toString() ?? '';
    data['action'] = 'add_tenant';

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/tenants/add_tenant'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(data),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'error') {
        throw Exception(decoded['message'] ?? 'Failed to add tenant');
      }
      return decoded;
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<List<dynamic>> fetchDealerLeads() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.get(
      Uri.parse('$baseUrl/dealer/leads/index.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load dealer leads');
    }
  }

  static Future<Map<String, dynamic>> checkDealerStatus(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/check_status.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'user_id': userId}),
    );

    if (response.statusCode == 200) {
      try {
        return jsonDecode(response.body);
      } catch (e) {
        throw Exception('Failed to parse dealer status: ${response.body}');
      }
    } else {
      throw Exception('Failed to check dealer status: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> fetchDealerReferralDashboard({
    String action = 'dashboard',
    String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    String resolvedUserId = (userId ?? '').trim();
    if (resolvedUserId.isEmpty) {
      resolvedUserId = (prefs.getString('user_id') ?? '').trim();
    }
    if (resolvedUserId.isEmpty) {
      final profile = await getProfile();
      resolvedUserId =
          profile['id']?.toString() ?? profile['user']?['id']?.toString() ?? '';
      if (resolvedUserId.isNotEmpty) {
        await prefs.setString('user_id', resolvedUserId);
      }
    }
    if (resolvedUserId.isEmpty) {
      throw Exception('User ID is required');
    }

    final normalizedAction = action.trim().isEmpty
        ? 'dashboard'
        : action.trim();
    // Pointing exactly to houseforrent.site/api as requested
    final endpoint = 'https://houseforrent.site/api/referral.php';

    try {
      // Pass as query parameters as a fallback, but still send POST body
      final uri = Uri.parse(
        '$endpoint?user_id=$resolvedUserId&action=$normalizedAction',
      );
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: {'action': normalizedAction, 'user_id': resolvedUserId},
      );

      if (response.statusCode == 200) {
        final decoded = _decodeJsonObjectSafe(response.body);
        if (decoded['status'] == 'success') return decoded;
        throw Exception(
          decoded['message'] ?? 'Failed to load referral dashboard',
        );
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to connect to referral API: $e');
    }
  }

  static Future<Map<String, dynamic>> fetchDealerSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.get(
      Uri.parse('$baseUrl/dealer/subscriptions/index.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load dealer subscription info');
    }
  }

  static Future<Map<String, dynamic>> initiateLencoPayment(
    String userId,
    String phone,
    String operator,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/payments/lenco_payment.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'initiate',
        'user_id': userId,
        'phone': phone,
        'operator': operator,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to initiate payment');
    }
  }

  static Future<Map<String, dynamic>> verifyLencoPayment(
    String reference,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/payments/lenco_payment.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'action': 'verify', 'reference': reference}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to verify payment');
    }
  }

  static Future<bool> checkEmailVerification(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/dealer/check_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'check_email_verification',
          'user_id': userId,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['is_verified'] == true;
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> checkIdentityVerification(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/dealer/check_status.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'check_dealer_verification',
          'user_id': userId,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['identity_verified'] == true;
      }
    } catch (_) {}
    return false;
  }

  // Tenant Management (Tenant Side)
  static Future<Map<String, dynamic>> fetchTenantDashboardData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    // First get the user profile to get the tenant_id
    final profile = await getProfile();
    final tenantId = profile['id']?.toString() ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/tenant/payments.php'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': 'Bearer $token',
      },
      body: {'action': 'get_history', 'tenant_id': tenantId},
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 'error') {
        throw Exception(decoded['message'] ?? 'Failed to load tenant data');
      }
      return decoded;
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> uploadTenantProof(
    String rentalId,
    String monthYear,
    String amount,
    String paymentMethod,
    String referenceNumber,
    String? imagePath,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    // First get the user profile to get the tenant_id
    final profile = await getProfile();
    final tenantId = profile['id']?.toString() ?? '';

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/tenant/payments.php'),
    );

    request.headers.addAll({'Authorization': 'Bearer $token'});

    request.fields['action'] = 'upload_proof';
    request.fields['tenant_id'] = tenantId;
    request.fields['rental_id'] = rentalId;
    request.fields['month_year'] = monthYear;
    request.fields['amount'] = amount;
    request.fields['payment_method'] = paymentMethod;
    request.fields['reference_number'] = referenceNumber;

    if (imagePath != null && imagePath.isNotEmpty) {
      request.files.add(
        await http.MultipartFile.fromPath('proof_image', imagePath),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> _rentSavingsRequest(
    String action, [
    Map<String, dynamic>? values,
  ]) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final response = await http.post(
      Uri.parse('https://houseforrent.site/api/rent_savings.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'action': action, ...?values}),
    );

    Map<String, dynamic> decoded;
    try {
      decoded = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw Exception(
        'Rent Savings server returned HTTP ${response.statusCode} instead of JSON. Please check the deployed API file.',
      );
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['status'] == 'error' ||
        decoded['status'] == 'maintenance') {
      throw Exception(decoded['message'] ?? 'Rent Savings request failed.');
    }
    return decoded;
  }

  static Future<Map<String, dynamic>> fetchRentSavings() =>
      _rentSavingsRequest('summary');

  static Future<Map<String, dynamic>> setRentSavingsGoal({
    required double amount,
    DateTime? targetDate,
  }) => _rentSavingsRequest('set_goal', {
    'rent_goal': amount,
    'target_date': targetDate == null
        ? ''
        : '${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}',
  });

  static Future<Map<String, dynamic>> depositRentSavings({
    required double amount,
    required int lockDays,
  }) =>
      _rentSavingsRequest('deposit', {'amount': amount, 'lock_days': lockDays});

  /// Step 1: email a 6-digit code to the tenant's registered email.
  static Future<Map<String, dynamic>> requestRentSavingsWithdrawOtp({
    required double amount,
    required String phone,
    required String operator,
  }) =>
      _rentSavingsRequest('request_withdraw_otp', {
        'amount': amount,
        'phone': phone,
        'operator': operator,
      });

  static Future<Map<String, dynamic>> withdrawRentSavings({
    required double amount,
    required String phone,
    required String operator,
    String? otpChallengeId,
    String? otpCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final response = await http.post(
      Uri.parse('https://houseforrent.site/api/rent_savings.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'withdraw',
        'amount': amount,
        'phone': phone,
        'operator': operator,
        if (otpChallengeId != null && otpChallengeId.isNotEmpty)
          'otp_challenge_id': otpChallengeId,
        if (otpCode != null && otpCode.isNotEmpty) 'otp_code': otpCode,
      }),
    );

    Map<String, dynamic> decoded;
    try {
      decoded = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw Exception(
        'Rent Savings server returned HTTP ${response.statusCode} instead of JSON.',
      );
    }

    final withdrawStatus =
        (decoded['withdrawal_status'] ?? '').toString().toLowerCase();
    final okStatuses = {'completed', 'processing', 'pending'};
    // Prefer withdraw payload even when HTTP is non-2xx but Lenco accepted it.
    if (okStatuses.contains(withdrawStatus) ||
        (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            decoded['status'] != 'error' &&
            decoded['status'] != 'maintenance')) {
      if (!decoded.containsKey('withdrawn_amount')) {
        decoded['withdrawn_amount'] = amount;
      }
      if (!decoded.containsKey('withdrawn_phone')) {
        decoded['withdrawn_phone'] = phone;
      }
      if (!decoded.containsKey('withdrawn_operator')) {
        decoded['withdrawn_operator'] = operator;
      }
      if (!decoded.containsKey('remaining_balance') &&
          decoded['balance'] != null) {
        decoded['remaining_balance'] = decoded['balance'];
      }
      if (!decoded.containsKey('remaining_available') &&
          decoded['available_balance'] != null) {
        decoded['remaining_available'] = decoded['available_balance'];
      }
      if (withdrawStatus.isEmpty) {
        decoded['withdrawal_status'] = 'completed';
      }
      return decoded;
    }

    throw Exception(decoded['message'] ?? 'Withdrawal failed.');
  }

  // Google Maps — Laravel proxy first, then website config (house/config/config.php),
  // then direct Google using the key from that config.
  static String get mapsProxyUrl =>
      'https://houseforrent.site/api/moving-laravel/public/api/v1/maps';

  static List<String> get _mapsProxyUrls => [
        mapsProxyUrl,
        'https://houseforrent.site/house/api/maps.php',
        'https://houseforrent.site/api/maps.php',
        '$baseUrl/maps.php',
      ];

  /// Same key as house/config/config.php on the live website.
  static const String _googleMapsFallbackKey =
      'AIzaSyDH0JpnMofvCFnx9byn6TUm_GV6YW9onZU';

  static Future<Map<String, dynamic>?> _postMapsAction(
    Map<String, dynamic> body,
  ) async {
    for (final url in _mapsProxyUrls) {
      try {
        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        if (response.statusCode != 200) continue;

        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['status'] == 'success') {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<String> _resolvedMapsApiKey() async {
    final fromServer = (await getGoogleMapsApiKey())?.trim() ?? '';
    return fromServer.isNotEmpty ? fromServer : _googleMapsFallbackKey;
  }

  static Future<List<Map<String, dynamic>>> autocompleteAddress(
    String input, {
    String country = 'zm', // '' or 'all' = worldwide
    double? biasLat,
    double? biasLng,
  }) async {
    final decoded = await _postMapsAction({
      'action': 'autocomplete',
      'input': input,
      'country': country,
      if (biasLat != null && biasLng != null) ...{
        'lat': biasLat,
        'lng': biasLng,
      },
    });
    if (decoded != null && decoded['predictions'] is List) {
      return List<Map<String, dynamic>>.from(decoded['predictions']);
    }

    return _autocompleteAddressDirect(
      input,
      country: country,
      biasLat: biasLat,
      biasLng: biasLng,
    );
  }

  static Future<List<Map<String, dynamic>>> _autocompleteAddressDirect(
    String input, {
    String country = 'zm',
    double? biasLat,
    double? biasLng,
  }) async {
    try {
      final key = await _resolvedMapsApiKey();
      final params = <String, String>{
        'input': input,
        'key': key,
      };
      final normalizedCountry = country.trim().toLowerCase();
      if (normalizedCountry.isNotEmpty && normalizedCountry != 'all') {
        params['components'] = 'country:$normalizedCountry';
      }
      if (biasLat != null && biasLng != null) {
        params['location'] = '$biasLat,$biasLng';
        params['radius'] = '80000';
      }

      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        params,
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) return [];

      final decoded = jsonDecode(response.body);
      final status = (decoded['status'] ?? '').toString();
      if (status != 'OK' && status != 'ZERO_RESULTS') return [];

      final predictions = decoded['predictions'] as List<dynamic>? ?? [];
      return predictions
          .map(
            (pred) => {
              'place_id': (pred['place_id'] ?? '').toString(),
              'description': (pred['description'] ?? '').toString(),
            },
          )
          .toList();
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    final decoded = await _postMapsAction({
      'action': 'place_details',
      'place_id': placeId,
    });
    if (decoded != null) return decoded;

    return _getPlaceDetailsDirect(placeId);
  }

  static Future<Map<String, dynamic>?> _getPlaceDetailsDirect(
    String placeId,
  ) async {
    try {
      final key = await _resolvedMapsApiKey();
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        {
          'place_id': placeId,
          'fields': 'geometry,formatted_address',
          'key': key,
        },
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if ((decoded['status'] ?? '').toString() != 'OK') return null;

      final location = decoded['result']?['geometry']?['location'];
      return {
        'status': 'success',
        'address': (decoded['result']?['formatted_address'] ?? '').toString(),
        'lat': location?['lat'],
        'lng': location?['lng'],
      };
    } catch (_) {}
    return null;
  }

  /// Turns GPS coordinates into a readable street address.
  static Future<String?> reverseGeocode(double lat, double lng) async {
    final decoded = await _postMapsAction({
      'action': 'geocode',
      'lat': lat,
      'lng': lng,
    });
    if (decoded != null) {
      final address = (decoded['address'] ?? '').toString();
      if (address.isNotEmpty) return address;
    }

    return _reverseGeocodeDirect(lat, lng);
  }

  static Future<String?> _reverseGeocodeDirect(double lat, double lng) async {
    try {
      final key = await _resolvedMapsApiKey();
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        {
          'latlng': '$lat,$lng',
          'key': key,
          'result_type':
              'street_address|premise|route|intersection|political|neighborhood',
        },
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if ((decoded['status'] ?? '').toString() != 'OK') return null;

      final results = decoded['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return null;
      final address = (results.first['formatted_address'] ?? '').toString();
      return address.isNotEmpty ? address : null;
    } catch (_) {}
    return null;
  }

  static Future<String?> getGoogleMapsApiKey() async {
    final decoded = await _postMapsAction({'action': 'get_api_key'});
    if (decoded != null) {
      final key = (decoded['api_key'] ?? '').toString().trim();
      if (key.isNotEmpty) return key;
    }
    return _googleMapsFallbackKey;
  }

  // ─── Notifications ───────────────────────────────────────────────────────────

  static Future<void> registerNotificationDevice(String fcmToken) async {
    final normalizedToken = fcmToken.trim();
    if (normalizedToken.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('token') ?? '';
    final userId = int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
    final role = (prefs.getString('role') ?? 'user').trim();
    if (authToken.isEmpty || userId <= 0) return;

    final platform = kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android');
    final response = await http.post(
      Uri.parse('$baseUrl/notifications/notifications.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({
        'action': 'register_device',
        'user_id': userId,
        'role': role.isEmpty ? 'user' : role,
        'fcm_token': normalizedToken,
        'platform': platform,
      }),
    );

    final decoded = _decodeJsonObjectSafe(response.body);
    if (response.statusCode != 200 || decoded['status'] != 'success') {
      throw Exception(decoded['message'] ?? 'Failed to register device');
    }
  }

  static Future<void> unregisterNotificationDevice(String fcmToken) async {
    final normalizedToken = fcmToken.trim();
    if (normalizedToken.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('token') ?? '';
    final userId = int.tryParse(prefs.getString('user_id') ?? '') ?? 0;
    final role = (prefs.getString('role') ?? 'user').trim();
    if (authToken.isEmpty || userId <= 0) return;

    final response = await http.post(
      Uri.parse('$baseUrl/notifications/notifications.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
      body: jsonEncode({
        'action': 'unregister_device',
        'user_id': userId,
        'role': role.isEmpty ? 'user' : role,
        'fcm_token': normalizedToken,
      }),
    );

    final decoded = _decodeJsonObjectSafe(response.body);
    if (response.statusCode != 200 || decoded['status'] != 'success') {
      throw Exception(decoded['message'] ?? 'Failed to unregister device');
    }
  }

  static Future<List<dynamic>> fetchNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final role = (prefs.getString('role') ?? 'user').trim().isEmpty
        ? 'user'
        : (prefs.getString('role') ?? 'user').trim();

    // Try cached user_id first; fall back to getProfile() if missing
    String userId = prefs.getString('user_id') ?? '';
    if (userId.isEmpty) {
      try {
        final profile = await getProfile();
        // Handle both flat {"id": x} and nested {"user": {"id": x}} responses
        userId =
            profile['id']?.toString() ??
            profile['user']?['id']?.toString() ??
            '';
        if (userId.isNotEmpty) await prefs.setString('user_id', userId);
      } catch (_) {}
    }

    if (userId.isEmpty) {
      throw Exception('Not authenticated. Please log in again.');
    }

    final endpoint = Uri.parse('$baseUrl/notifications/notifications.php');
    final userIdInt = int.tryParse(userId) ?? 0;

    final jsonResponse = await http.post(
      endpoint,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'get_notifications',
        'user_id': userIdInt,
        'role': role,
      }),
    );

    if (jsonResponse.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(jsonResponse.body);
      if (decoded['status'] == 'success') return decoded['data'] ?? [];
    }

    final formResponse = await http.post(
      endpoint,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': 'Bearer $token',
      },
      body: {
        'action': 'get_notifications',
        'user_id': userIdInt.toString(),
        'role': role,
      },
    );

    if (formResponse.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(formResponse.body);
      if (decoded['status'] == 'success') return decoded['data'] ?? [];
      throw Exception(decoded['message'] ?? 'Failed to load notifications');
    }

    throw Exception(
      'Server error: ${jsonResponse.statusCode}/${formResponse.statusCode}',
    );
  }

  static Future<List<dynamic>> fetchPublicAdminNotifications() async {
    // Use the same notifications API endpoint used by tenant/dealer panels.
    final endpoint = Uri.parse('$baseUrl/notifications/notifications.php');

    final response = await http.post(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'get_notifications',
        'user_id': 0,
        'role': 'user',
      }),
    );

    if (response.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(response.body);
      if (decoded['status'] == 'success') {
        final list = decoded['data'];
        if (list is List) return list;
        return <dynamic>[];
      }
    }

    // Fallback to form payload for servers that do not parse JSON POST bodies.
    final formResponse = await http.post(
      endpoint,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'action': 'get_notifications', 'user_id': '0', 'role': 'user'},
    );

    if (formResponse.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(formResponse.body);
      if (decoded['status'] == 'success') {
        final list = decoded['data'];
        if (list is List) return list;
        return <dynamic>[];
      }
      throw Exception(decoded['message'] ?? 'Failed to load notifications');
    }

    // Last fallback: some older backends may enforce role + user_id strongly.
    final strictFallback = await http.post(
      Uri.parse('$baseUrl/notifications/notifications.php'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'action': 'get_notifications', 'user_id': '0', 'role': 'all'},
    );

    if (strictFallback.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(strictFallback.body);
      if (decoded['status'] == 'success') {
        final list = decoded['data'];
        if (list is List) return list;
        return <dynamic>[];
      }
      throw Exception(decoded['message'] ?? 'Failed to load notifications');
    }

    final publicEndpointResponse = await http.get(
      Uri.parse('$baseUrl/public/admin_notifications.php'),
      headers: {'Accept': 'application/json'},
    );

    if (publicEndpointResponse.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(publicEndpointResponse.body);
      if (decoded['status'] == 'success') {
        final list = decoded['data'];
        if (list is List) return list;
        return <dynamic>[];
      }
      throw Exception(decoded['message'] ?? 'Failed to load notifications');
    }

    throw Exception(
      'Server error: ${formResponse.statusCode} / ${strictFallback.statusCode} / ${publicEndpointResponse.statusCode}',
    );
  }

  static Future<void> markNotificationRead(String notificationId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final role = (prefs.getString('role') ?? 'user').trim().isEmpty
        ? 'user'
        : (prefs.getString('role') ?? 'user').trim();
    int userId = int.tryParse(prefs.getString('user_id') ?? '0') ?? 0;
    if (userId == 0) {
      try {
        final profile = await getProfile();
        userId =
            int.tryParse(
              profile['id']?.toString() ??
                  profile['user']?['id']?.toString() ??
                  '0',
            ) ??
            0;
      } catch (_) {}
    }
    if (userId == 0) return;

    final endpoint = Uri.parse('$baseUrl/notifications/notifications.php');

    final jsonResponse = await http.post(
      endpoint,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'mark_read',
        'user_id': userId,
        'role': role,
        'notification_id': notificationId,
      }),
    );

    if (jsonResponse.statusCode == 200) return;

    await http.post(
      endpoint,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': 'Bearer $token',
      },
      body: {
        'action': 'mark_read',
        'user_id': userId.toString(),
        'role': role,
        'notification_id': notificationId,
      },
    );
  }

  static Future<void> markAllNotificationsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final role = (prefs.getString('role') ?? 'user').trim().isEmpty
        ? 'user'
        : (prefs.getString('role') ?? 'user').trim();
    int userId = int.tryParse(prefs.getString('user_id') ?? '0') ?? 0;
    if (userId == 0) {
      try {
        final profile = await getProfile();
        userId =
            int.tryParse(
              profile['id']?.toString() ??
                  profile['user']?['id']?.toString() ??
                  '0',
            ) ??
            0;
      } catch (_) {}
    }
    if (userId == 0) return;

    final endpoint = Uri.parse('$baseUrl/notifications/notifications.php');

    final jsonResponse = await http.post(
      endpoint,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'mark_all_read',
        'user_id': userId,
        'role': role,
      }),
    );

    if (jsonResponse.statusCode == 200) return;

    await http.post(
      endpoint,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Authorization': 'Bearer $token',
      },
      body: {
        'action': 'mark_all_read',
        'user_id': userId.toString(),
        'role': role,
      },
    );
  }
}

Map<String, dynamic> _decodeJsonObjectSafe(String rawBody) {
  String body = rawBody.trim();
  if (body.isEmpty) {
    throw const FormatException('Empty server response');
  }

  // Remove UTF-8 BOM if present.
  if (body.startsWith('\uFEFF')) {
    body = body.substring(1);
  }

  final objStart = body.indexOf('{');
  final arrStart = body.indexOf('[');
  int start = -1;
  if (objStart >= 0 && arrStart >= 0) {
    start = objStart < arrStart ? objStart : arrStart;
  } else if (objStart >= 0) {
    start = objStart;
  } else if (arrStart >= 0) {
    start = arrStart;
  }
  if (start > 0) {
    body = body.substring(start);
  }

  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {
      'status': 'error',
      'message': 'Unexpected response type from server.',
    };
  } catch (_) {
    final preview = body.length > 140 ? '${body.substring(0, 140)}...' : body;
    return {'status': 'error', 'message': 'Invalid server response: $preview'};
  }
}
