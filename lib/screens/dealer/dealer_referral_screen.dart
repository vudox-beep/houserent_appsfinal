import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import 'package:share_plus/share_plus.dart';
import '../../utils/app_error.dart';
import '../../widgets/skeleton_loader.dart';

class DealerReferralScreen extends StatefulWidget {
  const DealerReferralScreen({super.key});

  @override
  State<DealerReferralScreen> createState() => _DealerReferralScreenState();
}

class _DealerReferralScreenState extends State<DealerReferralScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _dashboardData;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final data = await ApiService.fetchDealerReferralDashboard();
      if (mounted) {
        setState(() {
          _dashboardData = data['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AppError.userMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _shareLink(String message) {
    Share.share(message);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_isLoading) {
      return const SkeletonDealerReferral();
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            Text(
              'Error loading referral data',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _fetchData();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
              ),
              child: const Text('Retry', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
    }

    final summary = _dashboardData?['summary'] ?? {};
    final settings = _dashboardData?['settings'] ?? {};
    final referrals = _dashboardData?['referrals'] as List? ?? [];
    final rewards = _dashboardData?['rewards'] as List? ?? [];

    final currency = settings['currency'] ?? 'K';
    final totalEarnings = summary['total_earnings']?.toString() ?? '0';
    final successful = summary['successful_referrals']?.toString() ?? '0';
    final pending = summary['pending_referrals']?.toString() ?? '0';
    final refLink = summary['referral_link']?.toString() ?? '';
    final shareMessage = summary['share_message']?.toString() ?? '';

    return RefreshIndicator(
      onRefresh: _fetchData,
      color: const Color(0xFFFFC107),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Referral Program',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            // Earnings Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F2041), Color(0xFF1E3A8A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'Total Earnings',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$currency $totalEarnings',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        'Successful',
                        successful,
                        Colors.greenAccent,
                      ),
                      _buildStatItem('Pending', pending, Colors.orangeAccent),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Share Section
            Text(
              'Your Referral Link',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      refLink,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy, color: colors.primary),
                    onPressed: () =>
                        _copyToClipboard(refLink, 'Referral link copied!'),
                  ),
                  IconButton(
                    icon: Icon(Icons.share, color: colors.primary),
                    onPressed: () => _shareLink(shareMessage),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Tabs for Referrals and Rewards
            DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    labelColor: colors.onSurface,
                    unselectedLabelColor: colors.onSurfaceVariant,
                    indicatorColor: Color(0xFFFFC107),
                    tabs: [
                      Tab(text: 'My Referrals'),
                      Tab(text: 'Rewards History'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 400, // Fixed height for tab views
                    child: TabBarView(
                      children: [
                        _buildReferralsList(referrals),
                        _buildRewardsList(rewards, currency),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildReferralsList(List referrals) {
    final colors = Theme.of(context).colorScheme;
    if (referrals.isEmpty) {
      return const Center(
        child: Text(
          'You haven\'t referred anyone yet.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: referrals.length,
      itemBuilder: (context, index) {
        final ref = referrals[index];
        final isVerified = ref['status'] == 'verified';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isVerified ? Colors.green : Colors.orange).withValues(
                  alpha: 0.16,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isVerified ? Icons.check_circle : Icons.pending,
                color: isVerified ? Colors.green : Colors.orange,
                size: 24,
              ),
            ),
            title: Text(
              ref['name']?.toString() ?? 'Unknown User',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                ref['email']?.toString() ?? '',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (isVerified ? Colors.green : Colors.orange).withValues(
                  alpha: 0.16,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isVerified ? 'Verified' : 'Pending',
                style: TextStyle(
                  color: isVerified
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRewardsList(List rewards, String currency) {
    final colors = Theme.of(context).colorScheme;
    if (rewards.isEmpty) {
      return const Center(
        child: Text(
          'No rewards earned yet.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: rewards.length,
      itemBuilder: (context, index) {
        final reward = rewards[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.monetization_on_rounded,
                color: Colors.green,
                size: 24,
              ),
            ),
            title: Text(
              reward['notes']?.toString() ?? 'Reward',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                reward['created_at']?.toString() ?? '',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ),
            trailing: Text(
              '+$currency ${reward['amount']}',
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        );
      },
    );
  }
}
