import 'package:flutter/material.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/tenant/tenant_dashboard.dart';
import 'screens/tenant/rent_savings_screen.dart';
import 'screens/tenant/tenant_rent_support_screen.dart';
import 'screens/dealer/dealer_dashboard.dart';
import 'screens/dealer/dealer_maintenance_screen.dart';
import 'screens/dealer/company_details_screen.dart';
import 'screens/rental_leases_screen.dart';
import 'screens/driver/driver_dashboard.dart';
import 'screens/driver/driver_identity_verification_screen.dart';
import 'screens/moving/tenant_moving_screen.dart';
import 'screens/moving/tenant_my_shifts_screen.dart';
import 'screens/advanced_search_screen.dart';
import 'screens/search_results_screen.dart';
import 'screens/property_details.dart';
import 'screens/dealer/dealer_identity_verification_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/public_notifications_screen.dart';
import 'screens/video_walkthroughs_screen.dart';
import 'screens/tenant_requests_screen.dart';
import 'screens/zed_bine_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/near_me_map_screen.dart';
import 'screens/legal_document_screen.dart';
import 'services/notification_service.dart';
import 'services/firebase_messaging_service.dart';

final ValueNotifier<ThemeMode> appThemeNotifier = ValueNotifier(
  ThemeMode.system,
);

void setAppThemeMode(ThemeMode mode) {
  if (appThemeNotifier.value == mode) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (appThemeNotifier.value != mode) {
      appThemeNotifier.value = mode;
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error: ${details.exceptionAsString()}');
  };

  runApp(const HouseRentApp());
}

Future<void> _bootstrapServices() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (error) {
    debugPrint('Firebase is waiting for its project configuration: $error');
  }

  try {
    await Supabase.initialize(
      url: 'https://zvrisevisfxtxiphzkuo.supabase.co',
      anonKey: 'sb_publishable_ccFKo_5mX3RBRKUm3gTmbg_VmU7I8Nl',
      debug: false,
    );
  } catch (error) {
    debugPrint('Supabase failed to start: $error');
  }

  try {
    await NotificationService.initialize();
  } catch (error) {
    debugPrint('Notification service failed to start: $error');
  }

  try {
    await NotificationService.startForegroundPolling(
      interval: const Duration(seconds: 20),
    );
  } catch (error) {
    debugPrint('Notification polling failed to start: $error');
  }

  try {
    if (Firebase.apps.isNotEmpty) {
      await FirebaseMessagingService.initialize();
    }
  } catch (error) {
    debugPrint('Firebase messaging failed to start: $error');
  }
}

