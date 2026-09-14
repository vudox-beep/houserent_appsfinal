import 'package:flutter/material.dart';

import '../../services/support_cases_service.dart';
import '../../utils/app_error.dart';
import '../../widgets/skeleton_loader.dart';

/// Dealer: view and update tenant maintenance tickets.
class DealerMaintenanceScreen extends StatefulWidget {
  const DealerMaintenanceScreen({super.key});

  @override
  State<DealerMaintenanceScreen> createState() => _DealerMaintenanceScreenState();
}

class _DealerMaintenanceScreenState extends State<DealerMaintenanceScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tickets = [];

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
      final tickets = await SupportCasesService.listMaintenance();
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.userMessage(e);
        _loading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'in_progress':
        return Colors.orange;
      case 'resolved':
      case 'closed':
        return Colors.green;
      default:
        return Colors.red;
    }
  }

  Future<void> _updateTicket(Map<String, dynamic> ticket) async {
    final id = int.tryParse('${ticket['id']}');
    if (id == null) return;

    String status = (ticket['status'] ?? 'open').toString();
    final noteCtrl = TextEditingController(text: ticket['dealer_note']?.toString() ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ticket['title']?.toString() ?? 'Ticket'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(ticket['description']?.toString() ?? ''),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('Open')),
                  DropdownMenuItem(value: 'in_progress', child: Text('In progress')),
                  DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                  DropdownMenuItem(value: 'closed', child: Text('Closed')),
                ],
                onChanged: (v) => status = v ?? status,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Note to tenant',
                  hintText: 'Plumber booked for Monday…',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await SupportCasesService.updateMaintenance(
        ticketId: id,
        status: status,
        dealerNote: noteCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ticket updated.')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SkeletonDealerMaintenance();
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_tickets.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No maintenance requests yet.\nTenants can report leaks and other issues from the app.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _tickets.length,
        itemBuilder: (_, i) {
          final t = _tickets[i];
          final status = (t['status'] ?? 'open').toString();
          return Card(
            child: ListTile(
              title: Text(t['title']?.toString() ?? 'Ticket'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${t['tenant_name'] ?? 'Tenant'} · ${t['property_title'] ?? ''}'),
                  if ((t['dealer_note'] ?? '').toString().isNotEmpty)
                    Text('Note: ${t['dealer_note']}'),
                ],
              ),
              isThreeLine: true,
              trailing: Chip(
                label: Text(status.replaceAll('_', ' ')),
                backgroundColor: _statusColor(status).withValues(alpha: 0.15),
                labelStyle: TextStyle(color: _statusColor(status)),
              ),
              onTap: () => _updateTicket(t),
            ),
          );
        },
      ),
    );
  }
}
