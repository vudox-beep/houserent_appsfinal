import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../dealer/dealer_payment_webview_screen.dart';

/// Token package — prices/tokens come from the API when possible.
class DriverTokenPackage {
  const DriverTokenPackage({
    required this.id,
    required this.tokens,
    required this.price,
    required this.label,
  });

  final String id;
  final int tokens;
  final double price;
  final String label;

  String get priceLabel {
    if (price == price.roundToDouble()) {
      return 'K ${price.toInt()}';
    }
    return 'K ${price.toStringAsFixed(2)}';
  }

  factory DriverTokenPackage.fromJson(Map<String, dynamic> json) {
    return DriverTokenPackage(
      id: (json['id'] ?? '').toString(),
      tokens: int.tryParse('${json['tokens']}') ?? 0,
      price: double.tryParse('${json['price']}') ?? 0,
      label: (json['label'] ?? json['id'] ?? 'Package').toString(),
    );
  }
}

/// Fallback only if the packages API is unreachable — must match
/// `driver_token_packages()` in `api/driver_token_payment.php`.
const List<DriverTokenPackage> kDriverTokenPackagesFallback = [
  DriverTokenPackage(id: 'starter', tokens: 2, price: 20, label: 'Starter'),
  DriverTokenPackage(id: 'plus', tokens: 3, price: 50, label: 'Plus'),
  DriverTokenPackage(id: 'pro', tokens: 5, price: 89, label: 'Pro'),
];

/// Extensionless path — host 301s `.php` away and WebView can hang on that.
const String kDriverTokenPayApi =
    'https://houseforrent.site/api/driver_token_payment';

Future<List<DriverTokenPackage>> fetchDriverTokenPackages() async {
  try {
    final res = await http
        .get(Uri.parse('$kDriverTokenPayApi?action=packages'))
        .timeout(const Duration(seconds: 12));
    final trimmed = res.body.trimLeft();
    if (res.statusCode >= 200 &&
        res.statusCode < 300 &&
        trimmed.startsWith('{')) {
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = decoded['packages'];
      if (raw is List) {
        final list = raw
            .whereType<Map>()
            .map((e) => DriverTokenPackage.fromJson(Map<String, dynamic>.from(e)))
            .where((p) => p.id.isNotEmpty && p.tokens > 0 && p.price > 0)
            .toList();
        if (list.isNotEmpty) return list;
      }
    }
  } catch (_) {}
  return kDriverTokenPackagesFallback;
}

/// Shows package picker → opens Lenco webview → returns true if paid.
Future<bool> showDriverBuyTokensSheet(BuildContext context) async {
  final picked = await showModalBottomSheet<DriverTokenPackage>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1A1A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) => const _DriverBuyTokensSheet(),
  );

  if (picked == null || !context.mounted) return false;

  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('user_id') ?? '';
  if (userId.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in again to buy tokens.')),
      );
    }
    return false;
  }

  final phone = prefs.getString('phone') ?? prefs.getString('user_phone') ?? '';
  final email = prefs.getString('email') ?? prefs.getString('user_email') ?? '';
  final name = prefs.getString('user_name') ?? 'Driver';

  if (!context.mounted) return false;

  final url = Uri.parse(kDriverTokenPayApi).replace(
    queryParameters: {
      'action': 'pay_page',
      'user_id': userId,
      'package_id': picked.id,
      'phone': phone.isEmpty ? '0970000000' : phone,
      'email': email.isEmpty ? 'driver@houserent.site' : email,
      'name': name.isEmpty ? 'Driver' : name,
      // Open Lenco checkout as soon as the page + SDK are ready.
      'auto': '1',
    },
  ).toString();

  final paid = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => DealerPaymentWebviewScreen(url: url),
    ),
  );

  return paid == true;
}

class _DriverBuyTokensSheet extends StatefulWidget {
  const _DriverBuyTokensSheet();

  @override
  State<_DriverBuyTokensSheet> createState() => _DriverBuyTokensSheetState();
}

class _DriverBuyTokensSheetState extends State<_DriverBuyTokensSheet> {
  bool _loading = true;
  List<DriverTokenPackage> _packages = kDriverTokenPackagesFallback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final packages = await fetchDriverTokenPackages();
    if (!mounted) return;
    setState(() {
      _packages = packages;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Buy tokens',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '1 token unlocks 1 moving request · prices from server',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: CircularProgressIndicator(color: Color(0xFFFFC107)),
              )
            else
              ..._packages.map((p) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.pop(context, p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFC107)
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                '${p.tokens}',
                                style: const TextStyle(
                                  color: Color(0xFFFFC107),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '${p.tokens} token${p.tokens == 1 ? '' : 's'} · ${p.priceLabel}',
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              p.priceLabel,
                              style: const TextStyle(
                                color: Color(0xFFFFC107),
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white38,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
