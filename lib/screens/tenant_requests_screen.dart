import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart'; 
import '../services/api_service.dart';

class TenantRequestsScreen extends StatefulWidget {
  const TenantRequestsScreen({super.key});

  @override
  State<TenantRequestsScreen> createState() => _TenantRequestsScreenState();
}

class _TenantRequestsScreenState extends State<TenantRequestsScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<dynamic> _requests = [];
  bool _isLoading = true;
  bool _isSending = false;
  String _currentUserId = '';
  
  String _selectedPropertyType = 'Any';
  String _selectedLocation = 'Any';
  final TextEditingController _budgetController = TextEditingController();

  final List<String> _propertyTypes = ['Any', 'House', 'Apartment', 'Boarding Houses', 'Commercial', 'Land'];

  // Supabase Channel
  RealtimeChannel? _supabaseChannel;
  bool _isRealtimeConnected = false;

  bool _isLoggedIn = false;
  bool _isCheckingAuth = true;
  String _userRole = '';
  int _houseHuntBadgeCount = 0;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _loadAuthStatus();
    _loadHouseHuntBadgeCount();
    _loadUnreadNotifications();
    _initData();
  }

  Future<void> _loadAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (mounted) {
      setState(() {
        _isLoggedIn = token != null && token.isNotEmpty;
        _userRole = prefs.getString('role') ?? '';
        _isCheckingAuth = false;
      });
      if (!_isLoggedIn) {
        // If not logged in, wait a moment and then redirect or show popup
        // Or we can just let the UI handle it by showing a login prompt
      }
    }
  }

  Future<void> _loadHouseHuntBadgeCount() async {
    final count = await ApiService.fetchTenantRequestsCount();
    if (mounted) {
      setState(() {
        _houseHuntBadgeCount = count;
      });
    }
  }

  Future<void> _loadUnreadNotifications() async {
    try {
      final notifs = await ApiService.fetchNotifications();
      if (mounted) {
        setState(() {
          _unreadNotifications = notifs.where((n) => n['is_read'] == 0).length;
        });
      }
    } catch (_) {}
  }

  Widget _buildHouseHuntIcon({required bool active, Color? iconColor}) {
    final icon = Icon(
      active ? Icons.campaign : Icons.campaign_outlined,
      color: iconColor,
    );
    if (_houseHuntBadgeCount <= 0) return icon;

    final badgeText = _houseHuntBadgeCount > 99 ? '99+' : _houseHuntBadgeCount.toString();
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

  Widget _buildNotificationIcon({required bool active}) {
    final icon = Icon(active ? Icons.notifications : Icons.notifications_outlined);
    if (_unreadNotifications <= 0) return icon;
    
    return Badge(
      label: Text('$_unreadNotifications'),
      child: icon,
    );
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    // Cache the user ID locally so we know which messages are "ours"
    _currentUserId = prefs.getString('user_id') ?? '';
    
    await _loadRequests();

    // SETUP SUPABASE REALTIME BROADCAST
    try {
      final supabase = Supabase.instance.client;
      _supabaseChannel = supabase.channel('public-requests');
      _supabaseChannel!.onBroadcast(
        event: 'new-request',
        callback: (payload) {
          if (!mounted) return;
          // Ignore our own broadcasts by checking if the user_id matches
          if (payload['user_id'].toString() == _currentUserId) return;
          
          // Check if it's already in our list (to prevent duplicates from the sender)
          final existingIds = _requests.map((r) => r['id'].toString()).toSet();
          if (!existingIds.contains(payload['id'].toString())) {
            setState(() {
              _requests.add(payload);
            });
            _scrollToBottom();
          }
        },
      ).subscribe((status, [error]) {
        if (!mounted) return;
        setState(() {
          _isRealtimeConnected = status == RealtimeSubscribeStatus.subscribed;
        });
      });
    } catch (e) {
      debugPrint('Supabase not initialized: $e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _budgetController.dispose();
    _scrollController.dispose();
    _supabaseChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadRequests({bool isPolling = false}) async {
    if (!mounted) return;
    if (!isPolling && _requests.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final data = await ApiService.fetchTenantRequests();
      if (!mounted) return;
      setState(() {
        _requests = data;
        _isLoading = false;
      });
      if (!isPolling) _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendRequest() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (_currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to post a request.')),
      );
      context.push('/login');
      return;
    }

    setState(() => _isSending = true);

    try {
      final newRequest = await ApiService.addTenantRequest(
        text,
        _selectedPropertyType,
        _selectedLocation,
        _budgetController.text.trim(),
      );

      _messageController.clear();
      _budgetController.clear();
      
      setState(() {
        _requests.add(newRequest);
      });
      _scrollToBottom();

      // BROADCAST TO SUPABASE
      try {
        // Only broadcast if we just created it (avoid double add if we also listen to our own broadcasts)
        Supabase.instance.client.channel('public-requests').sendBroadcastMessage(
          event: 'new-request',
          payload: newRequest,
        );
      } catch (_) {}
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showCreatePostDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String tempType = _selectedPropertyType;
        String tempLoc = _selectedLocation;
        TextEditingController tempBudget = TextEditingController(text: _budgetController.text);

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95), // Glass-like white
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, spreadRadius: 5)
                  ],
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const Text('Create Request', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(height: 8),
                      Text('What are you looking for?', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                      const SizedBox(height: 16),
                      
                      // Message Input
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: TextField(
                          controller: _messageController,
                          maxLines: 4,
                          minLines: 2,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'E.g., I am looking for a 2 bedroom house in Lusaka...',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      Text('Optional Tags', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                      const SizedBox(height: 12),
                      
                      // Property Type Dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: tempType,
                            isExpanded: true,
                            icon: Icon(Icons.keyboard_arrow_down, color: Colors.grey[600]),
                            items: _propertyTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontWeight: FontWeight.w500)))).toList(),
                            onChanged: (val) => setModalState(() => tempType = val!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Location Field
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: TextFormField(
                          initialValue: tempLoc == 'Any' ? '' : tempLoc,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Location (e.g. Lusaka)',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            icon: Icon(Icons.location_on_outlined, color: Colors.grey[500], size: 20),
                          ),
                          onChanged: (val) => tempLoc = val.isEmpty ? 'Any' : val,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Budget Field
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: TextFormField(
                          controller: tempBudget,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Max Budget (Optional)',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            icon: Text('ZMW', style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                side: BorderSide(color: Colors.grey[300]!),
                              ),
                              child: Text('Cancel', style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFC107),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: () async {
                                setState(() {
                                  _selectedPropertyType = tempType;
                                  _selectedLocation = tempLoc;
                                  _budgetController.text = tempBudget.text;
                                });
                                Navigator.pop(context);
                                await _sendRequest();
                              },
                              child: const Text('Post', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'House Hunt',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
            ),
            const SizedBox(width: 8),
            if (_isRealtimeConnected)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFFFFC107),
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Post what you are looking for. Dealers can see this and contact you!')),
              );
            },
          )
        ],
      ),
      body: _isCheckingAuth 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC107)))
          : !_isLoggedIn 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text('Login Required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Please login to view and post House Hunt requests.', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => context.go('/login'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFC107),
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        ),
                        child: const Text('Login', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                )
              : Column(
            children: [
              // Create Post Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.grey[200],
                  child: const Icon(Icons.person, color: Colors.grey),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _showCreatePostDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Text('What are you looking for?', style: TextStyle(color: Colors.grey[600])),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Chat Messages
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC107)))
                : _requests.isEmpty
                    ? const Center(child: Text('No requests yet. Be the first to ask!'))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _requests.length,
                        itemBuilder: (context, index) {
                          final req = _requests[index];
                          final isMe = req['user_id'].toString() == _currentUserId;
                          return _buildMessageBubble(req, isMe);
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
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
        currentIndex: 2, // 2 is House Hunt
        selectedItemColor: const Color(0xFFFFC107),
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          if (index == 0) {
            context.go('/home');
          } else if (index == 1) {
            if (_isLoggedIn) {
              if (_userRole == 'tenant' || _userRole == 'user' || _userRole.isEmpty) {
                context.go('/tenant-dashboard', extra: {'tab': 4});
              } else if (_userRole == 'dealer') {
                context.go('/dealer-dashboard');
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login to view saved properties')));
              context.go('/login');
            }
          } else if (index == 2) {
            // Already here
          } else if (index == 3) {
            context.go('/public-notifications');
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
        },
      ),
    );
  }

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 2, offset: const Offset(0, 1))
        ]
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> req, bool isMe) {
    String name = (req['name'] ?? '').toString().trim();
    final role = (req['role'] ?? '').toString();
    if (name.isEmpty) {
      name = role.isNotEmpty ? role[0].toUpperCase() + role.substring(1) : 'User';
    }
    
    final type = (req['property_type'] ?? '').toString();
    final loc = (req['location'] ?? '').toString();
    final budget = (req['budget'] ?? '').toString();
    final msg = (req['message'] ?? '').toString();
    final time = (req['created_at'] ?? '').toString();
    final commentCount = int.tryParse(req['comment_count']?.toString() ?? '0') ?? 0;
    
    // Only show text if there are actual comments
    String commentText = '';
    if (commentCount > 0) {
      commentText = '$commentCount Comment${commentCount != 1 ? 's' : ''}';
    }
    
    // Parse time to something simpler if possible
    String displayTime = time;
    try {
      if (time.isNotEmpty) {
        final dt = DateTime.parse(time).toLocal();
        displayTime = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFFFC107), // Yellow theme
              child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white, // All bubbles are clean white
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                ),
                border: Border.all(color: Colors.grey[200]!), // Subtle border
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))
                ]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        '$name ${role == 'dealer' ? '(Dealer)' : ''}', 
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[800])
                      ),
                    ),
                  Text(
                    msg,
                    style: const TextStyle(color: Colors.black87, fontSize: 14), // Text is always clean dark
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (type != 'Any' && type.isNotEmpty) _infoChip(Icons.home, type, isMe),
                      if (loc != 'Any' && loc.isNotEmpty) _infoChip(Icons.location_on, loc, isMe),
                      if (budget.isNotEmpty && budget != '0.00') _infoChip(Icons.attach_money, budget, isMe),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => _showCommentsBottomSheet(req),
                        child: Row(
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey[600]),
                            if (commentText.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Text(commentText, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                            ],
                          ],
                        ),
                      ),
                      Text(displayTime, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                    ],
                  ),
                  if (req['comments'] != null && (req['comments'] as List).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...((req['comments'] as List).take(2).map((c) {
                            String cName = (c['name'] ?? '').toString().trim();
                            final cRole = (c['role'] ?? '').toString();
                            if (cName.isEmpty) cName = cRole.isNotEmpty ? cRole[0].toUpperCase() + cRole.substring(1) : 'User';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4.0),
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                                  children: [
                                    TextSpan(text: '$cName: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    TextSpan(text: c['comment'].toString()),
                                  ]
                                )
                              ),
                            );
                          })),
                          if ((req['comments'] as List).length > 2)
                            GestureDetector(
                              onTap: () => _showCommentsBottomSheet(req),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text('View all ${(req['comments'] as List).length} comments', style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.w600)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, bool isMe) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.grey[700]),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[800])),
        ],
      ),
    );
  }

  void _showCommentsBottomSheet(Map<String, dynamic> request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return _CommentsSheet(
          requestId: request['id'].toString(), 
          currentUserId: _currentUserId,
          onCommentAdded: (newComment) {
            setState(() {
              final currentCount = int.tryParse(request['comment_count']?.toString() ?? '0') ?? 0;
              request['comment_count'] = currentCount + 1;
              if (request['comments'] == null) {
                request['comments'] = [];
              }
              request['comments'].add(newComment);
            });
          },
        );
      }
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  final String requestId;
  final String currentUserId;
  final Function(Map<String, dynamic>) onCommentAdded;
  
  const _CommentsSheet({required this.requestId, required this.currentUserId, required this.onCommentAdded});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _commentController = TextEditingController();
  List<dynamic> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    try {
      final comments = await ApiService.fetchRequestComments(widget.requestId);
      if (!mounted) return;
      setState(() {
        _comments = comments;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    if (widget.currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login to comment.')));
      return;
    }

    setState(() => _isSending = true);
    try {
      final newComment = await ApiService.addRequestComment(widget.requestId, text);
      if (!mounted) return;
      setState(() {
        _comments.add(newComment);
        _isSending = false;
      });
      _commentController.clear();
      widget.onCommentAdded(newComment);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Comments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFC107)))
                : _comments.isEmpty
                  ? const Center(child: Text('No comments yet. Be the first to reply!'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _comments.length,
                      itemBuilder: (context, index) {
                        final c = _comments[index];
                        String name = (c['name'] ?? '').toString().trim();
                        final role = (c['role'] ?? '').toString();
                        if (name.isEmpty) {
                          name = role.isNotEmpty ? role[0].toUpperCase() + role.substring(1) : 'User';
                        }
                        final isMe = c['user_id'].toString() == widget.currentUserId;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: isMe ? const Color(0xFFFFC107) : Colors.grey[300],
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'U', style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('$name ${role == 'dealer' ? '(Dealer)' : ''}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[800])),
                                      const SizedBox(height: 4),
                                      Text(c['comment'].toString(), style: const TextStyle(fontSize: 14)),
                                    ],
                                  ),
                                ),
                              )
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))]
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      decoration: InputDecoration(
                        hintText: 'Write a comment...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Colors.grey[200],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(color: Color(0xFFFFC107), shape: BoxShape.circle),
                    child: IconButton(
                      icon: _isSending 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87))
                        : const Icon(Icons.send, color: Colors.black87),
                      onPressed: _isSending ? null : _sendComment,
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
}
