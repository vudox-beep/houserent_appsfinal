import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Use the live production server URL
  static String get baseUrl {
    const String productionUrl = 'https://houseforrent.site/php_backend/api'; 
    return productionUrl;
  }

  static Future<Map<String, dynamic>> uploadVerificationDocument(String userId, String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    
    // Updated to use the correct endpoint
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/dealer/check_status.php'));
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['action'] = 'upload_verification';
    request.fields['user_id'] = userId;
    
    request.files.add(await http.MultipartFile.fromPath('document', filePath));
    
    var streamedResponse = await request.send();
    var response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      print('Upload Response Decoded: $decoded');
      return decoded;
    } else {
      print('Upload Failed with status code: ${response.statusCode}');
      print('Upload Response Body: ${response.body}');
      throw Exception('Failed to upload document');
    }
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'login',
          'email': email, 
          'password': password
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 'error') {
          return data; 
        }
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['user']['token'] ?? data['token'] ?? '');
        await prefs.setString('role', data['user']['role'] ?? data['role']);
        // Cache user_id so other endpoints don't need to re-call getProfile()
        final userId = data['user']['id']?.toString() ?? data['id']?.toString() ?? '';
        if (userId.isNotEmpty) await prefs.setString('user_id', userId);
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
        body: jsonEncode({
          'action': 'forgot_password',
          'email': email,
        }),
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

  static Future<Map<String, dynamic>> resendVerification(String email, {String name = 'User'}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/public/send_verification.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'name': name,
        }),
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

  static Future<Map<String, dynamic>> register(String name, String email, String password, String role) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'register',
          'name': name, 
          'email': email, 
          'password': password, 
          'role': role
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Server error');
      }
    } catch (e) {
      throw Exception('Please check your internet connection and try again.');
    }
  }

  static Future<List<dynamic>> fetchProperties([Map<String, String>? queryParams]) async {
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
    
    final response = await http.get(Uri.parse('$baseUrl/properties/index.php$queryString'));
    
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      // Support the new {"status": "success", "data": [...]} format or fallback to direct array
      final rawList = (decoded is Map && decoded['data'] != null) ? decoded['data'] : decoded;
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
    final expiry = _parseDate(_pickAny(p, const [
      'dealer_subscription_expiry',
      'subscription_expiry',
      'plan_expiry',
      'expiry',
      'expiry_date',
      'subscription_end',
    ]));
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
    final response = await http.get(Uri.parse('$baseUrl/properties/index.php?id=$id'));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      // Support the new {"status": "success", "data": [...]} format or fallback to direct object
      if (decoded is Map && decoded['data'] != null && (decoded['data'] as List).isNotEmpty) {
        return decoded['data'][0];
      }
      return decoded;
    } else {
      throw Exception('Failed to load property details');
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
        'Authorization': 'Bearer $token'
      },
      body: {
        'action': 'toggle',
        'user_id': userId,
        'property_id': propertyId,
      },
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
          'Authorization': 'Bearer $token'
        },
        body: {
          'action': 'check',
          'user_id': userId,
          'property_id': propertyId,
        },
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
        'Authorization': 'Bearer $token'
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
        'Authorization': 'Bearer $token'
      },
      body: {
        'action': 'get_all',
        'user_id': userId,
      },
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

  static Future<Map<String, dynamic>> sendForgotPasswordEmail(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/includes/SimpleMailer.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'forgot_password',
        'email': email,
        'reset_token': (100000 + DateTime.now().millisecondsSinceEpoch % 900000).toString(), // Generate 6 digit code
      }),
    );
    if (response.statusCode == 200) {
      return _decodeJsonObjectSafe(response.body);
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> sendVerificationEmail(String email, String name, String verifyLink) async {
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

  static Future<Map<String, dynamic>> sendPropertyInquiry(Map<String, dynamic> inquiryData) async {
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
      Uri.parse('$baseUrl/public/send_inquiry'), // Uses the .htaccess redirect without .php
      headers: {
        'Content-Type': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(inquiryData),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to send inquiry. Server responded with ${response.statusCode}');
    }
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
          'Authorization': 'Bearer $token'
        },
        body: jsonEncode({
          'action': 'history',
          'user_id': userId,
        }),
      );
      
      print('Dealer Payment History Response: ${response.body}');
      
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
          'Authorization': 'Bearer $token'
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to load payment history');
      }
    }
  }

  static Future<Map<String, dynamic>> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load profile');
    }
  }

  static Future<Map<String, dynamic>> updateProfile(String name, String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    
    final response = await http.put(
      Uri.parse('$baseUrl/auth/me.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      },
      body: jsonEncode({
        'name': name,
        'phone': phone,
      }),
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
        'Authorization': 'Bearer $token'
      },
    );

    if (response.statusCode == 200) {
      return {'status': 'success', 'data': jsonDecode(response.body)};
    } else {
      throw Exception('Failed to load dealer properties');
    }
  }

  static Future<Map<String, dynamic>> updatePropertyStatus(String propertyId, String status) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/properties/update_status.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      },
      body: jsonEncode({
        'property_id': propertyId,
        'status': status,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  // Add Property
  static Future<Map<String, dynamic>> createProperty(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    // Add action explicitly
    data['action'] = 'create_property';

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/properties/add_property.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      },
      body: jsonEncode(data),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> updateProperty(String propertyId, Map<String, dynamic> data) async {
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
        'Authorization': 'Bearer $token'
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final decoded = _decodeJsonObjectSafe(response.body);
      if (decoded is Map<String, dynamic> && decoded['status'] == 'success') {
        return decoded;
      }

      final fallbackBody = payload.map((k, v) => MapEntry(k, v?.toString() ?? ''));
      final fallbackResponse = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Bearer $token'
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
        'Authorization': 'Bearer $token'
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
          'Authorization': 'Bearer $token'
        },
        body: {
          'action': 'delete_property',
          'property_id': propertyId,
        },
      );
      if (fallbackResponse.statusCode == 200) {
        return _decodeJsonObjectSafe(fallbackResponse.body);
      }
      throw Exception('Server error: ${fallbackResponse.statusCode}');
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> uploadPropertyImages(String propertyId, List<String> imagePaths) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/dealer/properties/add_property.php'),
    );

    request.headers.addAll({
      'Authorization': 'Bearer $token',
    });

    request.fields['action'] = 'upload_property_images';
    request.fields['property_id'] = propertyId;

    for (var path in imagePaths) {
      request.files.add(await http.MultipartFile.fromPath(
        'images[]',
        path,
      ));
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return _decodeJsonObjectSafe(response.body);
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> replacePropertyImages(String propertyId, List<String> imagePaths) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/dealer/properties/add_property.php'),
    );

    request.headers.addAll({
      'Authorization': 'Bearer $token',
    });

    request.fields['action'] = 'replace_property_images';
    request.fields['property_id'] = propertyId;

    for (var path in imagePaths) {
      request.files.add(await http.MultipartFile.fromPath(
        'images[]',
        path,
      ));
    }

    final streamedResponse = await request.send();
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
        'Authorization': 'Bearer $token'
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
          'Authorization': 'Bearer $token'
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
  static Future<Map<String, dynamic>> approveTenantPayment(dynamic paymentId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final profile = await getProfile();
    final dealerId = profile['id']?.toString() ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/tenants/add_tenant'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      },
      body: jsonEncode({
        'action': 'verify_payment',
        'payment_id': paymentId.toString(),
        'dealer_id': dealerId,
        'status': 'approved'
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
        'Authorization': 'Bearer $token'
      },
      body: jsonEncode({
        'action': 'get_tenants',
        'dealer_id': dealerId
      }),
    );

    print('Fetch Tenants Response Status: ${response.statusCode}');
    print('Fetch Tenants Response Body: ${response.body}');

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

  static Future<Map<String, dynamic>> addTenant(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final profile = await getProfile();
    data['dealer_id'] = profile['id']?.toString() ?? '';
    data['action'] = 'add_tenant';

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/tenants/add_tenant'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
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
        'Authorization': 'Bearer $token'
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
        'Authorization': 'Bearer $token'
      },
      body: jsonEncode({
        'user_id': userId,
      }),
    );

    print('Dealer Check Status Code: ${response.statusCode}');
    print('Dealer Check Status Response: ${response.body}');

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

  static Future<Map<String, dynamic>> fetchDealerSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    
    final response = await http.get(
      Uri.parse('$baseUrl/dealer/subscriptions/index.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load dealer subscription info');
    }
  }

  static Future<Map<String, dynamic>> initiateLencoPayment(String userId, String phone, String operator) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/payments/lenco_payment.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      },
      body: jsonEncode({
        'action': 'initiate',
        'user_id': userId,
        'phone': phone,
        'operator': operator
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to initiate payment');
    }
  }

  static Future<Map<String, dynamic>> verifyLencoPayment(String reference) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';

    final response = await http.post(
      Uri.parse('$baseUrl/dealer/payments/lenco_payment.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      },
      body: jsonEncode({
        'action': 'verify',
        'reference': reference
      }),
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
    } catch (e) {
      print('Check verification error: $e');
    }
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
    } catch (e) {
      print('Check identity error: $e');
    }
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
        'Authorization': 'Bearer $token'
      },
      body: {
        'action': 'get_history',
        'tenant_id': tenantId,
      },
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
      String rentalId, String monthYear, String amount, String paymentMethod, String referenceNumber, String? imagePath) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    
    // First get the user profile to get the tenant_id
    final profile = await getProfile();
    final tenantId = profile['id']?.toString() ?? '';

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/tenant/payments.php'),
    );

    request.headers.addAll({
      'Authorization': 'Bearer $token',
    });

    request.fields['action'] = 'upload_proof';
    request.fields['tenant_id'] = tenantId;
    request.fields['rental_id'] = rentalId;
    request.fields['month_year'] = monthYear;
    request.fields['amount'] = amount;
    request.fields['payment_method'] = paymentMethod;
    request.fields['reference_number'] = referenceNumber;

    if (imagePath != null && imagePath.isNotEmpty) {
      request.files.add(await http.MultipartFile.fromPath(
        'proof_image',
        imagePath,
      ));
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }

  // Google Maps API Proxies
  static Future<List<Map<String, dynamic>>> autocompleteAddress(String input, {String country = 'zm'}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/maps.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'autocomplete',
          'input': input,
          'country': country
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['status'] == 'success') {
          return List<Map<String, dynamic>>.from(decoded['predictions']);
        } else {
          print('Maps Autocomplete Error: ${decoded['message']}');
        }
      } else {
        print('Maps Autocomplete HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('Maps Autocomplete Exception: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/maps.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'place_details',
          'place_id': placeId,
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['status'] == 'success') {
          return decoded;
        } else {
          print('Maps Place Details Error: ${decoded['message']}');
        }
      }
    } catch (e) {
      print('Maps Place Details Exception: $e');
    }
    return null;
  }

  static Future<String?> getGoogleMapsApiKey() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/maps.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'get_api_key',
        }),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['status'] == 'success') {
          return decoded['api_key'];
        }
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  // ─── Notifications ───────────────────────────────────────────────────────────

  static Future<List<dynamic>> fetchNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    final role  = prefs.getString('role') ?? 'user';

    // Try cached user_id first; fall back to getProfile() if missing
    String userId = prefs.getString('user_id') ?? '';
    if (userId.isEmpty) {
      try {
        final profile = await getProfile();
        // Handle both flat {"id": x} and nested {"user": {"id": x}} responses
        userId = profile['id']?.toString()
            ?? profile['user']?['id']?.toString()
            ?? '';
        if (userId.isNotEmpty) await prefs.setString('user_id', userId);
      } catch (_) {}
    }

    if (userId.isEmpty) {
      throw Exception('Not authenticated. Please log in again.');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/notifications/notifications.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action':  'get_notifications',
        'user_id': int.tryParse(userId) ?? 0,
        'role':    role,
      }),
    );

    if (response.statusCode == 200) {
      try {
        // Clean invisible characters/BOM or PHP notices before the JSON
        String rawBody = response.body;
        int startIndex = rawBody.indexOf('{');
        if (startIndex != -1) {
          rawBody = rawBody.substring(startIndex);
        }
        
        final decoded = jsonDecode(rawBody);
        if (decoded['status'] == 'success') {
          return decoded['data'] ?? [];
        }
        throw Exception(decoded['message'] ?? 'Failed to load notifications');
      } catch (e) {
        throw Exception("Server format error. Raw body: ${response.body}");
      }
    } else {
      throw Exception('Server error: ${response.statusCode}\n${response.body}');
    }
  }

  static Future<void> markNotificationRead(String notificationId) async {
    final prefs = await SharedPreferences.getInstance();
    final token  = prefs.getString('token') ?? '';
    final role   = prefs.getString('role') ?? 'user';
    final userId = int.tryParse(prefs.getString('user_id') ?? '0') ?? 0;
    if (userId == 0) return;

    await http.post(
      Uri.parse('$baseUrl/notifications/notifications.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action':          'mark_read',
        'user_id':         userId,
        'role':            role,
        'notification_id': notificationId,
      }),
    );
  }

  static Future<void> markAllNotificationsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final token  = prefs.getString('token') ?? '';
    final role   = prefs.getString('role') ?? 'user';
    final userId = int.tryParse(prefs.getString('user_id') ?? '0') ?? 0;
    if (userId == 0) return;

    await http.post(
      Uri.parse('$baseUrl/notifications/notifications.php'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action':  'mark_all_read',
        'user_id': userId,
        'role':    role,
      }),
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
      return {
        'status': 'error',
        'message': 'Invalid server response: $preview',
      };
    }
  }
