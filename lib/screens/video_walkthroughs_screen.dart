import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'dealer/dealer_payment_webview_screen.dart';
import '../services/api_service.dart';

class VideoWalkthroughsScreen extends StatefulWidget {
  const VideoWalkthroughsScreen({super.key});

  @override
  State<VideoWalkthroughsScreen> createState() =>
      _VideoWalkthroughsScreenState();
}

class _VideoWalkthroughsScreenState extends State<VideoWalkthroughsScreen> {
  final PageController _pageController = PageController();
  final Map<int, VideoPlayerController> _controllers = {};
  final Set<int> _failedVideoIndexes = <int>{};

  List<Map<String, dynamic>> _videoProperties = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _currentIndex = 0;
  bool _isMuted = false;
  bool _isLoggedIn = false;
  bool _hasPaidContactAccess = false;
  bool _isCheckingContactAccess = false;
  String _currentUserId = '';
  String _userRole = '';
  bool _showPlayOverlay = false;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _loadVideoProperties();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    super.dispose();
  }

  Future<void> _loadVideoProperties() async {
    try {
      final properties = await ApiService.fetchProperties();
      final videos = properties
          .whereType<Map>()
          .map((e) {
            final map = Map<String, dynamic>.from(e);
            map['_resolved_video_url'] = _extractVideoSource(map);
            return map;
          })
          .where(
            (p) =>
                (p['_resolved_video_url'] ?? '').toString().trim().isNotEmpty,
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _videoProperties = videos;
        _isLoading = false;
      });

      if (_videoProperties.isNotEmpty) {
        await _initializeController(0, autoPlay: true);
        _prepareNearbyControllers(0);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load video walkthroughs. Pull to retry.';
      });
    }
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final role = prefs.getString('role') ?? '';

    if (token == null || token.isEmpty) return;

    try {
      final profile = await ApiService.getProfile();
      if (!mounted) return;
      setState(() {
        _isLoggedIn = true;
        _userRole = role;
        _currentUserId =
            profile['id']?.toString() ??
            profile['user']?['id']?.toString() ??
            '';
      });

      if (_userRole == 'dealer' || _userRole == 'admin') {
        setState(() {
          _hasPaidContactAccess = true;
        });
      } else {
        await _checkContactAccessStatus();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoggedIn = false;
      });
    }
  }

  Future<void> _checkContactAccessStatus() async {
    if (!_isLoggedIn || _currentUserId.isEmpty) return;
    setState(() {
      _isCheckingContactAccess = true;
    });

    try {
      final response = await http.post(
        Uri.parse('https://houseforrent.site/api/tenant_contact_payment.php'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'action': 'get_status', 'user_id': _currentUserId},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map &&
            data['status'] == 'success' &&
            data['has_paid'] == true &&
            mounted) {
          setState(() {
            _hasPaidContactAccess = true;
          });
        }
      }
    } catch (_) {
      // Keep UI resilient if payment status check fails.
    } finally {
      if (!mounted) return;
      setState(() {
        _isCheckingContactAccess = false;
      });
    }
  }

  Future<void> _showContactAccessPrompt({
    required Future<void> Function() onPaidSuccess,
  }) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Premium Contact Access',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Pay once to unlock direct contact details for listings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFC107),
              foregroundColor: Colors.black87,
            ),
            child: Text(_isLoggedIn ? 'Pay Now' : 'Login to Pay'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    if (!_isLoggedIn) {
      await context.push('/login');
      if (!mounted) return;
      await _checkLoginStatus();
      if (!_isLoggedIn) return;
    }

    if (!mounted) return;
    final profile = await ApiService.getProfile();
    final phone = (profile['phone'] ?? '').toString();
    final email = (profile['email'] ?? '').toString();
    final name = (profile['name'] ?? '').toString();
    final url =
        'https://houseforrent.site/api/tenant_contact_payment.php?action=pay_page&user_id=$_currentUserId&phone=${Uri.encodeComponent(phone)}&email=${Uri.encodeComponent(email)}&name=${Uri.encodeComponent(name)}';

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DealerPaymentWebviewScreen(url: url),
      ),
    );

    await _checkContactAccessStatus();
    if (_hasPaidContactAccess) {
      await onPaidSuccess();
    }
  }

  String _normalizeZmPhone(String input) {
    var cleaned = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('00')) cleaned = cleaned.substring(2);
    if (cleaned.startsWith('260') && cleaned.length == 12) return cleaned;
    if (cleaned.startsWith('0') && cleaned.length == 10) {
      cleaned = '260${cleaned.substring(1)}';
    } else if (cleaned.length == 9) {
      cleaned = '260$cleaned';
    }
    return cleaned;
  }

  String _dealerPhone(Map<String, dynamic> property) {
    return (property['dealer_phone'] ?? property['phone'] ?? '')
        .toString()
        .trim();
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final normalized = _normalizeZmPhone(phoneNumber);
    if (normalized.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dealer phone is not available')),
      );
      return;
    }

    final uri = Uri.parse('tel:+$normalized');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not start phone call')));
  }

  Future<void> _openWhatsApp(String phoneNumber, String propertyTitle) async {
    final normalized = _normalizeZmPhone(phoneNumber);
    if (normalized.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dealer phone is not available')),
      );
      return;
    }

    final message = Uri.encodeComponent(
      'Hi, I am interested in $propertyTitle. Please share more details.',
    );
    final uri = Uri.parse('https://wa.me/$normalized?text=$message');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp')));
  }

  Future<void> _openContactSheet(Map<String, dynamic> property) async {
    final phone = _dealerPhone(property);
    final title = (property['title'] ?? 'this listing').toString();
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dealer contact not available')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Contact Owner',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107),
                  foregroundColor: Colors.black,
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  await _makePhoneCall(phone);
                },
                icon: const Icon(Icons.call),
                label: const Text('Call now'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  await _openWhatsApp(phone, title);
                },
                icon: const Icon(Icons.chat),
                label: const Text('WhatsApp'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleContactOwner(Map<String, dynamic> property) async {
    if (_hasPaidContactAccess ||
        _userRole == 'dealer' ||
        _userRole == 'admin') {
      await _openContactSheet(property);
      return;
    }
    await _showContactAccessPrompt(
      onPaidSuccess: () => _openContactSheet(property),
    );
  }

  String _normalizeVideoUrl(String rawUrl) {
    String processedUrl = rawUrl.trim().replaceAll('`', '');
    if (!processedUrl.startsWith('http')) {
      if (processedUrl.startsWith('/'))
        processedUrl = processedUrl.substring(1);
      if (processedUrl.startsWith('assets/')) {
        processedUrl = 'https://houseforrent.site/$processedUrl';
      } else if (processedUrl.startsWith('uploads/')) {
        processedUrl =
            'https://houseforrent.site/php_backend/api/$processedUrl';
      } else {
        processedUrl = 'https://houseforrent.site/assets/$processedUrl';
      }
    }
    return processedUrl;
  }

  bool _isExternalPlayerUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('vimeo.com') ||
        lower.contains('dailymotion.com') ||
        lower.contains('tiktok.com');
  }

  bool _isLikelyDirectVideo(String url) {
    if (_isExternalPlayerUrl(url)) return false;
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m3u8') ||
        lower.contains('/uploads/') ||
        lower.contains('/assets/');
  }

  Future<void> _initializeController(int index, {bool autoPlay = false}) async {
    if (index < 0 || index >= _videoProperties.length) return;
    if (_controllers[index] != null) {
      if (autoPlay) {
        final existing = _controllers[index]!;
        await existing.setVolume(_isMuted ? 0 : 1);
        await existing.play();
      }
      return;
    }

    final rawUrl = (_videoProperties[index]['_resolved_video_url'] ?? '')
        .toString();
    final url = _normalizeVideoUrl(rawUrl);
    if (!_isLikelyDirectVideo(url)) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));

    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_isMuted ? 0 : 1);
      _controllers[index] = controller;
      _failedVideoIndexes.remove(index);
      if (autoPlay) {
        await controller.play();
        _showPlayOverlay = false;
      }
      if (mounted) setState(() {});
    } catch (_) {
      _failedVideoIndexes.add(index);
      await controller.dispose();
      if (mounted) setState(() {});
    }
  }

  void _prepareNearbyControllers(int centerIndex) {
    _initializeController(centerIndex - 1);
    _initializeController(centerIndex + 1);

    final keep = {centerIndex - 1, centerIndex, centerIndex + 1};
    final toRemove = _controllers.keys.where((k) => !keep.contains(k)).toList();
    for (final index in toRemove) {
      _controllers[index]?.dispose();
      _controllers.remove(index);
    }
  }

  Future<void> _onPageChanged(int index) async {
    if (_controllers[_currentIndex] != null) {
      await _controllers[_currentIndex]!.pause();
    }
    setState(() {
      _currentIndex = index;
      _showPlayOverlay = false;
    });
    await _initializeController(index, autoPlay: true);
    _prepareNearbyControllers(index);
  }

  Future<void> _togglePlayPauseCurrent() async {
    final controller = _controllers[_currentIndex];
    if (controller == null || !controller.value.isInitialized) return;

    if (controller.value.isPlaying) {
      await controller.pause();
      if (!mounted) return;
      setState(() {
        _showPlayOverlay = true;
      });
    } else {
      await controller.play();
      if (!mounted) return;
      setState(() {
        _showPlayOverlay = false;
      });
    }
  }

  Future<void> _toggleMute() async {
    setState(() {
      _isMuted = !_isMuted;
    });
    for (final controller in _controllers.values) {
      await controller.setVolume(_isMuted ? 0 : 1);
    }
  }

  Future<void> _openVideoExternally(String rawUrl) async {
    final url = _normalizeVideoUrl(rawUrl);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open this video link')),
    );
  }

  String _extractVideoSource(Map<String, dynamic> property) {
    final direct = (property['video_url'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final images = property['images'];
    if (images is List) {
      for (final item in images) {
        String url = '';
        if (item is Map) {
          url = (item['url'] ?? item['image_path'] ?? '').toString().trim();
        } else if (item is String) {
          url = item.trim();
        }
        final lower = url.toLowerCase();
        if (lower.endsWith('.mp4') ||
            lower.endsWith('.mov') ||
            lower.endsWith('.m4v') ||
            lower.endsWith('.webm') ||
            lower.endsWith('.m3u8')) {
          return url;
        }
      }
    }
    return '';
  }

  String _location(Map<String, dynamic> p) {
    final city = (p['city'] ?? '').toString().trim();
    final country = (p['country'] ?? '').toString().trim();
    final location = (p['location'] ?? '').toString().trim();
    if (city.isNotEmpty && country.isNotEmpty) return '$city, $country';
    if (location.isNotEmpty) return location;
    return 'Location not set';
  }

  String _mainImageUrl(Map<String, dynamic> p) {
    final raw = (p['main_image'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    final images = p['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is Map) {
        return (first['url'] ?? '').toString().trim();
      }
      if (first is String) return first.trim();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        foregroundColor: Colors.white,
        title: const Text('House Reels'),
        actions: [
          IconButton(
            onPressed: _toggleMute,
            icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
            tooltip: _isMuted ? 'Unmute videos' : 'Mute videos',
          ),
        ],
      ),
      body: _isLoading
          ? const _HouseReelsSkeleton()
          : _errorMessage != null
          ? RefreshIndicator(
              onRefresh: _loadVideoProperties,
              child: ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.75,
                    child: Center(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : _videoProperties.isEmpty
          ? RefreshIndicator(
              onRefresh: _loadVideoProperties,
              child: ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.75,
                    child: const Center(
                      child: Text(
                        'No video walkthroughs yet.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: _videoProperties.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final property = _videoProperties[index];
                final controller = _controllers[index];
                final rawVideoUrl = (property['_resolved_video_url'] ?? '')
                    .toString();
                final normalizedVideoUrl = _normalizeVideoUrl(rawVideoUrl);
                final canPlayInline = _isLikelyDirectVideo(normalizedVideoUrl);
                final title = (property['title'] ?? 'Untitled Property')
                    .toString();
                final currency = (property['currency'] ?? 'ZMW').toString();
                final price = (property['price'] ?? '0').toString();
                final propertyId =
                    (property['id'] ?? property['property_id'] ?? '')
                        .toString();
                final posterUrl = _mainImageUrl(property);

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (canPlayInline &&
                        controller != null &&
                        controller.value.isInitialized)
                      Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        child: AspectRatio(
                          aspectRatio:
                              controller.value.aspectRatio > 0
                                  ? controller.value.aspectRatio
                                  : (9 / 16),
                          child: VideoPlayer(controller),
                        ),
                      )
                    else
                      Container(
                        color: Colors.black,
                        child: Center(
                          child:
                              _failedVideoIndexes.contains(index) ||
                                  !canPlayInline
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.ondemand_video,
                                      color: Colors.white70,
                                      size: 50,
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'This video opens in normal player',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                    const SizedBox(height: 12),
                                    ElevatedButton.icon(
                                      onPressed: () =>
                                          _openVideoExternally(rawVideoUrl),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFFFC107,
                                        ),
                                        foregroundColor: Colors.black,
                                      ),
                                      icon: const Icon(Icons.open_in_new),
                                      label: const Text('Open video'),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (posterUrl.isNotEmpty)
                                      Container(
                                        width: 180,
                                        height: 240,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          image: DecorationImage(
                                            image: NetworkImage(posterUrl),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 14),
                                    const CircularProgressIndicator(
                                      color: Color(0xFFFFC107),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Preparing video...',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.2),
                              Colors.transparent,
                              Colors.black.withOpacity(0.65),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _togglePlayPauseCurrent,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    if (_showPlayOverlay && index == _currentIndex)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          color: Colors.white70,
                          size: 76,
                        ),
                      ),
                    if (canPlayInline &&
                        controller != null &&
                        controller.value.isInitialized)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Color(0xFFFFC107),
                            bufferedColor: Colors.white54,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 26,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_location(property)}  •  $currency $price',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black87,
                                ),
                                onPressed: _isCheckingContactAccess
                                    ? null
                                    : () => _handleContactOwner(property),
                                icon: const Icon(Icons.call_outlined),
                                label: Text(
                                  _hasPaidContactAccess
                                      ? 'Contact owner'
                                      : 'Unlock to contact',
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFFC107),
                                  foregroundColor: Colors.black,
                                ),
                                onPressed: propertyId.isEmpty
                                    ? null
                                    : () {
                                        context.push('/property/$propertyId');
                                      },
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('View details'),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${index + 1}/${_videoProperties.length}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _HouseReelsSkeleton extends StatefulWidget {
  const _HouseReelsSkeleton();

  @override
  State<_HouseReelsSkeleton> createState() => _HouseReelsSkeletonState();
}

class _HouseReelsSkeletonState extends State<_HouseReelsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = 0.18 + (_controller.value * 0.16);
        return Container(
          color: const Color(0xFF0F0F0F),
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: 220,
                  height: 360,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(pulse),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 30,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skeletonBar(width: 210, height: 18, opacity: pulse),
                    const SizedBox(height: 10),
                    _skeletonBar(width: 165, height: 13, opacity: pulse),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _skeletonChip(width: 128, opacity: pulse),
                        const SizedBox(width: 8),
                        _skeletonChip(width: 116, opacity: pulse),
                        const SizedBox(width: 8),
                        _skeletonChip(width: 56, opacity: pulse),
                      ],
                    ),
                  ],
                ),
              ),
              const Positioned(
                top: 18,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Loading House Reels...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _skeletonBar({
    required double width,
    required double height,
    required double opacity,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(opacity),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _skeletonChip({required double width, required double opacity}) {
    return Container(
      width: width,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(opacity),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
