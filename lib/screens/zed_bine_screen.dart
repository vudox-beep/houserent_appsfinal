import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'home_screen.dart'; // To use PropertyCard

class ZedBineScreen extends StatefulWidget {
  const ZedBineScreen({super.key});

  @override
  State<ZedBineScreen> createState() => _ZedBineScreenState();
}

class _ZedBineScreenState extends State<ZedBineScreen> {
  bool _isLoading = true;
  List<dynamic> _services = [];
  String _selectedCategory = 'All';
  final List<Map<String, dynamic>> _categories = [
    {'name': 'All', 'icon': Icons.apps, 'label': 'All'},
    {'name': 'Salon & Beauty', 'icon': Icons.face_retouching_natural, 'label': 'Beauty'},
    {'name': 'Gadgets', 'icon': Icons.smartphone, 'label': 'Gadgets'},
    {'name': 'Repairs', 'icon': Icons.home_repair_service, 'label': 'Repairs'},
    {'name': 'Other Services', 'icon': Icons.handyman, 'label': 'Other'},
  ];
  
  int _publicNotifBadgeCount = 0;
  int _houseHuntBadgeCount = 0;
  final String _publicNotifBadgeCountKey = 'public_notif_badge_count';
  final String _houseHuntBadgeCountKey = 'house_hunt_badge_count';

  bool _isLoggedIn = false;
  String _userRole = 'tenant';

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _loadServices();
    _loadBadges();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final role = prefs.getString('role');
    
