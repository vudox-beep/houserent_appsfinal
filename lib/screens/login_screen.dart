import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

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

  @override
  void initState() {
    super.initState();
    _loadPublicNotificationBadgeCount();
    _refreshPublicNotificationBadgeCount();
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
    final count = await NotificationService.refreshPublicNotificationBadgeCount();
    if (!mounted) return;
    setState(() {
      _publicNotifBadgeCount = count;
    });
  }
  
  Future<void> _openForgotPasswordPage() async {
    final Uri forgotPasswordUri = Uri.parse('https://houseforrent.site/forgot_password.php');
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
            String errorMessage = response['message'] ?? 'Login failed. Please check your credentials and try again.';
            
            // Extract role safely if provided
            final role = response['user']?['role'] ?? response['role'];
            
            if (code == 'banned') {
              errorMessage = 'Your account has been locked. Please contact support.';
            }

            if (code == 'email_unverified') {
              setState(() {
                _isEmailUnverified = true;
                _errorMessage = 'Email not verified. Please check your email or spam folder for the verification link.';
              });
              return;
            }
            
            // If the error is 'subscription_inactive', we should STILL log them in 
            // and route them to the dashboard so they can see the lockout screen.
            if (code == 'subscription_inactive') {
               if (role == 'dealer') {
                 context.go('/dealer-dashboard');
                 return;
               }
            }
            
            setState(() {
              _errorMessage = errorMessage;
            });
          } else {
            // Success
            final role = response['user']['role'] ?? response['role'];
            await NotificationService.forceCheckNow();
            await NotificationService.scheduleQuickBackgroundCheck();
            if (role == 'dealer') {
              context.go('/dealer-dashboard');
            } else {
              context.go('/tenant-dashboard');
            }
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['message'] ?? 'Check your email for the verification link.'),
          backgroundColor: res['status'] == 'success' ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isResending = false;
          _errorMessage = 'Failed to resend verification email. Please try again later.';
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
      context.go('/public-notifications');
    } else if (index == 3) {
      // Already on profile/login page
    }
  }

  Widget _buildNotificationIcon({required bool active, Color? color}) {
    final icon = Icon(
      active ? Icons.notifications : Icons.notifications_none,
      color: color,
    );
    if (_publicNotifBadgeCount <= 0) return icon;
    final badgeText =
        _publicNotifBadgeCount > 99 ? '99+' : _publicNotifBadgeCount.toString();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Slightly off-white background
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => context.go('/home'),
          child: Row(
            children: [
              const Icon(Icons.real_estate_agent, color: Colors.white, size: 28),
              const SizedBox(width: 8),
              const Text(
                'HouseRent Africa', 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -0.5, fontSize: 20)
              ),
            ],
          ),
        ),
        elevation: 0,
        backgroundColor: const Color(0xFFFFC107), // Use yellow top bar
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Public notifications',
            onPressed: () => context.go('/public-notifications'),
            icon: _buildNotificationIcon(active: false, color: Colors.white),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const NetworkImage('https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?q=80&w=2075&auto=format&fit=crop'), // Clean interior background
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken), // Dark overlay so the card pops
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 550), // Prevent overflows on smaller screens
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95), // Slight transparency for the card
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 5,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFF9C4), // Light yellow background
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_outline, size: 40, color: Color(0xFFFFC107)), // Brand yellow icon
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Center(
                    child: Text(
                      'Welcome Back', 
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      'Sign in to manage your properties', 
                      style: TextStyle(fontSize: 16, color: Colors.black54)
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isEmailUnverified ? Colors.orange.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _isEmailUnverified ? Colors.orange.shade200 : Colors.red.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isEmailUnverified ? Icons.mark_email_unread_outlined : Icons.error_outline,
                                color: _isEmailUnverified ? Colors.orange.shade800 : Colors.red.shade800,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: _isEmailUnverified ? Colors.orange.shade900 : Colors.red.shade900,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (_errorMessage != null) const SizedBox(height: 24),
                  const Text('Email Address', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: InputDecoration(
                      hintText: 'Enter your email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (value) => value!.isEmpty ? 'Enter email' : null,
                    onSaved: (value) => _email = value!,
                  ),
                  const SizedBox(height: 24),
                  const Text('Password', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: InputDecoration(
                      hintText: 'Enter your password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    obscureText: true,
                    validator: (value) => value!.isEmpty ? 'Enter password' : null,
                    onSaved: (value) => _password = value!,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _openForgotPasswordPage,
                      child: const Text('Forgot Password?', style: TextStyle(color: Colors.black54)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC107), // Yellow
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      child: _isLoading 
                          ? const CircularProgressIndicator(color: Colors.black87)
                          : const Text('Sign In', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account?", style: TextStyle(color: Colors.black54)),
                      TextButton(
                        onPressed: () => context.go('/register'),
                        child: const Text('Register', style: TextStyle(color: Color(0xFF5A3D31), fontWeight: FontWeight.bold)),
                      )
                    ],
                  )
                ],
              ),
            ),
          ),
        ),
        ),
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
        selectedItemColor: const Color(0xFFD4AF37),
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 16,
      ),
    );
  }
}
