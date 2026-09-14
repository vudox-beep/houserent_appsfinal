import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../services/support_cases_service.dart';
import '../../utils/app_error.dart';
import '../../widgets/skeleton_loader.dart';

/// Tenant: rent payment disputes (admin chat) + maintenance reports.
class TenantRentSupportScreen extends StatefulWidget {
  const TenantRentSupportScreen({super.key});

  @override
  State<TenantRentSupportScreen> createState() => _TenantRentSupportScreenState();
}

class _TenantRentSupportScreenState extends State<TenantRentSupportScreen>
    with SingleTickerProviderStateMixin {
  static const _brown = Color(0xFF5A3D31);
  static const _gold = Color(0xFFFFC107);

  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _disputes = [];
  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _rentals = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rentals = await ApiService.fetchMyRentals();
      final disputes = await SupportCasesService.listDisputes();
      final tickets = await SupportCasesService.listMaintenance();
      if (!mounted) return;
      setState(() {
        _rentals = rentals
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _disputes = disputes;
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

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    BuildContext context, {
    required String label,
    String? hint,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F4F6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _gold, width: 1.5),
      ),
    );
  }

  Widget _statusChip(String status) {
    final normalized = status.toLowerCase();
    Color bg;
    Color fg;
    IconData icon;
    switch (normalized) {
      case 'resolved':
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        icon = Icons.check_circle_outline;
        break;
      case 'closed':
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade700;
        icon = Icons.lock_outline;
        break;
      case 'in_progress':
      case 'assigned':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
        icon = Icons.engineering_outlined;
        break;
      default:
        bg = _gold.withValues(alpha: 0.18);
        fg = const Color(0xFF8A6A00);
        icon = Icons.schedule_outlined;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            normalized.replaceAll('_', ' ').toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: fg,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBanner({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent, accent.withValues(alpha: 0.82)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.4,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _gold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: _brown),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: const Color(0xFF3E2A22),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listCard({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String subtitle,
    required String status,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.grey.shade100,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _brown, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isDark ? Colors.white : const Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _statusChip(status),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.white38 : Colors.black26,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDisputeChat(int caseId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TenantDisputeChatScreen(caseId: caseId),
      ),
    );
    _load();
  }

  Future<void> _createDispute() async {
    if (_rentals.isEmpty) {
      _toast('You need an active rental first.', error: true);
      return;
    }

    final rental = _rentals.first;
    final rentalId = int.tryParse('${rental['id']}');
    if (rentalId == null) return;

    String disputeType = 'tenant_claims_paid';
    final msgCtrl = TextEditingController();
    var submitting = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _gold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.gavel_outlined,
                                color: _brown,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Open payment dispute',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1F2937),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: submitting
                                  ? null
                                  : () => Navigator.pop(ctx, false),
                              icon: Icon(
                                Icons.close_rounded,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Admin will review your case and chat with you here.',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Property',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue:
                              rental['title']?.toString() ?? 'Active rental',
                          readOnly: true,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: _fieldDecoration(context, label: 'Rental'),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          value: disputeType,
                          decoration: _fieldDecoration(
                            context,
                            label: 'Issue type',
                          ),
                          dropdownColor:
                              isDark ? const Color(0xFF2C2C2C) : Colors.white,
                          items: const [
                            DropdownMenuItem(
                              value: 'tenant_claims_paid',
                              child: Text('I paid but it is not confirmed'),
                            ),
                            DropdownMenuItem(
                              value: 'payment_rejected',
                              child: Text('My payment was wrongly rejected'),
                            ),
                          ],
                          onChanged: submitting
                              ? null
                              : (v) => setDialogState(
                                    () => disputeType = v ?? disputeType,
                                  ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: msgCtrl,
                          maxLines: 4,
                          enabled: !submitting,
                          decoration: _fieldDecoration(
                            context,
                            label: 'Explain what happened',
                            hint: 'Month, amount, reference number…',
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: submitting
                                    ? null
                                    : () => Navigator.pop(ctx, false),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: submitting
                                    ? null
                                    : () async {
                                        if (msgCtrl.text.trim().isEmpty) {
                                          _toast(
                                            'Please describe the issue.',
                                            error: true,
                                          );
                                          return;
                                        }
                                        setDialogState(() => submitting = true);
                                        try {
                                          final id =
                                              await SupportCasesService.createDispute(
                                            rentalId: rentalId,
                                            disputeType: disputeType,
                                            message: msgCtrl.text.trim(),
                                          );
                                          if (ctx.mounted) {
                                            Navigator.pop(ctx, true);
                                            if (mounted) {
                                              await _openDisputeChat(id);
                                            }
                                          }
                                        } catch (e) {
                                          if (ctx.mounted) {
                                            setDialogState(
                                              () => submitting = false,
                                            );
                                            _toast(
                                              AppError.userMessage(e),
                                              error: true,
                                            );
                                          }
                                        }
                                      },
                                style: FilledButton.styleFrom(
                                  backgroundColor: _brown,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: submitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Submit dispute',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    msgCtrl.dispose();
    if (ok == true) _load();
  }

  Future<void> _createMaintenance() async {
    if (_rentals.isEmpty) {
      _toast('You need an active rental first.', error: true);
      return;
    }

    final rental = _rentals.first;
    final rentalId = int.tryParse('${rental['id']}');
    if (rentalId == null) return;

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = 'plumbing';
    String priority = 'normal';
    var submitting = false;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _brown.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.build_circle_outlined,
                              color: _brown,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Report maintenance',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        rental['title']?.toString() ?? 'Your rental',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: titleCtrl,
                        enabled: !submitting,
                        decoration: _fieldDecoration(
                          context,
                          label: 'Title',
                          hint: 'e.g. Leaking tap in kitchen',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: category,
                        decoration: _fieldDecoration(context, label: 'Category'),
                        items: const [
                          DropdownMenuItem(
                            value: 'plumbing',
                            child: Text('Plumbing'),
                          ),
                          DropdownMenuItem(
                            value: 'electrical',
                            child: Text('Electrical'),
                          ),
                          DropdownMenuItem(
                            value: 'structural',
                            child: Text('Structural'),
                          ),
                          DropdownMenuItem(
                            value: 'general',
                            child: Text('General'),
                          ),
                        ],
                        onChanged: submitting
                            ? null
                            : (v) => setSheetState(() => category = v ?? category),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Priority',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final item in const [
                            ('low', 'Low'),
                            ('normal', 'Normal'),
                            ('urgent', 'Urgent'),
                          ]) ...[
                            if (item.$1 != 'low') const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: Center(child: Text(item.$2)),
                                selected: priority == item.$1,
                                selectedColor: _gold.withValues(alpha: 0.35),
                                showCheckmark: false,
                                labelStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                                side: BorderSide(
                                  color: priority == item.$1
                                      ? _gold
                                      : Theme.of(context)
                                          .colorScheme
                                          .outlineVariant,
                                ),
                                onSelected: submitting
                                    ? null
                                    : (_) => setSheetState(
                                          () => priority = item.$1,
                                        ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        maxLines: 4,
                        enabled: !submitting,
                        decoration: _fieldDecoration(
                          context,
                          label: 'Details',
                          hint: 'Describe the problem…',
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: submitting
                            ? null
                            : () async {
                                if (titleCtrl.text.trim().isEmpty ||
                                    descCtrl.text.trim().isEmpty) {
                                  _toast(
                                    'Please fill in title and details.',
                                    error: true,
                                  );
                                  return;
                                }
                                setSheetState(() => submitting = true);
                                try {
                                  await SupportCasesService.createMaintenance(
                                    rentalId: rentalId,
                                    title: titleCtrl.text.trim(),
                                    description: descCtrl.text.trim(),
                                    category: category,
                                    priority: priority,
                                  );
                                  if (sheetCtx.mounted) {
                                    Navigator.pop(sheetCtx, true);
                                  }
                                } catch (e) {
                                  setSheetState(() => submitting = false);
                                  _toast(AppError.userMessage(e), error: true);
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: _brown,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Send to landlord',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    titleCtrl.dispose();
    descCtrl.dispose();

    if (ok == true) {
      _toast('Maintenance request sent to your landlord.');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDisputesTab = _tabs.index == 0;

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF121212)
          : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: _brown,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/tenant-dashboard');
            }
          },
        ),
        title: const Text(
          'Help & maintenance',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _gold,
          indicatorWeight: 3,
          labelColor: _gold,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Payment disputes'),
            Tab(text: 'Maintenance'),
          ],
        ),
      ),
      body: _loading
          ? _loadingBody()
          : _error != null
              ? _errorBody()
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _disputesTab(),
                    _maintenanceTab(),
                  ],
                ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: isDisputesTab ? _createDispute : _createMaintenance,
              backgroundColor: _gold,
              foregroundColor: const Color(0xFF3E2A22),
              elevation: 2,
              icon: Icon(isDisputesTab ? Icons.gavel_outlined : Icons.add),
              label: Text(
                isDisputesTab ? 'Open dispute' : 'Report issue',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
    );
  }

  Widget _loadingBody() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        SkeletonBox(height: 110, borderRadius: BorderRadius.all(Radius.circular(16))),
        SizedBox(height: 16),
        SkeletonBox(height: 96, borderRadius: BorderRadius.all(Radius.circular(16))),
        SizedBox(height: 12),
        SkeletonBox(height: 96, borderRadius: BorderRadius.all(Radius.circular(16))),
      ],
    );
  }

  Widget _errorBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
              style: FilledButton.styleFrom(
                backgroundColor: _brown,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _disputesTab() {
    if (_disputes.isEmpty) {
      return _emptyState(
        icon: Icons.support_agent_outlined,
        title: 'No payment disputes',
        subtitle:
            'Use this if you paid rent but it was not confirmed, or your payment was wrongly rejected.',
        actionLabel: 'Open dispute',
        onAction: _createDispute,
      );
    }

    return RefreshIndicator(
      color: _brown,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 88),
        children: [
          _infoBanner(
            icon: Icons.chat_bubble_outline,
            title: 'Payment disputes',
            subtitle:
                'Chat with admin to resolve payment issues. Keep your reference number handy.',
            accent: _brown,
          ),
          const SizedBox(height: 18),
          ..._disputes.map((d) {
            final status = (d['status'] ?? 'open').toString();
            return _listCard(
              icon: Icons.receipt_long_outlined,
              iconBg: _gold.withValues(alpha: 0.15),
              title: d['summary']?.toString() ?? 'Dispute',
              subtitle: d['property_title']?.toString() ?? 'Property',
              status: status,
              onTap: () => _openDisputeChat(int.parse('${d['id']}')),
            );
          }),
        ],
      ),
    );
  }

  Widget _maintenanceTab() {
    if (_tickets.isEmpty) {
      return _emptyState(
        icon: Icons.handyman_outlined,
        title: 'No maintenance requests',
        subtitle:
            'Report leaks, power issues, broken fixtures, and other repairs to your landlord.',
        actionLabel: 'Report issue',
        onAction: _createMaintenance,
      );
    }

    return RefreshIndicator(
      color: _brown,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 88),
        children: [
          _infoBanner(
            icon: Icons.build_outlined,
            title: 'Maintenance requests',
            subtitle:
                'Your landlord sees these in their app and can update the status.',
            accent: const Color(0xFF8A6554),
          ),
          const SizedBox(height: 18),
          ..._tickets.map((t) {
            final status = (t['status'] ?? 'open').toString();
            final category = (t['category'] ?? '').toString();
            return _listCard(
              icon: Icons.home_repair_service_outlined,
              iconBg: Colors.blue.shade50,
              title: t['title']?.toString() ?? 'Ticket',
              subtitle:
                  '${t['property_title'] ?? 'Property'}${category.isNotEmpty ? ' · $category' : ''}',
              status: status,
            );
          }),
        ],
      ),
    );
  }
}

