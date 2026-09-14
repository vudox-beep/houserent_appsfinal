import 'dart:async';

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'skeleton_loader.dart';

class HomeSlidingBanner extends StatefulWidget {
  const HomeSlidingBanner({super.key});

  @override
  State<HomeSlidingBanner> createState() => HomeSlidingBannerState();
}

class HomeSlidingBannerState extends State<HomeSlidingBanner> {
  static const List<String> _fallback = <String>[
    'Welcome to HouseRent Africa — find your next home.',
    'Tip: Use House Request to tell landlords what you are looking for.',
  ];

  List<String> _messages = const <String>[];
  bool _loading = true;
  double _offset = 0;
  double _segmentWidth = 1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> reload() async {
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _loading = true;
        _offset = 0;
      });
    }
    try {
      final messages = await ApiService.fetchHomeBanners();
      if (!mounted) return;
      setState(() {
        _messages = messages.isEmpty ? _fallback : messages;
        _loading = false;
      });
      _startSlide();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = _fallback;
        _loading = false;
      });
      _startSlide();
    }
  }

  String get _ticker {
    final parts = _messages
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();
    final joined = (parts.isEmpty ? _fallback : parts).join('   •   ');
    return '$joined   •   ';
  }

  TextStyle _style(bool isDark) {
    return TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      color: isDark ? const Color(0xFFFFF6D8) : const Color(0xFF4A3B00),
    );
  }

  void _measure(bool isDark) {
    final painter = TextPainter(
      text: TextSpan(text: _ticker, style: _style(isDark)),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    _segmentWidth = painter.width <= 0 ? 1.0 : painter.width;
  }

  void _startSlide() {
    _timer?.cancel();
    if (!mounted) return;

    const step = 0.65;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) return;
      setState(() {
        _offset += step;
        if (_offset >= _segmentWidth) {
          _offset -= _segmentWidth;
        }
      });
    });
  }

  BoxDecoration _bannerDecoration(bool isDark) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: isDark
            ? const [Color(0xFF2A2110), Color(0xFF1A160C), Color(0xFF2A2110)]
            : const [Color(0xFFFFF8E1), Color(0xFFFFECB3), Color(0xFFFFF8E1)],
      ),
      border: Border(
        bottom: BorderSide(
          color: isDark
              ? const Color(0xFFFFC107).withValues(alpha: 0.18)
              : const Color(0xFFE0C35A).withValues(alpha: 0.45),
        ),
      ),
    );
  }

  Widget _buildSkeleton(bool isDark) {
    return Container(
      width: double.infinity,
      height: 42,
      decoration: _bannerDecoration(isDark),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SkeletonBox(
            width: 18,
            height: 18,
            borderRadius: BorderRadius.circular(6),
            baseColor: isDark
                ? const Color(0xFF3A3018)
                : const Color(0xFFE8D9A0),
            highlightColor: isDark
                ? const Color(0xFF4A3D20)
                : const Color(0xFFFFF8E7),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SkeletonBox(
              height: 14,
              borderRadius: BorderRadius.circular(8),
              baseColor: isDark
                  ? const Color(0xFF3A3018)
                  : const Color(0xFFE8D9A0),
              highlightColor: isDark
                  ? const Color(0xFF4A3D20)
                  : const Color(0xFFFFF8E7),
            ),
          ),
          const SizedBox(width: 10),
          SkeletonBox(
            width: 72,
            height: 14,
            borderRadius: BorderRadius.circular(8),
            baseColor: isDark
                ? const Color(0xFF3A3018)
                : const Color(0xFFE8D9A0),
            highlightColor: isDark
                ? const Color(0xFF4A3D20)
                : const Color(0xFFFFF8E7),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return _buildSkeleton(isDark);
    }

    final textStyle = _style(isDark);
    final ticker = _ticker;
    _measure(isDark);
    final left = _offset - _segmentWidth;

    return Container(
      width: double.infinity,
      height: 42,
      decoration: _bannerDecoration(isDark),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFFFFC107).withValues(alpha: 0.16)
                  : const Color(0xFFFFC107).withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.campaign_rounded,
              size: 16,
              color: isDark
                  ? const Color(0xFFFFC107)
                  : const Color(0xFF8A6D00),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  width: constraints.maxWidth,
                  height: 42,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned(
                        left: left,
                        top: 0,
                        bottom: 0,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                ticker,
                                maxLines: 1,
                                softWrap: false,
                                style: textStyle,
                              ),
                              Text(
                                ticker,
                                maxLines: 1,
                                softWrap: false,
                                style: textStyle,
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
        ],
      ),
    );
  }
}
