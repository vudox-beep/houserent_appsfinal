import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../utils/app_error.dart';

class DealerTenantsScreen extends StatefulWidget {
  const DealerTenantsScreen({super.key});

  @override
  State<DealerTenantsScreen> createState() => _DealerTenantsScreenState();
}

class _DealerTenantsScreenState extends State<DealerTenantsScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _ratings = [];

  @override
  void initState() {
    super.initState();
    _loadRatings();
  }

  Future<void> _launchWebsite() async {
    final Uri url = Uri.parse('https://houseforrent.site/dealer');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _loadRatings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final ratings = await ApiService.fetchDealerTenantRatings();
      if (!mounted) return;
      setState(() {
        _ratings = ratings;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.userMessage(
          e,
          fallback: 'Unable to load tenant ratings right now.',
        );
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadRatings, child: const Text('Retry')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRatings,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _ratings.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.open_in_browser,
                      color: Colors.blue.shade600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'To manage tenants, visit houseforrent.site.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _launchWebsite,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.black87,
                    ),
                    child: const Text('Manage Tenants'),
                  ),
                ],
              ),
            );
          }

          final item = _ratings[index - 1];
          final tenantName = (item['tenant_name'] ?? 'Tenant').toString();
          final tenantEmail = (item['tenant_email'] ?? '').toString();
          final myRatingMap = item['my_rating'] is Map
              ? Map<String, dynamic>.from(item['my_rating'] as Map)
              : <String, dynamic>{};
          final myRating =
              int.tryParse(myRatingMap['rating']?.toString() ?? '0') ?? 0;
          final myReview = (myRatingMap['review'] ?? '').toString().trim();
          final avgRating =
              double.tryParse(item['average_rating']?.toString() ?? '0') ?? 0;
          final totalRatings =
              int.tryParse(item['total_ratings']?.toString() ?? '0') ?? 0;
          final updatedAt = (item['updated_at'] ?? '').toString();
          final recentReviews = item['recent_reviews'] is List
              ? (item['recent_reviews'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
              : <Map<String, dynamic>>[];

          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tenantName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (tenantEmail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(tenantEmail),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ...List.generate(
                        5,
                        (star) => Icon(
                          star < myRating ? Icons.star : Icons.star_border,
                          color: const Color(0xFFFFC107),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Your rating: $myRating • Avg ${avgRating.toStringAsFixed(1)} ($totalRatings)',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    myReview.isEmpty ? 'Your review: none' : 'Your review: $myReview',
                    style: const TextStyle(height: 1.35),
                  ),
                  if (recentReviews.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Who rated:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    ...recentReviews.map((r) {
                      final dealerName = (r['dealer_name'] ?? 'Dealer').toString();
                      final reviewText = (r['review'] ?? '').toString().trim();
                      final ratingValue =
                          int.tryParse(r['rating']?.toString() ?? '0') ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '$dealerName ($ratingValue★): ${reviewText.isEmpty ? "No comment" : reviewText}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                            height: 1.3,
                          ),
                        ),
                      );
                    }),
                  ],
                  if (updatedAt.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Updated: $updatedAt',
                      style: const TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
