import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Rent disputes + maintenance tickets (single backend: support_cases.php).
class SupportCasesService {
  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token') ?? '';
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> _post(
    Map<String, dynamic> body,
  ) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/support_cases.php'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    final data = jsonDecode(res.body);
    if (data is! Map) throw Exception('Invalid response');
    if (data['status'] != 'success') {
      throw Exception(data['message']?.toString() ?? 'Request failed');
    }
    return Map<String, dynamic>.from(data);
  }

  static Future<List<Map<String, dynamic>>> listDisputes() async {
    final data = await _post({'action': 'list_disputes'});
    final list = data['cases'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> getDispute(int caseId) async {
    final data = await _post({'action': 'get_dispute', 'case_id': caseId});
    return {
      'case': Map<String, dynamic>.from(data['case'] as Map),
      'messages': (data['messages'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    };
  }

  static Future<int> createDispute({
    required int rentalId,
    int? paymentId,
    required String disputeType,
    required String message,
  }) async {
    final data = await _post({
      'action': 'create_dispute',
      'rental_id': rentalId,
      if (paymentId != null) 'payment_id': paymentId,
      'dispute_type': disputeType,
      'message': message,
    });
    return int.parse('${data['case_id']}');
  }

  static Future<void> sendDisputeMessage({
    required int caseId,
    required String message,
  }) async {
    await _post({
      'action': 'send_dispute_message',
      'case_id': caseId,
      'message': message,
    });
  }

  static Future<List<Map<String, dynamic>>> listMaintenance() async {
    final data = await _post({'action': 'list_maintenance'});
    final list = data['tickets'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<int> createMaintenance({
    required int rentalId,
    required String title,
    required String description,
    String category = 'general',
    String priority = 'normal',
  }) async {
    final data = await _post({
      'action': 'create_maintenance',
      'rental_id': rentalId,
      'title': title,
      'description': description,
      'category': category,
      'priority': priority,
    });
    return int.parse('${data['ticket_id']}');
  }

  static Future<void> updateMaintenance({
    required int ticketId,
    required String status,
    String? dealerNote,
  }) async {
    await _post({
      'action': 'update_maintenance',
      'ticket_id': ticketId,
      'status': status,
      if (dealerNote != null) 'dealer_note': dealerNote,
    });
  }
}
