import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../utils/app_error.dart';

/// Agent private chats with house-hunt request owners.
class AgentRequestChatListScreen extends StatefulWidget {
  const AgentRequestChatListScreen({super.key});

  @override
  State<AgentRequestChatListScreen> createState() =>
      _AgentRequestChatListScreenState();
}

class _AgentRequestChatListScreenState
    extends State<AgentRequestChatListScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _requests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.agentRequestChat(action: 'list_requests');
      if (!mounted) return;
      if (res['status'] == 'success') {
        setState(() {
          _requests = (res['data'] as List?) ?? [];
          _loading = false;
        });
      } else {
        setState(() {
          _error = res['message']?.toString() ?? 'Could not load requests.';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.userMessage(e, fallback: 'Could not load requests.');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const brown = Color(0xFF5A3D31);
    const gold = Color(0xFFFFC107);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      color: brown,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5A3D31), Color(0xFF8A6554)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'House-hunt chat',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Message seekers privately about their requests.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_requests.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE8E4DF)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.forum_outlined, size: 40, color: brown),
                  SizedBox(height: 10),
                  Text(
                    'No house-hunt requests yet',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            )
          else
            ..._requests.map((raw) {
              final r = Map<String, dynamic>.from(raw as Map);
              final unread = int.tryParse('${r['unread'] ?? 0}') ?? 0;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  title: Text(
                    (r['title'] ?? r['message'] ?? 'Request #${r['id']}')
                        .toString(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    () {
                      final seeker = r['seeker_name'] ?? 'Seeker';
                      final loc = r['location'] ?? 'Zambia';
                      final type = '${r['property_type'] ?? ''}'.trim();
                      if (type.isNotEmpty && type.toLowerCase() != 'any') {
                        return '$seeker · $loc · $type';
                      }
                      return '$seeker · $loc';
                    }(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: unread > 0
                      ? CircleAvatar(
                          radius: 12,
                          backgroundColor: gold,
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Colors.black87,
                            ),
                          ),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AgentRequestChatScreen(
                          requestId: int.parse('${r['id']}'),
                          title: r['title']?.toString() ?? 'Chat',
                          peerName: r['seeker_name']?.toString() ?? 'Seeker',
                        ),
                      ),
                    );
                    _load();
                  },
                ),
              );
            }),
        ],
      ),
    );
  }
}

class AgentRequestChatScreen extends StatefulWidget {
  const AgentRequestChatScreen({
    super.key,
    required this.requestId,
    required this.title,
    required this.peerName,
  });

  final int requestId;
  final String title;
  final String peerName;

  @override
  State<AgentRequestChatScreen> createState() => _AgentRequestChatScreenState();
}

class _AgentRequestChatScreenState extends State<AgentRequestChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  List<dynamic> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService.agentRequestChat(
        action: 'get_messages',
        extra: {'request_id': widget.requestId},
      );
      if (!mounted || res['status'] != 'success') return;
      setState(() {
        _messages = (res['data'] as List?) ?? [];
        _loading = false;
      });
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await ApiService.agentRequestChat(
        action: 'send_message',
        extra: {'request_id': widget.requestId, 'message': text},
      );
      if (res['status'] == 'success') {
        _ctrl.clear();
        await _load();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFC107);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 16)),
            Text(
              widget.peerName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = Map<String, dynamic>.from(_messages[i] as Map);
                      final mine =
                          m['sender_name']?.toString() != widget.peerName;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: mine ? gold : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            m['message']?.toString() ?? '',
                            style: TextStyle(
                              color: mine ? Colors.black87 : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      decoration: InputDecoration(
                        hintText: 'Type a private message…',
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    style: IconButton.styleFrom(backgroundColor: gold),
                    icon: const Icon(Icons.send, color: Colors.black87),
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
