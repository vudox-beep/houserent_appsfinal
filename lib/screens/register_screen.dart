import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../utils/app_error.dart';
import '../utils/legal_navigation.dart';
import '../screens/legal_document_screen.dart';
import '../widgets/app_logo.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const String _publicNotifBadgeCountKey =
      'public_admin_notifications_badge_v1';

  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _email = '';
  String _phone = '';
  String _password = '';
  String _confirmPassword = '';
  String _role = 'user';
  String _referralCode = '';
  String _vehicleType = '';
  String _vehicleCapacity = '';
  String _serviceArea = '';
  bool _acceptedTerms = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _registered = false;
  bool _isResending = false;
  String? _errorMessage;
  String? _successMessage;
  int _selectedIndex = 4;
  int _publicNotifBadgeCount = 0;
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
    setState(() => _houseHuntBadgeCount = count);
  }

  Future<void> _loadPublicNotificationBadgeCount() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_publicNotifBadgeCountKey) ?? 0;
    if (!mounted) return;
    setState(() => _publicNotifBadgeCount = count);
  }

  Future<void> _refreshPublicNotificationBadgeCount() async {
    final count =
        await NotificationService.refreshPublicNotificationBadgeCount();
    if (!mounted) return;
    setState(() => _publicNotifBadgeCount = count);
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

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    if (_password != _confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    if (!_acceptedTerms) {
      setState(() => _errorMessage = 'Please accept the Terms of Service.');
      return;
    }

    if (_role == 'driver' &&
        (_vehicleType.isEmpty ||
            _vehicleCapacity.isEmpty ||
            _serviceArea.isEmpty)) {
      setState(() => _errorMessage =
          'Please tell us about your moving vehicle and service area.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiService.register(
        name: _name,
        email: _email,
        password: _password,
        confirmPassword: _confirmPassword,
        role: _role,
        phone: _phone,
        referralCode: _referralCode,
        vehicleType: _vehicleType,
        vehicleCapacity: _vehicleCapacity,
        serviceArea: _serviceArea,
      );

      if (!mounted) return;

      if (response['status'] == 'success') {
        setState(() {
          _registered = true;
          _successMessage = AppError.sanitizePublicText(
            response['message']?.toString() ??
                'Registration successful. Please check your email to verify your account.',
            fallback:
                'Registration successful. Please check your email to verify your account.',
          );
          _errorMessage = null;
        });
      } else {
        setState(() {
          _errorMessage = AppError.sanitizePublicText(
            response['message']?.toString() ??
                'Registration failed. Please try again.',
            fallback: 'Registration failed. Please try again.',
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppError.sanitizePublicText(
          AppError.userMessage(
            e,
            fallback: 'Registration failed. Please try again.',
          ),
          fallback: 'Registration failed. Please try again.',
        );
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendVerificationEmail() async {
    setState(() {
      _isResending = true;
      _errorMessage = null;
    });
    try {
      final res = await ApiService.resendVerification(_email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppError.sanitizePublicText(
              res['message']?.toString() ??
                  'Check your email for the verification link.',
              fallback: 'Check your email for the verification link.',
            ),
          ),
          backgroundColor:
              res['status'] == 'success' ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Failed to resend verification email. Please try again later.';
      });
    } finally {
      if (mounted) setState(() => _isResending = false);
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
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFC107),
              foregroundColor: Colors.black87,
            ),
            child: const Text('Login'),
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
      context.go('/tenant-requests');
    } else if (index == 3) {
      context.go('/public-notifications');
    } else if (index == 4) {
      context.go('/login');
    }
  }

  Widget _buildNotificationIcon({required bool active, Color? color}) {
    final icon = Icon(
      active ? Icons.notifications : Icons.notifications_outlined,
      color: color,
    );
    if (_publicNotifBadgeCount <= 0) return icon;
    final badgeText =
        _publicNotifBadgeCount > 99 ? '99+' : '$_publicNotifBadgeCount';
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
    final badgeText =
        _houseHuntBadgeCount > 99 ? '99+' : '$_houseHuntBadgeCount';
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

  String _maskedEmail(String email) {
    final trimmed = email.trim();
    final at = trimmed.indexOf('@');
    if (at <= 0 || at >= trimmed.length - 1) {
      return '••••@••••';
    }

    final local = trimmed.substring(0, at);
    final domain = trimmed.substring(at + 1);

    String maskPart(String value, {int visible = 1}) {
      if (value.isEmpty) return '••••';
      final keep = value.length <= visible ? 1 : visible;
      final shown = value.substring(0, keep);
      final stars = '*' * (value.length > keep + 2 ? 3 : 2);
      return '$shown$stars';
    }

    // e.g. lucky@gmail.com → lu***@g***.com
    final domainDot = domain.lastIndexOf('.');
    if (domainDot > 0) {
      final domainName = domain.substring(0, domainDot);
      final tld = domain.substring(domainDot); // .com
      return '${maskPart(local, visible: 2)}@${maskPart(domainName, visible: 1)}$tld';
    }

    return '${maskPart(local, visible: 2)}@${maskPart(domain, visible: 1)}';
  }

  Widget _verificationSuccessCard({
    required bool isDark,
    required Color titleColor,
    required Color muted,
    required Color accent,
    required Color brown,
  }) {
    Widget step({
      required String number,
      required String title,
      required String subtitle,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.22 : 0.35),
                shape: BoxShape.circle,
              ),
              child: Text(
                number,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: brown,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: muted,
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.45),
                  accent.withValues(alpha: 0.15),
                ],
              ),
            ),
            child: Icon(
              Icons.mark_email_unread_rounded,
              size: 44,
              color: brown,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Check your email',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Account created. We sent a verification link to:',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: muted,
              height: 1.4,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF242424)
                  : const Color(0xFFFFF8E7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: accent.withValues(alpha: 0.55),
              ),
            ),
            child: Text(
              _maskedEmail(_email),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: titleColor,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Next steps',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                color: titleColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          step(
            number: '1',
            title: 'Open your email',
            subtitle: 'Check inbox and spam/junk folder.',
          ),
          step(
            number: '2',
            title: 'Tap “Verify Email Address”',
            subtitle: 'This activates your HouseRent Africa account.',
          ),
          step(
            number: '3',
            title: 'Come back and log in',
            subtitle: 'After verification, sign in with your email and password.',
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: brown.withValues(alpha: isDark ? 0.25 : 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: brown.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: brown, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You must verify your email before you can log in. After you verify, return here and tap Login below.',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: () => context.go('/login'),
              icon: const Icon(Icons.login_rounded),
              label: const Text(
                'After verify → Login',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: brown,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _isResending ? null : _resendVerificationEmail,
              style: OutlinedButton.styleFrom(
                foregroundColor: brown,
                side: BorderSide(color: accent.withValues(alpha: 0.85)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isResending
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: brown,
                      ),
                    )
                  : const Text(
                      'Resend verification email',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Didn’t get it? Wait a minute, check spam, then resend.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleDetailsSection({
    required bool isDark,
    required Color titleColor,
    required Color muted,
    required Color accent,
    required Color brown,
  }) {
    const vehicles = [
      ('Pickup truck', Icons.airport_shuttle_outlined, 'Small loads'),
      ('Cargo van', Icons.airport_shuttle_rounded, 'Furniture'),
      ('Box truck', Icons.local_shipping_outlined, 'Full house'),
      ('Lorry', Icons.fire_truck_outlined, 'Heavy loads'),
    ];
    const capacities = ['500 kg', '1 tonne', '2 tonnes', '3+ tonnes'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222222) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE8E4DF),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: brown.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.local_shipping_outlined, color: brown, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Moving vehicle details',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Only vehicles suited for household moves.',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Vehicle type',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.55,
            children: vehicles.map((v) {
              final selected = _vehicleType == v.$1;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _vehicleType = v.$1),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? accent.withValues(alpha: isDark ? 0.18 : 0.2)
                          : (isDark ? const Color(0xFF2A2A2A) : Colors.white),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? accent
                            : (isDark ? Colors.white12 : const Color(0xFFE5E7EB)),
                        width: selected ? 1.8 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              v.$2,
                              size: 20,
                              color: selected ? brown : muted,
                            ),
                            const Spacer(),
                            if (selected)
                              Icon(Icons.check_circle, size: 18, color: brown),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          v.$1,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: titleColor,
                          ),
                        ),
                        Text(
                          v.$3,
                          style: TextStyle(
                            fontSize: 11,
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text(
            'Load capacity',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: capacities.map((cap) {
              final selected = _vehicleCapacity == cap;
              return ChoiceChip(
                label: Text(cap),
                selected: selected,
                showCheckmark: false,
                selectedColor: accent.withValues(alpha: 0.35),
                backgroundColor:
                    isDark ? const Color(0xFF2A2A2A) : Colors.white,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: titleColor,
                ),
                side: BorderSide(
                  color: selected
                      ? accent
                      : (isDark ? Colors.white24 : const Color(0xFFE5E7EB)),
                ),
                onSelected: (_) => setState(() => _vehicleCapacity = cap),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          TextFormField(
            style: TextStyle(color: titleColor),
            decoration: _fieldDecoration(
              isDark: isDark,
              hint: 'Or type custom capacity',
              icon: Icons.scale_outlined,
            ),
            onChanged: (v) => setState(() => _vehicleCapacity = v.trim()),
          ),
          const SizedBox(height: 16),
          Text(
            'Service area',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            style: TextStyle(color: titleColor),
            textCapitalization: TextCapitalization.words,
            decoration: _fieldDecoration(
              isDark: isDark,
              hint: 'e.g. Lusaka and nearby areas',
              icon: Icons.map_outlined,
            ),
            onChanged: (v) => _serviceArea = v.trim(),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountTypeSelector({
    required bool isDark,
    required Color titleColor,
    required Color muted,
    required Color accent,
    required Color brown,
  }) {
    const options = [
      (
        'user',
        Icons.home_outlined,
        'Tenant',
        'Find and rent properties',
      ),
      (
        'dealer',
        Icons.apartment_outlined,
        'Landlord',
        'List and manage your rentals',
      ),
      (
        'agent',
        Icons.handshake_outlined,
        'Agent',
        'Become a HouseRent Africa agent and earn',
      ),
      (
        'company',
        Icons.business_outlined,
        'Private company',
        'List and manage rentals for your company',
      ),
      (
        'driver',
        Icons.local_shipping_outlined,
        'Moving Driver',
        'Help people move with your vehicle',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Account type',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            color: titleColor,
          ),
        ),
        const SizedBox(height: 10),
        ...options.map((option) {
          final selected = _role == option.$1;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _role = option.$1),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withValues(alpha: isDark ? 0.14 : 0.12)
                        : (isDark
                            ? const Color(0xFF242424)
                            : const Color(0xFFFAFAFA)),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? accent
                          : (isDark ? Colors.white12 : const Color(0xFFE5E7EB)),
                      width: selected ? 2 : 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.18),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: selected
                              ? accent.withValues(alpha: 0.28)
                              : brown.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          option.$2,
                          size: 22,
                          color: selected ? brown : muted,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.$3,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                                color: titleColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              option.$4,
                              style: TextStyle(
                                fontSize: 12,
                                color: muted,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? accent : Colors.transparent,
                          border: Border.all(
                            color: selected
                                ? accent
                                : (isDark
                                    ? Colors.white24
                                    : Colors.grey.shade400),
                            width: 2,
                          ),
                        ),
                        child: selected
                            ? Icon(Icons.check, size: 14, color: brown)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
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
                  colors: [Color(0xFF1A160F), Color(0xFF121212)],
                )
              : null,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
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
                          if (!_registered) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accent.withValues(
                                  alpha: isDark ? 0.16 : 0.28,
                                ),
                              ),
                              child: const AppLogo(size: 72),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Create account',
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
                              'Join HouseRent Africa — verify your email to get started',
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
                                          color: isDark
                                              ? const Color(0xFF3A1515)
                                              : const Color(0xFFFFEBEE),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: Colors.red.withValues(
                                              alpha: 0.35,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              Icons.error_outline_rounded,
                                              color: Colors.red.shade400,
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
                                      ),
                                      const SizedBox(height: 18),
                                    ],
                                    _buildAccountTypeSelector(
                                      isDark: isDark,
                                      titleColor: titleColor,
                                      muted: muted,
                                      accent: accent,
                                      brown: brown,
                                    ),
                                    if (_role == 'dealer') ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.green.shade200,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.card_giftcard,
                                              color: Colors.green.shade700,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                'Landlords get a free trial when you sign up.',
                                                style: TextStyle(
                                                  color: Colors.green.shade900,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (_role == 'agent') ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF8E7),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: const Color(0xFFE0B84A),
                                          ),
                                        ),
                                        child: const Text(
                                          'Become a HouseRent Africa agent and earn. Use the listing panel and chat privately with house-hunt requests.',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            height: 1.4,
                                            color: Color(0xFF5A3D31),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (_role == 'company') ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEEF4FF),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: const Color(0xFF90B4E8),
                                          ),
                                        ),
                                        child: const Text(
                                          'Private companies use the listing panel. After login you will complete your company details.',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            height: 1.4,
                                            color: Color(0xFF1A3A6B),
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 18),
                                    Text(
                                      'Full name',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                        color: titleColor,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      style: TextStyle(color: titleColor),
                                      textInputAction: TextInputAction.next,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      decoration: _fieldDecoration(
                                        isDark: isDark,
                                        hint: 'Your full name',
                                        icon: Icons.person_outline,
                                      ),
                                      validator: (value) =>
                                          value == null || value.trim().isEmpty
                                              ? 'Enter your name'
                                              : null,
                                      onSaved: (value) =>
                                          _name = value!.trim(),
                                    ),
                                    const SizedBox(height: 16),
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
                                      validator: (value) {
                                        final v = value?.trim() ?? '';
                                        if (v.isEmpty) return 'Enter your email';
                                        if (!v.contains('@')) {
                                          return 'Enter a valid email';
                                        }
                                        return null;
                                      },
                                      onSaved: (value) =>
                                          _email = value!.trim().toLowerCase(),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Phone',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                        color: titleColor,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      style: TextStyle(color: titleColor),
                                      keyboardType: TextInputType.phone,
                                      textInputAction: TextInputAction.next,
                                      decoration: _fieldDecoration(
                                        isDark: isDark,
                                        hint: '0971234567',
                                        icon: Icons.phone_outlined,
                                      ),
                                      validator: (value) =>
                                          value == null || value.trim().isEmpty
                                              ? 'Enter your phone number'
                                              : null,
                                      onSaved: (value) =>
                                          _phone = value!.trim(),
                                    ),
                                    if (_role == 'driver') ...[
                                      const SizedBox(height: 16),
                                      _buildVehicleDetailsSection(
                                        isDark: isDark,
                                        titleColor: titleColor,
                                        muted: muted,
                                        accent: accent,
                                        brown: brown,
                                      ),
                                    ],
                                    if (_role == 'dealer' ||
                                        _role == 'agent' ||
                                        _role == 'company') ...[
                                      const SizedBox(height: 16),
                                      Text(
                                        'Referral code (optional)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5,
                                          color: titleColor,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextFormField(
                                        style: TextStyle(color: titleColor),
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        decoration: _fieldDecoration(
                                          isDark: isDark,
                                          hint: 'Dealer referral code',
                                          icon: Icons.redeem_outlined,
                                        ),
                                        onSaved: (value) => _referralCode =
                                            value?.trim().toUpperCase() ?? '',
                                      ),
                                    ],
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
                                      textInputAction: TextInputAction.next,
                                      decoration: _fieldDecoration(
                                        isDark: isDark,
                                        hint: 'At least 8 characters',
                                        icon: Icons.lock_outline,
                                        suffix: IconButton(
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                          ),
                                          onPressed: () => setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          ),
                                        ),
                                      ),
                                      validator: (value) {
                                        final v = value ?? '';
                                        if (v.length < 8) {
                                          return 'Password must be at least 8 characters';
                                        }
                                        return null;
                                      },
                                      onSaved: (value) => _password = value!,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Confirm password',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.5,
                                        color: titleColor,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      style: TextStyle(color: titleColor),
                                      obscureText: _obscureConfirm,
                                      textInputAction: TextInputAction.done,
                                      onFieldSubmitted: (_) => _register(),
                                      decoration: _fieldDecoration(
                                        isDark: isDark,
                                        hint: 'Repeat password',
                                        icon: Icons.lock_outline,
                                        suffix: IconButton(
                                          icon: Icon(
                                            _obscureConfirm
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                          ),
                                          onPressed: () => setState(
                                            () => _obscureConfirm =
                                                !_obscureConfirm,
                                          ),
                                        ),
                                      ),
                                      validator: (value) =>
                                          value == null || value.isEmpty
                                              ? 'Confirm your password'
                                              : null,
                                      onSaved: (value) =>
                                          _confirmPassword = value!,
                                    ),
                                    const SizedBox(height: 14),
                                    CheckboxListTile(
                                      value: _acceptedTerms,
                                      onChanged: (v) => setState(
                                        () => _acceptedTerms = v ?? false,
                                      ),
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      title: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            'I agree to the ',
                                            style: TextStyle(
                                              color: muted,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => openLegalDocument(
                                              context,
                                              type: LegalDocumentType.terms,
                                            ),
                                            child: Text(
                                              'Terms',
                                              style: TextStyle(
                                                color: brown,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            ' and ',
                                            style: TextStyle(
                                              color: muted,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => openLegalDocument(
                                              context,
                                              type: LegalDocumentType.privacy,
                                            ),
                                            child: Text(
                                              'Privacy Policy',
                                              style: TextStyle(
                                                color: brown,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 52,
                                      child: FilledButton(
                                        onPressed:
                                            _isLoading ? null : _register,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: brown,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                        ),
                                        child: _isLoading
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2.4,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Text(
                                                'Create account',
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
                                        onPressed: () => context.go('/login'),
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
                                          'Already have an account? Sign in',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ] else
                            _verificationSuccessCard(
                              isDark: isDark,
                              titleColor: titleColor,
                              muted: muted,
                              accent: accent,
                              brown: brown,
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
