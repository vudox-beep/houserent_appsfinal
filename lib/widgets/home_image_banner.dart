import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import 'skeleton_loader.dart';

class HomeImageBanner extends StatefulWidget {
  const HomeImageBanner({super.key});

  @override
  State<HomeImageBanner> createState() => HomeImageBannerState();
}

class HomeImageBannerState extends State<HomeImageBanner> {
  final PageController _pageController = PageController();
  final Map<String, double> _aspects = <String, double>{};
  List<HomeBannerItem> _banners = const [];
  bool _loading = true;
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _loading = true;
        _index = 0;
        _aspects.clear();
      });
    }
    try {
      final items = await ApiService.fetchHomeBannerItems(forceRefresh: true);
      if (!mounted) return;
      final banners = items.where((item) => item.hasImage).toList();
      setState(() {
        _banners = banners;
        _loading = false;
      });
      for (final banner in banners) {
        _readAspect(banner.imageUrl);
      }
      _startAutoPlay();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _banners = const [];
        _loading = false;
      });
    }
  }

  void _readAspect(String url) {
    if (url.isEmpty || _aspects.containsKey(url)) return;
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        final width = info.image.width.toDouble();
        final height = info.image.height.toDouble();
        if (!mounted || width <= 0 || height <= 0) return;
        setState(() => _aspects[url] = width / height);
      },
      onError: (_, __) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  void _startAutoPlay() {
    _timer?.cancel();
    if (_banners.length < 2) return;
    _timer = Timer.periodic(const Duration(milliseconds: 5500), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_index + 1) % _banners.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _openLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  double _bannerHeight(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final currentUrl =
        _banners.isEmpty ? '' : _banners[_index.clamp(0, _banners.length - 1)].imageUrl;
    final aspect = _aspects[currentUrl] ??
        (_aspects.isNotEmpty ? _aspects.values.first : (16 / 9));
    return width / aspect;
  }

  @override
  Widget build(BuildContext context) {
    final height = _bannerHeight(context);

    if (_loading) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return SizedBox(
        width: double.infinity,
        height: height,
        child: SkeletonBox(
          width: double.infinity,
          height: height,
          borderRadius: BorderRadius.zero,
          baseColor: isDark ? const Color(0xFF1A2233) : const Color(0xFFE8EDF5),
          highlightColor:
              isDark ? const Color(0xFF2A3348) : const Color(0xFFF7F9FC),
        ),
      );
    }

    if (_banners.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: _banners.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final banner = _banners[i];
                final image = SizedBox.expand(
                  child: Image.network(
                    banner.imageUrl,
                    fit: BoxFit.fill,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                );
                if (banner.linkUrl.isEmpty) {
                  return image;
                }
                return GestureDetector(
                  onTap: () => _openLink(banner.linkUrl),
                  child: image,
                );
              },
            ),
            if (_banners.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_banners.length, (i) {
                    final active = i == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 16 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFFFC107)
                            : Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