    if (token != null && token.isNotEmpty) {
      if (mounted) {
        setState(() {
          _isLoggedIn = true;
          _userRole = (role != null && role.isNotEmpty) ? role : 'tenant';
        });
      }
    }
  }

  void _showLoginRequiredPopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Login Required',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        content: const Text(
          'Please login to access this feature.',
          style: TextStyle(height: 1.4, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not now', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFC107),
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Login', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadBadges() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _publicNotifBadgeCount = prefs.getInt(_publicNotifBadgeCountKey) ?? 0;
      _houseHuntBadgeCount = prefs.getInt(_houseHuntBadgeCountKey) ?? 0;
    });
  }

  Future<void> _loadServices() async {
    try {
      final properties = await ApiService.fetchProperties();
      if (!mounted) return;

      final zedBineTypes = ['salon', 'gadget', 'mechanic', 'other_service'];

      final filtered = properties.where((p) {
        final type = (p['property_type'] ?? p['type'] ?? '').toString().toLowerCase();
        return zedBineTypes.contains(type);
      }).toList();

      setState(() {
        _services = filtered;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load services: $e')),
        );
      }
    }
  }

  List<dynamic> get _filteredServices {
    if (_selectedCategory == 'All') return _services;
    
    return _services.where((s) {
      final rawType = (s['property_type'] ?? s['type'] ?? '').toString().toLowerCase();
      if (_selectedCategory == 'Salon & Beauty' && rawType == 'salon') return true;
      if (_selectedCategory == 'Gadgets' && rawType == 'gadget') return true;
      if (_selectedCategory == 'Repairs' && (rawType == 'mechanic' || rawType == 'gadget')) return true; // Show gadgets under repairs if they are related
      if (_selectedCategory == 'Other Services' && rawType == 'other_service') return true;
      return false;
    }).toList();
  }

  List<dynamic> _latestServices() {
    final list = List<dynamic>.from(_filteredServices);
    list.sort((a, b) {
      DateTime? parseDate(dynamic p) {
        if (p is! Map) return null;
        final raw = (p['created_at'] ?? p['date_added'] ?? p['updated_at'] ?? '').toString().trim();
        if (raw.isEmpty) return null;
        return DateTime.tryParse(raw);
      }

      int parseId(dynamic p) {
        if (p is! Map) return 0;
        final raw = (p['id'] ?? p['property_id'] ?? '0').toString();
        return int.tryParse(raw) ?? 0;
      }

      final bDate = parseDate(b);
      final aDate = parseDate(a);
      if (bDate != null && aDate != null) {
        return bDate.compareTo(aDate); // newest first
      }
      if (bDate != null) return 1;
      if (aDate != null) return -1;
      return parseId(b).compareTo(parseId(a)); // fallback newest ID first
    });
    return list;
  }

  void _onItemTapped(int index) {
    if (index == 0) {
      context.go('/home');
    } else if (index == 1) {
      if (_isLoggedIn) {
        if (_userRole == 'tenant' || _userRole == 'user' || _userRole.isEmpty) { 
          context.go('/tenant-dashboard', extra: {'tab': 4}); // Use standard tab routing
        } else if (_userRole == 'dealer') {
          context.go('/dealer-dashboard');
        }
      } else {
        _showLoginRequiredPopup();
      }
    } else if (index == 2) {
      if (_isLoggedIn) {
        context.go('/tenant-requests');
      } else {
        _showLoginRequiredPopup();
      }
    } else if (index == 3) {
      if (_isLoggedIn) {
        context.go('/public-notifications');
      } else {
        _showLoginRequiredPopup();
      }
    } else if (index == 4) {
      if (_isLoggedIn) {
        if (_userRole == 'dealer') {
          context.go('/dealer-dashboard'); 
        } else {
          context.go('/tenant-dashboard', extra: {'tab': 3}); 
        }
      } else {
        context.go('/login');
      }
    }
  }

  Widget _buildNotificationIcon({
    required bool active,
    Color? iconColor,
  }) {
    final icon = Icon(
      active ? Icons.notifications : Icons.notifications_none,
      color: iconColor,
    );
    if (_publicNotifBadgeCount <= 0) return icon;

    final badgeText =
        _publicNotifBadgeCount > 99 ? '99+' : _publicNotifBadgeCount.toString();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -8,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
            child: Text(
              badgeText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHouseHuntIcon({
    required bool active,
    Color? iconColor,
  }) {
    final icon = Icon(
      active ? Icons.campaign : Icons.campaign_outlined,
      color: iconColor,
    );
    if (_houseHuntBadgeCount <= 0) return icon;

    final badgeText =
        _houseHuntBadgeCount > 99 ? '99+' : _houseHuntBadgeCount.toString();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -8,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
            child: Text(
              badgeText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayServices = _filteredServices;
    final featuredServices = displayServices.where((p) => p['is_featured']?.toString() == '1').toList();
    final latestServices = _latestServices();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Zed Bine', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B), // Match banner dark elegant gradient
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // Top Banner
                SliverToBoxAdapter(
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16.0, 32.0, 16.0, 72.0), // Increased bottom padding to make room for overlapping category container
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF1E293B), Color(0xFF0F172A)], // Dark elegant gradient
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(32),
                            bottomRight: Radius.circular(32),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Zed Bine',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFC107).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFFFC107).withOpacity(0.5)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.star, size: 14, color: Color(0xFFFFC107)),
                                      SizedBox(width: 4),
                                      Text(
                                        'PRO',
                                        style: TextStyle(
                                          color: Color(0xFFFFC107),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Tiliko Che!',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFFFC107),
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your go-to marketplace for Gadgets, Repairs, Salons & more.',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.white.withOpacity(0.9),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Decorative abstract shapes
                      Positioned(
                        right: -20,
                        top: -20,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.05),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 20,
                        top: 20,
                        child: Icon(
                          Icons.handyman,
                          size: 80,
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                      Positioned(
                        right: 80,
                        bottom: -20,
                        child: Icon(
                          Icons.devices,
                          size: 100,
                          color: const Color(0xFFFFC107).withOpacity(0.05),
                        ),
                      ),
                      Positioned(
                        right: 60,
                        bottom: -30,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFFC107).withOpacity(0.1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Categories Grid (Replaces Slider for a more marketplace feel)
                SliverToBoxAdapter(
                  child: Transform.translate(
                    offset: const Offset(0, -32), // Pull it up to overlap the banner more
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Categories',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: _categories.map((cat) {
                                  final categoryName = (cat['name'] ?? '').toString();
                                  final label = (cat['label'] ?? cat['name'] ?? '').toString();
                                  final icon = cat['icon'] as IconData;
                                  final isSelected = _selectedCategory == categoryName;
                                  
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedCategory = categoryName;
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 20.0),
                                      child: Column(
                                        children: [
                                          Container(
                                            width: 60,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              color: isSelected 
                                                  ? const Color(0xFFFFC107) 
                                                  : Colors.grey.shade100,
                                              shape: BoxShape.circle,
                                              boxShadow: isSelected ? [
                                                BoxShadow(
                                                  color: const Color(0xFFFFC107).withOpacity(0.4),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                )
                                              ] : null,
                                            ),
                                            child: Icon(
                                              icon,
                                              color: isSelected ? Colors.white : Colors.grey.shade600,
                                              size: 26,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            width: 70,
                                            child: Text(
                                              label,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                color: isSelected ? const Color(0xFF1E293B) : Colors.grey.shade600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                if (displayServices.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Transform.translate(
                      offset: const Offset(0, -20),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 20.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.handyman, size: 80, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              'No services found.',
                              style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Check another category or check back later!',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  // Featured Services Section
                  if (featuredServices.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Transform.translate(
                        offset: const Offset(0, -16), // Adjust to maintain spacing since we pulled the categories up
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16.0),
                                child: Text('Featured Services', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 310,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                  itemCount: featuredServices.length,
                                  itemBuilder: (context, index) {
                                    return Container(
                                      width: MediaQuery.of(context).size.width * 0.75 > 320 
                                          ? 320 
                                          : MediaQuery.of(context).size.width * 0.75,
                                      margin: const EdgeInsets.only(right: 16.0, bottom: 8.0),
                                      child: PropertyCard(property: featuredServices[index], isFeatured: true),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Latest Services Section
                  if (latestServices.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Transform.translate(
                        offset: const Offset(0, -16), // Adjust to maintain spacing since we pulled the categories up
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 0.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16.0),
                                child: Text('All Services', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 310,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                  itemCount: latestServices.length,
                                  itemBuilder: (context, index) {
                                    return Container(
                                      width: MediaQuery.of(context).size.width * 0.75 > 320 
                                          ? 320 
                                          : MediaQuery.of(context).size.width * 0.75,
                                      margin: const EdgeInsets.only(right: 16.0, bottom: 8.0),
                                      child: PropertyCard(property: latestServices[index], isFeatured: false, showNewBadge: true),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            activeIcon: Icon(Icons.favorite),
            label: 'Saved',
          ),
          BottomNavigationBarItem(
            icon: _buildHouseHuntIcon(active: false),
            activeIcon: _buildHouseHuntIcon(active: true),
            label: 'House Hunt',
          ),
          BottomNavigationBarItem(
            icon: _buildNotificationIcon(active: false),
            activeIcon: _buildNotificationIcon(active: true),
            label: 'Alerts',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        currentIndex: 0, // Not explicitly selecting a tab since we are in a sub-page, but defaulting to 0
        selectedItemColor: Colors.grey, // Grey out since we are not technically on any of these main tabs
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 16,
      ),
    );
  }
}
