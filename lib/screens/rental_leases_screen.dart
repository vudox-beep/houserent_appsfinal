import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../utils/app_error.dart';

/// Dealer or tenant: list + create + sign digital leases.
class RentalLeasesScreen extends StatefulWidget {
  const RentalLeasesScreen({
    super.key,
    this.isDealer = false,
    this.preselectRentalId,
  });

  final bool isDealer;
  final String? preselectRentalId;

  @override
  State<RentalLeasesScreen> createState() => _RentalLeasesScreenState();
}

class _RentalLeasesScreenState extends State<RentalLeasesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _leases = [];
  Map<String, dynamic>? _selected;

  final List<_StrokePoint?> _points = [];
  final _nameCtrl = TextEditingController();
  bool _signing = false;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.isDealer &&
        widget.preselectRentalId != null &&
        widget.preselectRentalId!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _promptCreate(rentalId: widget.preselectRentalId);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ApiService.fetchRentalLeases();
      if (!mounted) return;
      setState(() {
        _leases = list;
        _loading = false;
        if (_selected != null) {
          final id = _selected!['id']?.toString();
          _selected = list.cast<Map<String, dynamic>?>().firstWhere(
                (e) => e?['id']?.toString() == id,
                orElse: () => _selected,
              );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppError.userMessage(e, fallback: 'Could not load leases.');
      });
    }
  }

  Future<void> _openLease(Map<String, dynamic> lease) async {
    try {
      final full = await ApiService.fetchRentalLease(lease['id'].toString());
      if (!mounted) return;
      setState(() {
        _selected = full;
        _points.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    }
  }

  Future<void> _promptCreate({String? rentalId}) async {
    final rentalCtrl = TextEditingController(text: rentalId ?? '');
    final depositCtrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create digital lease'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: rentalCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Rental ID',
                helperText: 'From the tenant card / add-tenant response',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: depositCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Deposit (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create & send')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final res = await ApiService.createRentalLease(
        rentalId: rentalCtrl.text.trim(),
        depositAmount: double.tryParse(depositCtrl.text.trim()) ?? 0,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Lease created')),
      );
      await _load();
      final data = res['data'];
      if (data is Map<String, dynamic>) {
        setState(() => _selected = data);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    }
  }

  Future<void> _sign() async {
    final lease = _selected;
    if (lease == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your full name')),
      );
      return;
    }
    if (_points.whereType<_StrokePoint>().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draw your signature')),
      );
      return;
    }

    setState(() => _signing = true);
    try {
      // Encode a simple SVG-like path as a data URI alternative: store stroke JSON.
      // Website uses PNG canvas; for Flutter we store a compact stroke payload
      // prefixed so both platforms can still store a string signature.
      final strokes = _points
          .map((p) => p == null ? '|' : '${p.x.toStringAsFixed(1)},${p.y.toStringAsFixed(1)}')
          .join(';');
      final signatureData = 'stroke:v1:$strokes';

      final updated = await ApiService.signRentalLease(
        leaseId: lease['id'].toString(),
        signedName: name,
        signatureData: signatureData,
      );
      if (!mounted) return;
      setState(() {
        _selected = updated;
        _points.clear();
        _signing = false;
      });
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signature saved')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _signing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    }
  }

  bool get _canSign {
    final lease = _selected;
    if (lease == null) return false;
    final status = (lease['status'] ?? '').toString();
    if (status == 'cancelled' || status == 'signed') return false;
    if (widget.isDealer) {
      return (lease['dealer_signed_at'] ?? '').toString().isEmpty;
    }
    return (lease['tenant_signed_at'] ?? '').toString().isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    const brown = Color(0xFF5A3D31);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isDealer ? 'Digital leases' : 'My leases'),
        actions: [
          if (widget.isDealer)
            IconButton(
              tooltip: 'Create lease',
              onPressed: () => _promptCreate(),
              icon: const Icon(Icons.add),
            ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _selected != null
                  ? _buildDetail(brown)
                  : _buildList(),
    );
  }

  Widget _buildList() {
    if (_leases.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            widget.isDealer
                ? 'No leases yet. Create one after adding a tenant.'
                : 'No leases yet. Your landlord will send one here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _leases.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final l = _leases[i];
          final title = (l['property_title'] ?? 'Property').toString();
          final status = (l['status'] ?? '').toString();
          final other = widget.isDealer
              ? (l['tenant_name'] ?? '').toString()
              : (l['dealer_name'] ?? '').toString();
          return ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('$other\n$status'),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openLease(l),
          );
        },
      ),
    );
  }

  Widget _buildDetail(Color brown) {
    final lease = _selected!;
    final terms = (lease['terms_body'] ?? '').toString();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _selected = null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('All leases'),
          ),
        ),
        Text(
          (lease['property_title'] ?? 'Lease').toString(),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text('Status: ${lease['status']}'),
        Text(
          'Rent: ${lease['currency'] ?? 'ZMW'} ${lease['rent_amount'] ?? '0'}',
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(terms, style: const TextStyle(height: 1.4, fontSize: 13)),
        ),
        const SizedBox(height: 16),
        _sigStatus(
          'Landlord',
          lease['dealer_signed_name']?.toString(),
          lease['dealer_signed_at']?.toString(),
        ),
        const SizedBox(height: 8),
        _sigStatus(
          'Tenant',
          lease['tenant_signed_name']?.toString(),
          lease['tenant_signed_at']?.toString(),
        ),
        if (_canSign) ...[
          const SizedBox(height: 18),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Full name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Draw signature', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            height: 140,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            child: GestureDetector(
              onPanStart: (d) => setState(() => _points.add(_StrokePoint(d.localPosition.dx, d.localPosition.dy))),
              onPanUpdate: (d) => setState(() => _points.add(_StrokePoint(d.localPosition.dx, d.localPosition.dy))),
              onPanEnd: (_) => setState(() => _points.add(null)),
              child: CustomPaint(
                painter: _SignaturePainter(_points),
                size: Size.infinite,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _points.clear()),
                child: const Text('Clear'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _signing ? null : _sign,
                style: FilledButton.styleFrom(backgroundColor: brown),
                child: _signing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(widget.isDealer ? 'Sign as landlord' : 'Sign lease'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _sigStatus(String label, String? name, String? at) {
    final signed = (at ?? '').isNotEmpty;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        signed ? Icons.check_circle : Icons.hourglass_empty,
        color: signed ? Colors.green : Colors.orange,
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(signed ? '${name ?? ''} · $at' : 'Waiting'),
    );
  }
}

class _StrokePoint {
  _StrokePoint(this.x, this.y);
  final double x;
  final double y;
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.points);
  final List<_StrokePoint?> points;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a == null || b == null) continue;
      canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
