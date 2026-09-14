import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../../services/api_service.dart';
import '../../utils/app_error.dart';
import '../../widgets/skeleton_loader.dart';

class DealerLeadsScreen extends StatefulWidget {
  const DealerLeadsScreen({super.key});

  @override
  State<DealerLeadsScreen> createState() => _DealerLeadsScreenState();
}

class _DealerLeadsScreenState extends State<DealerLeadsScreen> {
  static const String _blockedPhonesKey = 'dealer_blocked_phones_v1';
  static const String _blockedEmailsKey = 'dealer_blocked_emails_v1';

  List<dynamic> _leads = [];
  bool _isLoading = true;
  Set<String> _blockedPhones = {};
  Set<String> _blockedEmails = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadBlocked();
    await _loadLeads();
  }

  Future<void> _loadBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final phones = prefs.getStringList(_blockedPhonesKey) ?? const <String>[];
    final emails = prefs.getStringList(_blockedEmailsKey) ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _blockedPhones = phones
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      _blockedEmails = emails
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
    });
  }

  Future<void> _saveBlocked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _blockedPhonesKey,
      _blockedPhones.toList()..sort(),
    );
    await prefs.setStringList(
      _blockedEmailsKey,
      _blockedEmails.toList()..sort(),
    );
  }

  bool _isBlockedLead(dynamic lead) {
    final phone = (lead is Map ? lead['phone'] : null)?.toString().trim() ?? '';
    final email =
        (lead is Map ? lead['email'] : null)?.toString().trim().toLowerCase() ??
        '';
    if (phone.isNotEmpty && _blockedPhones.contains(phone)) return true;
    if (email.isNotEmpty && _blockedEmails.contains(email)) return true;
    return false;
  }

  Future<void> _loadLeads() async {
    try {
      final leads = await ApiService.fetchDealerLeads();
      final filtered = leads.where((l) => !_isBlockedLead(l)).toList();
      setState(() {
        // fetchDealerLeads returns a List directly from ApiService
        _leads = filtered;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppError.userMessage(e, fallback: 'Failed to load inquiries.'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmAndBlockLead(dynamic lead) async {
    final phone = (lead is Map ? lead['phone'] : null)?.toString().trim() ?? '';
    final email = (lead is Map ? lead['email'] : null)?.toString().trim() ?? '';
    final name =
        (lead is Map ? lead['name'] : null)?.toString().trim() ?? 'this user';

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block user'),
        content: Text(
          'Block $name?\n\nThey will be hidden from your inquiries and you will not see their messages here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    setState(() {
      if (phone.isNotEmpty) _blockedPhones.add(phone);
      if (email.isNotEmpty) _blockedEmails.add(email.toLowerCase());
      _leads.remove(lead);
    });
    await _saveBlocked();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('User blocked')));
  }

  Future<void> _showBlockedUsersDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final phones = _blockedPhones.toList()..sort();
        final emails = _blockedEmails.toList()..sort();
        return AlertDialog(
          title: const Text('Blocked users'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Phones (${phones.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (phones.isEmpty)
                  Text(
                    'None',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  ...phones.map(
                    (p) => Row(
                      children: [
                        Expanded(
                          child: Text(p, overflow: TextOverflow.ellipsis),
                        ),
                        IconButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            setState(() => _blockedPhones.remove(p));
                            await _saveBlocked();
                            if (!mounted) return;
                            await _loadLeads();
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Emails (${emails.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (emails.isEmpty)
                  Text(
                    'None',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  ...emails.map(
                    (e) => Row(
                      children: [
                        Expanded(
                          child: Text(e, overflow: TextOverflow.ellipsis),
                        ),
                        IconButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            setState(() => _blockedEmails.remove(e));
                            await _saveBlocked();
                            if (!mounted) return;
                            await _loadLeads();
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (_isLoading) {
      return const SkeletonDealerLeads();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Leads & Inquiries',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: _showBlockedUsersDialog,
              icon: const Icon(Icons.block, size: 18),
              label: Text(
                'Blocked (${_blockedPhones.length + _blockedEmails.length})',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Manage messages from interested clients.',
          style: textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 32),

        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_leads.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'No inquiries yet.',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth > 1200
                                  ? constraints.maxWidth
                                  : 1200,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.surfaceContainerHighest,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(12),
                                    ),
                                    border: Border(
                                      bottom: BorderSide(
                                        color: colors.outlineVariant,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 300,
                                        child: Text(
                                          'CLIENT DETAILS',
                                          style: textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 250,
                                        child: Text(
                                          'PROPERTY INTEREST',
                                          style: textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 300,
                                        child: Text(
                                          'MESSAGE',
                                          style: textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 120,
                                        child: Text(
                                          'DATE',
                                          style: textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 100,
                                        child: Text(
                                          'STATUS',
                                          style: textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 120,
                                        child: Text(
                                          'ACTIONS',
                                          style: textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: SizedBox(
                                    width: constraints.maxWidth > 1200
                                        ? constraints.maxWidth
                                        : 1200,
                                    child: ListView.separated(
                                      itemCount: _leads.length,
                                      separatorBuilder: (context, index) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final lead = _leads[index];
                                        final name = lead['name'] ?? 'Unknown';
                                        final initial = name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?';
                                        final message =
                                            (lead['message'] ??
                                                    'No message provided')
                                                .replaceAll('&#039;', "'");
                                        final dateStr =
                                            lead['created_at'] ?? '';
                                        final parts = dateStr.split(' ');
                                        final date = parts.isNotEmpty
                                            ? parts[0]
                                            : '';
                                        final time = parts.length > 1
                                            ? parts[1]
                                            : '';

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 20,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              SizedBox(
                                                width: 300,
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    CircleAvatar(
                                                      radius: 24,
                                                      backgroundColor:
                                                          Colors.blue.shade100,
                                                      child: Text(
                                                        initial,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.orange,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 16),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            name,
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 16,
                                                                ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                          const SizedBox(
                                                            height: 4,
                                                          ),
                                                          Row(
                                                            children: [
                                                              Icon(
                                                                Icons.phone,
                                                                size: 14,
                                                                color: colors
                                                                    .onSurfaceVariant,
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  lead['phone'] ??
                                                                      'N/A',
                                                                  style: TextStyle(
                                                                    color: colors
                                                                        .onSurfaceVariant,
                                                                  ),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                            height: 2,
                                                          ),
                                                          Row(
                                                            children: [
                                                              Icon(
                                                                Icons.email,
                                                                size: 14,
                                                                color: colors
                                                                    .onSurfaceVariant,
                                                              ),
                                                              const SizedBox(
                                                                width: 4,
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  lead['email'] ??
                                                                      'N/A',
                                                                  style: TextStyle(
                                                                    color: colors
                                                                        .onSurfaceVariant,
                                                                  ),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              SizedBox(
                                                width: 200,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        const Icon(
                                                          Icons.open_in_new,
                                                          size: 14,
                                                          color: Color(
                                                            0xFFFFC107,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            lead['property_title'] ??
                                                                'Property',
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  color: Color(
                                                                    0xFFFFC107,
                                                                  ),
                                                                ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Ref: #${lead['property_id']?.toString().padLeft(6, '0') ?? '000000'}',
                                                      style: TextStyle(
                                                        color: colors
                                                            .onSurfaceVariant,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              SizedBox(
                                                width: 300,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 16.0,
                                                      ),
                                                  child: Text(
                                                    message,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 120,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      date,
                                                      style: TextStyle(
                                                        color: colors
                                                            .onSurfaceVariant,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                    Text(
                                                      time,
                                                      style: TextStyle(
                                                        color: colors
                                                            .onSurfaceVariant,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              SizedBox(
                                                width: 100,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.green
                                                          .withValues(
                                                            alpha: 0.16,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            20,
                                                          ),
                                                      border: Border.all(
                                                        color: Colors
                                                            .green
                                                            .shade200,
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      'New',
                                                      style: TextStyle(
                                                        color: Colors.green,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width:
                                                    120, // Keep fixed width instead of Expanded
                                                child: Wrap(
                                                  spacing: 4,
                                                  runSpacing: 4,
                                                  children: [
                                                    _buildActionButton(
                                                      Icons.block,
                                                      Colors.red.shade600,
                                                      () async {
                                                        await _confirmAndBlockLead(
                                                          lead,
                                                        );
                                                      },
                                                    ),
                                                    _buildActionButton(
                                                      Icons.chat_bubble_outline,
                                                      Colors.green,
                                                      () async {
                                                        final phone =
                                                            lead['phone'] ?? '';
                                                        if (phone.isNotEmpty) {
                                                          String digitsOnly =
                                                              phone.replaceAll(
                                                                RegExp(
                                                                  r'[^\d]',
                                                                ),
                                                                '',
                                                              );
                                                          if (digitsOnly
                                                              .startsWith(
                                                                '0',
                                                              )) {
                                                            digitsOnly =
                                                                '260${digitsOnly.substring(1)}';
                                                          } else if (!digitsOnly
                                                              .startsWith(
                                                                '260',
                                                              )) {
                                                            digitsOnly =
                                                                '260$digitsOnly';
                                                          }

                                                          final cleanPhone =
                                                              '+$digitsOnly';
                                                          final webPhone =
                                                              digitsOnly;
                                                          final chatUrls = <Uri>[
                                                            Uri.parse(
                                                              'whatsapp://send?phone=$cleanPhone',
                                                            ),
                                                            Uri.parse(
                                                              'https://api.whatsapp.com/send?phone=$webPhone',
                                                            ),
                                                            Uri.parse(
                                                              'https://wa.me/$webPhone',
                                                            ),
                                                          ];

                                                          for (final chatUrl
                                                              in chatUrls) {
                                                            try {
                                                              final launched =
                                                                  await url_launcher.launchUrl(
                                                                    chatUrl,
                                                                    mode: url_launcher
                                                                        .LaunchMode
                                                                        .externalApplication,
                                                                  );
                                                              if (launched) {
                                                                return;
                                                              }
                                                            } catch (_) {
                                                              // Keep trying the next URL format.
                                                            }
                                                          }

                                                          try {
                                                            final launched = await url_launcher.launchUrl(
                                                              Uri.parse(
                                                                'whatsapp://send?text=Hello',
                                                              ),
                                                              mode: url_launcher
                                                                  .LaunchMode
                                                                  .externalApplication,
                                                            );
                                                            if (launched) {
                                                              return;
                                                            }
                                                          } catch (_) {}

                                                          try {
                                                            await url_launcher.launchUrl(
                                                              Uri.parse(
                                                                'https://wa.me/',
                                                              ),
                                                              mode: url_launcher
                                                                  .LaunchMode
                                                                  .externalApplication,
                                                            );
                                                          } catch (_) {}
                                                        }
                                                      },
                                                    ),
                                                    _buildActionButton(
                                                      Icons.phone_outlined,
                                                      Colors.grey.shade600,
                                                      () async {
                                                        final phone =
                                                            lead['phone'] ?? '';
                                                        if (phone.isNotEmpty) {
                                                          final url = Uri.parse(
                                                            'tel:$phone',
                                                          );
                                                          try {
                                                            await url_launcher
                                                                .launchUrl(url);
                                                          } catch (_) {}
                                                        }
                                                      },
                                                    ),
                                                    _buildActionButton(
                                                      Icons.email_outlined,
                                                      Colors.blue,
                                                      () async {
                                                        final email =
                                                            lead['email'] ?? '';
                                                        if (email.isNotEmpty) {
                                                          final url = Uri.parse(
                                                            'mailto:$email?subject=Regarding your property inquiry on HouseRent Africa',
                                                          );
                                                          try {
                                                            await url_launcher.launchUrl(
                                                              url,
                                                              mode: url_launcher
                                                                  .LaunchMode
                                                                  .externalApplication,
                                                            );
                                                          } catch (_) {}
                                                        }
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 18),
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(),
      ),
    );
  }
}
