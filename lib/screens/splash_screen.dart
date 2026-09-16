import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/app_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward().then((_) async {
      try {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
        // Keep the session alive across refreshes: any logged-in user goes
        // straight back to their dashboard instead of the welcome/login flow.
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('token') ?? '';
        final role = prefs.getString('role') ?? '';
        var userId = prefs.getString('user_id') ?? '';
        if (token.isNotEmpty && userId.isEmpty) {
          final parts = token.split('.');
          if (parts.length == 3) {
            try {
              var normalized = parts[1].replaceAll('-', '+').replaceAll('_', '/');
              final mod = normalized.length % 4;
              if (mod == 2) normalized += '==';
              if (mod == 3) normalized += '=';
              final payload = jsonDecode(utf8.decode(base64.decode(normalized)));
              final id = payload is Map ? payload['id'] : null;
              if (id != null) {
                userId = id.toString();
                await prefs.setString('user_id', userId);
              }
            } catch (_) {}
          }
        }
        if (!mounted) return;
        if (token.isNotEmpty) {
          switch (role) {
            case 'driver':
              context.go('/driver-dashboard');
              return;
            case 'dealer':
            case 'agent':
            case 'company':
              context.go('/dealer-dashboard');
              return;
            case 'user':
            case 'tenant':
              context.go('/tenant-dashboard');
              return;
          }
        }
        context.go('/welcome');
      } catch (_) {
        if (!mounted) return;
        context.go('/welcome');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFC107), // Brand yellow
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: _opacityAnimation.value,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppLogo(size: 128),
                    const SizedBox(height: 24),
                    const Text(
                      'HouseRent Africa',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF5A3D31), // Brand brown
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Find Your Perfect Home',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black54,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 48),
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Color(0xFF5A3D31), // Brand brown
                        strokeWidth: 3,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
