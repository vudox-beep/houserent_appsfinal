import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../utils/app_error.dart';
import '../../widgets/skeleton_loader.dart';
import '../home_screen.dart'; // Import PropertyCard from home_screen.dart
import '../notifications_screen.dart';

const List<String> _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

DateTime? _tryParseDate(dynamic value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;

  final direct = DateTime.tryParse(raw);
  if (direct != null) return direct;

  // Handles values like "Apr 05, 2026".
  final parts = raw.split(',');
  if (parts.length == 2) {
    final left = parts[0].trim().split(RegExp(r'\s+'));
    final year = int.tryParse(parts[1].trim());
    if (left.length == 2 && year != null) {
      const shortMonths = <String>[
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final monthIndex = shortMonths.indexOf(left[0]);
      final day = int.tryParse(left[1]);
      if (monthIndex >= 0 && day != null) {
        return DateTime(year, monthIndex + 1, day);
      }
    }
  }

  return null;
}

String _formatDate(DateTime date) => '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';

String _calculateNextDueDate(Map<String, dynamic>? rental) {
  if (rental == null) return '--';

  final parsedApiDue = _tryParseDate(rental['next_due_date']);
  if (parsedApiDue != null) {
    return _formatDate(parsedApiDue);
  }

  final rawApiDue = rental['next_due_date']?.toString().trim();
  if (rawApiDue != null && rawApiDue.isNotEmpty) {
    return rawApiDue;
  }

  final now = DateTime.now();
  final start = _tryParseDate(rental['start_date']) ?? now;
  final startDay = start.day;

  final latestPayment = rental['latest_payment'];
  if (latestPayment is Map<String, dynamic>) {
    final monthYearRaw = latestPayment['month_year']?.toString().trim() ?? '';
    final monthYearParts = monthYearRaw.split(RegExp(r'\s+'));
    if (monthYearParts.length == 2) {
      final year = int.tryParse(monthYearParts[1]);
      final monthName = monthYearParts[0];
      final monthIndex = _monthNames.indexWhere((m) => m == monthName);
      if (year != null && monthIndex >= 0) {
        var monthsPaid = int.tryParse('${latestPayment['months_paid'] ?? ''}') ?? 0;
        if (monthsPaid < 1) {
          final paidAmount = double.tryParse('${latestPayment['amount'] ?? ''}') ?? 0;
          final rentAmount = double.tryParse('${rental['rent_amount'] ?? rental['price'] ?? ''}') ?? 0;
          if (rentAmount > 0) {
            monthsPaid = (paidAmount / rentAmount).round();
          }
          if (monthsPaid < 1) monthsPaid = 1;
        }

        final monthBase = DateTime(year, monthIndex + 1, 1);
        final dueBase = DateTime(monthBase.year, monthBase.month + monthsPaid, 1);
        final lastDay = DateTime(dueBase.year, dueBase.month + 1, 0).day;
        final due = DateTime(dueBase.year, dueBase.month, startDay <= lastDay ? startDay : lastDay);
        return _formatDate(due);
      }
    }
  }

  // Fallback to next cycle using rental start day.
  var dueYear = now.year;
  var dueMonth = now.month;
  if (now.day > startDay) {
    dueMonth += 1;
    if (dueMonth > 12) {
      dueMonth = 1;
      dueYear += 1;
    }
  }
  final daysInMonth = DateTime(dueYear, dueMonth + 1, 0).day;
  final dueDay = startDay <= daysInMonth ? startDay : daysInMonth;
  return _formatDate(DateTime(dueYear, dueMonth, dueDay));
}

class TenantDashboard extends StatefulWidget {
  final int initialTabIndex;

  const TenantDashboard({super.key, this.initialTabIndex = 0});

  @override
  State<TenantDashboard> createState() => _TenantDashboardState();
}

class _TenantDashboardState extends State<TenantDashboard> {
  int _selectedIndex = 0;
  int _unreadNotifications = 0;

  static final List<Widget> _widgetOptions = <Widget>[
    const _TenantOverviewTab(),
    const _TenantRentalsTab(),
    const _TenantPaymentsTab(),
    const _TenantProfileTab(),
    const _TenantSavedTab(),
    const NotificationsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final notifs = await ApiService.fetchNotifications();
      if (mounted) {
        setState(() {
          _unreadNotifications = notifs.where((n) => n['is_read'] == 0).length;
        });
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(TenantDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    print("TenantDashboard didUpdateWidget: new ${widget.initialTabIndex}, old ${oldWidget.initialTabIndex}");
    if (widget.initialTabIndex != oldWidget.initialTabIndex) {
      setState(() {
        _selectedIndex = widget.initialTabIndex;
      });
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('role');
    if (context.mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF5A3D31),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: const Text(
          'Tenant Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Home',
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
                onPressed: () => setState(() => _selectedIndex = 5),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          )
        ],
      ),
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.key_outlined),
            activeIcon: Icon(Icons.key),
            label: 'My Rentals',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.payment_outlined),
            activeIcon: Icon(Icons.payment),
            label: 'Payments',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            activeIcon: Icon(Icons.favorite),
            label: 'Saved',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              label: Text('$_unreadNotifications'),
              isLabelVisible: _unreadNotifications > 0,
              child: const Icon(Icons.notifications_outlined),
            ),
            activeIcon: Badge(
              label: Text('$_unreadNotifications'),
              isLabelVisible: _unreadNotifications > 0,
              child: const Icon(Icons.notifications),
            ),
            label: 'Alerts',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFF5A3D31),
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

