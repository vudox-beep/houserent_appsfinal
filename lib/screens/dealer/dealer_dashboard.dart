import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dealer_properties_screen.dart';
import 'dealer_leads_screen.dart';
import 'dealer_subscription_screen.dart';
import 'dealer_profile_screen.dart';
import 'dealer_add_property_screen.dart';
import 'dealer_tenants_screen.dart';
import 'dealer_payment_history_screen.dart';
import 'dealer_referral_screen.dart';
import '../../services/api_service.dart';
import '../../utils/app_error.dart';
import '../notifications_screen.dart';

class DealerDashboard extends StatefulWidget {
  const DealerDashboard({super.key});

  @override
  State<DealerDashboard> createState() => _DealerDashboardState();
}

class _DealerDashboardState extends State<DealerDashboard> {
  int _selectedIndex = 0;
  Map<String, dynamic>? _profile;
  List<dynamic> _properties = [];
  Map<String, dynamic>? _subscription;
  bool _isLoading = true;
  Map<String, dynamic>? _dealerStatus;
  int _unreadNotifications = 0;
  int _unreadLeads = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _loadUnreadData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final profile = await ApiService.getProfile();
      final userId = profile['id']?.toString() ?? '';
      
      Map<String, dynamic>? statusData;
      if (userId.isNotEmpty) {
        try {
          statusData = await ApiService.checkDealerStatus(userId);
        } catch (e) {
          debugPrint('Failed to load dealer status: $e');
        }
      }
      
      Map<String, dynamic>? tenantData;
      try {
        tenantData = await ApiService.fetchDealerTenantsAndActivity();
      } catch (e) {
        debugPrint('Failed to load tenant data: $e');
      }
      
      List<dynamic> properties = [];
      int calculatedTotalViews = 0;
      try {
        final propResponse = await ApiService.fetchDealerProperties();
        properties = propResponse['data'] ?? [];
        for (var prop in properties) {
          calculatedTotalViews += (int.tryParse(prop['views']?.toString() ?? '0') ?? 0);
        }
      } catch (e) {
        debugPrint('Failed to load properties: $e');
      }
      
      Map<String, dynamic>? subscription;
      try {
        subscription = await ApiService.fetchDealerSubscription();
      } catch (e) {
        debugPrint('Failed to load subscription: $e');
      }

      List<dynamic> parsedRecentPayments = [];
      try {
        final paymentRes = await ApiService.fetchPaymentHistory();
        debugPrint('Dashboard Payment History Raw Response: $paymentRes');
        if (paymentRes is List) {
          parsedRecentPayments = paymentRes.take(5).toList();
        } else if (paymentRes is Map && paymentRes['transactions'] is List) {
          parsedRecentPayments = (paymentRes['transactions'] as List).take(5).toList();
        } else if (paymentRes is Map && paymentRes['data'] is List) {
          parsedRecentPayments = (paymentRes['data'] as List).take(5).toList();
        } else if (paymentRes is Map && paymentRes['payments'] is List) {
          parsedRecentPayments = (paymentRes['payments'] as List).take(5).toList();
        }
        debugPrint('Dashboard Parsed Payments count: ${parsedRecentPayments.length}');
      } catch (e) {
        debugPrint('Failed to load recent payments: $e');
      }

