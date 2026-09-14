import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/app_logo.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Widget _highlight({
    required IconData icon,
    required String label,
    required Color labelColor,
    required Color iconColor,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: labelColor,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A140F);
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF6B5E52);
    final accent = const Color(0xFFFFC107);
    final brown = const Color(0xFF5A3D31);
    final sheetColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final highlightBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFFFF8E7);
    final highlightIcon = isDark ? accent : brown;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [
                    Color(0xFF1A160F),
                    Color(0xFF121212),
                    Color(0xFF0E0E0E),
                  ]
                : const [
                    Color(0xFFFFF4D6),
                    Color(0xFFFFFAF0),
                    Color(0xFFF7F3EC),
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 36, 28, 20),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: isDark ? 0.16 : 0.28),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(
                                alpha: isDark ? 0.18 : 0.35,
                              ),
                              blurRadius: 36,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const AppLogo(size: 96),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'HouseRent Africa',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: titleColor,
                          letterSpacing: -0.6,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Find homes faster. List with confidence.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: subtitleColor,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 36),
                      _highlight(
                        icon: Icons.map_outlined,
                        label: 'Search homes on the map',
                        labelColor: titleColor,
                        iconColor: highlightIcon,
                        background: highlightBg,
                      ),
                      const SizedBox(height: 10),
                      _highlight(
                        icon: Icons.verified_outlined,
                        label: 'Verified dealers & landlords',
                        labelColor: titleColor,
                        iconColor: highlightIcon,
                        background: highlightBg,
                      ),
                      const SizedBox(height: 10),
                      _highlight(
                        icon: Icons.support_agent_outlined,
                        label: 'Request a house and get matched',
                        labelColor: titleColor,
                        iconColor: highlightIcon,
                        background: highlightBg,
                      ),
                      const SizedBox(height: 10),
                      _highlight(
                        icon: Icons.local_shipping_outlined,
                        label:
                            'Truck drivers can register to help tenants move',
                        labelColor: titleColor,
                        iconColor: highlightIcon,
                        background: highlightBg,
                      ),
                      const SizedBox(height: 10),
                      _highlight(
                        icon: Icons.money_off_outlined,
                        label:
                            'Free to list — no commission for landlords & drivers',
                        labelColor: titleColor,
                        iconColor: highlightIcon,
                        background: highlightBg,
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Kulibe ndiwe wako komboni — we accept.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? accent.withValues(alpha: 0.85)
                              : brown.withValues(alpha: 0.85),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                decoration: BoxDecoration(
                  color: sheetColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.4 : 0.08,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: () => context.go('/login'),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: brown,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Login',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => context.go('/register'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: titleColor,
                          side: BorderSide(
                            color: isDark
                                ? accent.withValues(alpha: 0.65)
                                : const Color(0xFFD4A017),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton(
                        onPressed: () => context.go('/home'),
                        style: TextButton.styleFrom(
                          foregroundColor: isDark ? Colors.white70 : brown,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Continue to Home',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
