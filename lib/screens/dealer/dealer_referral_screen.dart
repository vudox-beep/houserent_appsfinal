import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

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
          _errorMessage = e.toString().replaceAll('Exception: ', '');
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
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: AppBar(
          title: const Text('Referral Program', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        body: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(height: 24),
                Container(height: 20, width: 150, color: Colors.white),
                const SizedBox(height: 12),
                Container(
                  height: 50,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 24),
                Container(height: 40, width: double.infinity, color: Colors.white),
                const SizedBox(height: 16),
                for (int i = 0; i < 3; i++)
                  Container(
                    height: 80,
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: Center(
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
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC107)),
                child: const Text('Retry', style: TextStyle(color: Colors.black)),
              )
            ],
          ),
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

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Referral Program', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchData,
        color: const Color(0xFFFFC107),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      color: Colors.black.withOpacity(0.1),
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
                        _buildStatItem('Successful', successful, Colors.greenAccent),
                        _buildStatItem('Pending', pending, Colors.orangeAccent),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Share Section
              const Text('Your Referral Link', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F2041))),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        refLink,
                        style: TextStyle(color: Colors.grey.shade800, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Color(0xFF0F2041)),
                      onPressed: () => _copyToClipboard(refLink, 'Referral link copied!'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share, color: Color(0xFF0F2041)),
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
                    const TabBar(
                      labelColor: Color(0xFF0F2041),
                      unselectedLabelColor: Colors.grey,
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
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold),
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
    if (referrals.isEmpty) {
      return const Center(
        child: Text('You haven\'t referred anyone yet.', style: TextStyle(color: Colors.grey)),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isVerified ? Colors.green.shade50 : Colors.orange.shade50,
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
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F2041), fontSize: 16)
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                ref['email']?.toString() ?? '',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isVerified ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isVerified ? 'Verified' : 'Pending',
                style: TextStyle(
                  color: isVerified ? Colors.green.shade700 : Colors.orange.shade700,
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
    if (rewards.isEmpty) {
      return const Center(
        child: Text('No rewards earned yet.', style: TextStyle(color: Colors.grey)),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.monetization_on_rounded, color: Colors.green, size: 24),
            ),
            title: Text(
              reward['notes']?.toString() ?? 'Reward',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F2041), fontSize: 16),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                reward['created_at']?.toString() ?? '',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
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
