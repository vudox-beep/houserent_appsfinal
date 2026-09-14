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
import 'agent_request_chat_screen.dart';
import '../../services/api_service.dart';
import '../../services/firebase_messaging_service.dart';
import '../../utils/app_error.dart';
import '../../widgets/skeleton_loader.dart';
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
  String _accountRole = 'dealer';

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
      final role = (profile['role'] ?? 'dealer').toString().toLowerCase();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('role', role);

      Map<String, dynamic>? statusData;
      if (userId.isNotEmpty) {
        try {
          statusData = await ApiService.checkPanelStatus(userId);
        } catch (_) {}
      }

      // Private company must complete details before using the panel.
      if (role == 'company' &&
          statusData != null &&
          statusData['needs_company_details'] == true) {
        if (mounted) {
          setState(() {
            _profile = profile;
            _accountRole = role;
            _dealerStatus = statusData;
            _isLoading = false;
          });
          context.go('/company-details');
        }
        return;
      }

      Map<String, dynamic>? tenantData;
      try {
        tenantData = await ApiService.fetchDealerTenantsAndActivity();
      } catch (_) {}

      List<dynamic> properties = [];
      int calculatedTotalViews = 0;
      try {
        final propResponse = await ApiService.fetchDealerProperties();
        properties = propResponse['data'] ?? [];
        for (var prop in properties) {
          calculatedTotalViews +=
              (int.tryParse(prop['views']?.toString() ?? '0') ?? 0);
        }
      } catch (_) {}

      Map<String, dynamic>? subscription;
      try {
        subscription = await ApiService.fetchDealerSubscription();
      } catch (_) {}

      List<dynamic> parsedRecentPayments = [];
      try {
        final paymentRes = await ApiService.fetchPaymentHistory();
        if (paymentRes is List) {
          parsedRecentPayments = paymentRes.take(5).toList();
        } else if (paymentRes is Map && paymentRes['transactions'] is List) {
          parsedRecentPayments = (paymentRes['transactions'] as List)
              .take(5)
              .toList();
        } else if (paymentRes is Map && paymentRes['data'] is List) {
          parsedRecentPayments = (paymentRes['data'] as List).take(5).toList();
        } else if (paymentRes is Map && paymentRes['payments'] is List) {
          parsedRecentPayments = (paymentRes['payments'] as List)
              .take(5)
              .toList();
        }
      } catch (e) {
        // suppressed
      }

      if (mounted) {
        setState(() {
          _profile = profile;
          _accountRole = role;
          _properties = properties;
          _subscription = subscription;
          _dealerStatus = statusData;

          if (_dealerStatus == null) {
            _dealerStatus = {};
          }

          if (tenantData != null) {
            _dealerStatus!['active_tenants'] =
                (tenantData['tenants'] as List?)?.length ?? 0;
          }

          _dealerStatus!['total_views'] = calculatedTotalViews;
          _dealerStatus!['recent_payments'] = parsedRecentPayments;
          if (statusData != null && statusData['subscription_fee'] != null) {
            _dealerStatus!['subscription_fee'] = statusData['subscription_fee'];
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppError.userMessage(
                e,
                fallback: 'Failed to load dashboard data.',
              ),
            ),
          ),
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

  Future<void> _logout() async {
    await FirebaseMessagingService.unregisterCurrentDevice();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('role');
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compactTopBar = MediaQuery.sizeOf(context).width < 600;
    // Determine subscription status safely
    bool isSubActive = false;
    if (_dealerStatus != null &&
        _dealerStatus!.containsKey('is_payment_locked')) {
      isSubActive = !(_dealerStatus!['is_payment_locked'] as bool);
    } else if (_subscription != null &&
        _subscription!.containsKey('subscription_status')) {
      isSubActive = _subscription!['subscription_status'] == 'active';
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey.shade50,
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(
                _accountRole == 'agent'
                    ? 'Agent Dashboard'
                    : _accountRole == 'company'
                        ? 'Company Dashboard'
                        : 'Dealer Dashboard',
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            if (!compactTopBar &&
                !_isLoading &&
                (_dealerStatus != null || _subscription != null))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSubActive
                      ? Colors.green.shade100
                      : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isSubActive ? 'Active Plan' : 'Expired/Inactive',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSubActive
                        ? Colors.green.shade800
                        : Colors.red.shade800,
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
          if (!compactTopBar)
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
          if (compactTopBar)
            PopupMenuButton<String>(
              tooltip: 'More actions',
              onSelected: (value) async {
                if (value == 'home') {
                  context.go('/home');
                } else if (value == 'logout') {
                  await _logout();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'home',
                  child: ListTile(
                    leading: Icon(Icons.home_outlined),
                    title: Text('Home'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('Log out'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Log out',
              onPressed: _logout,
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
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        selectedItemColor: const Color(0xFFFFC107),
        unselectedItemColor: isDark ? Colors.white60 : Colors.grey.shade700,
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
          if (_accountRole == 'agent')
            const BottomNavigationBarItem(
              icon: Icon(Icons.forum_outlined),
              activeIcon: Icon(Icons.forum),
              label: 'Hunt chat',
            ),
        ],
        currentIndex: _getBottomNavIndex(),
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
            if (index == 8 && _accountRole == 'agent') {
              _selectedIndex = 9; // House-hunt chat
            }
          });
        },
        type: BottomNavigationBarType.fixed,
        elevation: 16.0,
      ),
    );
  }

  int _getBottomNavIndex() {
    switch (_selectedIndex) {
      case 0:
        return 0; // Overview
      case 1:
        return 1; // Properties
      case 2:
        return 2; // Inquiries
      case 6:
        return 3; // Payment History
      case 3:
        return 4; // Subscription
      case 5:
        return 5; // Tenants
      case 4:
        return 6; // Profile
      case 8:
        return 7; // Referral
      case 9:
        return _accountRole == 'agent' ? 8 : 0; // Hunt chat
      default:
        return 0;
    }
  }

  bool _isIdentityPending() {
    if (_dealerStatus != null) {
      final identityStatus =
          _dealerStatus!['identity_status']?.toString().toLowerCase().trim() ??
          '';
      if (identityStatus == 'pending') return true;

      final identityVerifiedRaw = _dealerStatus!['identity_verified'];
      final int identityVerified = identityVerifiedRaw is String
          ? int.tryParse(identityVerifiedRaw) ?? 0
          : (identityVerifiedRaw as int? ?? 0);
      final hasDoc =
          (_dealerStatus!['verification_document']
              ?.toString()
              .trim()
              .isNotEmpty ??
          false);
      if (identityVerified == 0 && hasDoc) return true;
    }

    final dynamic idVerifiedRaw = _profile?['identity_verified'];
    final int idVerified = (idVerifiedRaw is String)
        ? int.tryParse(idVerifiedRaw) ?? 0
        : (idVerifiedRaw as int? ?? 0);
    final bool hasDoc =
        _profile?['verification_document'] != null &&
        _profile!['verification_document'].toString().trim().isNotEmpty;
    return idVerified == 0 && hasDoc;
  }

  Widget _buildIdentityPendingBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF2D2416), Color(0xFF3A2E1C)]
              : const [Color(0xFFFFF8E7), Color(0xFFFFF1D6)],
        ),
        border: Border.all(
          color: isDark ? Colors.orange.shade700 : const Color(0xFFE0B84A),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFC107).withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_top, color: Color(0xFF8A6500)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Verification under review',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1A140F),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Usually approved within 1–24 hours.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isDark ? Colors.white70 : const Color(0xFF6B5E52),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingApprovalPanel({
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required VoidCallback onRefresh,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const brown = Color(0xFF5A3D31);
    const gold = Color(0xFFFFC107);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white12 : const Color(0xFFE8E4DF),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Column(
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: gold.withValues(alpha: 0.28),
                  border: Border.all(color: gold, width: 2),
                  gradient: LinearGradient(
                    colors: [
                      gold.withValues(alpha: 0.4),
                      gold.withValues(alpha: 0.15),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  size: 44,
                  color: brown,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: gold),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pending_actions_rounded, size: 16, color: brown),
                    SizedBox(width: 6),
                    Text(
                      'UNDER REVIEW',
                      style: TextStyle(
                        color: brown,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Submitted — waiting for approval',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: primaryTextColor,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'We received your document. An admin will review it soon. Please check back within 1 to 24 hours.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 22),
              _buildReviewStep(
                done: true,
                title: 'Document submitted',
                subtitle: 'Your file is safely on file',
                isDark: isDark,
              ),
              _buildReviewStep(
                done: false,
                active: true,
                title: 'Admin review',
                subtitle: 'Usually takes 1–24 hours',
                isDark: isDark,
              ),
              _buildReviewStep(
                done: false,
                title: 'Account unlocked',
                subtitle: 'Full dealer dashboard access',
                isDark: isDark,
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onRefresh,
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
              foregroundColor: isDark ? Colors.white : Colors.black87,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.refresh_rounded,
                  size: 24,
                  color: isDark ? Colors.white : brown,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Refresh Status',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () {
              context.push(
                '/dealer-identity-verification',
                extra: _profile?['id']?.toString() ?? '',
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: Colors.black87,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.visibility_rounded, size: 24, color: Colors.black87),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'View submission',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewStep({
    required bool done,
    bool active = false,
    required String title,
    required String subtitle,
    required bool isDark,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: done
                      ? Colors.green.shade600
                      : active
                          ? const Color(0xFFFFC107)
                          : (isDark ? Colors.white12 : const Color(0xFFEEEAE5)),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: done
                        ? Colors.green.shade700
                        : active
                            ? const Color(0xFF8A6500)
                            : (isDark ? Colors.white24 : const Color(0xFFD5CFC7)),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  done
                      ? Icons.check_rounded
                      : active
                          ? Icons.hourglass_top_rounded
                          : Icons.lock_outline_rounded,
                  size: 18,
                  color: done
                      ? Colors.white
                      : active
                          ? const Color(0xFF5A3D31)
                          : (isDark ? Colors.white70 : Colors.black54),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 22,
                  margin: const EdgeInsets.only(top: 4),
                  color: isDark ? Colors.white12 : const Color(0xFFE8E4DF),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1A140F),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white60 : const Color(0xFF6B5E52),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_isLoading) {
      return const SkeletonDealerOverview();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    // First we check the dealer status API for the advanced status
    // If not available, fallback to profile logic
    String identityStatus = 'verified';

    if (_dealerStatus != null &&
        _dealerStatus!.containsKey('identity_status')) {
      identityStatus = _dealerStatus!['identity_status'];
    } else {
      // Handle identity_verified coming as string "0" or int 0
      final dynamic idVerifiedRaw = _profile?['identity_verified'];
      final int idVerified = (idVerifiedRaw is String)
          ? int.tryParse(idVerifiedRaw) ?? 0
          : (idVerifiedRaw as int? ?? 0);

      final bool hasDoc =
          _profile?['verification_document'] != null &&
          _profile!['verification_document'].toString().isNotEmpty;

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
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 40,
                maxWidth: 500,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (identityStatus == 'pending') ...[
                      _buildWaitingApprovalPanel(
                        primaryTextColor: primaryTextColor,
                        secondaryTextColor: secondaryTextColor,
                        onRefresh: () {
                          setState(() {
                            _isLoading = true;
                          });
                          _loadDashboardData();
                        },
                      ),
                    ] else if (identityStatus == 'rejected') ...[
                      const Icon(Icons.cancel, size: 80, color: Colors.red),
                      const SizedBox(height: 24),
                      Text(
                        'Verification Rejected',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _dealerStatus?['identity_message'] ??
                            'Your identity document was rejected by the admin. Please upload a clear, valid document to proceed.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            context.push(
                              '/dealer-identity-verification',
                              extra: _profile?['id']?.toString() ?? '',
                            );
                          },
                          icon: const Icon(Icons.upload_file),
                          label: const Text(
                            'Re-upload Document',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC107),
                            foregroundColor: Colors.black87,
                          ),
                        ),
                      ),
                    ] else ...[
                      const Icon(Icons.gpp_maybe, size: 80, color: Colors.orange),
                      const SizedBox(height: 24),
                      Text(
                        'Identity Verification Required',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _dealerStatus?['identity_message'] ??
                            'Your account is currently restricted. To access the Dealer Dashboard, manage properties, and view leads, you must verify your identity.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: secondaryTextColor,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            context.push(
                              '/dealer-identity-verification',
                              extra: _profile?['id']?.toString() ?? '',
                            );
                          },
                          icon: const Icon(Icons.upload_file),
                          label: const Text(
                            'Upload Identity Document',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
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
            ),
          );
        },
      );
    }

    // Fallback to _subscription if _dealerStatus is missing keys
    final subData = _subscription;

    // Check if the user is completely locked out (inactive subscription)
    bool isPaymentLocked = false;
    if (_dealerStatus != null &&
        _dealerStatus!.containsKey('is_payment_locked')) {
      isPaymentLocked = _dealerStatus!['is_payment_locked'] == true;
    } else if (_dealerStatus != null &&
        _dealerStatus!.containsKey('is_locked')) {
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
                Text(
                  'Subscription Required',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your subscription is inactive. Please renew your plan to manage properties and view leads.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondaryTextColor, fontSize: 16),
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
                    label: const Text(
                      'View Subscription Plans',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
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
          child: DealerLeadsScreen(),
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
      case 9:
        return const AgentRequestChatListScreen();
      case 0:
      default:
        return _buildOverview();
    }
  }

  Widget _buildOverview() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const brown = Color(0xFF5A3D31);
    const gold = Color(0xFFFFC107);
    final titleColor = isDark ? Colors.white : const Color(0xFF1A140F);
    final muted = isDark ? Colors.white70 : const Color(0xFF6B5E52);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final border = isDark ? Colors.white12 : const Color(0xFFE8E4DF);

    final userName = _dealerStatus?['name'] ?? _profile?['name'] ?? 'Dealer';
    final subData = _subscription;

    bool isSubActive = false;
    if (_dealerStatus != null &&
        _dealerStatus!.containsKey('is_payment_locked')) {
      isSubActive = !(_dealerStatus!['is_payment_locked'] as bool);
    } else if (subData != null && subData.containsKey('subscription_status')) {
      isSubActive = subData['subscription_status'] == 'active';
    }

    String planName = 'Free Trial';
    if (_dealerStatus != null && _dealerStatus!.containsKey('plan_name')) {
      planName = _dealerStatus!['plan_name'].toString();
    } else if (isSubActive) {
      planName = subData?['plan_name']?.toString() ?? 'Dealer Pro';
    }

    String expiryDate = 'N/A';
    String? rawExpiry;
    if (_dealerStatus != null &&
        _dealerStatus!['subscription_expiry'] != null) {
      rawExpiry = _dealerStatus!['subscription_expiry'].toString();
    } else if (_subscription != null &&
        _subscription!['subscription_expiry'] != null) {
      rawExpiry = _subscription!['subscription_expiry'].toString();
    }
    if (rawExpiry != null && rawExpiry.isNotEmpty) {
      try {
        final dt = DateTime.parse(rawExpiry);
        expiryDate =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      } catch (_) {
        expiryDate = rawExpiry.split(' ').first;
      }
    }

    final totalProperties = _properties.length.toString();
    final activeListings = _properties
        .where((p) {
          final status = p['status']?.toString().toLowerCase();
          return status == 'active' || status == 'available';
        })
        .length
        .toString();
    final activeTenants =
        _dealerStatus?['active_tenants']?.toString() ?? '0';
    final totalViews = _dealerStatus?['total_views']?.toString() ?? '0';

    List<dynamic> recentPayments = [];
    if (_dealerStatus?['recent_payments'] is List) {
      recentPayments = _dealerStatus!['recent_payments'] as List<dynamic>;
    }

    return RefreshIndicator(
      color: brown,
      onRefresh: () async {
        setState(() => _isLoading = true);
        await _loadDashboardData();
        await _loadUnreadData();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5A3D31), Color(0xFF8A6554)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Welcome back,\n$userName',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: gold.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: gold.withValues(alpha: 0.7)),
                      ),
                      child: Text(
                        isSubActive ? 'PRO' : 'TRIAL',
                        style: const TextStyle(
                          color: gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  planName,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Valid until $expiryDate',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: () async {
                final updated = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DealerAddPropertyScreen(),
                  ),
                );
                if (updated == true && mounted) {
                  setState(() => _isLoading = true);
                  await _loadDashboardData();
                }
              },
              icon: const Icon(Icons.add_home_work_outlined),
              label: const Text(
                'Upload property',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Properties',
                  totalProperties,
                  Icons.home_work_outlined,
                  gold.withValues(alpha: 0.2),
                  brown,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Active',
                  activeListings,
                  Icons.check_circle_outline,
                  Colors.green.shade50,
                  Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Tenants',
                  activeTenants,
                  Icons.people_outline,
                  Colors.blue.shade50,
                  Colors.blue.shade700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Views',
                  totalViews,
                  Icons.visibility_outlined,
                  Colors.teal.shade50,
                  Colors.teal.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Text(
                'Recent payments',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: titleColor,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _selectedIndex = 6),
                child: const Text(
                  'View all',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: brown,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (recentPayments.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 36, color: muted),
                  const SizedBox(height: 10),
                  Text(
                    'No recent payments',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Subscription and rent payments will show here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            ...recentPayments.take(5).map((payment) {
              final status = payment['status']?.toString() ?? 'Pending';
              var dateStr = payment['created_at']?.toString() ?? '-';
              if (dateStr.length > 10) dateStr = dateStr.substring(0, 10);
              final ref = payment['reference']?.toString() ??
                  payment['payment_reference']?.toString() ??
                  'Payment';
              final amount =
                  'ZMW ${payment['amount']?.toString() ?? '0.00'}';
              return _buildPaymentTile(
                ref: ref,
                amount: amount,
                status: status,
                date: dateStr,
                cardBg: cardBg,
                border: border,
                titleColor: titleColor,
                muted: muted,
              );
            }),
          if (!isSubActive) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2118) : const Color(0xFFFFF8E7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: gold.withValues(alpha: 0.55),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.workspace_premium_outlined, color: brown),
                      const SizedBox(width: 8),
                      Text(
                        'Upgrade your plan',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: titleColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You are on a free trial. Upgrade to Dealer Pro for unlimited listings and full lead access.',
                    style: TextStyle(
                      color: muted,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      onPressed: () => setState(() => _selectedIndex = 3),
                      style: FilledButton.styleFrom(
                        backgroundColor: brown,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Upgrade to Pro',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentTile({
    required String ref,
    required String amount,
    required String status,
    required String date,
    required Color cardBg,
    required Color border,
    required Color titleColor,
    required Color muted,
  }) {
    final ok = status.toLowerCase() == 'successful' ||
        status.toLowerCase() == 'completed' ||
        status.toLowerCase() == 'success' ||
        status.toLowerCase() == 'approved';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ok
                  ? Colors.green.withValues(alpha: 0.12)
                  : const Color(0xFFFFC107).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              ok ? Icons.check_circle_outline : Icons.schedule,
              color: ok ? Colors.green.shade700 : const Color(0xFF5A3D31),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ref,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: titleColor,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date,
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: titleColor,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: ok
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: ok ? Colors.green.shade800 : Colors.orange.shade800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color bgColor,
    Color iconColor,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE8E4DF),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? iconColor.withValues(alpha: 0.18) : bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF1A140F),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white60 : const Color(0xFF6B5E52),
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
