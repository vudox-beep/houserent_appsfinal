import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/moving_marketplace_service.dart';
import '../../utils/app_error.dart';

/// Dedicated chat page for a moving booking (driver ↔ client).
class MovingChatScreen extends StatefulWidget {
  const MovingChatScreen({
    super.key,
    required this.bookingId,
    required this.isDriver,
    this.peerName,
    this.driverId,
  });

  final int bookingId;
  final bool isDriver;
  final String? peerName;
  final int? driverId;

  @override
  State<MovingChatScreen> createState() => _MovingChatScreenState();
}

class _MovingChatScreenState extends State<MovingChatScreen> {
  static const _bg = Color(0xFF111111);
  static const _sheet = Color(0xFF1A1A1A);
  static const _accent = Color(0xFFFFC107);
  static const _bubbleMine = Color(0xFFFFC107);
  static const _bubbleTheirs = Color(0xFF2A2A2A);

  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  List<Map<String, dynamic>> _messages = [];
  int? _driverId;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _poll;

  String get _title {
    final name = (widget.peerName ?? '').trim();
    if (name.isNotEmpty) return name;
    return widget.isDriver ? 'Client' : 'Driver';
  }

  @override
  void initState() {
    super.initState();
    _driverId = widget.driverId;
    _load(initial: true);
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    if (_sending) return;
    try {
      var driverId = _driverId;
      if (!widget.isDriver && driverId == null) {
        final booking =
            await MovingMarketplaceService.getBooking(widget.bookingId);
        if (booking['driver'] is Map) {
          driverId = int.tryParse(booking['driver']['id']?.toString() ?? '');
        }
      }

      final messages = await MovingMarketplaceService.listMessages(
        bookingId: widget.bookingId,
        driverId: widget.isDriver ? null : driverId,
      );

      if (!mounted) return;
      final grew = messages.length > _messages.length;
      setState(() {
        _messages = messages;
        _driverId = driverId;
        _loading = false;
        _error = null;
      });
      if (grew || initial) _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      if (initial) {
        setState(() {
          _loading = false;
          _error = AppError.userMessage(e);
        });
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  bool _isMine(Map<String, dynamic> m) {
    final role = (m['sender_role'] ?? '').toString();
    return widget.isDriver ? role == 'driver' : role == 'user' || role == 'tenant';
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final optimistic = <String, dynamic>{
      'id': 'local_${DateTime.now().millisecondsSinceEpoch}',
      'message': text,
      'sender_role': widget.isDriver ? 'driver' : 'user',
      'created_at': DateTime.now().toIso8601String(),
    };
    setState(() {
      _messages = [..._messages, optimistic];
      _ctrl.clear();
    });
    _scrollToEnd();
    HapticFeedback.selectionClick();

    try {
      await MovingMarketplaceService.sendMessage(
        bookingId: widget.bookingId,
        message: text,
        driverId: widget.isDriver ? null : _driverId,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .where((m) => m['id']?.toString() != optimistic['id'])
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppError.userMessage(e)),
          backgroundColor: const Color(0xFF2A2A2A),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _sheet,
        elevation: 0,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF2A2A2A),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_rounded, color: _accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                  Text(
                    widget.isDriver
                        ? 'HouseRent Africa ride'
                        : 'HouseRent Africa ride chat',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: _accent),
                  )
                : _error != null && _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextButton(
                                onPressed: () {
                                  setState(() => _loading = true);
                                  _load(initial: true);
                                },
                                child: const Text(
                                  'Retry',
                                  style: TextStyle(
                                    color: _accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              child: Text(
                                widget.isDriver
                                    ? 'Message your HouseRent Africa client'
                                    : 'Message your HouseRent Africa driver',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final m = _messages[i];
                              final mine = _isMine(m);
                              final text = (m['message'] ?? '').toString();
                              return Align(
                                alignment: mine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width * 0.78,
                                  ),
                                  decoration: BoxDecoration(
                                    color: mine ? _bubbleMine : _bubbleTheirs,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: Radius.circular(mine ? 16 : 4),
                                      bottomRight:
                                          Radius.circular(mine ? 4 : 16),
                                    ),
                                  ),
                                  child: Text(
                                    text,
                                    style: TextStyle(
                                      color: mine ? Colors.black : Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: const BoxDecoration(
                  color: _sheet,
                  border: Border(
                    top: BorderSide(color: Colors.white10),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        cursorColor: _accent,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: 'Type a message…',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontWeight: FontWeight.w600,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF2A2A2A),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: _accent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sending ? null : _send,
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: _sending
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.black,
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  color: Colors.black,
                                  size: 22,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