final GoRouter _router = GoRouter(
  initialLocation: '/',
  errorBuilder: (context, state) {
    // Helps when an old build is missing a new route (e.g. /driver-dashboard).
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.link_off, size: 48, color: Colors.black45),
              const SizedBox(height: 12),
              Text(
                'Page not found\n${state.uri}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107),
                  foregroundColor: Colors.black87,
                ),
                child: const Text('Go home'),
              ),
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text('Back to login'),
              ),
            ],
          ),
        ),
      ),
    );
  },
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
    GoRoute(
      path: '/welcome',
      builder: (context, state) => const WelcomeScreen(),
    ),
    GoRoute(
      path: '/near-me',
      builder: (context, state) => const NearMeMapScreen(),
    ),
    GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/public-notifications',
      builder: (context, state) => const PublicNotificationsScreen(),
    ),
    GoRoute(
      path: '/video-walkthroughs',
      builder: (context, state) => const VideoWalkthroughsScreen(),
    ),
    GoRoute(
      path: '/tenant-requests',
      builder: (context, state) => const TenantRequestsScreen(),
    ),
    GoRoute(
      path: '/property/:id',
      builder: (context, state) => PropertyDetailsScreen(
        propertyId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/privacy',
      builder: (context, state) => const LegalDocumentScreen(
        type: LegalDocumentType.privacy,
      ),
    ),
    GoRoute(
      path: '/terms',
      builder: (context, state) => const LegalDocumentScreen(
        type: LegalDocumentType.terms,
      ),
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
      path: '/rent-savings',
      builder: (context, state) => const RentSavingsScreen(),
    ),
    GoRoute(
      path: '/tenant-rent-support',
      builder: (context, state) => const TenantRentSupportScreen(),
    ),
    GoRoute(
      path: '/tenant-rent-support/dispute/:id',
      builder: (context, state) => TenantDisputeChatScreen(
        caseId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/dealer-maintenance',
      builder: (context, state) => const Scaffold(
        body: SafeArea(child: DealerMaintenanceScreen()),
      ),
    ),
    GoRoute(
      path: '/rental-leases',
      builder: (context, state) {
        final isDealer = state.uri.queryParameters['dealer'] == '1';
        final rentalId = state.uri.queryParameters['rental_id'];
        return RentalLeasesScreen(
          isDealer: isDealer,
          preselectRentalId: rentalId,
        );
      },
    ),
    GoRoute(
      path: '/dealer-dashboard',
      builder: (context, state) => const DealerDashboard(),
    ),
    GoRoute(
      path: '/company-details',
      builder: (context, state) => const CompanyDetailsScreen(),
    ),
    GoRoute(
      path: '/driver-dashboard',
      builder: (context, state) => const DriverDashboard(),
    ),
    // Alias in case an older build navigates here
    GoRoute(
      path: '/driver',
      builder: (context, state) => const DriverDashboard(),
    ),
    GoRoute(
      path: '/moving',
      builder: (context, state) {
        final extra = state.extra;
        return TenantMovingScreen(
          resumeTrip: extra is Map<String, dynamic> ? extra : null,
        );
      },
    ),
    GoRoute(
      path: '/moving/my-shifts',
      builder: (context, state) => const TenantMyShiftsScreen(),
    ),
    GoRoute(
      path: '/dealer-identity-verification',
      builder: (context, state) {
        final userId = state.extra as String? ?? '';
        return DealerIdentityVerificationScreen(userId: userId);
      },
    ),
    GoRoute(
      path: '/driver-identity-verification',
      builder: (context, state) => const DriverIdentityVerificationScreen(),
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
    GoRoute(
      path: '/zed-bine',
      builder: (context, state) => const ZedBineScreen(),
    ),
  ],
);

class HouseRentApp extends StatefulWidget {
  const HouseRentApp({super.key});

  @override
  State<HouseRentApp> createState() => _HouseRentAppState();
}

class _HouseRentAppState extends State<HouseRentApp> {
  @override
  void initState() {
    super.initState();
    // Ask for notification/background permission after the first screen is
    // visible. Requesting too early (no Activity) skips the Android 13+ dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapServices());
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp.router(
          title: 'HouseRent Africa',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          themeAnimationDuration: Duration.zero,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF9FAFB),
            primaryColor: const Color(0xFFFFD700),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFFFD700),
              primary: const Color(0xFFFFD700),
              secondary: Colors.black87,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              scrolledUnderElevation: 0,
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Colors.white,
              selectedItemColor: Color(0xFFFFD700),
              unselectedItemColor: Colors.black54,
              elevation: 8,
              type: BottomNavigationBarType.fixed,
            ),
            cardTheme: const CardThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
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
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF121212),
            primaryColor: const Color(0xFFFFD700),
            colorScheme: ColorScheme.fromSeed(
              brightness: Brightness.dark,
              seedColor: const Color(0xFFFFD700),
              primary: const Color(0xFFFFD700),
              secondary: Colors.white70,
              surface: const Color(0xFF1E1E1E),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              scrolledUnderElevation: 0,
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Color(0xFF1E1E1E),
              selectedItemColor: Color(0xFFFFD700),
              unselectedItemColor: Colors.white54,
              elevation: 8,
              type: BottomNavigationBarType.fixed,
            ),
            cardTheme: const CardThemeData(
              color: Color(0xFF1E1E1E),
              surfaceTintColor: Colors.transparent,
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
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black87,
                disabledBackgroundColor: Colors.white12,
                disabledForegroundColor: Colors.white38,
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFFD700),
                side: const BorderSide(color: Color(0xFFFFD700)),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFFD700),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF2A2A2A),
              labelStyle: const TextStyle(color: Colors.white70),
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIconColor: Colors.white60,
              suffixIconColor: Colors.white60,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: Color(0xFFFFD700),
                  width: 1.5,
                ),
              ),
            ),
            dividerTheme: const DividerThemeData(color: Colors.white12),
            popupMenuTheme: const PopupMenuThemeData(
              color: Color(0xFF2C2C2C),
              surfaceTintColor: Colors.transparent,
              textStyle: TextStyle(color: Colors.white),
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF2C2C2C),
              surfaceTintColor: Colors.transparent,
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              contentTextStyle: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
          routerConfig: _router,
        );
      },
    );
  }
}
