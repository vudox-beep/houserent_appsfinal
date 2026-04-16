import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class DealerSubscriptionScreen extends StatefulWidget {
  const DealerSubscriptionScreen({super.key});

  @override
  State<DealerSubscriptionScreen> createState() => _DealerSubscriptionScreenState();
}

class _DealerSubscriptionScreenState extends State<DealerSubscriptionScreen> {
  Map<String, dynamic>? _subscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
  }

  Future<void> _loadSubscription() async {
    try {
      final sub = await ApiService.fetchDealerSubscription();
      setState(() {
        _subscription = sub;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // Handle error gracefully
    }
  }

  Future<void> _handleUpgrade() async {
    final profile = await ApiService.getProfile();
    final userId = profile['id']?.toString() ?? '';
    final phone = profile['phone']?.toString() ?? '';

    if (userId.isEmpty) return;

    // Show operator selection dialog
    String selectedOperator = 'mtn';
    
    if (!mounted) return;
    
    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (context) {
        String tempOperator = 'mtn';
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: const Text('Complete Payment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Amount: ZMW 20.00', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                const Text('Select Mobile Network:'),
                DropdownButton<String>(
                  value: tempOperator,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'mtn', child: Text('MTN Mobile Money')),
                    DropdownMenuItem(value: 'airtel', child: Text('Airtel Money')),
                    DropdownMenuItem(value: 'zamtel', child: Text('Zamtel Kwacha')),
                  ],
                  onChanged: (val) {
                    setStateDialog(() => tempOperator = val!);
                    selectedOperator = val!;
                  },
                ),
                const SizedBox(height: 16),
                Text('Phone: $phone\n(Please ensure this number is registered for mobile money)', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFC107)),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Pay Now', style: TextStyle(color: Colors.black87)),
              ),
            ],
          ),
        );
      }
    );

    if (proceed != true) return;

    setState(() => _isLoading = true);

    try {
      final initRes = await ApiService.initiateLencoPayment(userId, phone, selectedOperator);
      
      if (initRes['status'] == 'success') {
        final reference = initRes['reference'];
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment initiated. Please check your phone for the prompt.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 10),
            )
          );
        }

        // Wait a bit then check status automatically (or let user click a verify button)
        await Future.delayed(const Duration(seconds: 15));
        
        final verifyRes = await ApiService.verifyLencoPayment(reference);
        if (mounted) {
          if (verifyRes['status'] == 'success') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Payment Successful! Subscription activated.'), backgroundColor: Colors.green)
            );
            _loadSubscription(); // Reload data
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(verifyRes['message'] ?? 'Payment pending or failed.'), backgroundColor: Colors.red)
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(initRes['message'] ?? 'Failed to initiate payment'), backgroundColor: Colors.red)
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error processing payment.'), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
      child: Center(
        child: Column(
          children: [
            const Text('Choose Your Plan', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF0F2041))),
            const SizedBox(height: 8),
            const Text('Unlock unlimited listings and premium features.', style: TextStyle(fontSize: 16, color: Colors.black54)),
            const SizedBox(height: 48),
            
            Wrap(
              spacing: 32,
              runSpacing: 32,
              alignment: WrapAlignment.center,
              children: [
                _buildBasicPlanCard(),
                _buildProPlanCard(),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildBasicPlanCard() {
    return Container(
      width: 350,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          const Text('Basic Access', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFF4A5568))),
          const SizedBox(height: 24),
          const Text('Free', style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
          const SizedBox(height: 8),
          const Text('Forever', style: TextStyle(fontSize: 16, color: Colors.black54)),
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
              onPressed: null, // Disabled as it's the current plan for un-upgraded users
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: const Text('Current Plan', style: TextStyle(fontSize: 16, color: Colors.black45)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildProPlanCard() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 350,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 30,
                offset: const Offset(0, 15),
              )
            ],
          ),
          child: Column(
            children: [
              const Text('Dealer Pro', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Color(0xFFFFC107))),
              const SizedBox(height: 24),
              const Text('ZMW 20', style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
              const SizedBox(height: 8),
              const Text('Per Month', style: TextStyle(fontSize: 16, color: Colors.black54)),
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
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Upgrade Plan'),
                        content: const Text('To make a payment and upgrade your plan, please login to the HouseRent Africa website using your credentials.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('OK', style: TextStyle(color: Color(0xFFFFC107))),
                          ),
                        ],
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('Upgrade Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              )
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
            child: const Text('RECOMMENDED', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
          ),
        )
      ],
    );
  }

  Widget _buildFeatureRow(String text, bool included, {bool isPro = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          included ? Icons.check_circle : Icons.cancel,
          color: included ? (isPro ? const Color(0xFFFFC107) : Colors.green) : Colors.grey.shade400,
          size: 20,
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 160,
          child: Text(text, style: TextStyle(fontSize: 16, color: Colors.grey.shade800)),
        ),
      ],
    );
  }
}