class _TenantOverviewTab extends StatefulWidget {
  const _TenantOverviewTab();

  @override
  State<_TenantOverviewTab> createState() => _TenantOverviewTabState();
}

class _TenantOverviewTabState extends State<_TenantOverviewTab> {
  Map<String, dynamic>? _profile;
  List<dynamic> _rentals = [];
  List<dynamic> _payments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final profile = await ApiService.getProfile();
      final rentals = await ApiService.fetchMyRentals();
      final payments = await ApiService.fetchPaymentHistory();

      setState(() {
        _profile = profile;
        _rentals = rentals;
        _payments = payments;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SkeletonTenantOverview();
    }

    final userName = _profile?['name'] ?? 'Tenant';
    final userEmail = _profile?['email'] ?? 'your email';
    
    final hasRental = _rentals.isNotEmpty;
    final currentRental = hasRental ? _rentals.first['title'] ?? 'Active Rental' : 'None';
    
    final nextDueDate = hasRental ? _calculateNextDueDate(_rentals.first as Map<String, dynamic>?) : '--'; 
    final lastPayment = _payments.isNotEmpty ? 'ZMW ${_payments.first['amount']}' : '--';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome back, $userName!', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
          const SizedBox(height: 8),
          const Text('Manage your rental and payments.', style: TextStyle(fontSize: 16, color: Colors.black54)),
          const SizedBox(height: 24),
          
          // Summary Cards Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isSmall = constraints.maxWidth < 600;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: isSmall ? double.infinity : (constraints.maxWidth - 32) / 3,
                    child: _buildInfoCard(context, 'Current Rental', currentRental, Icons.home, Colors.brown.shade100, Colors.brown),
                  ),
                  SizedBox(
                    width: isSmall ? double.infinity : (constraints.maxWidth - 32) / 3,
                    child: _buildInfoCard(context, 'Next Due Date', nextDueDate, Icons.calendar_today, Colors.orange.shade100, Colors.orange),
                  ),
                  SizedBox(
                    width: isSmall ? double.infinity : (constraints.maxWidth - 32) / 3,
                    child: _buildInfoCard(context, 'Last Payment', lastPayment, Icons.account_balance_wallet, Colors.green.shade100, Colors.green),
                  ),
                ],
              );
            }
          ),
          
          const SizedBox(height: 24),
          
          if (!hasRental)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.lightBlue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.lightBlue.shade100),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info, color: Colors.lightBlue, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('No Active Rental Found', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF005b9f), fontSize: 16)),
                        const SizedBox(height: 4),
                        Text.rich(
                          TextSpan(
                            text: 'You are not currently linked to any property. Ask your landlord/dealer to add you to their property using your email: ',
                            style: TextStyle(color: Colors.blueGrey.shade800),
                            children: [
                              TextSpan(text: userEmail, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          const SizedBox(height: 40),
          
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
                        onPressed: () {
                          // Navigate to payments tab
                          final state = context.findAncestorStateOfType<_TenantDashboardState>();
                          if (state != null) {
                            state.setState(() {
                              state._selectedIndex = 2; // Payments tab index
                            });
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('View History'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                    columns: const [
                      DataColumn(label: Text('MONTH')),
                      DataColumn(label: Text('AMOUNT')),
                      DataColumn(label: Text('PROOF')),
                      DataColumn(label: Text('STATUS')),
                      DataColumn(label: Text('DATE UPLOADED')),
                    ],
                    rows: _payments.take(5).map((payment) {
                      return DataRow(cells: [
                        DataCell(Text(payment['month_year'] ?? 'N/A')),
                        DataCell(Text('${payment['currency'] ?? 'ZMW'} ${payment['amount'] ?? '0.00'}')),
                        DataCell(
                          payment['proof_file'] != null
                              ? const Icon(Icons.description, color: Colors.blue)
                              : const Text('--'),
                        ),
                        DataCell(Text((payment['status'] ?? 'pending').toString().toUpperCase())),
                        DataCell(Text(payment['created_at']?.substring(0, 10) ?? 'N/A')),
                      ]);
                    }).toList(),
                  ),
                ),
                if (_payments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: Text('No recent payments.', style: TextStyle(color: Colors.black54)),
                    ),
                  ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String title, String value, IconData icon, Color bgColor, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.black54, fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TenantRentalsTab extends StatefulWidget {
  const _TenantRentalsTab();

  @override
  State<_TenantRentalsTab> createState() => _TenantRentalsTabState();
}

class _TenantRentalsTabState extends State<_TenantRentalsTab> {
  List<dynamic> _rentals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRentals();
  }

  Future<void> _loadRentals() async {
    try {
      final rentals = await ApiService.fetchMyRentals();
      if (mounted) {
        setState(() {
          _rentals = rentals;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SkeletonTenantRentals();
    }

    if (_rentals.isEmpty) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text('You have no active rentals.', style: TextStyle(fontSize: 18, color: Colors.black54)),
        ),
      );
    }

    return Container(
      color: Colors.white,
      child: ListView.builder(
        padding: const EdgeInsets.all(24.0),
        itemCount: _rentals.length,
        itemBuilder: (context, index) {
          final rentalRaw = _rentals[index];
          final rental = rentalRaw is Map
              ? Map<String, dynamic>.from(rentalRaw)
              : <String, dynamic>{};
          final latestPayment = rental['latest_payment'];
          
          final dueDate = _calculateNextDueDate(rental); 
          final status = latestPayment != null && latestPayment['status'] == 'completed' ? 'Paid' : 'Due';

          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(rental['title'] ?? 'Property Title', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: status == 'Paid' ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: status == 'Paid' ? Colors.green : Colors.red),
                        ),
                        child: Text(
                          status, 
                          style: TextStyle(fontWeight: FontWeight.bold, color: status == 'Paid' ? Colors.green : Colors.red)
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.black54),
                      const SizedBox(width: 4),
                      Text(rental['location'] ?? 'Location', style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Divider(),
                  ),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Monthly Rent', style: TextStyle(color: Colors.black54)),
                          const SizedBox(height: 4),
                          Text('ZMW ${rental['rent_amount'] ?? rental['price'] ?? 0}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Next Due Date', style: TextStyle(color: Colors.black54)),
                          const SizedBox(height: 4),
                          Text(dueDate, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      ElevatedButton(
                        onPressed: status == 'Paid' ? null : () {
                          // Implement pay rent flow by switching to payments tab
                          final state = context.findAncestorStateOfType<_TenantDashboardState>();
                          if (state != null) {
                            state.setState(() {
                              state._selectedIndex = 2; // Payments tab index
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: status == 'Paid' ? Colors.grey : const Color(0xFFFFC107),
                          foregroundColor: Colors.black87,
                        ),
                        child: Text(status == 'Paid' ? 'Paid' : 'Pay Rent', style: const TextStyle(fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: Colors.black54),
                        const SizedBox(width: 8),
                        Text('Landlord: ${rental['landlord_name'] ?? 'N/A'}'),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.phone, color: Colors.blue),
                          onPressed: () {},
                          tooltip: 'Call Landlord',
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TenantPaymentsTab extends StatefulWidget {
  const _TenantPaymentsTab();

  @override
  State<_TenantPaymentsTab> createState() => _TenantPaymentsTabState();
}

class _TenantPaymentsTabState extends State<_TenantPaymentsTab> {
  List<dynamic> _payments = [];
  bool _isLoading = true;
  String? _selectedProofImagePath;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    try {
      final data = await ApiService.fetchTenantDashboardData();
      if (mounted) {
        setState(() {
          _payments = data['payment_history'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load tenant payments: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showMakePaymentDialog(BuildContext context) async {
    // Show a loading dialog while fetching rentals
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFFFFC107))),
    );

    try {
      // Instead of relying solely on the specific backend 'rental_info' structure that might be failing,
      // let's fetch the user's active rentals directly to populate the form
      final data = await ApiService.fetchTenantDashboardData();
      final rentalInfo = data['rental_info'];
      final rentalsList = await ApiService.fetchMyRentals();
      
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (rentalsList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active rental found to make a payment for.'), backgroundColor: Colors.red));
        return;
      }

      // Use the first active rental for the form
      final activeRental = rentalsList.first;

      String selectedRentalId = activeRental['id']?.toString() ?? '';
      String amount = (activeRental['rent_amount'] ?? activeRental['price'] ?? '0').toString();
      
      // Auto-calculate the next month for the default Month/Year value
      final now = DateTime.now();
      const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
      int nextMonthIndex = now.day > 5 ? now.month : now.month - 1;
      int year = now.year;
      if (nextMonthIndex == 12) {
        nextMonthIndex = 0;
        year++;
      }
      String monthYear = '${monthNames[nextMonthIndex]} $year';
      
      String paymentMethod = 'Bank Transfer';
      
      // Generate a 16-digit reference number (e.g. 1774380755123456)
      String generateRef() {
        String timestamp = DateTime.now().millisecondsSinceEpoch.toString(); // 13 digits
        String random = (100 + (DateTime.now().microsecond % 900)).toString(); // 3 digits
        return timestamp + random;
      }
      String referenceNumber = generateRef();
      
      // Extract dealer payment details
      String dealerBankName = rentalInfo?['bank_name'] ?? 'Not provided';
      String dealerBankAccount = rentalInfo?['bank_account'] ?? 'Not provided';
      String dealerMobileMoney = rentalInfo?['dealer_phone'] ?? 'Not provided';
      
      _selectedProofImagePath = null;
      bool isSubmitting = false;

      showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Container(
                  width: 500,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Make a Payment', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            )
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Rental Property', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4B5563))),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    initialValue: activeRental['title'] ?? 'Unknown Property',
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                      filled: true,
                                      fillColor: Colors.grey.shade100,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Reference No.', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4B5563))),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    initialValue: referenceNumber,
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                      filled: true,
                                      fillColor: Colors.grey.shade100,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Amount (ZMW)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4B5563))),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    initialValue: amount,
                                    decoration: InputDecoration(
                                      prefixText: 'K ',
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    ),
                                    keyboardType: TextInputType.number,
                                    onChanged: (val) => amount = val,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Month/Year', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4B5563))),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    initialValue: monthYear,
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                    ),
                                    onChanged: (val) => monthYear = val,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4B5563))),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: paymentMethod,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Bank Transfer', child: Text('Bank Transfer')),
                            DropdownMenuItem(value: 'Mobile Money', child: Text('Mobile Money')),
                            DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                paymentMethod = value;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        // Show Dealer Payment Info based on selection
                        if (paymentMethod != 'Cash') ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Payment Instructions', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                const SizedBox(height: 8),
                                if (paymentMethod == 'Bank Transfer') ...[
                                  Text('Bank: $dealerBankName'),
                                  Text('Account: $dealerBankAccount'),
                                ] else if (paymentMethod == 'Mobile Money') ...[
                                  Text('Mobile Money Number: $dealerMobileMoney'),
                                ],
                                const SizedBox(height: 8),
                                const Text('Please use the Reference No. above as your payment reference.', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text('Upload Proof of Payment (Image/PDF)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4B5563))),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
                              FilePickerResult? result = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
                              );
                              if (result != null) {
                                setDialogState(() {
                                  _selectedProofImagePath = result.files.single.path;
                                });
                              }
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid),
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.grey.shade50,
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.upload_file, color: Colors.blue.shade400, size: 32),
                                  const SizedBox(height: 8),
                                  Text(
                                    _selectedProofImagePath != null 
                                        ? _selectedProofImagePath!.split('\\').last.split('/').last 
                                        : 'Tap to select file',
                                    style: TextStyle(color: _selectedProofImagePath != null ? Colors.green : Colors.black54),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ] else ...[
                          const SizedBox(height: 16),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isSubmitting ? null : () async {
                              if (paymentMethod != 'Cash' && _selectedProofImagePath == null) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload a proof of payment')));
                                return;
                              }
                              
                              setDialogState(() => isSubmitting = true);
                              try {
                                final res = await ApiService.uploadTenantProof(
                                  selectedRentalId, 
                                  monthYear, 
                                  amount, 
                                  paymentMethod,
                                  referenceNumber,
                                  _selectedProofImagePath
                                );
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  if (res['status'] == 'success') {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment submitted successfully!'), backgroundColor: Colors.green));
                                    _loadPayments();
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Failed to submit payment'), backgroundColor: Colors.red));
                                  }
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(AppError.userMessage(e, fallback: 'Unable to submit payment right now.')),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  setDialogState(() => isSubmitting = false);
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF5A3D31),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: isSubmitting 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Submit Payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              );
            }
          );
        },
      );

    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e, fallback: 'Unable to load rental information.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SkeletonTenantTable();
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Payment History', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: () => _showMakePaymentDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Make Payment', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107), // Updated to yellow
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_payments.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No payment history found.', style: TextStyle(fontSize: 18, color: Colors.black54)),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _payments.length,
                itemBuilder: (context, index) {
                  final payment = _payments[index];
                  final status = payment['status'] ?? 'pending';
                  
                  Color statusColor = Colors.orange;
                  if (status == 'approved') statusColor = Colors.green;
                  if (status == 'rejected') statusColor = Colors.red;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.receipt_long, color: Colors.blue),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(payment['property_title'] ?? 'Property Rent', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text('Month: ${payment['month_year'] ?? 'N/A'} • Method: ${payment['payment_method'] ?? 'N/A'}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                                const SizedBox(height: 4),
                                Text('Date: ${payment['created_at']?.substring(0, 10) ?? 'N/A'}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${payment['currency'] ?? 'ZMW'} ${payment['amount'] ?? '0.00'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  status.toString().toUpperCase(),
                                  style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TenantSavedTab extends StatefulWidget {
  const _TenantSavedTab();

  @override
  State<_TenantSavedTab> createState() => _TenantSavedTabState();
}

class _TenantSavedTabState extends State<_TenantSavedTab> {
  List<dynamic> _saved = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    try {
      final saved = await ApiService.fetchFavorites();
      if (mounted) {
        setState(() {
          _saved = saved;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AppError.userMessage(e, fallback: 'Unable to load saved properties.');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SkeletonTenantRentals();
    }

    return Container(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Saved Properties', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                    const SizedBox(height: 4),
                    const Text('Your favorite listings.', style: TextStyle(fontSize: 14, color: Colors.black54)),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    context.go('/home');
                  },
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Browse More', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null)
               Expanded(child: Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))))
            else if (_saved.isEmpty)
              Expanded(
                child: Container(
                  width: double.infinity,
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
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_border, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      const Text('No saved properties yet', style: TextStyle(fontSize: 20, color: Colors.black54)),
                      const SizedBox(height: 8),
                      const Text('Start browsing and save properties you like!', style: TextStyle(color: Colors.black45)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          context.go('/home');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFC107),
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: const Text('Browse Properties', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: MediaQuery.of(context).size.width > 800 ? 4 : (MediaQuery.of(context).size.width > 500 ? 3 : 2),
                    childAspectRatio: MediaQuery.of(context).size.width < 400 ? 0.52 : 0.60, // Further reduced aspect ratio to fix bottom overflow completely
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _saved.length,
                  itemBuilder: (context, index) {
                        // Map the API output to the format PropertyCard expects
                      final property = Map<String, dynamic>.from(_saved[index]);
                      
                      // Convert formatted URL strings back into a list format if needed for PropertyCard fallback
                      // But since PropertyCard now correctly parses `main_image` directly, we don't need to do much!
                      if (property['main_image'] != null) {
                        // Clean up any literal backticks if they exist
                        String mainImg = property['main_image'].toString().trim();
                        property['main_image'] = mainImg.replaceAll('`', '');
                      }
                      
                      return PropertyCard(
                        property: property,
                        isFeatured: property['is_featured']?.toString() == '1',
                      ); 
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TenantProfileTab extends StatefulWidget {
  const _TenantProfileTab();

  @override
  State<_TenantProfileTab> createState() => _TenantProfileTabState();
}

class _TenantProfileTabState extends State<_TenantProfileTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final data = await ApiService.getProfile();
      if (mounted) {
        setState(() {
          _nameController.text = data['name']?.toString() ?? '';
          _emailController.text = data['email']?.toString() ?? '';
          _phoneController.text = data['phone']?.toString() ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AppError.userMessage(e, fallback: 'Unable to load profile details.');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await ApiService.updateProfile(_nameController.text, _phoneController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppError.userMessage(e, fallback: 'Failed to update profile.')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SkeletonProfile();
    }

    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)));
    }

    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Form(
            key: _formKey,
            child: Container(
              width: 600,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Profile Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 32),
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.grey.shade200,
                          child: const Icon(Icons.person, size: 60, color: Colors.grey),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFC107),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, size: 20, color: Colors.black87),
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text('Full Name', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    validator: (value) => value == null || value.isEmpty ? 'Please enter your name' : null,
                  ),
                  const SizedBox(height: 20),
                  const Text('Email Address', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    readOnly: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.email_outlined),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Phone Number', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) => value == null || value.isEmpty ? 'Please enter your phone number' : null,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC107),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
