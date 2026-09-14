import 'package:flutter/material.dart';
import '../widgets/app_logo.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/firebase_messaging_service.dart';
import '../services/notification_service.dart';
import 'driver/driver_dashboard.dart';
import 'dealer/dealer_dashboard.dart';
import 'tenant/tenant_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _publicNotifBadgeCountKey =
      'public_admin_notifications_badge_v1';
  final _formKey = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  bool _isLoading = false;
  int _selectedIndex = 3;
  int _publicNotifBadgeCount = 0;
  String? _errorMessage;
  bool _isEmailUnverified = false;
  bool _isResending = false;
  bool _obscurePassword = true;
  int _houseHuntBadgeCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPublicNotificationBadgeCount();
    _refreshPublicNotificationBadgeCount();
    _loadHouseHuntBadgeCount();
  }

  Future<void> _loadHouseHuntBadgeCount() async {
    final count = await ApiService.fetchTenantRequestsCount();
    if (!mounted) return;
    setState(() {
      _houseHuntBadgeCount = count;
    });
  }

  Future<void> _loadPublicNotificationBadgeCount() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_publicNotifBadgeCountKey) ?? 0;
    if (!mounted) return;
    setState(() {
      _publicNotifBadgeCount = count;
    });
  }

  Future<void> _refreshPublicNotificationBadgeCount() async {
    final count =
        await NotificationService.refreshPublicNotificationBadgeCount();
    if (!mounted) return;
    setState(() {
      _publicNotifBadgeCount = count;
    });
  }

  Future<void> _openForgotPasswordPage() async {
    final Uri forgotPasswordUri = Uri.parse(
      'https://houseforrent.site/forgot_password.php',
    );
    await launchUrl(forgotPasswordUri, mode: LaunchMode.externalApplication);
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _isEmailUnverified = false;
      });

      try {
        final response = await ApiService.login(_email, _password);
        if (mounted) {
          if (response['status'] == 'error') {
            final String code = response['code'] ?? '';
            String errorMessage =
                response['message'] ??
                'Login failed. Please check your credentials and try again.';

            // Extract role safely if provided
            final role = response['user']?['role'] ?? response['role'];

            if (code == 'banned') {
              errorMessage =
                  'Your account has been locked. Please contact support.';
            }

            if (code == 'email_unverified') {
              setState(() {
                _isEmailUnverified = true;
                _errorMessage =
                    'Email not verified. Please check your email or spam folder for the verification link.';
              });
              return;
            }

            // If the error is 'subscription_inactive', we should STILL log them in
            // and route them to the dashboard so they can see the lockout screen.
            if (code == 'subscription_inactive') {
              if (role == 'dealer' || role == 'agent' || role == 'company') {
                context.go('/dealer-dashboard');
                return;
              }
            }

            setState(() {
              _errorMessage = errorMessage;
            });
          } else {
            // Success
            final role = (response['user']?['role'] ?? response['role'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            await FirebaseMessagingService.syncToken();
            await NotificationService.forceCheckNow();
            await NotificationService.scheduleQuickBackgroundCheck();
            if (!mounted) return;

            final isListingPanel =
                role == 'dealer' || role == 'agent' || role == 'company';

            // Use MaterialPageRoute for dashboards so login works even if
            // GoRouter was created before these routes existed (hot reload).
            final Widget next;
            if (isListingPanel) {
              next = const DealerDashboard();
            } else if (role == 'driver') {
              next = const DriverDashboard();
            } else {
              next = const TenantDashboard();
            }
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => next),
              (_) => false,
            );
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Invalid email or password. Please try again.';
          });
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    setState(() {
      _isResending = true;
      _errorMessage = null;
    });
    try {
      final res = await ApiService.resendVerification(_email);
      if (mounted) {
        setState(() {
          _isResending = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['message'] ?? 'Check your email for the verification link.',
            ),
            backgroundColor: res['status'] == 'success'
                ? Colors.green
                : Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isResending = false;
          _errorMessage =
              'Failed to resend verification email. Please try again later.';
        });
      }
    }
  }

  void _showLoginRequiredPopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Login Required',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Please login to view and save your favorite properties.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _onItemTapped(int index) {
    if (index == 0) {
      context.go('/home');
    } else if (index == 1) {
      _showLoginRequiredPopup();
    } else if (index == 2) {
      _showLoginRequiredPopup();
    } else if (index == 3) {
      _showLoginRequiredPopup();
    } else if (index == 4) {
      // Already on profile/login page
    }
  }

  Widget _buildNotificationIcon({required bool active, Color? color}) {
    final icon = Icon(
      active ? Icons.notifications : Icons.notifications_none,
      color: color,
    );
    if (_publicNotifBadgeCount <= 0) return icon;
    final badgeText = _publicNotifBadgeCount > 99
        ? '99+'
        : _publicNotifBadgeCount.toString();
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
  InputDecoration _fieldDecoration({
    required bool isDark,
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
      ),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? Colors.white38 : Colors.black38,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(
        icon,
        color: isDark ? const Color(0xFFFFC107) : const Color(0xFF5A3D31),
      ),
      suffixIcon: suffix,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFFC107), width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade400),
      ),
      filled: true,
      fillColor: isDark ? const Color(0xFF242424) : const Color(0xFFFAFAFA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFFFFC107);
    const brown = Color(0xFF5A3D31);
    final titleColor = isDark ? Colors.white : const Color(0xFF1A140F);
    final muted = isDark ? Colors.white70 : const Color(0xFF6B5E52);
    final sheet = isDark ? const Color(0xFF1A1A1A) : Colors.white;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? null : Colors.white,
          gradient: isDark
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1A160F),
                    Color(0xFF121212),
                    Color(0xFF0E0E0E),
                  ],
                )
              : null,
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/home');
                        }
                      },
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: isDark ? accent : brown,
                      ),
                    ),
                    Expanded(
                      child: AppBrand(
                        logoSize: 28,
                        fontSize: 17,
                        textColor: isDark ? accent : brown,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Public notifications',
                      onPressed: () => context.go('/public-notifications'),
                      icon: _buildNotificationIcon(
                        active: false,
                        color: isDark ? accent : brown,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withValues(
                                alpha: isDark ? 0.16 : 0.28,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(
                                    alpha: isDark ? 0.16 : 0.3,
                                  ),
                                  blurRadius: 28,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: const AppLogo(size: 72),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Welcome back',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sign in to continue to HouseRent Africa',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: muted,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                            decoration: BoxDecoration(
                              color: sheet,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: isDark ? 0.35 : 0.08,
                                  ),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_errorMessage != null) ...[
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: _isEmailUnverified
                                            ? (isDark
                                                ? const Color(0xFF3A2A10)
                                                : const Color(0xFFFFF8E1))
                                            : (isDark
                                                ? const Color(0xFF3A1515)
                                                : const Color(0xFFFFEBEE)),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: _isEmailUnverified
                                              ? accent.withValues(alpha: 0.45)
                                              : Colors.red.withValues(
                                                  alpha: 0.35,
                                                ),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                _isEmailUnverified
                                                    ? Icons
                                                        .mark_email_unread_rounded
                                                    : Icons.error_outline_rounded,
                                                color: _isEmailUnverified
                                                    ? accent
                                                    : Colors.red.shade400,
                                                size: 22,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  _errorMessage!,
                                                  style: TextStyle(
                                                    color: titleColor,
                                                    fontWeight: FontWeight.w600,
                                                    height: 1.35,
                                                    fontSize: 13.5,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (_isEmailUnverified) ...[
                                            const SizedBox(height: 10),
                                            SizedBox(
                                              width: double.infinity,
                                              height: 40,
                                              child: OutlinedButton(
                                                onPressed: _isResending
                                                    ? null
                                                    : _resendVerificationEmail,
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: brown,
                                                  side: BorderSide(
                                                    color: accent.withValues(
                                                      alpha: 0.8,
                                                    ),
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      10,
                                                    ),
                                                  ),
                                                ),
                                                child: _isResending
                                                    ? const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: brown,
                                                        ),
                                                      )
                                                    : const Text(
                                                        'Resend verification email',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                  ],
                                  Text(
                                    'Email',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                      color: titleColor,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    style: TextStyle(color: titleColor),
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    decoration: _fieldDecoration(
                                      isDark: isDark,
                                      hint: 'you@email.com',
                                      icon: Icons.email_outlined,
                                    ),
                                    validator: (value) =>
                                        value == null || value.trim().isEmpty
                                        ? 'Enter your email'
                                        : null,
                                    onSaved: (value) =>
                                        _email = value!.trim(),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Password',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                      color: titleColor,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    style: TextStyle(color: titleColor),
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) {
                                      if (!_isLoading) _login();
                                    },
                                    decoration: _fieldDecoration(
                                      isDark: isDark,
                                      hint: 'Enter your password',
                                      icon: Icons.lock_outline_rounded,
                                      suffix: IconButton(
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          color: muted,
                                        ),
                                      ),
                                    ),
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                        ? 'Enter your password'
                                        : null,
                                    onSaved: (value) => _password = value!,
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: _openForgotPasswordPage,
                                      style: TextButton.styleFrom(
                                        foregroundColor: isDark
                                            ? accent
                                            : brown,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 8,
                                        ),
                                      ),
                                      child: const Text(
                                        'Forgot password?',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 52,
                                    child: FilledButton(
                                      onPressed: _isLoading ? null : _login,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: accent,
                                        foregroundColor: brown,
                                        disabledBackgroundColor: accent
                                            .withValues(alpha: 0.55),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.4,
                                                color: brown,
                                              ),
                                            )
                                          : const Text(
                                              'Sign In',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Divider(
                                          color: isDark
                                              ? Colors.white12
                                              : const Color(0xFFE5E7EB),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        child: Text(
                                          'or',
                                          style: TextStyle(
                                            color: muted,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Divider(
                                          color: isDark
                                              ? Colors.white12
                                              : const Color(0xFFE5E7EB),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          context.go('/register'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: titleColor,
                                        side: BorderSide(
                                          color: isDark
                                              ? accent.withValues(alpha: 0.65)
                                              : const Color(0xFFD4A017),
                                          width: 1.5,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                      ),
                                      child: const Text(
                                        'Create an account',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Center(
                                    child: TextButton(
                                      onPressed: () => context.go('/home'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: muted,
                                      ),
                                      child: const Text(
                                        'Continue to Home',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
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
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        selectedItemColor: accent,
        unselectedItemColor: isDark ? Colors.grey[400] : Colors.grey,
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
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        elevation: 16,
      ),
    );
  }
}