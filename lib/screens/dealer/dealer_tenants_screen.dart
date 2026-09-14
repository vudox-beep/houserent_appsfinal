import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../utils/app_error.dart';
import '../rental_leases_screen.dart';
import '../../widgets/skeleton_loader.dart';

class DealerTenantsScreen extends StatefulWidget {
  const DealerTenantsScreen({super.key});

  @override
  State<DealerTenantsScreen> createState() => _DealerTenantsScreenState();
}

class _DealerTenantsScreenState extends State<DealerTenantsScreen> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _tenants = [];
  List<Map<String, dynamic>> _properties = [];
  Map<String, dynamic> _paymentCounts = {};
  final Set<String> _reviewingPaymentIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final paymentData = await ApiService.fetchDealerTenantRentPayments();
      if (!mounted) return;
      setState(() {
        _payments = (paymentData['payments'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _tenants = (paymentData['tenants'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _properties = (paymentData['properties'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _paymentCounts = paymentData['counts'] is Map
            ? Map<String, dynamic>.from(paymentData['counts'] as Map)
            : <String, dynamic>{};
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AppError.userMessage(
          e,
          fallback: 'Unable to load tenant payments right now.',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddTenantDialog() async {
    if (_properties.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No available rental property was found. Mark a rental property as available first.',
          ),
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final emailController = TextEditingController();
    final rentController = TextEditingController();
    final startController = TextEditingController(
      text: DateTime.now().toIso8601String().split('T').first,
    );
    final endController = TextEditingController();
    final roomController = TextEditingController();
    String selectedPropertyId = _properties.first['id'].toString();
    rentController.text = (_properties.first['price'] ?? '').toString();
    bool submitting = false;

    Future<void> pickDate(
      BuildContext dialogContext,
      TextEditingController controller,
    ) async {
      final initialDate = DateTime.tryParse(controller.text) ?? DateTime.now();
      final selected = await showDatePicker(
        context: dialogContext,
        initialDate: initialDate,
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (selected != null) {
        controller.text = selected.toIso8601String().split('T').first;
      }
    }

    final tenantAdded = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add tenant by email'),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Registered tenant email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        return email.contains('@')
                            ? null
                            : 'Enter a valid email';
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedPropertyId,
                      decoration: const InputDecoration(
                        labelText: 'Property',
                        prefixIcon: Icon(Icons.home_outlined),
                      ),
                      items: _properties
                          .map(
                            (property) => DropdownMenuItem<String>(
                              value: property['id'].toString(),
                              child: Text(
                                (property['title'] ?? 'Property').toString(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: submitting
                          ? null
                          : (value) {
                              if (value == null) return;
                              final property = _properties.firstWhere(
                                (item) => item['id'].toString() == value,
                              );
                              setDialogState(() {
                                selectedPropertyId = value;
                                rentController.text = (property['price'] ?? '')
                                    .toString();
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: rentController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Monthly rent',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                      validator: (value) {
                        final amount = double.tryParse(value?.trim() ?? '');
                        return amount != null && amount > 0
                            ? null
                            : 'Enter a valid rent amount';
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: startController,
                      readOnly: true,
                      onTap: () => pickDate(dialogContext, startController),
                      decoration: const InputDecoration(
                        labelText: 'Start date',
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: endController,
                      readOnly: true,
                      onTap: () => pickDate(dialogContext, endController),
                      decoration: const InputDecoration(
                        labelText: 'End date (optional)',
                        prefixIcon: Icon(Icons.event_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: roomController,
                      decoration: const InputDecoration(
                        labelText: 'Room number (optional)',
                        prefixIcon: Icon(Icons.meeting_room_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setDialogState(() => submitting = true);
                      try {
                        await ApiService.addDealerTenantByEmail(
                          email: emailController.text,
                          propertyId: selectedPropertyId,
                          rentAmount: rentController.text,
                          startDate: startController.text,
                          endDate: endController.text,
                          roomNumber: roomController.text,
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext, true);
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() => submitting = false);
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppError.userMessage(
                                error,
                                fallback: 'Unable to add tenant.',
                              ),
                            ),
                          ),
                        );
                      }
                    },
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add tenant'),
            ),
          ],
        ),
      ),
    );

    // Refresh only after the dialog route is fully dismissed. Rebuilding this
    // screen while the dialog is closing can leave its form in an invalid state.
    if (tenantAdded == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tenant added successfully.'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadData();
    }
  }

  Widget _buildPaymentSummary() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pending = _paymentCounts['pending'] ?? 0;
    final approved = _paymentCounts['approved'] ?? 0;
    final rejected = _paymentCounts['rejected'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Tenant rent payments',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            FilledButton.icon(
              onPressed: _showAddTenantDialog,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add tenant'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: const Icon(Icons.schedule, size: 18),
              label: Text('$pending pending'),
              backgroundColor: isDark
                  ? Colors.orange.withValues(alpha: 0.18)
                  : Colors.orange.shade50,
            ),
            Chip(
              avatar: const Icon(Icons.check_circle_outline, size: 18),
              label: Text('$approved approved'),
              backgroundColor: isDark
                  ? Colors.green.withValues(alpha: 0.18)
                  : Colors.green.shade50,
            ),
            Chip(
              avatar: const Icon(Icons.cancel_outlined, size: 18),
              label: Text('$rejected rejected'),
              backgroundColor: isDark
                  ? Colors.red.withValues(alpha: 0.18)
                  : Colors.red.shade50,
            ),
          ],
        ),
        if (_payments.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('No tenant rent payments have been submitted yet.'),
          ),
      ],
    );
  }

  Widget _buildTenantCard(Map<String, dynamic> tenant) {
    final dueStatus = (tenant['due_status'] ?? 'upcoming').toString();
    final dueColor = dueStatus == 'overdue' ? Colors.red : Colors.blue;
    final latestStatus = (tenant['latest_payment_status'] ?? 'not_paid')
        .toString()
        .replaceAll('_', ' ');
    final latestMethod = (tenant['latest_payment_method'] ?? '')
        .toString()
        .replaceAll('_', ' ');
    final property = (tenant['property_title'] ?? 'Property').toString();
    final room = (tenant['room_number'] ?? '').toString().trim();
    final paymentId = (tenant['payment_reference'] ?? '').toString().trim();
    final monthsCovered = (tenant['months_covered'] ?? '0').toString();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person_outline)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (tenant['tenant_name'] ?? 'Tenant').toString(),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text((tenant['tenant_email'] ?? '').toString()),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: dueColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    dueStatus.toUpperCase(),
                    style: TextStyle(
                      color: dueColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(room.isEmpty ? property : '$property • Room $room'),
            const SizedBox(height: 6),
            Text(
              'Rent: ${tenant['currency'] ?? 'ZMW'} ${tenant['rent_amount'] ?? '0'}',
            ),
            Text('Months covered: $monthsCovered'),
            if ((tenant['paid_through_date'] ?? '').toString().isNotEmpty)
              Text('Paid through: ${tenant['paid_through_date']}'),
            Text('Next due: ${tenant['next_due_date'] ?? 'Not available'}'),
            Text(
              latestMethod.isEmpty
                  ? 'Latest payment: $latestStatus'
                  : 'Latest payment: $latestStatus • $latestMethod',
            ),
            if (paymentId.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildPaymentId(paymentId),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  final rentalId = (tenant['rental_id'] ?? tenant['id'] ?? '')
                      .toString();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RentalLeasesScreen(
                        isDealer: true,
                        preselectRentalId: rentalId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.file_present_outlined, size: 18),
                label: const Text('Create lease'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reviewPayment(
    Map<String, dynamic> payment,
    String reviewStatus,
  ) async {
    final paymentId = (payment['payment_id'] ?? '').toString();
    if (paymentId.isEmpty || _reviewingPaymentIds.contains(paymentId)) return;

    final approved = reviewStatus == 'approved';
    final reverting = reviewStatus == 'pending';
    setState(() => _reviewingPaymentIds.add(paymentId));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            reverting
                ? 'Revert payment?'
                : approved
                ? 'Approve payment?'
                : 'Reject payment?',
          ),
          content: Text(
            reverting
                ? 'This payment will return to pending and will no longer count toward the due date.'
                : approved
                ? 'This payment will count toward the tenant’s rent and update the due date.'
                : 'This payment will be marked as rejected and will not change the due date.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: reverting
                    ? Colors.orange
                    : approved
                    ? Colors.green
                    : Colors.red,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                reverting
                    ? 'Revert'
                    : approved
                    ? 'Approve'
                    : 'Reject',
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      await ApiService.reviewDealerTenantRentPayment(
        paymentId: paymentId,
        status: reviewStatus,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reverting
                ? 'Payment reverted to pending.'
                : approved
                ? 'Payment approved.'
                : 'Payment rejected.',
          ),
          backgroundColor: reverting
              ? Colors.orange
              : approved
              ? Colors.green
              : Colors.red,
        ),
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppError.userMessage(
              error,
              fallback: 'Unable to review this payment.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _reviewingPaymentIds.remove(paymentId));
      }
    }
  }

  Widget _buildPaymentCard(Map<String, dynamic> payment) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = (payment['payment_status'] ?? 'pending')
        .toString()
        .toLowerCase();
    final statusColor = switch (status) {
      'approved' => Colors.green,
      'rejected' => Colors.red,
      _ => Colors.orange,
    };
    final proofUrl = (payment['proof_url'] ?? '').toString();
    final property = (payment['property_title'] ?? 'Property').toString();
    final room = (payment['room_number'] ?? '').toString().trim();
    final currency = (payment['currency'] ?? 'ZMW').toString();
    final amount = (payment['amount'] ?? '0').toString();
    final method = (payment['payment_method'] ?? 'Not specified')
        .toString()
        .replaceAll('_', ' ');
    final paymentId = (payment['payment_reference'] ?? '').toString().trim();
    final paymentRecordId = (payment['payment_id'] ?? '').toString();
    final coveredMonths = (payment['covered_months'] ?? '1').toString();
    final reviewing = _reviewingPaymentIds.contains(paymentRecordId);

    return Card(
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(child: Icon(Icons.person_outline)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (payment['tenant_name'] ?? 'Tenant').toString(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(room.isEmpty ? property : '$property • Room $room'),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor.shade700,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _paymentDetail(Icons.payments_outlined, '$currency $amount'),
                _paymentDetail(
                  Icons.calendar_month_outlined,
                  (payment['month_year'] ?? '').toString(),
                ),
                _paymentDetail(Icons.account_balance_wallet_outlined, method),
                _paymentDetail(
                  Icons.date_range_outlined,
                  '$coveredMonths month${coveredMonths == '1' ? '' : 's'}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Next due: ${payment['next_due_date'] ?? 'Not available'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  (payment['submitted_at'] ?? '').toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (paymentId.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildPaymentId(paymentId),
            ],
            if (proofUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(proofUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('View proof of payment'),
              ),
            ],
            if (status == 'pending') ...[
              const Divider(height: 24),
              if (reviewing)
                const Center(child: CircularProgressIndicator())
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _reviewPayment(payment, 'rejected'),
                        icon: const Icon(Icons.close),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _reviewPayment(payment, 'approved'),
                        icon: const Icon(Icons.check),
                        label: const Text('Approve'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
            ] else ...[
              const Divider(height: 24),
              if (reviewing)
                const Center(child: CircularProgressIndicator())
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => _reviewPayment(payment, 'pending'),
                    icon: const Icon(Icons.undo),
                    label: const Text('Revert to pending'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paymentDetail(IconData icon, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildPaymentId(String paymentId) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_outlined, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bank payment ID',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                SelectableText(
                  paymentId,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy payment ID',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: paymentId));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Bank payment ID copied.')),
              );
            },
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SkeletonDealerTenants();
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            onPressed: () => context.push('/dealer-maintenance'),
            icon: const Icon(Icons.build_circle_outlined),
            label: const Text('Maintenance tickets'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RentalLeasesScreen(isDealer: true),
                ),
              );
            },
            icon: const Icon(Icons.file_present_outlined),
            label: const Text('Digital leases'),
          ),
          const SizedBox(height: 16),
          _buildPaymentSummary(),
          const SizedBox(height: 20),
          Text(
            'Tenants and due dates',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (_tenants.isEmpty)
            const Text('No tenants have been added yet.')
          else
            ..._tenants.expand(
              (tenant) => [
                _buildTenantCard(tenant),
                const SizedBox(height: 12),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            'Payment activity',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (_payments.isEmpty)
            const Text('No rent payments have been submitted yet.')
          else
            ..._payments.expand(
              (payment) => [
                _buildPaymentCard(payment),
                const SizedBox(height: 12),
              ],
            ),
        ],
      ),
    );
  }
}
