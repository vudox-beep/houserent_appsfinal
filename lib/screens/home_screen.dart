import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../widgets/skeleton_loader.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoggedIn = false;
  String _userName = '';
  String _userRole = '';

  int _selectedIndex = 0;
  List<dynamic> _properties = [];
  bool _isLoading = true;
  String _appVersionLabel = 'Version --';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _loadProperties();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersionLabel = 'Version ${info.version}';
      });
    } catch (_) {}
  }

  Future<void> _loadProperties() async {
    try {
      final properties = await ApiService.fetchProperties();

      // Hide properties whose dealer subscription is inactive/expired (defensive frontend filter).
      final now = DateTime.now();
      final filtered = properties.where((p) {
        final status = (p['dealer_subscription_status'] ?? p['subscription_status'] ?? p['dealer_status'] ?? '').toString().toLowerCase();
        final expiryRaw = p['dealer_subscription_expiry'] ?? p['subscription_expiry'];
        DateTime? expiry;
        if (expiryRaw is String && expiryRaw.isNotEmpty && expiryRaw != '0000-00-00 00:00:00') {
          try {
            expiry = DateTime.parse(expiryRaw);
          } catch (_) {}
        }

        final isActiveStatus = status.isEmpty || status == 'active';
        final isNotExpired = expiry == null || !expiry.isBefore(now);
        return isActiveStatus && isNotExpired;
      }).toList();

      if (mounted) {
        setState(() {
          _properties = filtered;
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

  List<dynamic> _latestProperties() {
    final list = List<dynamic>.from(_properties);
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

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final role = prefs.getString('role');
    
    if (token != null && token.isNotEmpty) {
      // Temporarily set isLoggedIn to true immediately so the UI responds faster, 
      // even if the profile fetch takes a second.
      if (mounted) {
        setState(() {
          _isLoggedIn = true;
          // Ensure role defaults to tenant if null to prevent redirect issues
          _userRole = (role != null && role.isNotEmpty) ? role : 'tenant';
        });
      }

      try {
        final profile = await ApiService.getProfile();
        if (mounted) {
          setState(() {
            _userName = profile['name'] ?? 'User';
            // Overwrite role if API returns it, just in case
            if (profile['role'] != null) {
              _userRole = profile['role'];
            }
          });
        }
      } catch (e) {
        // Token might be invalid or expired
        if (mounted) {
          setState(() {
            _isLoggedIn = false;
          });
        }
      }
    }
  }

  void _navigateToDashboard() {
    if (_userRole == 'dealer') {
      context.go('/dealer-dashboard');
    } else {
      context.go('/tenant-dashboard');
    }
  }

  void _onItemTapped(int index) {
    print("Nav tapped: index $index, loggedIn: $_isLoggedIn, role: $_userRole"); // Debug print

    if (index == 1) {
      if (_isLoggedIn) {
        if (_userRole == 'tenant' || _userRole == 'user' || _userRole.isEmpty) { 
          print("Navigating to tenant-dashboard tab 4");
          try {
            // Using context.go instead of push to ensure clean navigation
            context.go('/tenant-dashboard', extra: {'tab': 4});
          } catch (e) {
            print("Navigation error: $e");
          }
        } else if (_userRole == 'dealer') {
          context.go('/dealer-dashboard');
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login to view saved properties')));
        context.go('/login');
      }
    } else if (index == 2) {
      // Profile clicked
      if (_isLoggedIn) {
        if (_userRole == 'dealer') {
          context.go('/dealer-dashboard'); 
        } else {
          context.go('/tenant-dashboard', extra: {'tab': 3}); 
        }
      } else {
        context.go('/login');
      }
    } else {
      // Home tab clicked
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  void _submitHomeSearch() {
    final raw = _searchController.text.trim();
    if (raw.isEmpty) {
      context.go('/search-results');
      return;
    }
    context.go('/search-results?location=${Uri.encodeComponent(raw)}');
  }

  Widget _buildFeatureItem(IconData icon, String title, String desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFC107).withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFFFFC107), size: 24),
        ),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
        const SizedBox(height: 4),
        Text(desc, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, height: 1.4)),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.real_estate_agent, color: Colors.white, size: 32),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'HouseRent Africa', 
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: -0.5, fontSize: 22)
              ),
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: const Color(0xFFFFC107), // Use the primary button yellow
        centerTitle: false,
        actions: [
          if (_isLoggedIn)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: _navigateToDashboard,
                icon: const Icon(Icons.person, color: Colors.white),
                label: Text('Hi, ${_userName.split(' ').first}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.1), // Subtle dark background for the menu button on yellow bar
                  borderRadius: BorderRadius.circular(12),
                ),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.menu_rounded, color: Colors.white), // White icon
                  color: Colors.white, // Clean white background
                  surfaceTintColor: Colors.white, // Prevent Material 3 tinting
                  elevation: 6, // Nice shadow
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  offset: const Offset(0, 50),
                  onSelected: (value) {
                    if (value == 'login') {
                      context.go('/login');
                    } else if (value == 'signup') {
                      context.go('/register');
                    } else if (value == 'share') {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Share functionality coming soon')),
                      );
                    } else if (value == 'privacy') {
                      launchUrl(Uri.parse('https://houseforrent.site/privacy.php'), mode: LaunchMode.externalApplication);
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                    PopupMenuItem(
                      value: 'login',
                      child: Row(
                        children: const [
                          Icon(Icons.login, size: 20, color: Colors.black54),
                          SizedBox(width: 12),
                          Text('Login', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'signup',
                      child: Row(
                        children: const [
                          Icon(Icons.person_add, size: 20, color: Colors.black54),
                          SizedBox(width: 12),
                          Text('Sign Up', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: const [
                          Icon(Icons.share, size: 20, color: Colors.black54),
                          SizedBox(width: 12),
                          Text('Share App', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'privacy',
                      child: Row(
                        children: const [
                          Icon(Icons.privacy_tip_outlined, size: 20, color: Colors.black54),
                          SizedBox(width: 12),
                          Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Hero Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 80, bottom: 0), // Removed horizontal padding and bottom padding to let slider touch edges
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9C4), // Fallback color
                image: DecorationImage(
                  image: const NetworkImage('https://images.unsplash.com/photo-1512917774080-9991f1c4c750?q=80&w=2070&auto=format&fit=crop'), // Modern real estate image
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.5), BlendMode.darken), // Dark overlay for text readability
                ),
              ),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Find Your Perfect Home in Zambia',
                      style: TextStyle(
                        fontSize: 40, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Discover apartments, houses, and properties for rent across Zambia and the continent.',
                      style: TextStyle(
                        fontSize: 18, 
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: 600,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))
                        ]
                      ),
                      child: TextField(
                        controller: _searchController,
                        onSubmitted: (_) => _submitHomeSearch(),
                        decoration: InputDecoration(
                          hintText: 'Search by location...',
                          prefixIcon: const Icon(Icons.search, color: Colors.black54),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          suffixIcon: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.tune),
                                  onPressed: () {
                                    context.go('/advanced-search');
                                  },
                                  tooltip: 'Advanced Search',
                                ),
                                ElevatedButton(
                                  onPressed: _submitHomeSearch,
                                  style: ElevatedButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Search'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40), // Increased spacing before slider
                  
                  // Category Slider touching the edges
                  SizedBox(
                    width: double.infinity,
                    height: 54, // Slightly taller for better touch target
                    child: Builder(
                      builder: (context) {
                        final categories = ['For Rent', 'For Sale', 'Boarding Houses', 'Apartment', 'Wedding Lodges', 'Studios', 'Land for Sale'];
                        
                        // Optionally merge with dynamically found categories if needed
                        final dynamicCats = _properties
                            .map((p) => (p['property_type'] ?? p['type'] ?? '').toString())
                            .where((e) => e.trim().isNotEmpty && !categories.contains(e))
                            .toSet()
                            .toList();
                            
                        categories.addAll(dynamicCats);
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: categories.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final label = categories[index];
                            return InkWell(
                              onTap: () {
                                String paramType = '';
                                String paramPurpose = '';
                                
                                if (label == 'Boarding Houses') {
                                  paramType = 'boarding_house';
                                } else if (label == 'Wedding Lodges') {
                                  paramType = 'wedding_lodge';
                                } else if (label == 'For Rent') {
                                  paramPurpose = 'rent';
                                } else if (label == 'For Sale') {
                                  paramPurpose = 'sale';
                                } else if (label == 'Land for Sale') {
                                  paramType = 'land';
                                  paramPurpose = 'sale';
                                } else if (label == 'Apartment') {
                                  paramType = 'apartment';
                                } else if (label == 'Studios') {
                                  paramType = 'studio';
                                } else {
                                  paramType = label.toLowerCase().replaceAll(' ', '_');
                                }
                                
                                String query = '';
                                if (paramType.isNotEmpty) {
                                  query += 'type=$paramType';
                                }
                                if (paramPurpose.isNotEmpty) {
                                  if (query.isNotEmpty) query += '&';
                                  query += 'purpose=$paramPurpose';
                                }
                                
                                context.go('/search-results${query.isNotEmpty ? '?$query' : ''}');
                              },
                              borderRadius: BorderRadius.circular(24),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.3), // Dark translucent glass effect
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.category_outlined, size: 16, color: Colors.white),
                                        const SizedBox(width: 8),
                                        Text(
                                          label,
                                          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            
            // Featured Properties Section
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, right: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Featured Properties', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () => context.go('/search-results?featured=1'),
                          child: const Text('View All', style: TextStyle(color: Color(0xFFFFC107), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoading)
                    const SkeletonPropertyCarousel(height: 310)
                  else if (_properties.where((p) => p['is_featured']?.toString() == '1').isEmpty)
                    const SizedBox(
                      height: 100,
                      child: Center(child: Text('No featured properties available')),
                    )
                  else
                    SizedBox(
                      height: 310, // Matching the height for consistency
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0), // Touch edge a bit
                        itemCount: _properties.where((p) => p['is_featured']?.toString() == '1').length, 
                        itemBuilder: (context, index) {
                          final featuredProps = _properties.where((p) => p['is_featured']?.toString() == '1').toList();
                          
                          return Container(
                            width: MediaQuery.of(context).size.width * 0.75 > 320 
                                ? 320 // Max width for larger screens
                                : MediaQuery.of(context).size.width * 0.75, // Make cards wider (75% of screen width)
                            margin: const EdgeInsets.only(right: 16.0, bottom: 8.0), // Tighter margin
                            child: PropertyCard(property: featuredProps[index], isFeatured: true),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            
            // Latest Listings Section
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, right: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Latest Listings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () => context.go('/search-results'),
                          child: const Text('View All', style: TextStyle(color: Color(0xFFFFC107), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoading)
                    const SkeletonPropertyCarousel(height: 310)
                  else if (_properties.isEmpty)
                    const SizedBox(
                      height: 280,
                      child: Center(child: Text('No properties available')),
                    )
                  else
                    Builder(
                      builder: (context) {
                        final latestProps = _latestProperties();
                        final latestCount = latestProps.length > 5 ? 5 : latestProps.length;
                        return SizedBox(
                          height: 310, // Increased height to prevent content overflow in neat design
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            itemCount: latestCount,
                            itemBuilder: (context, index) {
                              return Container(
                                width: MediaQuery.of(context).size.width * 0.75 > 320
                                    ? 320
                                    : MediaQuery.of(context).size.width * 0.75, // Make cards wider (75% of screen width)
                                margin: const EdgeInsets.only(right: 16.0, bottom: 8.0), // increased margin for breathing room
                                child: PropertyCard(
                                  property: latestProps[index],
                                  isFeatured: false,
                                  showNewBadge: true,
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),

            // Boarding Houses Section
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, right: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Boarding Houses', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        TextButton(
                          onPressed: () => context.go('/search-results?type=boarding_house'),
                          child: const Text('View All', style: TextStyle(color: Color(0xFFFFC107), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoading)
                    const SkeletonPropertyCarousel(height: 310)
                  else if (_properties.where((p) => p['property_type']?.toString().toLowerCase() == 'boarding_house').isEmpty)
                    const SizedBox(
                      height: 100,
                      child: Center(child: Text('No boarding houses available')),
                    )
                  else
                    SizedBox(
                      height: 310, // Matching the height for consistency
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        itemCount: _properties.where((p) => p['property_type']?.toString().toLowerCase() == 'boarding_house').length, 
                        itemBuilder: (context, index) {
                          final boardingProps = _properties.where((p) => p['property_type']?.toString().toLowerCase() == 'boarding_house').toList();
                          
                          return Container(
                            width: MediaQuery.of(context).size.width * 0.75 > 320 
                                ? 320 
                                : MediaQuery.of(context).size.width * 0.75,
                            margin: const EdgeInsets.only(right: 16.0, bottom: 8.0),
                            child: PropertyCard(
                              property: boardingProps[index],
                              isFeatured: false,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            // Why Choose Us Banner
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Why We Are The Best',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F2041),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildFeatureItem(
                          Icons.verified_user_outlined,
                          'Verified Listings',
                          'Every property is checked for your safety.',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildFeatureItem(
                          Icons.chat_bubble_outline,
                          'Direct Contact',
                          'Chat directly with landlords with zero hidden fees.',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildFeatureItem(
                          Icons.map_outlined,
                          'Wide Coverage',
                          'Thousands of homes available across Zambia and the continent.',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildFeatureItem(
                          Icons.support_agent,
                          '24/7 Support',
                          'Our dedicated team is always here to assist you.',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Landlord Registration Banner
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: DecorationImage(
                  image: const NetworkImage('https://images.unsplash.com/photo-1560518883-ce09059eeffa?q=80&w=1973&auto=format&fit=crop'), // Nice house exterior
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.65), BlendMode.darken),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Are you a Landlord?',
                    style: TextStyle(
                      color: Color(0xFFFFC107), // Yellow text
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'List your properties and reach thousands of potential tenants across Zambia and Africa.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => context.go('/register'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Register Now',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Footer
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.real_estate_agent, color: Colors.black87, size: 28),
                      SizedBox(width: 8),
                      Text(
                        'HouseRent Africa', 
                        style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, letterSpacing: -0.5, fontSize: 20)
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Find Your Perfect Home in Zambia & Africa',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Divider(color: Colors.grey.shade200),
                  const SizedBox(height: 24),
                  Text(
                    '© ${DateTime.now().year} HouseRent Africa. All rights reserved.',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _appVersionLabel,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            activeIcon: Icon(Icons.favorite),
            label: 'Saved',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFFFFC107), // Yellow for active items
        unselectedItemColor: Colors.grey, // Grey for unselected
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white, // White background
        elevation: 16,
      ),
    );
  }
}

class PropertyCard extends StatelessWidget {
  final Map<String, dynamic> property;
  final bool isFeatured;
  final bool showNewBadge;

  const PropertyCard({
    super.key,
    required this.property,
    this.isFeatured = false,
    this.showNewBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    // Dynamically calculate width to fit 2 cards per row with some spacing
    // Increased the card width to make them wider on the home screen
    final screenWidth = MediaQuery.of(context).size.width;
    // Less margin means wider cards. We reduce the deducted padding from 48+16 to just 32.
    final cardWidth = screenWidth < 600 ? (screenWidth - 32) / 2 : 320.0;
    
    final id = property['id']?.toString() ?? '1';
    final title = property['title'] ?? 'Unknown Property';
    final location = property['city'] != null && property['country'] != null 
        ? '${property['city']}, ${property['country']}' 
        : (property['location'] ?? 'Unknown Location');
    final currency = property['currency'] ?? 'ZMW';
    final price = property['price']?.toString() ?? '0';
    final type = (property['property_type']?.toString() ?? 'House').trim();
    final typeLower = type.toLowerCase();
    
    final bool isService = typeLower.contains('wedding') || typeLower.contains('studio') || typeLower.contains('lodge') || typeLower.contains('studies') || typeLower.contains('restaurant');
    final String purposeKey = _purposeKey(property, typeLower);
    final String purposeBadge = _purposeBadgeText(purposeKey);
    final Color purposeBadgeColor = _purposeBadgeColor(purposeKey);
    final bool isNewListing = showNewBadge || _isNewListing(property);
    
    final beds = property['bedrooms']?.toString() ?? '';
    final baths = property['bathrooms']?.toString() ?? '';
    final size = property['size_sqm']?.toString() ?? property['size']?.toString() ?? '';
    final rooms = property['rooms']?.toString() ?? '';
    final capacity = property['capacity']?.toString() ?? '';
    final eventType = property['event_type']?.toString() ?? '';
    final peoplePerRoom = property['people_per_room']?.toString() ?? '';
    
    // Get first image if available
    String? imageUrl;
    
    // The new API structure returns 'main_image' with the fully formatted URL
    if (property['main_image'] != null && property['main_image'].toString().isNotEmpty) {
      String mainImg = property['main_image'].toString().trim();
      // Remove any literal backticks the API might accidentally include
      mainImg = mainImg.replaceAll('`', '').trim();
      imageUrl = mainImg;
    } 
    // Fallback for older API structure
    else if (property['images'] != null && property['images'].isNotEmpty) {
      var firstImage = property['images'][0];
      if (firstImage is Map && firstImage['url'] != null) {
        String urlStr = firstImage['url'].toString().trim();
        urlStr = urlStr.replaceAll('`', '').trim();
        imageUrl = urlStr;
      } else if (firstImage is String) {
        String imagePath = firstImage.trim();
        imagePath = imagePath.replaceAll('`', '').trim();
        
        if (imagePath.startsWith('http')) {
          imageUrl = imagePath;
        } else {
          if (imagePath.startsWith('/')) {
            imagePath = imagePath.substring(1);
          }
          if (imagePath.startsWith('assets/')) {
            imageUrl = 'https://houseforrent.site/$imagePath';
          } else if (imagePath.startsWith('uploads/')) {
            imageUrl = 'https://houseforrent.site/php_backend/api/$imagePath';
          } else {
            if (!imagePath.startsWith('assets/')) {
              imageUrl = 'https://houseforrent.site/assets/$imagePath';
            } else {
              imageUrl = 'https://houseforrent.site/$imagePath';
            }
          }
        }
      }
    }
    
    return GestureDetector(
      onTap: () {
        context.push('/property/$id');
      },
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.only(bottom: 0), // Removed right margin to let ListView padding handle it
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Section
              Container(
                height: 160, // Increased image height slightly for better proportion
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl != null)
                      Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.image, size: 40, color: Colors.black26)))
                    else
                      const Center(child: Icon(Icons.image, size: 40, color: Colors.black26)),
                    
                    // Gradient overlay at bottom of image for contrast
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black.withOpacity(0.4), Colors.transparent],
                          )
                        ),
                      ),
                    ),
                    
                    if ((property['status']?.toString().toLowerCase() ?? '') == 'taken')
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))
                            ]
                          ),
                          child: const Text(
                            'TAKEN', 
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white, letterSpacing: 0.5)
                          ),
                        ),
                      ),

                    Positioned(
                      top: 12,
                      right: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (isNewListing)
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))
                                ]
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white, letterSpacing: 0.5),
                              ),
                            ),
                          if (isFeatured)
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black87, // Black badge for featured
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2))
                                ]
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.star, color: Color(0xFFFFC107), size: 12),
                                  SizedBox(width: 4),
                                  Text(
                                    'FEATURED', 
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9, color: Colors.white, letterSpacing: 0.5)
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: purposeBadgeColor,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))
                              ]
                            ),
                            child: Text(
                              purposeBadge,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.white, letterSpacing: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Details Section
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0), // Reduced vertical padding
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title, 
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87, height: 1.2),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4), // Reduced spacing
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  location, 
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4), // Reduced spacing
                          Text(
                            (isService && purposeKey == 'service') ? '$currency $price per service' : '$currency $price',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF5A3D31)) // Slightly smaller price
                          ),
                        ],
                      ),
                      
                      // Divider line
                      Divider(color: Colors.grey.shade200, height: 12, thickness: 1), // Reduced height

                      // Amenities row at bottom
                      SizedBox(
                        height: 20, // Reduced height
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          children: [
                            if (typeLower == 'apartment' || typeLower == 'house') ...[
                              if (beds.isNotEmpty && beds != '0') _buildProfessionalAmenity(Icons.bed_outlined, '$beds Beds'),
                              if (beds.isNotEmpty && beds != '0') const SizedBox(width: 12),
                              if (baths.isNotEmpty && baths != '0') _buildProfessionalAmenity(Icons.bathtub_outlined, '$baths Baths'),
                              if (baths.isNotEmpty && baths != '0') const SizedBox(width: 12),
                            ] else if (typeLower.contains('boarding')) ...[
                              if (capacity.isNotEmpty && capacity != '0') _buildProfessionalAmenity(Icons.group_outlined, 'Cap: $capacity'),
                              if (capacity.isNotEmpty && capacity != '0') const SizedBox(width: 12),
                              if (peoplePerRoom.isNotEmpty && peoplePerRoom != '0') _buildProfessionalAmenity(Icons.person_outline, '$peoplePerRoom/Room'),
                              if (peoplePerRoom.isNotEmpty && peoplePerRoom != '0') const SizedBox(width: 12),
                            ] else if (typeLower.contains('wedding') || typeLower.contains('studio')) ...[
                              if (capacity.isNotEmpty && capacity != '0') _buildProfessionalAmenity(Icons.groups_outlined, 'Cap: $capacity'),
                              if (capacity.isNotEmpty && capacity != '0') const SizedBox(width: 12),
                              if (eventType.isNotEmpty) _buildProfessionalAmenity(Icons.event_outlined, eventType),
                              if (eventType.isNotEmpty) const SizedBox(width: 12),
                            ] else ...[
                              if (rooms.isNotEmpty && rooms != '0') _buildProfessionalAmenity(Icons.door_front_door_outlined, '$rooms Rooms'),
                              if (rooms.isNotEmpty && rooms != '0') const SizedBox(width: 12),
                            ],
                            if (size.isNotEmpty && size != '0') _buildProfessionalAmenity(Icons.square_foot_outlined, '${size}m²'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfessionalAmenity(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600), 
        const SizedBox(width: 4), 
        Text(text, 
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        )
      ],
    );
  }

  String _purposeKey(Map<String, dynamic> property, String typeLower) {
    final rawPurpose = (property['purpose'] ?? property['listing_purpose'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    if (rawPurpose.contains('sale') || rawPurpose == 'sell') return 'sale';
    if (rawPurpose.contains('service')) return 'service';
    if (rawPurpose.contains('rent')) {
      final bool serviceType = typeLower.contains('wedding') ||
          typeLower.contains('studio') ||
          typeLower.contains('lodge') ||
          typeLower.contains('studies') ||
          typeLower.contains('restaurant');
      return serviceType ? 'service' : 'rent';
    }

    if (typeLower.contains('land')) return 'sale';
    return 'rent';
  }

  String _purposeBadgeText(String purposeKey) {
    switch (purposeKey) {
      case 'sale':
        return 'FOR SALE';
      case 'service':
        return 'SERVICE';
      default:
        return 'FOR RENT';
    }
  }

  Color _purposeBadgeColor(String purposeKey) {
    switch (purposeKey) {
      case 'sale':
        return const Color(0xFF1E3A8A);
      case 'service':
        return const Color(0xFF6D28D9);
      default:
        return const Color(0xFF0F766E);
    }
  }

  bool _isNewListing(Map<String, dynamic> property) {
    final createdRaw = (property['created_at'] ??
            property['date_added'] ??
            property['createdAt'] ??
            '')
        .toString()
        .trim();
    if (createdRaw.isEmpty) return false;

    try {
      final createdAt = DateTime.parse(createdRaw);
      return DateTime.now().difference(createdAt).inDays <= 14;
    } catch (_) {
      return false;
    }
  }
}