class TenantDisputeChatScreen extends StatefulWidget {
  const TenantDisputeChatScreen({super.key, required this.caseId});

  final int caseId;

  @override
  State<TenantDisputeChatScreen> createState() => _TenantDisputeChatScreenState();
}

class _TenantDisputeChatScreenState extends State<TenantDisputeChatScreen> {
  static const _brown = Color(0xFF5A3D31);
  static const _gold = Color(0xFFFFC107);

  Map<String, dynamic>? _case;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await SupportCasesService.getDispute(widget.caseId);
      if (!mounted) return;
      setState(() {
        _case = data['case'] as Map<String, dynamic>;
        _messages = data['messages'] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppError.userMessage(e))),
      );
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    if ((_case?['status'] ?? '') != 'open') return;
    setState(() => _sending = true);
    try {
      await SupportCasesService.sendDisputeMessage(
        caseId: widget.caseId,
        message: text,
      );
      _ctrl.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppError.userMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _statusBadge(String status) {
    final open = status == 'open';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: open
            ? _gold.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: open ? _gold : Colors.white38,
        ),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: open ? _gold : Colors.white70,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _messageBubble(Map<String, dynamic> m) {
    final role = (m['sender_role'] ?? '').toString();
    final mine = role == 'tenant';
    final isAdmin = role == 'admin';

    Color bubbleColor;
    Color textColor;
    if (mine) {
      bubbleColor = _gold;
      textColor = const Color(0xFF3E2A22);
    } else if (isAdmin) {
      bubbleColor = _brown;
      textColor = Colors.white;
    } else {
      bubbleColor = Colors.white;
      textColor = const Color(0xFF1F2937);
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
          border: mine || isAdmin
              ? null
              : Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  isAdmin ? 'Admin' : (m['sender_name'] ?? 'Landlord').toString(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isAdmin
                        ? Colors.white.withValues(alpha: 0.85)
                        : Colors.grey.shade600,
                  ),
                ),
              ),
            Text(
              m['message']?.toString() ?? '',
              style: TextStyle(
                color: textColor,
                height: 1.35,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              m['created_at']?.toString() ?? '',
              style: TextStyle(
                fontSize: 10,
                color: textColor.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = (_case?['status'] ?? 'open').toString();
    final isOpen = status == 'open';
    final summary = _case?['summary']?.toString() ?? 'Dispute chat';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: _brown,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dispute #${widget.caseId}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              summary,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _statusBadge(status)),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _brown),
            )
          : Column(
              children: [
                if (_case != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.home_outlined, color: _brown, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _case!['property_title']?.toString() ?? 'Property',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Text(
                            'No messages yet.\nSend a message to start the chat.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _messageBubble(_messages[i]),
                        ),
                ),
                if (isOpen)
                  Container(
                    color: Colors.white,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      10,
                      12,
                      10 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: 'Message admin or landlord…',
                              filled: true,
                              fillColor: const Color(0xFFF3F4F6),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: _brown,
                          borderRadius: BorderRadius.circular(24),
                          child: InkWell(
                            onTap: _sending ? null : _send,
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              width: 46,
                              height: 46,
                              alignment: Alignment.center,
                              child: _sending
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.send_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    color: Colors.grey.shade200,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'This dispute is $status.',
                          style: TextStyle(
                            color: Colors.grey.shade700,
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
}
