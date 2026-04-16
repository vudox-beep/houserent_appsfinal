import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../../services/api_service.dart';
import '../../utils/app_error.dart';

class DealerLeadsScreen extends StatefulWidget {
  const DealerLeadsScreen({super.key});

  @override
  State<DealerLeadsScreen> createState() => _DealerLeadsScreenState();
}

class _DealerLeadsScreenState extends State<DealerLeadsScreen> {
  List<dynamic> _leads = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLeads();
  }

  Future<void> _loadLeads() async {
    try {
      final leads = await ApiService.fetchDealerLeads();
      setState(() {
        // fetchDealerLeads returns a List directly from ApiService
        _leads = leads;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppError.userMessage(e, fallback: 'Failed to load inquiries.'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Leads & Inquiries', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF0F2041))),
        const SizedBox(height: 8),
        const Text('Manage messages from interested clients.', style: TextStyle(fontSize: 16, color: Colors.black54)),
        const SizedBox(height: 32),
        
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
          color: Colors.black.withOpacity(0.02),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_leads.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('No inquiries yet.', style: TextStyle(color: Colors.black54)),
                    ),
                  )
                else
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: constraints.maxWidth > 1200 ? constraints.maxWidth : 1200),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                                    ),
                                    child: Row(
                                      children: const [
                                        SizedBox(width: 300, child: Text('CLIENT DETAILS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
                                        SizedBox(width: 250, child: Text('PROPERTY INTEREST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
                                        SizedBox(width: 300, child: Text('MESSAGE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
                                        SizedBox(width: 120, child: Text('DATE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
                                        SizedBox(width: 100, child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
                                        SizedBox(width: 120, child: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87))),
                                      ],
                                    ),
                                  ),
                                Expanded(
                                    child: SizedBox(
                                      width: constraints.maxWidth > 1200 ? constraints.maxWidth : 1200,
                                      child: ListView.separated(
                                        itemCount: _leads.length,
                                        separatorBuilder: (context, index) => const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                  final lead = _leads[index];
                                  final name = lead['name'] ?? 'Unknown';
                                  final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                                  final message = (lead['message'] ?? 'No message provided').replaceAll('&#039;', "'");
                                  final dateStr = lead['created_at'] ?? '';
                                  final parts = dateStr.split(' ');
                                  final date = parts.isNotEmpty ? parts[0] : '';
                                  final time = parts.length > 1 ? parts[1] : '';

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 300,
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              CircleAvatar(
                                                radius: 24,
                                                backgroundColor: Colors.blue.shade100,
                                                child: Text(initial, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F2937)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.phone, size: 14, color: Colors.black54),
                                                        const SizedBox(width: 4),
                                                        Expanded(child: Text(lead['phone'] ?? 'N/A', style: const TextStyle(color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.email, size: 14, color: Colors.black54),
                                                        const SizedBox(width: 4),
                                                        Expanded(child: Text(lead['email'] ?? 'N/A', style: const TextStyle(color: Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis)),
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
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(Icons.open_in_new, size: 14, color: Color(0xFFFFC107)),
                                                  const SizedBox(width: 4),
                                                  Expanded(child: Text(lead['property_title'] ?? 'Property', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFC107)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text('Ref: #${lead['property_id']?.toString().padLeft(6, '0') ?? '000000'}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                        SizedBox(
                                          width: 300,
                                          child: Padding(
                                            padding: const EdgeInsets.only(right: 16.0),
                                            child: Text(message, style: const TextStyle(color: Colors.black87), maxLines: 2, overflow: TextOverflow.ellipsis),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 120,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(date, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                                              Text(time, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                        SizedBox(
                                          width: 100,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade50,
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(color: Colors.green.shade200),
                                              ),
                                              child: const Text('New', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 120, // Keep fixed width instead of Expanded
                                          child: Wrap(
                                            spacing: 4,
                                            runSpacing: 4,
                                            children: [
                                              _buildActionButton(Icons.chat_bubble_outline, Colors.green, () async {
                                                final phone = lead['phone'] ?? '';
                                                if (phone.isNotEmpty) {
                                                  String digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
                                                  if (digitsOnly.startsWith('0')) {
                                                    digitsOnly = '260${digitsOnly.substring(1)}';
                                                  } else if (!digitsOnly.startsWith('260')) {
                                                    digitsOnly = '260$digitsOnly';
                                                  }

                                                  final cleanPhone = '+$digitsOnly';
                                                  final webPhone = digitsOnly;
                                                  final chatUrls = <Uri>[
                                                    Uri.parse('whatsapp://send?phone=$cleanPhone'),
                                                    Uri.parse('https://api.whatsapp.com/send?phone=$webPhone'),
                                                    Uri.parse('https://wa.me/$webPhone'),
                                                  ];

                                                  for (final chatUrl in chatUrls) {
                                                    try {
                                                      final launched = await url_launcher.launchUrl(
                                                        chatUrl,
                                                        mode: url_launcher.LaunchMode.externalApplication,
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
                                                      Uri.parse('whatsapp://send?text=Hello'),
                                                      mode: url_launcher.LaunchMode.externalApplication,
                                                    );
                                                    if (launched) {
                                                      return;
                                                    }
                                                  } catch (e) {
                                                    debugPrint('Could not launch WhatsApp fallback: $e');
                                                  }

                                                  try {
                                                    await url_launcher.launchUrl(
                                                      Uri.parse('https://wa.me/'),
                                                      mode: url_launcher.LaunchMode.externalApplication,
                                                    );
                                                  } catch (e) {
                                                    debugPrint('Could not launch WhatsApp: $e');
                                                  }
                                                }
                                              }),
                                              _buildActionButton(Icons.phone_outlined, Colors.grey.shade600, () async {
                                                final phone = lead['phone'] ?? '';
                                                if (phone.isNotEmpty) {
                                                  final url = Uri.parse('tel:$phone');
                                                  try {
                                                    await url_launcher.launchUrl(url);
                                                  } catch (e) {
                                                    debugPrint('Could not launch Dialer: $e');
                                                  }
                                                }
                                              }),
                                              _buildActionButton(Icons.email_outlined, Colors.blue, () async {
                                                final email = lead['email'] ?? '';
                                                if (email.isNotEmpty) {
                                                  final url = Uri.parse('mailto:$email?subject=Regarding your property inquiry on HouseRent Africa');
                                                  try {
                                                    await url_launcher.launchUrl(
                                                      url,
                                                      mode: url_launcher.LaunchMode.externalApplication,
                                                    );
                                                  } catch (e) {
                                                    debugPrint('Could not launch Email: $e');
                                                  }
                                                }
                                              }),
                                            ],
                                          ),
                                        ),
                                      ],
                                      ),
                                    );
                                  },
                                ),
                              )),
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

  Widget _buildActionButton(IconData icon, Color color, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
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
