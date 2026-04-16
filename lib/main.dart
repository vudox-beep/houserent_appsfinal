import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/tenant/tenant_dashboard.dart';
import 'screens/dealer/dealer_dashboard.dart';
import 'screens/advanced_search_screen.dart';
import 'screens/search_results_screen.dart';
import 'screens/property_details.dart';
import 'screens/dealer/dealer_identity_verification_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/notifications_screen.dart';

void main() {
  runApp(const HouseRentApp());
}

final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/property/:id',
      builder: (context, state) => PropertyDetailsScreen(propertyId: int.parse(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
        path: '/tenant-dashboard',
        builder: (context, state) {
          // If we pass an extra map like extra: {'tab': 4}, use it to open that tab
          final extra = state.extra as Map<String, dynamic>?;
          final tabIndex = extra?['tab'] as int? ?? 0;
          return TenantDashboard(initialTabIndex: tabIndex);
        },
      ),
    GoRoute(
      path: '/dealer-dashboard',
      builder: (context, state) => const DealerDashboard(),
    ),
    GoRoute(
      path: '/dealer-identity-verification',
      builder: (context, state) {
        final userId = state.extra as String? ?? '';
        return DealerIdentityVerificationScreen(userId: userId);
      },
    ),
    GoRoute(
      path: '/advanced-search',
      builder: (context, state) => const AdvancedSearchScreen(),
    ),
    GoRoute(
      path: '/search-results',
      builder: (context, state) {
        final extraParams = state.extra as Map<String, String>? ?? {};
        final queryParams = state.uri.queryParameters;
        final params = <String, String>{...queryParams, ...extraParams};
        return SearchResultsScreen(searchParams: params);
      },
    ),
  ],
);

class HouseRentApp extends StatelessWidget {
  const HouseRentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'HouseRent Africa',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        primaryColor: const Color(0xFFFFD700), // Yellow
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD700),
          primary: const Color(0xFFFFD700),
          secondary: Colors.black87,
          background: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: Colors.black87,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      routerConfig: _router,
    );
  }
}
