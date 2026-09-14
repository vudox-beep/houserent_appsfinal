import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../widgets/skeleton_loader.dart';

class DealerPaymentHistoryScreen extends StatefulWidget {
  const DealerPaymentHistoryScreen({super.key});

  @override
  State<DealerPaymentHistoryScreen> createState() =>
      _DealerPaymentHistoryScreenState();
}

class _DealerPaymentHistoryScreenState
    extends State<DealerPaymentHistoryScreen> {
  List<Map<String, dynamic>> _payments = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchPayments();
  }

  Future<void> _fetchPayments() async {
    try {
      // Fetch dealer-specific payment history from their own endpoint
      final response = await ApiService.fetchPaymentHistory();
      if (mounted) {
        setState(() {
          if (response is List) {
            _payments = response
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          } else if (response is Map) {
            final mapResponse = response as Map<String, dynamic>;
            if (mapResponse['transactions'] is List) {
              _payments = (mapResponse['transactions'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            } else if (mapResponse['data'] is List) {
              _payments = (mapResponse['data'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            } else if (mapResponse['payments'] is List) {
              _payments = (mapResponse['payments'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            } else {
              _payments = [];
            }
          } else {
            _payments = [];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load payment history.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final pagePadding = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 24.0;
    return Padding(
      padding: EdgeInsets.all(pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [
              Text(
                'Payment History',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Make Payment'),
                      content: const Text(
                        'To make a payment, please login to the HouseRent Africa website using your credentials.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'OK',
                            style: TextStyle(color: Color(0xFFFFC107)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.payment, size: 18),
                label: const Text(
                  'Make Payment',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC107),
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ],
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
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth > 1000
                                  ? constraints.maxWidth
                                  : 1000,
                            ),
                            child: SizedBox(
                              height: constraints.maxHeight,
                              width: constraints.maxWidth > 1000
                                  ? constraints.maxWidth
                                  : 1000,
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
                                          width: 200,
                                          child: Text(
                                            'REFERENCE',
                                            style: textTheme.labelLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 120,
                                          child: Text(
                                            'AMOUNT',
                                            style: textTheme.labelLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 120,
                                          child: Text(
                                            'METHOD',
                                            style: textTheme.labelLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 120,
                                          child: Text(
                                            'STATUS',
                                            style: textTheme.labelLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 180,
                                          child: Text(
                                            'DATE',
                                            style: textTheme.labelLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            'DESCRIPTION',
                                            style: textTheme.labelLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: _isLoading
                                        ? const SkeletonDealerPayments()
                                        : _error != null
                                        ? Center(
                                            child: Text(
                                              _error!,
                                              style: const TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          )
                                        : _payments.isEmpty
                                        ? Center(
                                            child: Text(
                                              'No payment history found',
                                              style: TextStyle(
                                                color: colors.onSurfaceVariant,
                                              ),
                                            ),
                                          )
                                        : ListView.separated(
                                            itemCount: _payments.length,
                                            separatorBuilder:
                                                (context, index) =>
                                                    const Divider(height: 1),
                                            itemBuilder: (context, index) {
                                              final payment = _payments[index];
                                              final status =
                                                  payment['status']
                                                      ?.toString() ??
                                                  'Pending';
                                              final isSuccess =
                                                  status.toLowerCase() ==
                                                      'successful' ||
                                                  status.toLowerCase() ==
                                                      'completed' ||
                                                  status.toLowerCase() ==
                                                      'success' ||
                                                  status.toLowerCase() ==
                                                      'approved';

                                              return Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 24,
                                                      vertical: 16,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    SizedBox(
                                                      width: 200,
                                                      child: Text(
                                                        payment['reference']
                                                                ?.toString() ??
                                                            'N/A',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Color(
                                                            0xFFFFC107,
                                                          ),
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 120,
                                                      child: Text(
                                                        '${payment['currency'] ?? 'ZMW'} ${payment['amount']?.toString() ?? '0.00'}',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 15,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 120,
                                                      child: Text(
                                                        payment['payment_method']
                                                                ?.toString() ??
                                                            'Subscription',
                                                        style: TextStyle(
                                                          color: colors
                                                              .onSurfaceVariant,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 120,
                                                      child: Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 4,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                (isSuccess
                                                                        ? Colors
                                                                              .green
                                                                        : Colors
                                                                              .orange)
                                                                    .withValues(
                                                                      alpha:
                                                                          0.16,
                                                                    ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  20,
                                                                ),
                                                            border: Border.all(
                                                              color: isSuccess
                                                                  ? Colors
                                                                        .green
                                                                        .shade200
                                                                  : Colors
                                                                        .orange
                                                                        .shade200,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            status,
                                                            style: TextStyle(
                                                              color: isSuccess
                                                                  ? Colors.green
                                                                  : Colors
                                                                        .orange
                                                                        .shade700,
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 180,
                                                      child: Text(
                                                        payment['created_at']
                                                                ?.toString() ??
                                                            payment['date']
                                                                ?.toString() ??
                                                            'N/A',
                                                        style: TextStyle(
                                                          color: colors
                                                              .onSurfaceVariant,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: Text(
                                                        payment['tenant_name'] !=
                                                                null
                                                            ? 'Rent Payment - ${payment['tenant_name']}'
                                                            : (payment['description']
                                                                      ?.toString() ??
                                                                  'Dealer Subscription'),
                                                        style: TextStyle(
                                                          color: colors
                                                              .onSurfaceVariant,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
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
      ),
    );
  }
}
