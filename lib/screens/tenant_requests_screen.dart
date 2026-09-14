import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_service.dart';
import '../services/firebase_messaging_service.dart';
import '../services/notification_service.dart';
import '../widgets/skeleton_loader.dart';
import 'dealer/dealer_payment_webview_screen.dart';

class TenantRequestsScreen extends StatefulWidget {
  const TenantRequestsScreen({super.key});

  @override
  State<TenantRequestsScreen> createState() => _TenantRequestsScreenState();
}

class _TenantRequestsScreenState extends State<TenantRequestsScreen> {
  static const String _blockedUsersKey = 'tenant_blocked_users_v1';
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<dynamic> _requests = [];
  bool _isLoading = true;
  bool _isPosting = false;
  String _currentUserId = '';
  Map<String, String> _blockedUsers = {};

  Map<String, dynamic>? _topViewedProperty;
  bool _isLoadingTrending = false;

  String _selectedPropertyType = 'Any';
  String _selectedLocation = 'Any';
  final TextEditingController _budgetController = TextEditingController();

  final List<String> _propertyTypes = [
    'Any',
    'House',
    'Apartment',
    'Boarding Houses',
    'Commercial',
    'Land',
  ];

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
    _loadBlockedUsers();
    _loadTopViewedProperty();
    _initData();
    FirebaseMessagingService.syncToken();
  }

  String? _propertyImageUrl(Map<String, dynamic> property) {
    final main = property['main_image']?.toString().trim();
    if (main != null && main.isNotEmpty) {
      return main.replaceAll('`', '').trim();
    }
    final images = property['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is Map && first['url'] != null) {
        return first['url'].toString().replaceAll('`', '').trim();
      }
      if (first is String) {
        var imagePath = first.replaceAll('`', '').trim();
        if (imagePath.isEmpty) return null;
        if (imagePath.startsWith('http')) return imagePath;
        if (imagePath.startsWith('/')) imagePath = imagePath.substring(1);
        if (imagePath.startsWith('assets/'))
          return 'https://houseforrent.site/$imagePath';
        if (imagePath.startsWith('uploads/'))
          return 'https://houseforrent.site/php_backend/api/$imagePath';
        return 'https://houseforrent.site/assets/$imagePath';
      }
    }
    return null;
  }

  int _propertyViews(Map<String, dynamic> property) {
    final raw =
        property['views'] ?? property['view_count'] ?? property['views_count'];
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Future<void> _loadTopViewedProperty() async {
    if (!mounted) return;
    setState(() {
      _isLoadingTrending = true;
    });
    try {
      final properties = await ApiService.fetchProperties();
      Map<String, dynamic>? best;
      var bestViews = -1;
      for (final p in properties) {
        if (p is! Map) continue;
        final map = Map<String, dynamic>.from(p);
        final type = (map['property_type'] ?? map['type'] ?? '')
            .toString()
            .toLowerCase();
        if (type.contains('salon') ||
            type.contains('gadget') ||
            type.contains('mechanic') ||
            type.contains('other_service')) {
          continue;
        }
        final v = _propertyViews(map);
        if (v > bestViews) {
          best = map;
          bestViews = v;
        }
      }
      if (!mounted) return;
      setState(() {
        _topViewedProperty = best;
        _isLoadingTrending = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingTrending = false;
      });
    }
  }

  Widget _buildTrendingHouseCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isLoadingTrending) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: const [
            SkeletonBox(
              width: 92,
              height: 68,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(
                    height: 16,
                    width: 180,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  SizedBox(height: 8),
                  SkeletonBox(
                    height: 13,
                    width: 120,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final property = _topViewedProperty;
    if (property == null) return const SizedBox.shrink();

    final id = (property['id'] ?? property['property_id'] ?? '')
        .toString()
        .trim();
    if (id.isEmpty) return const SizedBox.shrink();

    final title = (property['title'] ?? 'Trending house').toString();
    final location = (property['city'] != null && property['country'] != null)
        ? '${property['city']}, ${property['country']}'
        : (property['location'] ?? '').toString();
    final currency = (property['currency'] ?? 'ZMW').toString();
    final price = (property['price'] ?? '').toString();
    final views = _propertyViews(property);
    final imageUrl = _propertyImageUrl(property);

    return GestureDetector(
      onTap: () => context.push('/property/$id'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 92,
                height: 68,
                color: isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade200,
                child: imageUrl == null
                    ? Icon(
                        Icons.home,
                        color: isDark ? Colors.white54 : Colors.black45,
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => Icon(
                          Icons.broken_image,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFFC107,
                          ).withValues(alpha: isDark ? 0.22 : 0.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Trending',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFFFC107),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.visibility,
                            size: 14,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$views',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    location.isEmpty
                        ? '$currency $price'
                        : '$location • $currency $price',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadBlockedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_blockedUsersKey) ?? const <String>[];
    final map = <String, String>{};
    for (final item in raw) {
      final parts = item.split('::');
      if (parts.isEmpty) continue;
      final id = parts[0].trim();
      if (id.isEmpty) continue;
      final label = parts.length > 1
          ? parts.sublist(1).join('::').trim()
          : 'Blocked user';
      map[id] = label.isEmpty ? 'Blocked user' : label;
    }
    if (!mounted) return;
    setState(() {
      _blockedUsers = map;
    });
  }

  Future<void> _saveBlockedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final list =
        _blockedUsers.entries.map((e) => '${e.key}::${e.value}').toList()
          ..sort();
    await prefs.setStringList(_blockedUsersKey, list);
  }

  bool _isBlockedUserId(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return false;
    return _blockedUsers.containsKey(id);
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

    final badgeText = _houseHuntBadgeCount > 99
        ? '99+'
        : _houseHuntBadgeCount.toString();
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
    final icon = Icon(
      active ? Icons.notifications : Icons.notifications_outlined,
    );
    if (_unreadNotifications <= 0) return icon;

    return Badge(label: Text('$_unreadNotifications'), child: icon);
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
      _supabaseChannel!
          .onBroadcast(
            event: 'new-request',
            callback: (payload) {
              if (!mounted) return;
              if (_isBlockedUserId(payload['user_id']?.toString() ?? ''))
                return;

              // Check if it's already in our list (to prevent duplicates from the sender)
              final existingIds = _requests
                  .map((r) => r['id'].toString())
                  .toSet();
              if (!existingIds.contains(payload['id'].toString())) {
                setState(() {
                  _requests.add(payload);
                });
                _scrollToBottom();
              }
            },
          )
          .onBroadcast(
            event: 'new-comment',
            callback: (payload) {
              if (!mounted) return;
              if (_isBlockedUserId(payload['user_id']?.toString() ?? '')) {
                return;
              }

              final requestId = payload['request_id']?.toString() ?? '';
              if (requestId.isEmpty) return;

              setState(() {
                for (final req in _requests) {
                  if (req['id']?.toString() != requestId) continue;

                  final currentCount =
                      int.tryParse(req['comment_count']?.toString() ?? '0') ?? 0;
                  req['comment_count'] = currentCount + 1;
                  if (req['comments'] == null) {
                    req['comments'] = <dynamic>[];
                  }
                  final comments = List<dynamic>.from(req['comments'] as List);
                  final commentIds = comments
                      .map((c) => c['id']?.toString() ?? '')
                      .toSet();
                  final newCommentId = payload['id']?.toString() ?? '';
                  if (newCommentId.isNotEmpty &&
                      !commentIds.contains(newCommentId)) {
                    comments.add(payload);
                    req['comments'] = comments;
                  }
                  break;
                }
              });
            },
          )
          .subscribe((status, [error]) {
            if (!mounted) return;
            setState(() {
              _isRealtimeConnected =
                  status == RealtimeSubscribeStatus.subscribed;
            });
          });
    } catch (_) {}
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
      final filtered = data
          .where((r) => !_isBlockedUserId(r['user_id']?.toString() ?? ''))
          .toList();
      if (!mounted) return;
      setState(() {
        _requests = filtered;
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

  Future<bool> _hasPaidTenantAccess() async {
    if (_currentUserId.isEmpty) return false;

    try {
      final response = await http.post(
        Uri.parse('https://houseforrent.site/api/tenant_contact_payment.php'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'get_status', 'user_id': _currentUserId}),
      );
      if (response.statusCode != 200) return false;
      final decoded = jsonDecode(response.body);
      return decoded is Map && decoded['has_paid'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showHouseRequestPaymentPrompt() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final primaryText = isDark ? Colors.white : Colors.black87;
        final secondaryText = isDark ? Colors.white70 : Colors.black54;

        Widget benefit(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text, style: TextStyle(color: primaryText)),
              ),
            ],
          ),
        );

        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Post a House Request',
            style: TextStyle(fontWeight: FontWeight.bold, color: primaryText),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3A3000)
                      : const Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFC107)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.campaign, color: Color(0xFFFFC107)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Request fee: ZMW 10.00',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pay a one-time K10 tenant access fee to publish House Requests on HouseRent Africa.',
                style: TextStyle(color: secondaryText, height: 1.4),
              ),
              const SizedBox(height: 12),
              benefit('Get tenants and landlords to respond to you'),
              benefit('Reach dealers looking for tenant leads'),
              benefit('The same payment also unlocks listing contacts'),
              benefit('Pay once for this account'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('Cancel', style: TextStyle(color: secondaryText)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: Colors.black87,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Pay K10 & Post',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (proceed != true || !mounted) return;

    try {
      final profile = await ApiService.getProfile();
      _currentUserId =
          profile['id']?.toString() ??
          profile['user']?['id']?.toString() ??
          _currentUserId;
      final query = <String, String>{
        'action': 'pay_page',
        'user_id': _currentUserId,
        'phone': profile['phone']?.toString() ?? '',
        'email': profile['email']?.toString() ?? '',
        'name': profile['name']?.toString() ?? 'Tenant',
      };
      final url = Uri.https(
        'houseforrent.site',
        '/api/tenant_contact_payment.php',
        query,
      ).toString();

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DealerPaymentWebviewScreen(url: url)),
      );

      if (!mounted) return;
      if (await _hasPaidTenantAccess()) {
        await _sendRequest(paymentConfirmed: true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment is not confirmed yet. Complete the K10 payment to post your request.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open payment right now.')),
      );
    }
  }

  Future<void> _sendRequest({bool paymentConfirmed = false}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (_currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to post a request.')),
      );
      context.push('/login');
      return;
    }

    if (!paymentConfirmed) {
      // The existing tenant payment also unlocks House Requests, so users who
      // already paid for contact access do not pay a second time.
      if (await _hasPaidTenantAccess()) {
        await _sendRequest(paymentConfirmed: true);
        return;
      }
      await _showHouseRequestPaymentPrompt();
      return;
    }

    try {
      if (mounted) {
        setState(() => _isPosting = true);
      }

      final newRequest = await ApiService.addTenantRequest(
        text,
        _selectedPropertyType,
        _selectedLocation,
        _budgetController.text.trim(),
      );
      if (!mounted) return;

      _messageController.clear();
      _budgetController.clear();

      setState(() {
        _requests.add(newRequest);
        _isPosting = false;
      });
      _scrollToBottom();
      _loadHouseHuntBadgeCount();
      _loadUnreadNotifications();

      await NotificationService.showPushNotification(
        id: 'house_hunt_post_${newRequest['id']}',
        title: 'Your house request is live',
        body: 'Everyone can now see your post on House Hunt.',
        data: {
          'type': 'house_hunt',
          'request_id': newRequest['id']?.toString() ?? '',
          'route': '/tenant-requests',
        },
      );

      // BROADCAST TO SUPABASE
      try {
        // Only broadcast if we just created it (avoid double add if we also listen to our own broadcasts)
        Supabase.instance.client
            .channel('public-requests')
            .sendBroadcastMessage(event: 'new-request', payload: newRequest);
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPosting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Future<void> _confirmAndBlockUser({
    required String userId,
    required String label,
  }) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    if (id == _currentUserId.trim()) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block user'),
        content: Text(
          'Block $label?\n\nYou will no longer see their posts or comments in House Request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    setState(() {
      _blockedUsers[id] = label;
      _requests.removeWhere((r) => r['user_id']?.toString().trim() == id);
    });
    await _saveBlockedUsers();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('User blocked')));
  }

  Future<void> _showBlockedUsersDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final entries = _blockedUsers.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        return AlertDialog(
          title: Text('Blocked users (${entries.length})'),
          content: SizedBox(
            width: 420,
            child: entries.isEmpty
                ? const Text('No blocked users.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = entries[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          e.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          e.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            Navigator.of(context).pop();
                            setState(() => _blockedUsers.remove(e.key));
                            await _saveBlockedUsers();
                            if (!mounted) return;
                            await _loadRequests();
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showCreatePostDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        String tempType = _selectedPropertyType;
        String tempLoc = _selectedLocation;
        TextEditingController tempBudget = TextEditingController(
          text: _budgetController.text,
        );
        final isDark = Theme.of(context).brightness == Brightness.dark;

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
                  color: isDark
                      ? const Color(0xFF1E1E1E)
                      : Colors.white.withOpacity(0.95), // Glass-like white
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.white,
                    width: 1.5,
                  ),
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
                            color: isDark ? Colors.grey[700] : Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      Text(
                        'Create Request',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'What are you looking for? Tenants, landlords, and dealers can respond to you.',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Message Input
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2C)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.grey[200]!,
                          ),
                        ),
                        child: TextField(
                          controller: _messageController,
                          maxLines: 4,
                          minLines: 2,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText:
                                'E.g., I am looking for a 2 bedroom house in Lusaka...',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.white38 : Colors.grey[500],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      Text(
                        'Optional Tags',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Property Type Dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 0,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2C)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.grey[200]!,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: tempType,
                            isExpanded: true,
                            dropdownColor: isDark
                                ? const Color(0xFF2C2C2C)
                                : Colors.white,
                            icon: Icon(
                              Icons.keyboard_arrow_down,
                              color: isDark ? Colors.white54 : Colors.grey[600],
                            ),
                            items: _propertyTypes
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(
                                      t,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setModalState(() => tempType = val!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Location Field
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 0,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2C)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.grey[200]!,
                          ),
                        ),
                        child: TextFormField(
                          initialValue: tempLoc == 'Any' ? '' : tempLoc,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Location (e.g. Lusaka)',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.white38 : Colors.grey[500],
                            ),
                            icon: Icon(
                              Icons.location_on_outlined,
                              color: isDark ? Colors.white54 : Colors.grey[500],
                              size: 20,
                            ),
                          ),
                          onChanged: (val) =>
                              tempLoc = val.isEmpty ? 'Any' : val,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Budget Field
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 0,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2C)
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.grey[200]!,
                          ),
                        ),
                        child: TextFormField(
                          controller: tempBudget,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Max Budget (Optional)',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.white38 : Colors.grey[500],
                            ),
                            icon: Text(
                              'K',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey[500],
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.grey[300]!,
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey[800],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFC107),
                                foregroundColor: Colors.black87,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
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
                              child: const Text(
                                'Post',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRequestsSkeletonList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        final alignRight = index.isOdd;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            mainAxisAlignment: alignRight
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!alignRight) ...[
                const SkeletonBox(
                  width: 36,
                  height: 36,
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(
                        height: 14,
                        width: alignRight ? 90 : 110,
                        borderRadius: const BorderRadius.all(Radius.circular(8)),
                      ),
                      const SizedBox(height: 10),
                      SkeletonBox(
                        height: 12,
                        width: alignRight ? 210 : 240,
                        borderRadius: const BorderRadius.all(Radius.circular(8)),
                      ),
                      const SizedBox(height: 8),
                      SkeletonBox(
                        height: 12,
                        width: alignRight ? 160 : 180,
                        borderRadius: const BorderRadius.all(Radius.circular(8)),
                      ),
                    ],
                  ),
                ),
              ),
              if (alignRight) ...[
                const SizedBox(width: 10),
                const SkeletonBox(
                  width: 36,
                  height: 36,
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildPostingOverlay() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AbsorbPointer(
      child: Container(
        color: Colors.black.withOpacity(0.45),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  color: Color(0xFFFFC107),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Updating feed…',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Posting your house request',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[100],
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'House Request',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: isDark ? Colors.white : Colors.white,
              ),
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
        backgroundColor: isDark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFFFFC107),
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.white),
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
            icon: const Icon(Icons.block),
            onPressed: _showBlockedUsersDialog,
            tooltip: 'Blocked users',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Post what you are looking for. Tenants, landlords, and dealers can respond to you!',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _isCheckingAuth
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC107)),
            )
          : !_isLoggedIn
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 64,
                    color: isDark ? Colors.white38 : Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Login Required',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please login to view and post house requests.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => context.go('/login'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'Login',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Create Post Header
                Container(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: isDark
                            ? const Color(0xFF2C2C2C)
                            : Colors.grey[200],
                        child: Icon(
                          Icons.person,
                          color: isDark ? Colors.white54 : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _showCreatePostDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2C2C2C)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white12
                                    : Colors.grey[300]!,
                              ),
                            ),
                            child: Text(
                              'What are you looking for?',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                _buildTrendingHouseCard(),

                // Chat Messages
                Expanded(
                  child: _isLoading
                      ? _buildRequestsSkeletonList()
                      : _requests.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.campaign_outlined,
                                size: 56,
                                color: isDark
                                    ? Colors.white24
                                    : Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No requests yet',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Be the first to ask for a house',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _requests.length,
                          itemBuilder: (context, index) {
                            final req = _requests[index];
                            final isMe =
                                req['user_id'].toString() == _currentUserId;
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
            label: 'House Request',
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
        currentIndex: 2, // 2 is House Request
        onTap: (index) {
          if (index == 0) {
            context.go('/home');
          } else if (index == 1) {
            // Check login first for Saved
            if (_isLoggedIn) {
              if (_userRole == 'tenant' ||
                  _userRole == 'user' ||
                  _userRole.isEmpty) {
                context.go('/tenant-dashboard', extra: {'tab': 3});
              } else if (_userRole == 'dealer') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Dealers do not have saved properties'),
                  ),
                );
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please login to view saved properties'),
                ),
              );
              context.go('/login');
            }
          } else if (index == 3) {
            context.go('/notifications');
          } else if (index == 4) {
            if (_isLoggedIn) {
              if (_userRole == 'dealer') {
                context.go('/dealer-dashboard');
              } else {
                context.go('/tenant-dashboard');
              }
            } else {
              context.go('/login');
            }
          }
        },
        type: BottomNavigationBarType.fixed,
        elevation: 16,
      ),
        ),
        if (_isPosting) _buildPostingOverlay(),
      ],
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
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[800],
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> req, bool isMe) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String name = (req['name'] ?? '').toString().trim();
    final role = (req['role'] ?? '').toString();
    final userId = (req['user_id'] ?? '').toString().trim();
    if (name.isEmpty) {
      name = role.isNotEmpty
          ? role[0].toUpperCase() + role.substring(1)
          : 'User';
    }
    final label = '$name${role == 'dealer' ? ' (Dealer)' : ''}';

    final type = (req['property_type'] ?? '').toString();
    final loc = (req['location'] ?? '').toString();
    final budget = (req['budget'] ?? '').toString();
    final msg = (req['message'] ?? '').toString();
    final time = (req['created_at'] ?? '').toString();
    final commentCount =
        int.tryParse(req['comment_count']?.toString() ?? '0') ?? 0;

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
        displayTime =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {}

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFFFC107), // Yellow theme
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E)
                    : Colors.white, // All bubbles are clean white
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe
                      ? const Radius.circular(16)
                      : const Radius.circular(4),
                  bottomRight: isMe
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                ),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey[200]!,
                ), // Subtle border
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey[800],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.block,
                              size: 18,
                              color: isDark
                                  ? Colors.red.shade300
                                  : Colors.red.shade700,
                            ),
                            tooltip: 'Block user',
                            onPressed: userId.isEmpty
                                ? null
                                : () => _confirmAndBlockUser(
                                    userId: userId,
                                    label: label,
                                  ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    msg,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ), // Text is always clean dark
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (type != 'Any' && type.isNotEmpty)
                        _infoChip(Icons.home, type, isMe),
                      if (loc != 'Any' && loc.isNotEmpty)
                        _infoChip(Icons.location_on, loc, isMe),
                      if (budget.isNotEmpty && budget != '0.00')
                        _infoChip(Icons.payments, 'K $budget', isMe),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showCommentsBottomSheet(req),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 14,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey[600],
                              ),
                              if (commentText.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    commentText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.grey[600],
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        displayTime,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? Colors.white38 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  if (req['comments'] != null &&
                      (req['comments'] as List).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2C2C2C)
                            : Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.grey[200]!,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...((req['comments'] as List).take(2).map((c) {
                            String cName = (c['name'] ?? '').toString().trim();
                            final cRole = (c['role'] ?? '').toString();
                            if (cName.isEmpty)
                              cName = cRole.isNotEmpty
                                  ? cRole[0].toUpperCase() + cRole.substring(1)
                                  : 'User';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4.0),
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '$cName: ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(text: c['comment'].toString()),
                                  ],
                                ),
                              ),
                            );
                          })),
                          if ((req['comments'] as List).length > 2)
                            GestureDetector(
                              onTap: () => _showCommentsBottomSheet(req),
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  'View all ${(req['comments'] as List).length} comments',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.lightBlueAccent
                                        : Colors.blue[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[100],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 10,
            color: isDark ? Colors.white54 : Colors.grey[700],
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white70 : Colors.grey[800],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showCommentsBottomSheet(Map<String, dynamic> request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E1E1E)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _CommentsSheet(
          requestId: request['id'].toString(),
          currentUserId: _currentUserId,
          onCommentAdded: (newComment) {
            setState(() {
              final currentCount =
                  int.tryParse(request['comment_count']?.toString() ?? '0') ??
                  0;
              request['comment_count'] = currentCount + 1;
              if (request['comments'] == null) {
                request['comments'] = [];
              }
              request['comments'].add(newComment);
            });
          },
        );
      },
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  final String requestId;
  final String currentUserId;
  final Function(Map<String, dynamic>) onCommentAdded;

  const _CommentsSheet({
    required this.requestId,
    required this.currentUserId,
    required this.onCommentAdded,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  static const String _blockedUsersKey = 'tenant_blocked_users_v1';
  final TextEditingController _commentController = TextEditingController();
  List<dynamic> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;
  Map<String, String> _blockedUsers = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadBlockedUsers();
    await _loadComments();
  }

  Future<void> _loadBlockedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_blockedUsersKey) ?? const <String>[];
    final map = <String, String>{};
    for (final item in raw) {
      final parts = item.split('::');
      if (parts.isEmpty) continue;
      final id = parts[0].trim();
      if (id.isEmpty) continue;
      final label = parts.length > 1
          ? parts.sublist(1).join('::').trim()
          : 'Blocked user';
      map[id] = label.isEmpty ? 'Blocked user' : label;
    }
    if (!mounted) return;
    setState(() {
      _blockedUsers = map;
    });
  }

  Future<void> _saveBlockedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final list =
        _blockedUsers.entries.map((e) => '${e.key}::${e.value}').toList()
          ..sort();
    await prefs.setStringList(_blockedUsersKey, list);
  }

  bool _isBlockedUserId(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return false;
    return _blockedUsers.containsKey(id);
  }

  Future<void> _confirmAndBlockUser({
    required String userId,
    required String label,
  }) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    if (id == widget.currentUserId.trim()) return;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block user'),
        content: Text(
          'Block $label?\n\nYou will no longer see their posts or comments in House Request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    setState(() {
      _blockedUsers[id] = label;
      _comments.removeWhere((c) => c['user_id']?.toString().trim() == id);
    });
    await _saveBlockedUsers();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('User blocked')));
  }

  Future<void> _loadComments() async {
    try {
      final comments = await ApiService.fetchRequestComments(widget.requestId);
      final filtered = comments
          .where((c) => !_isBlockedUserId(c['user_id']?.toString() ?? ''))
          .toList();
      if (!mounted) return;
      setState(() {
        _comments = filtered;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please login to comment.')));
      return;
    }

    setState(() => _isSending = true);
    try {
      final newComment = await ApiService.addRequestComment(
        widget.requestId,
        text,
      );
      if (!mounted) return;
      setState(() {
        _comments.add(newComment);
        _isSending = false;
      });
      _commentController.clear();
      widget.onCommentAdded(newComment);

      try {
        Supabase.instance.client.channel('public-requests').sendBroadcastMessage(
              event: 'new-comment',
              payload: {
                ...Map<String, dynamic>.from(newComment),
                'request_id': widget.requestId,
              },
            );
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Comments',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFFC107),
                      ),
                    )
                  : _comments.isEmpty
                  ? Center(
                      child: Text(
                        'No comments yet. Be the first to reply!',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _comments.length,
                      itemBuilder: (context, index) {
                        final c = _comments[index];
                        String name = (c['name'] ?? '').toString().trim();
                        final role = (c['role'] ?? '').toString();
                        if (name.isEmpty) {
                          name = role.isNotEmpty
                              ? role[0].toUpperCase() + role.substring(1)
                              : 'User';
                        }
                        final isMe =
                            c['user_id'].toString() == widget.currentUserId;
                        final userId = (c['user_id'] ?? '').toString().trim();
                        final label =
                            '$name${role == 'dealer' ? ' (Dealer)' : ''}';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: isMe
                                    ? const Color(0xFFFFC107)
                                    : (isDark
                                          ? const Color(0xFF2C2C2C)
                                          : Colors.grey[300]),
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                  style: TextStyle(
                                    color: isMe
                                        ? Colors.black87
                                        : (isDark
                                              ? Colors.white70
                                              : Colors.black87),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF2C2C2C)
                                        : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white12
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              label,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: isDark
                                                    ? Colors.white70
                                                    : Colors.grey[800],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (!isMe)
                                            IconButton(
                                              icon: Icon(
                                                Icons.block,
                                                size: 18,
                                                color: isDark
                                                    ? Colors.red.shade300
                                                    : Colors.red.shade700,
                                              ),
                                              tooltip: 'Block user',
                                              onPressed: userId.isEmpty
                                                  ? null
                                                  : () => _confirmAndBlockUser(
                                                      userId: userId,
                                                      label: label,
                                                    ),
                                              padding: EdgeInsets.zero,
                                              constraints:
                                                  const BoxConstraints(),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        c['comment'].toString(),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Write a comment...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.black54,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF2C2C2C)
                            : Colors.grey[200],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFC107),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black87,
                              ),
                            )
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
