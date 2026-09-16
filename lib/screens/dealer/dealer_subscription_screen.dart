import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/api_service.dart';
import '../../widgets/skeleton_loader.dart';
import 'dealer_payment_webview_screen.dart';

class DealerSubscriptionScreen extends StatefulWidget {
  const DealerSubscriptionScreen({super.key});

  @override
  State<DealerSubscriptionScreen> createState() =>
      _DealerSubscriptionScreenState();
}

class _DealerSubscriptionScreenState extends State<DealerSubscriptionScreen> {
  static const String _dealerPaymentUrl =
      'https://houseforrent.site/api/dealer_payment.php';
  static const String _dealerWebsiteLoginUrl =
      'https://houseforrent.site/login';

  Map<String, dynamic>? _subscription;
  bool _isLoading = true;
  double _fee = 300;
  String _planLabel = 'Dealer Pro';

  @override
  void initState() {
    super.initState();
    _loadSubscription();
  }

  Future<void> _loadSubscription() async {
    try {
      final profile = await ApiService.getProfile();
      final userId = profile['id']?.toString() ?? '';

      Map<String, dynamic> sub = await _dealerPaymentRequest(
        action: 'get_status',
        userId: userId,
      );
      _fee = double.tryParse('${sub['subscription_fee'] ?? 300}') ?? 300;
      _planLabel = 'Dealer Pro';

      if (!mounted) return;
      setState(() {
        _subscription = sub;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>> _dealerPaymentRequest({
    required String action,
    required String userId,
    Map<String, dynamic>? extra,
  }) async {
    final body = <String, dynamic>{
      'action': action,
      'user_id': userId,
      ...?extra,
    };

    final response = await http.post(
      Uri.parse(_dealerPaymentUrl),
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

    return {'status': 'error', 'message': 'Invalid server response'};
  }

  Future<void> _handleUpgrade() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const DealerPaymentWebviewScreen(
          url: _dealerWebsiteLoginUrl,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _isLoading = true);
    await _loadSubscription();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    if (_isLoading) {
      return const SkeletonDealerSubscription();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
      child: Center(
        child: Column(
          children: [
            Text(
              'Choose Your Plan',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Unlock unlimited listings and premium features.',
              style: textTheme.bodyLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),

            Wrap(
              spacing: 32,
              runSpacing: 32,
              alignment: WrapAlignment.center,
              children: [_buildBasicPlanCard(), _buildProPlanCard()],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicPlanCard() {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: 350,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Text(
            'Basic Access',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          Text(
            'Free',
            style: textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Forever',
            style: textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 40),

          _buildFeatureRow('Browse Properties', true),
          const SizedBox(height: 16),
          _buildFeatureRow('Contact Dealers', true),
          const SizedBox(height: 16),
          _buildFeatureRow('List Properties', false),
          const SizedBox(height: 16),
          _buildFeatureRow('Analytics Dashboard', false),

          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed:
                  null, // Disabled as it's the current plan for un-upgraded users
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide(color: colors.outlineVariant),
              ),
              child: Text(
                'Current Plan',
                style: TextStyle(fontSize: 16, color: colors.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProPlanCard() {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 350,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFFC107).withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            children: [
              Text(
                _planLabel,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFFC107),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'ZMW ${_fee == _fee.roundToDouble() ? _fee.toInt() : _fee.toStringAsFixed(0)}',
                style: textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Per Month',
                style: textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 40),

              _buildFeatureRow('Unlimited Listings', true, isPro: true),
              const SizedBox(height: 16),
              _buildFeatureRow('Featured Properties', true, isPro: true),
              const SizedBox(height: 16),
              _buildFeatureRow('Analytics & Leads', true, isPro: true),
              const SizedBox(height: 16),
              _buildFeatureRow('Verified Badge', true, isPro: true),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleUpgrade,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _isLoading ? 'Please wait...' : 'Upgrade Now',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFFFC107),
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(8),
              ),
            ),
            child: const Text(
              'RECOMMENDED',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureRow(String text, bool included, {bool isPro = false}) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          included ? Icons.check_circle : Icons.cancel,
          color: included
              ? (isPro ? const Color(0xFFFFC107) : Colors.green)
              : Colors.grey.shade400,
          size: 20,
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 160,
          child: Text(
            text,
            style: TextStyle(
              fontSize: 16,
              color: included ? colors.onSurface : colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
