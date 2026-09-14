import 'package:flutter/material.dart';

import '../utils/legal_navigation.dart';
import '../widgets/app_logo.dart';

enum LegalDocumentType { privacy, terms }

/// In-app Privacy / Terms — same content as houseforrent.site, app colors + dark mode.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.type});

  final LegalDocumentType type;

  static const _brown = Color(0xFF5A3D31);
  static const _gold = Color(0xFFFFC107);

  bool get _isPrivacy => type == LegalDocumentType.privacy;

  String get _title => _isPrivacy ? 'Privacy Policy' : 'Terms of Service';

  String get _updatedLabel {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final now = DateTime.now();
    final day = now.day.toString().padLeft(2, '0');
    return 'Last Updated: ${months[now.month - 1]} $day, ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121212) : Colors.white;
    final card = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A140F);
    final muted = isDark ? Colors.white70 : const Color(0xFF6B5E52);
    final border = isDark ? Colors.white12 : const Color(0xFFE8E4DF);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: _brown,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          TextButton(
            onPressed: () {
              openLegalDocument(
                context,
                type: _isPrivacy
                    ? LegalDocumentType.terms
                    : LegalDocumentType.privacy,
              );
            },
            child: Text(
              _isPrivacy ? 'Terms' : 'Privacy',
              style: const TextStyle(
                color: _gold,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        children: [
          Row(
            children: [
              const AppLogo(size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'HouseRent Africa',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: isDark ? _gold : _brown,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            _title,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _updatedLabel,
            style: TextStyle(
              color: muted,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 18),
          if (_isPrivacy) ..._privacySections(card, titleColor, muted, border, isDark),
          if (!_isPrivacy) ..._termsSections(card, titleColor, muted, border, isDark),
          const SizedBox(height: 12),
          Text(
            '© ${DateTime.now().year} HouseRent Africa. All rights reserved.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Same policy as houseforrent.site',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: muted.withValues(alpha: 0.85),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _privacySections(
    Color card,
    Color titleColor,
    Color muted,
    Color border,
    bool isDark,
  ) {
    return [
      _banner(
        icon: Icons.shield_outlined,
        color: _gold,
        textColor: _brown,
        bg: isDark ? _gold.withValues(alpha: 0.14) : const Color(0xFFFFF4D0),
        child: Text.rich(
          TextSpan(
            style: TextStyle(
              color: titleColor,
              height: 1.4,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
            children: const [
              TextSpan(
                text: 'Data Privacy Commitment: ',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              TextSpan(
                text:
                    'We process your verification data strictly for account authentication and fraud prevention. Your data is never sold, shared, or used for any other purpose.',
              ),
            ],
          ),
        ),
      ),
      _section(
        card: card,
        border: border,
        titleColor: titleColor,
        muted: muted,
        title: '1. Information Collection and Usage',
        body: [
          'We collect information you provide directly to us, such as when you create an account, update your profile, post a listing, or communicate with other users. This includes your name, email address, phone number, and payment information.',
          'Identity Verification Data: For dealers and property managers, we may require identification documents or photographs (e.g., a photo at the property). This data is collected to maintain the security and integrity of our platform.',
        ],
      ),
      _section(
        card: card,
        border: border,
        titleColor: titleColor,
        muted: muted,
        title: '2. Purpose of Data Processing',
        body: const [
          'We process the information we collect to:',
        ],
        bullets: const [
          'Provide, maintain, and improve our services.',
          'Process transactions and send related notifications.',
          'Verify your identity and prevent fraud. Verification Data is used only for identity validation and fraud prevention.',
          'Send technical notices, updates, security alerts, and administrative messages.',
        ],
      ),
      _section(
        card: card,
        border: border,
        titleColor: titleColor,
        muted: muted,
        title: '3. Confidentiality of Verification Data',
        body: const [
          'We acknowledge the sensitivity of Identity Verification Data and follow these protocols:',
        ],
        bullets: const [
          'Sole Purpose Limitation: Verification Data is used only to verify identity and property ownership claims — not for marketing or profiling.',
          'Access Control: Access is restricted to authorized admin staff who need it for verification.',
          'Non-Disclosure: We do not sell, lease, trade, or disclose Verification Data except when required by law.',
          'Data Security: We use industry-standard measures to protect Verification Data.',
          'Retention: Data is kept only as long as needed for verification and legal obligations, then deleted on request or account termination per our schedule.',
        ],
      ),
      _section(
        card: card,
        border: border,
        titleColor: titleColor,
        muted: muted,
        title: '4. Fake Listings & Fraud Prevention',
        accentTitle: true,
        body: const [
          'We have a zero-tolerance policy for fake listings. Anyone posting false information, misleading photos, or non-existent properties will be banned immediately.',
          'Consequences include: account suspension or permanent ban; reporting to local authorities; forfeiture of subscription fees.',
        ],
      ),
      _section(
        card: card,
        border: border,
        titleColor: titleColor,
        muted: muted,
        title: '5. Data Security',
        body: const [
          'We implement reasonable security measures to help protect your personal information. However, no method of transmission over the Internet is 100% secure, and we cannot guarantee absolute security.',
        ],
      ),
      _section(
        card: card,
        border: border,
        titleColor: titleColor,
        muted: muted,
        title: '6. Changes to This Policy',
        body: const [
          'We may change this Privacy Policy from time to time. If we make changes, we will update the date at the top and, in some cases, provide additional notice.',
        ],
      ),
      _banner(
        icon: Icons.info_outline_rounded,
        color: _brown,
        textColor: isDark ? Colors.white : _brown,
        bg: isDark ? _brown.withValues(alpha: 0.35) : const Color(0xFFF3EDE8),
        child: Text(
          'By using our services, you agree to the collection and use of information in accordance with this policy.',
          style: TextStyle(
            color: titleColor,
            height: 1.4,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ),
    ];
  }

  List<Widget> _termsSections(
    Color card,
    Color titleColor,
    Color muted,
    Color border,
    bool isDark,
  ) {
    return [
      _section(
        card: card,
        border: border,
        titleColor: titleColor,
        muted: muted,
        title: '1. Acceptance of Terms',
        body: const [
          'By accessing or using HouseRent Africa, you agree to be bound by these Terms of Service. If you do not agree to all of these terms, you may not access or use our services.',
        ],
      ),
      _section(
        card: card,
        border: border,
        titleColor: titleColor,
        muted: muted,
        title: '2. User Accounts',
        body: const [
          'When you create an account with us, you must provide information that is accurate, complete, and current at all times. Failure to do so constitutes a breach of the Terms.',
        ],
      ),
      _section(
        card: card,
        border: border,
        titleColor: titleColor,
        muted: muted,
        title: '3. Platform Nature & Services',
        highlight: true,
        body: const [
          'HouseRent Africa is a property listing and management platform. We do not own the properties listed. We do provide property management services to assist dealers and landlords.',
          'While we are not a traditional real estate agency for sales, we facilitate rental management, tenant communications, and payment processing for registered dealers.',
        ],
      ),
      _banner(
        icon: Icons.warning_amber_rounded,
        color: Colors.red.shade700,
        textColor: Colors.red.shade800,
        bg: isDark ? const Color(0xFF3A1515) : const Color(0xFFFFEBEE),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '4. CRITICAL: Tenant Safety & Payment',
              style: TextStyle(
                color: isDark ? Colors.red.shade200 : Colors.red.shade800,
                fontWeight: FontWeight.w900,
                fontSize: 14.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'DO NOT PAY IN ADVANCE until you have visited the property and verified the landlord/agent.\n\n'
              'VERIFY FIRST: Inspect the property and confirm the person has keys and authority to rent.\n\n'
              'PLATFORM LIABILITY: HouseRent Africa is a listing platform. We are not liable for losses if you transfer money without due diligence.',
              style: TextStyle(
                color: titleColor,
                height: 1.45,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      _section(
        card: card,
        border: border,
        titleColor: titleColor,
        muted: muted,
        title: '5. Anti-Fraud & Fake Listings',
        body: const [
          'All listings must accurately represent the property. Photos must be current and truthful.',
          'Fake listings, scams, or misrepresentation may result in permanent ban, reporting to law enforcement, blacklisting, and legal action.',
        ],
      ),
      _section(
        card: card,
        border: border,
        titleColor: titleColor,
        muted: muted,
        title: '6. Fees and Payments',
        body: const [
          'Dealers must pay subscription fees to list properties. Fees are non-refundable unless stated in writing by HouseRent Africa.',
        ],
      ),
      _section(
        card: card,
        border: border,
        titleColor: titleColor,
        muted: muted,
        title: '7. Limitation of Liability',
        body: const [
          'HouseRent Africa and its partners shall not be liable for indirect, incidental, special, consequential, or punitive damages, including loss of profits, data, or goodwill.',
        ],
      ),
      _section(
        card: card,
        border: border,
        titleColor: titleColor,
        muted: muted,
        title: '8. Changes to Terms',
        body: const [
          'We may modify these Terms at any time. Continued use after changes means you accept the revised terms.',
        ],
      ),
      _banner(
        icon: Icons.gavel_outlined,
        color: _brown,
        textColor: _brown,
        bg: isDark ? _gold.withValues(alpha: 0.12) : const Color(0xFFFFF4D0),
        child: Text(
          'Violation of these terms will result in immediate termination of your access to the Service.',
          style: TextStyle(
            color: titleColor,
            height: 1.4,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
      ),
    ];
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required Color textColor,
    required Color bg,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor, size: 22),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _section({
    required Color card,
    required Color border,
    required Color titleColor,
    required Color muted,
    required String title,
    required List<String> body,
    List<String> bullets = const [],
    bool accentTitle = false,
    bool highlight = false,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight ? _gold.withValues(alpha: 0.55) : border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15.5,
              color: accentTitle ? Colors.red.shade700 : titleColor,
            ),
          ),
          const SizedBox(height: 10),
          ...body.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                p,
                style: TextStyle(
                  color: muted,
                  height: 1.45,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Icon(Icons.circle, size: 6, color: _gold),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      b,
                      style: TextStyle(
                        color: muted,
                        height: 1.45,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