      if (mounted) {
        setState(() {
          _profile = profile;
          _properties = properties;
          _subscription = subscription;
          _dealerStatus = statusData;
          
          if (_dealerStatus == null) {
            _dealerStatus = {};
          }
          
          if (tenantData != null) {
            _dealerStatus!['active_tenants'] = (tenantData['tenants'] as List?)?.length ?? 0;
          }
          
          _dealerStatus!['total_views'] = calculatedTotalViews;
          _dealerStatus!['recent_payments'] = parsedRecentPayments;
          
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppError.userMessage(e, fallback: 'Failed to load dashboard data.'))),
        );
      }
    }
  }

  Future<void> _loadUnreadData() async {
    try {
      final notifs = await ApiService.fetchNotifications();
      int unreadNotifs = 0;
      for (var n in notifs) {
        if (n['is_read'] == 0) unreadNotifs++;
      }
      
      final leads = await ApiService.fetchDealerLeads();
      int leadsCount = leads.length;
      
      if (mounted) {
        setState(() {
          _unreadNotifications = unreadNotifs;
          _unreadLeads = leadsCount;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Determine subscription status safely
    bool isSubActive = false;
    if (_dealerStatus != null && _dealerStatus!.containsKey('is_payment_locked')) {
      isSubActive = !(_dealerStatus!['is_payment_locked'] as bool);
    } else if (_subscription != null && _subscription!.containsKey('subscription_status')) {
      isSubActive = _subscription!['subscription_status'] == 'active';
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Flexible(
              child: Text(
                'Dealer Dashboard', 
                style: TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            if (!_isLoading && (_dealerStatus != null || _subscription != null))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSubActive ? Colors.green.shade100 : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isSubActive ? 'Active Plan' : 'Expired/Inactive',
                  style: TextStyle(
                    fontSize: 12, 
                    fontWeight: FontWeight.bold, 
                    color: isSubActive ? Colors.green.shade800 : Colors.red.shade800
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF5A3D31),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _loadDashboardData();
              _loadUnreadData();
            },
            tooltip: 'Refresh Dashboard',
          ),
          TextButton.icon(
            icon: const Icon(Icons.home, color: Colors.white),
            label: const Text('Home', style: TextStyle(color: Colors.white)),
            onPressed: () => context.go('/home'),
          ),
          // 🔔 Notification bell with unread badge
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Badge(
              label: Text('$_unreadNotifications'),
              isLabelVisible: _unreadNotifications > 0,
              offset: const Offset(-4, 4),
              child: IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'Notifications',
                onPressed: () => setState(() => _selectedIndex = 7),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token');
              await prefs.remove('role');
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isIdentityPending()) _buildIdentityPendingBanner(),
          Expanded(child: _buildMainContent()),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            activeIcon: Icon(Icons.list),
            label: 'Properties',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              label: Text('$_unreadLeads'),
              isLabelVisible: _unreadLeads > 0,
              child: const Icon(Icons.message_outlined),
            ),
            activeIcon: Badge(
              label: Text('$_unreadLeads'),
              isLabelVisible: _unreadLeads > 0,
              child: const Icon(Icons.message),
            ),
            label: 'Inquiries',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.payment_outlined),
            activeIcon: Icon(Icons.payment),
            label: 'History',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.star_outline),
            activeIcon: Icon(Icons.star),
            label: 'Subscription',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Tenants',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.group_add_outlined),
            activeIcon: Icon(Icons.group_add),
            label: 'Referral',
          ),
        ],
        currentIndex: _getBottomNavIndex(),
        selectedItemColor: const Color(0xFFFFC107),
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            if (index == 0) _selectedIndex = 0; // Overview
            if (index == 1) _selectedIndex = 1; // Properties
            if (index == 2) _selectedIndex = 2; // Inquiries
            if (index == 3) _selectedIndex = 6; // Payment History
            if (index == 4) _selectedIndex = 3; // Subscription
            if (index == 5) _selectedIndex = 5; // Tenants
            if (index == 6) _selectedIndex = 4; // Profile
            if (index == 7) _selectedIndex = 8; // Referral
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 16,
      ),
    );
  }

  int _getBottomNavIndex() {
    switch (_selectedIndex) {
      case 0: return 0; // Overview
      case 1: return 1; // Properties
      case 2: return 2; // Inquiries
      case 6: return 3; // Payment History
      case 3: return 4; // Subscription
      case 5: return 5; // Tenants
      case 4: return 6; // Profile
      case 8: return 7; // Referral
      default: return 0;
    }
  }

  bool _isIdentityPending() {
    if (_dealerStatus != null) {
      final identityStatus = _dealerStatus!['identity_status']?.toString().toLowerCase().trim() ?? '';
      if (identityStatus == 'pending') return true;

      final identityVerifiedRaw = _dealerStatus!['identity_verified'];
      final int identityVerified = identityVerifiedRaw is String
          ? int.tryParse(identityVerifiedRaw) ?? 0
          : (identityVerifiedRaw as int? ?? 0);
      final hasDoc = (_dealerStatus!['verification_document']?.toString().trim().isNotEmpty ?? false);
      if (identityVerified == 0 && hasDoc) return true;
    }

    final dynamic idVerifiedRaw = _profile?['identity_verified'];
    final int idVerified = (idVerifiedRaw is String)
        ? int.tryParse(idVerifiedRaw) ?? 0
        : (idVerifiedRaw as int? ?? 0);
    final bool hasDoc =
        _profile?['verification_document'] != null && _profile!['verification_document'].toString().trim().isNotEmpty;
    return idVerified == 0 && hasDoc;
  }

  Widget _buildIdentityPendingBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: const [
          Icon(Icons.hourglass_top, color: Colors.orange),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your account verification is being reviewed. Please wait for admin approval.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // First we check the dealer status API for the advanced status
    // If not available, fallback to profile logic
    String identityStatus = 'verified';
    
    if (_dealerStatus != null && _dealerStatus!.containsKey('identity_status')) {
      identityStatus = _dealerStatus!['identity_status'];
    } else {
      // Handle identity_verified coming as string "0" or int 0
      final dynamic idVerifiedRaw = _profile?['identity_verified'];
      final int idVerified = (idVerifiedRaw is String) 
          ? int.tryParse(idVerifiedRaw) ?? 0 
          : (idVerifiedRaw as int? ?? 0);
          
      final bool hasDoc = _profile?['verification_document'] != null && _profile!['verification_document'].toString().isNotEmpty;
      
      if (idVerified == 0) {
        if (hasDoc) {
          identityStatus = 'pending';
        } else {
          identityStatus = 'unverified';
        }
      }
    }
        
    // If dealer is unverified, show the lock screen on ALL tabs FIRST
    if (identityStatus != 'verified') {
      return Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (identityStatus == 'pending') ...[
                const Icon(Icons.hourglass_empty, size: 80, color: Colors.orange),
                const SizedBox(height: 24),
                const Text('Submitted, Waiting For Approval', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text(
                  'Submitted, waiting for approval.\n\nPlease check back within 1 to 24 hours.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Refresh the status to see if admin approved it
                      setState(() {
                        _isLoading = true;
                      });
                      _loadDashboardData();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Status', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                    ),
                  ),
                ),
              ] else if (identityStatus == 'rejected') ...[
                const Icon(Icons.cancel, size: 80, color: Colors.red),
                const SizedBox(height: 24),
                const Text('Verification Rejected', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Text(
                  _dealerStatus?['identity_message'] ?? 'Your identity document was rejected by the admin. Please upload a clear, valid document to proceed.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      context.push('/dealer-identity-verification', extra: _profile?['id']?.toString() ?? '');
                    },
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Re-upload Document', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.black87,
                    ),
                  ),
                ),
              ] else ...[
                const Icon(Icons.gpp_maybe, size: 80, color: Colors.orange),
                const SizedBox(height: 24),
                const Text('Identity Verification Required', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Text(
                  _dealerStatus?['identity_message'] ?? 'Your account is currently restricted. To access the Dealer Dashboard, manage properties, and view leads, you must verify your identity.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 16),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      context.push('/dealer-identity-verification', extra: _profile?['id']?.toString() ?? '');
                    },
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload Identity Document', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.black87,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Fallback to _subscription if _dealerStatus is missing keys
    final subData = _subscription;

    // Check if the user is completely locked out (inactive subscription)
    bool isPaymentLocked = false;
    if (_dealerStatus != null && _dealerStatus!.containsKey('is_payment_locked')) {
      isPaymentLocked = _dealerStatus!['is_payment_locked'] == true;
    } else if (_dealerStatus != null && _dealerStatus!.containsKey('is_locked')) {
      isPaymentLocked = _dealerStatus!['is_locked'] == true;
    } else if (subData != null && subData.containsKey('subscription_status')) {
      // Fallback check if API failed
      isPaymentLocked = subData['subscription_status'] != 'active';
    }

    if (isPaymentLocked) {
      // Allow access ONLY to Subscription (3) when locked out due to payment
      if (_selectedIndex != 3) {
        return Center(
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.lock, size: 80, color: Colors.red),
                const SizedBox(height: 24),
                const Text('Subscription Required', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text(
                  'Your subscription is inactive. Please renew your plan to manage properties and view leads.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 16),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedIndex = 3;
                      });
                    },
                    icon: const Icon(Icons.payment),
                    label: const Text('View Subscription Plans', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    switch (_selectedIndex) {
      case 1:
        return const DealerPropertiesScreen();
      case 2:
        return const Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tenant Inquiries', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 20),
              Expanded(child: DealerLeadsScreen()),
            ],
          ),
        );
      case 3:
        return const DealerSubscriptionScreen();
      case 4:
        return const DealerProfileScreen();
      case 5:
        return const DealerTenantsScreen();
      case 6:
        return const DealerPaymentHistoryScreen();
      case 7:
        return const NotificationsScreen();
      case 8:
        return const DealerReferralScreen();
      case 0:
      default:
        return _buildOverview();
    }
  }

  Widget _buildOverview() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Attempt to pull the real name from the check_status API first, fallback to the profile API
    final userName = _dealerStatus?['name'] ?? _profile?['name'] ?? 'Dealer';
    
    // Fallback to _subscription if _dealerStatus failed to load
    final subData = _subscription;
    
    // Check subscription status directly from the new synchronized API response
    // Or fallback to checking the string manually
    bool isSubActive = false;
    if (_dealerStatus != null && _dealerStatus!.containsKey('is_payment_locked')) {
      isSubActive = !(_dealerStatus!['is_payment_locked'] as bool);
    } else if (subData != null && subData.containsKey('subscription_status')) {
      isSubActive = subData['subscription_status'] == 'active';
    }
    
    // If they have no subscription record at all, or it's not active, show Free Trial
    String planName = 'Free Trial';
    if (_dealerStatus != null && _dealerStatus!.containsKey('plan_name')) {
      planName = _dealerStatus!['plan_name'];
    } else if (isSubActive) {
      planName = subData?['plan_name'] ?? 'Dealer Pro';
    }
    
    // Determine the color for the plan badge
    Color planBadgeColor = isSubActive ? const Color(0xFFFFC107) : Colors.orange;
    Color planBadgeBgColor = planBadgeColor.withOpacity(0.2);
    String planBadgeText = isSubActive ? 'Pro' : 'Free Trial';
    
    // Parse expiry date if available (even for free trials if they have an expiry set)
    String expiryDate = 'N/A';
    String? rawExpiry;
    if (_dealerStatus != null && _dealerStatus!.containsKey('subscription_expiry') && _dealerStatus!['subscription_expiry'] != null) {
      rawExpiry = _dealerStatus!['subscription_expiry'].toString();
    } else if (_subscription != null && _subscription!['subscription_expiry'] != null) {
      rawExpiry = _subscription!['subscription_expiry'].toString();
    }
    
    if (rawExpiry != null && rawExpiry.isNotEmpty) {
      try {
        DateTime dt = DateTime.parse(rawExpiry);
        // Format to a clean date: e.g. 24/02/2026
        expiryDate = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      } catch (e) {
        expiryDate = rawExpiry.split(' ').first;
      }
    }

    final totalProperties = _properties.length.toString();
    // Count active listings based on the status field from API
    final activeListings = _properties.where((p) {
      final status = p['status']?.toString().toLowerCase();
      return status == 'active' || status == 'available';
    }).length.toString();

    // Pull total tenants and total views directly from the dealerStatus API if available, else default to 0
    final activeTenants = _dealerStatus != null && _dealerStatus!['active_tenants'] != null 
        ? _dealerStatus!['active_tenants'].toString() 
        : '0';
    
    final totalViews = _dealerStatus != null && _dealerStatus!['total_views'] != null 
        ? _dealerStatus!['total_views'].toString() 
        : '0';
    
    // Recent payments from backend
    // Since we fetch it independently in _loadDashboardData and attach it to _dealerStatus, 
    // let's grab it safely here. If it's missing, default to empty.
    List<dynamic> recentPayments = [];
    if (_dealerStatus != null && _dealerStatus!.containsKey('recent_payments') && _dealerStatus!['recent_payments'] != null) {
      recentPayments = _dealerStatus!['recent_payments'] as List<dynamic>;
    }
    
    debugPrint('Building overview with ${recentPayments.length} recent payments');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Banner
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5A3D31), Color(0xFF8D6E63)], // Dark brown to a slightly lighter brown
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF5A3D31).withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // If the screen is too small, stack the text. Otherwise, put it in a row.
                if (constraints.maxWidth < 400) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome back, $userName!', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 8),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Plan: ', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: planBadgeBgColor, 
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: planBadgeColor.withOpacity(0.5)),
                            ),
                            child: Text(planBadgeText, style: TextStyle(color: planBadgeColor, fontSize: 12, fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Valid until', style: TextStyle(color: Colors.white70)),
                      Text(expiryDate, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Welcome back, $userName!', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 8),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('Plan: ', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: planBadgeBgColor, 
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: planBadgeColor.withOpacity(0.5)),
                                ),
                                child: Text(planBadgeText, style: TextStyle(color: planBadgeColor, fontSize: 12, fontWeight: FontWeight.bold)),
                              )
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Valid until', style: TextStyle(color: Colors.white70)),
                        Text(expiryDate, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    )
                  ],
                );
              }
            ),
          ),
          const SizedBox(height: 24),
          
          // Stats Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isSmall = constraints.maxWidth < 800;
              final cardWidth = isSmall 
                  ? constraints.maxWidth // 1 card per row on very small screens
                  : (constraints.maxWidth - 32) / 3; // 3 cards per row on large screens
              
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(width: cardWidth, child: _buildStatCard('Total Properties', totalProperties, Icons.home, Colors.brown.shade100, Colors.brown)),
                  SizedBox(width: cardWidth, child: _buildStatCard('Active Listings', activeListings, Icons.check_circle, Colors.orange.shade100, Colors.orange)),
                  SizedBox(width: cardWidth, child: _buildStatCard('Total Views', totalViews, Icons.visibility, Colors.teal.shade100, Colors.teal)),
                ],
              );
            }
          ),
          const SizedBox(height: 40),

          // Recent Payments Section
          // Removed the 'if (isSubActive)' check so it always shows the payment history,
          // regardless of whether the dealer is on a free trial or active subscription.
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Recent Payments', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      OutlinedButton(
                        onPressed: () => setState(() => _selectedIndex = 6), // 6 is DealerPaymentHistoryScreen
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue),
                        ),
                        child: const Text('View History'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                LayoutBuilder(
                  builder: (context, constraints) {
                    debugPrint('Rendering DataTable with ${recentPayments.length} payments');
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                        child: DataTable(
                          headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                          columns: const [
                            DataColumn(label: Text('REFERENCE')),
                            DataColumn(label: Text('AMOUNT')),
                            DataColumn(label: Text('STATUS')),
                            DataColumn(label: Text('DATE')),
                          ],
                          rows: recentPayments.isEmpty 
                            ? [_buildPaymentRow('No payments', '-', '-', '-')]
                            : recentPayments.map((payment) {
                                String dateStr = payment['created_at']?.toString() ?? '-';
                                if (dateStr.length > 10) {
                                  dateStr = dateStr.substring(0, 10); // Extract YYYY-MM-DD
                                }
                                return _buildPaymentRow(
                                  payment['reference']?.toString() ?? payment['payment_reference']?.toString() ?? 'Unknown',
                                  'ZMW ${payment['amount']?.toString() ?? '0.00'}',
                                  payment['status']?.toString() ?? 'Pending',
                                  dateStr,
                                );
                              }).toList(),
                        ),
                      ),
                    );
                  }
                ),
              ],
            ),
          ),
          
          if (!isSubActive)
             Container(
              margin: const EdgeInsets.only(top: 24),
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 40),
                  const SizedBox(height: 12),
                  const Text('Free Trial Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                  const SizedBox(height: 8),
                  const Text(
                    'You are currently using a free account with limited features. Upgrade to Dealer Pro to manage unlimited properties and view tenant leads.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _selectedIndex = 3),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Upgrade to Pro'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  DataRow _buildPaymentRow(String ref, String amount, String status, String date) {
    final isSuccess = status.toLowerCase() == 'successful' || 
                      status.toLowerCase() == 'completed' || 
                      status.toLowerCase() == 'success' || 
                      status.toLowerCase() == 'approved';

    return DataRow(cells: [
      DataCell(Text(ref, style: const TextStyle(fontWeight: FontWeight.w600))),
      DataCell(Text(amount, style: const TextStyle(fontWeight: FontWeight.bold))),
      DataCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSuccess ? Colors.green.shade50 : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSuccess ? Colors.green.shade200 : Colors.orange.shade200),
          ),
          child: Text(
            status.toUpperCase(), 
            style: TextStyle(
              color: isSuccess ? Colors.green : Colors.orange.shade700, 
              fontSize: 11, 
              fontWeight: FontWeight.bold
            )
          ),
        ),
      ),
      DataCell(Text(date, style: const TextStyle(color: Colors.black54))),
    ]);
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color bgColor, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 28, color: iconColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.black54, fontSize: 14)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
