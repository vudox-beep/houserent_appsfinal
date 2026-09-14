import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../dealer/dealer_payment_webview_screen.dart';

class RentSavingsScreen extends StatefulWidget {
  const RentSavingsScreen({super.key});

  @override
  State<RentSavingsScreen> createState() => _RentSavingsScreenState();
}

class _RentSavingsScreenState extends State<RentSavingsScreen> {
  static const _brown = Color(0xFF5A3D31);
  static const _gold = Color(0xFFFFC107);
  // Withdrawals require the emailed 6-digit code.
  static const bool _requireWithdrawOtp = true;
  // TESTING: set false to block Add Money in the app again.
  static const bool _depositsEnabled = true;

  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _startingDeposit = false;
  bool _workingOpen = false;
  Map<String, dynamic>? _lastWithdraw;
  String? _error;

  double _number(dynamic value) =>
      double.tryParse(value?.toString() ?? '') ?? 0;

  String _money(dynamic value) => 'K${_number(value).toStringAsFixed(2)}';

  String _message(Object error) =>
      error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await ApiService.fetchRentSavings();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && !quiet) setState(() => _error = _message(error));
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  void _disposeLater(TextEditingController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });
  }

  void _closeWorkingDialog() {
    if (!mounted || !_workingOpen) return;
    _workingOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _showWorking(String text) {
    if (_workingOpen) return;
    _workingOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          content: Row(
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      _workingOpen = false;
    });
  }

  InputDecoration _sheetFieldDecoration({
    required String label,
    String? hint,
    String? prefixText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  Future<Map<String, dynamic>?> _moneyDetails({required String title}) async {
    final amount = TextEditingController();
    final phone = TextEditingController();
    var operator = 'mtn';
    final fee = _number(_data?['withdrawal_fee'] ?? 28.5);
    final available = _number(_data?['available_balance']);

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final typed = double.tryParse(amount.text.trim()) ?? 0;
          final totalOut = typed > 0 ? typed + fee : 0.0;
          final canContinue = typed > 0 && phone.text.trim().length >= 9;

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Available ${_money(available)} · Fee ${_money(fee)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amount,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setSheetState(() {}),
                    decoration: _sheetFieldDecoration(
                      label: 'Amount to receive',
                      prefixText: 'K ',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    onChanged: (_) => setSheetState(() {}),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: _sheetFieldDecoration(
                      label: 'Mobile number',
                      hint: '0971234567',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final item in const [
                        ('mtn', 'MTN'),
                        ('airtel', 'Airtel'),
                        ('zamtel', 'Zamtel'),
                      ]) ...[
                        if (item.$1 != 'mtn') const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: Center(child: Text(item.$2)),
                            selected: operator == item.$1,
                            selectedColor: _gold.withValues(alpha: .35),
                            showCheckmark: false,
                            labelStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                            side: BorderSide(
                              color: operator == item.$1
                                  ? _gold
                                  : Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                            ),
                            onSelected: (_) =>
                                setSheetState(() => operator = item.$1),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (typed > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _brown.withValues(alpha: .07),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Receive ${_money(typed)} · Deduct ${_money(totalOut)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: !canContinue
                          ? null
                          : () {
                              Navigator.pop(sheetContext, {
                                'amount': typed,
                                'phone': phone.text.trim(),
                                'operator': operator,
                              });
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: _brown,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _brown.withValues(alpha: .3),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _requireWithdrawOtp ? 'Send code' : 'Withdraw',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    _disposeLater(amount);
    _disposeLater(phone);
    return result;
  }

  Future<void> _editGoal() async {
    final account = Map<String, dynamic>.from(_data?['account'] as Map? ?? {});
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RentGoalDialog(
        initialAmount: _number(account['rent_goal']),
        initialTarget: DateTime.tryParse(
          account['target_date']?.toString() ?? '',
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      final data = await ApiService.setRentSavingsGoal(
        amount: result['amount'] as double,
        targetDate: result['date'] as DateTime?,
      );
      if (!mounted) return;
      setState(() => _data = data);
      _toast('Your rent goal has been updated.');
    } catch (error) {
      _toast(_message(error), error: true);
    }
  }

  Future<void> _deposit() async {
    if (_startingDeposit) return;
    if (!_depositsEnabled) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.construction_outlined, color: Colors.orange, size: 40),
          title: const Text('Temporarily unavailable'),
          content: const Text(
            'Adding money to Rent Savings is under development. Please try again later.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final amountController = TextEditingController();
    final lockDaysController = TextEditingController(text: '30');
    double? selectedAmount;
    var selectedLockDays = 30;
    final depositDetails = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              4,
              22,
              22 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add to Rent Savings',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose an amount. You will complete payment securely on the next page.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [20.0, 50.0, 100.0, 500.0].map((value) {
                    return ChoiceChip(
                      label: Text('K${value.toStringAsFixed(0)}'),
                      selected: selectedAmount == value,
                      selectedColor: _gold.withValues(alpha: .35),
                      labelStyle: TextStyle(
                        color: selectedAmount == value
                            ? Theme.of(context).colorScheme.onSurface
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                      side: BorderSide(
                        color: selectedAmount == value
                            ? _gold
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                      onSelected: (_) {
                        setSheetState(() => selectedAmount = value);
                        amountController.text = value.toStringAsFixed(0);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setSheetState(() => selectedAmount = null),
                  decoration: InputDecoration(
                    labelText: 'Or enter another amount',
                    prefixText: 'K ',
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Lock withdrawals for',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  'This deposit cannot be withdrawn until the selected number of days has passed.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [7, 14, 30, 60, 90].map((days) {
                    return ChoiceChip(
                      label: Text('$days days'),
                      selected: selectedLockDays == days,
                      selectedColor: _gold.withValues(alpha: .35),
                      labelStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                      side: BorderSide(
                        color: selectedLockDays == days
                            ? _gold
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                      onSelected: (_) {
                        setSheetState(() => selectedLockDays = days);
                        lockDaysController.text = '$days';
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lockDaysController,
                  keyboardType: TextInputType.number,
                  onChanged: (value) => setSheetState(
                    () => selectedLockDays = int.tryParse(value) ?? 0,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Custom lock period',
                    suffixText: 'days',
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      final value = double.tryParse(
                        amountController.text.trim(),
                      );
                      final lockDays = int.tryParse(
                        lockDaysController.text.trim(),
                      );
                      if (value != null &&
                          value >= 1 &&
                          lockDays != null &&
                          lockDays >= 1 &&
                          lockDays <= 3650) {
                        Navigator.pop(sheetContext, {
                          'amount': value,
                          'lock_days': lockDays,
                        });
                      }
                    },
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Continue to Payment'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _brown,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _disposeLater(amountController);
    _disposeLater(lockDaysController);
    if (depositDetails == null) return;
    final amount = depositDetails['amount'] as double;
    final lockDays = depositDetails['lock_days'] as int;
    setState(() => _startingDeposit = true);
    try {
      final result = await ApiService.depositRentSavings(
        amount: amount,
        lockDays: lockDays,
      );
      if (!mounted) return;
      final paymentUrl = result['payment_url']?.toString() ?? '';
      if (paymentUrl.isEmpty) {
        throw Exception('Payment page was not returned.');
      }
      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DealerPaymentWebviewScreen(url: paymentUrl),
        ),
      );
      await _load();
      if (completed == true) _toast('Money added to your Rent Savings.');
    } catch (error) {
      if (mounted) _toast(_message(error), error: true);
    } finally {
      if (mounted) setState(() => _startingDeposit = false);
    }
  }

  Future<void> _handleWithdrawTap({
    required double balance,
    required double availableBalance,
    required double lockedBalance,
    String? nextUnlock,
  }) async {
    if (availableBalance > 0) {
      await _withdraw();
      return;
    }

    final hasLockedFunds = lockedBalance > 0;
    final title = hasLockedFunds ? 'Funds are locked' : 'No funds available';
    final message = hasLockedFunds
        ? 'You have ${_money(balance)} saved, but only ${_money(availableBalance)} is currently available. '
              '${nextUnlock == null ? 'Your deposit is still within its lock period.' : 'Your next deposit unlocks on ${nextUnlock.length >= 10 ? nextUnlock.substring(0, 10) : nextUnlock}.'}'
        : 'Add money to Rent Savings before requesting a withdrawal.';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          hasLockedFunds ? Icons.lock_clock_outlined : Icons.savings_outlined,
          color: hasLockedFunds ? Colors.orange : _gold,
          size: 44,
        ),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (!hasLockedFunds)
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _deposit();
              },
              child: const Text('Add Money'),
            ),
        ],
      ),
    );
  }

  Future<void> _withdraw() async {
    final details = await _moneyDetails(title: 'Withdraw savings');
    if (details == null || !mounted) return;
    final amount = _number(details['amount']);
    final phone = details['phone']?.toString() ?? '';
    final operator = details['operator']?.toString() ?? 'mtn';
    if (amount <= 0 || phone.isEmpty) {
      _toast('Enter a valid amount and phone number.', error: true);
      return;
    }

    final available = _number(_data?['available_balance']);
    final fee = _number(_data?['withdrawal_fee'] ?? 28.5);
    final needed = amount + fee;
    if (available < needed) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 36),
          title: const Text(
            'Not enough balance',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          content: Text(
            'Available ${_money(available)}\nNeeded ${_money(needed)} (incl. ${_money(fee)} fee)',
            textAlign: TextAlign.center,
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                style: FilledButton.styleFrom(backgroundColor: _brown),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      );
      return;
    }

    String challengeId = '';
    String code = '';

    if (_requireWithdrawOtp) {
      _showWorking('Sending code…');
      Map<String, dynamic> otpSession;
      try {
        otpSession = await ApiService.requestRentSavingsWithdrawOtp(
          amount: amount,
          phone: phone,
          operator: operator,
        );
        _closeWorkingDialog();
      } catch (error) {
        _closeWorkingDialog();
        _toast(_message(error), error: true);
        return;
      }

      challengeId = (otpSession['challenge_id'] ?? '').toString();
      final masked = (otpSession['email_masked'] ?? 'your email').toString();
      if (challengeId.isEmpty) {
        _toast('Could not start email verification.', error: true);
        return;
      }

      final entered = await _askWithdrawOtp(maskedEmail: masked);
      if (entered == null || entered.length != 6 || !mounted) return;
      code = entered;
    }

    _showWorking('Submitting withdrawal…');
    try {
      final result = await ApiService.withdrawRentSavings(
        amount: amount,
        phone: phone,
        operator: operator,
        otpChallengeId: challengeId.isEmpty ? null : challengeId,
        otpCode: code.isEmpty ? null : code,
      );
      _closeWorkingDialog();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;

      final previousBalance = _number(_data?['balance']);
      final previousAvailable = _number(_data?['available_balance']);
      final feeNow = _number(
        result['withdrawn_fee'] ??
            result['withdrawal_fee'] ??
            _data?['withdrawal_fee'] ??
            28.5,
      );
      final deducted = _number(result['total_deducted'] ?? (amount + feeNow));

      final merged = Map<String, dynamic>.from(result);
      merged['withdrawn_amount'] = merged['withdrawn_amount'] ?? amount;
      merged['withdrawn_fee'] = feeNow;
      merged['total_deducted'] = deducted;
      merged['withdrawn_phone'] = merged['withdrawn_phone'] ?? phone;
      merged['withdrawn_operator'] = merged['withdrawn_operator'] ?? operator;
      merged['withdrawal_fee'] = feeNow;

      final apiStatus =
          (merged['withdrawal_status'] ?? '').toString().toLowerCase();
      if (apiStatus != 'failed') {
        merged['withdrawal_status'] = 'completed';
      }

      var remaining = merged['remaining_balance'] != null
          ? _number(merged['remaining_balance'])
          : (merged['balance'] != null
              ? _number(merged['balance'])
              : (previousBalance - deducted));
      var remainingAvailable = merged['remaining_available'] != null
          ? _number(merged['remaining_available'])
          : (merged['available_balance'] != null
              ? _number(merged['available_balance'])
              : (previousAvailable - deducted));
      if (remaining < 0) remaining = 0;
      if (remainingAvailable < 0) remainingAvailable = 0;

      merged['remaining_balance'] = remaining;
      merged['remaining_available'] = remainingAvailable;
      merged['balance'] = remaining;
      merged['available_balance'] = remainingAvailable;
      merged['locked_balance'] = remaining - remainingAvailable;
      if (_number(merged['locked_balance']) < 0) {
        merged['locked_balance'] = 0;
      }

      setState(() {
        _data = merged;
        _lastWithdraw = merged;
      });

      await _showWithdrawResult(
        merged,
        fallbackAmount: amount,
        fallbackPhone: phone,
        fallbackOperator: operator,
      );
      if (mounted) {
        await _load(quiet: true);
        if (mounted && _data != null) {
          setState(() {
            _lastWithdraw = {
              ...?_lastWithdraw,
              'remaining_balance': _data!['balance'],
              'remaining_available': _data!['available_balance'],
              'balance': _data!['balance'],
              'available_balance': _data!['available_balance'],
            };
          });
        }
      }
    } catch (error) {
      _closeWorkingDialog();
      if (!mounted) return;
      _toast(_message(error), error: true);
    }
  }

  Future<void> _showWithdrawResult(
    Map<String, dynamic> result, {
    required double fallbackAmount,
    required String fallbackPhone,
    required String fallbackOperator,
  }) async {
    if (!mounted) return;
    final status = (result['withdrawal_status'] ?? 'completed')
        .toString()
        .toLowerCase();
    final completed = status != 'failed';
    final amount = _number(result['withdrawn_amount'] ?? fallbackAmount);
    final fee = _number(result['withdrawn_fee'] ?? result['withdrawal_fee'] ?? 28.5);
    final totalDeducted = _number(result['total_deducted'] ?? (amount + fee));
    final phone = (result['withdrawn_phone'] ?? fallbackPhone).toString();
    final operator =
        (result['withdrawn_operator'] ?? fallbackOperator).toString().toUpperCase();
    final remaining = _number(
      result['remaining_balance'] ?? result['balance'],
    );
    final title = completed ? 'Withdrawal completed' : 'Withdrawal failed';
    final icon = completed
        ? Icons.check_circle_outline
        : Icons.error_outline;
    final iconColor = completed ? Colors.green : Colors.redAccent;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Icon(icon, color: iconColor, size: 40),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _resultRow('Status', completed ? 'COMPLETED' : 'FAILED'),
            _resultRow('Received', _money(amount)),
            _resultRow('Fee', _money(fee)),
            _resultRow('Deducted', _money(totalDeducted)),
            _resultRow('Sent to', '$operator $phone'),
            const Divider(height: 18),
            _resultRow('Remaining', _money(remaining)),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: FilledButton.styleFrom(backgroundColor: _brown),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _askWithdrawOtp({required String maskedEmail}) async {
    final digits = List<String>.filled(6, '');
    final focuses = List.generate(6, (_) => FocusNode());
    final controllers = List.generate(6, (_) => TextEditingController());
    String currentCode() => digits.join();

    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filled = currentCode().length == 6;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: const Text(
              'Enter code',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sent to $maskedEmail',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final boxW = ((constraints.maxWidth - 40) / 6).clamp(
                      36.0,
                      44.0,
                    );
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (index) {
                        return Padding(
                          padding: EdgeInsets.only(left: index == 0 ? 0 : 6),
                          child: SizedBox(
                            width: boxW,
                            child: TextField(
                              controller: controllers[index],
                              focusNode: focuses[index],
                              autofocus: index == 0,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              maxLength: 1,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                counterText: '',
                                filled: true,
                                fillColor: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                    color: _brown,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              onChanged: (value) {
                                if (value.isNotEmpty) {
                                  digits[index] = value.substring(
                                    value.length - 1,
                                  );
                                  controllers[index].text = digits[index];
                                  controllers[index].selection =
                                      const TextSelection.collapsed(offset: 1);
                                  if (index < 5) {
                                    focuses[index + 1].requestFocus();
                                  } else {
                                    focuses[index].unfocus();
                                    if (currentCode().length == 6) {
                                      Navigator.pop(
                                        dialogContext,
                                        currentCode(),
                                      );
                                    }
                                  }
                                } else {
                                  digits[index] = '';
                                  if (index > 0) {
                                    focuses[index - 1].requestFocus();
                                  }
                                }
                                setDialogState(() {});
                              },
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ],
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: filled
                          ? () => Navigator.pop(dialogContext, currentCode())
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: _brown,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Confirm'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    for (final node in focuses) {
      node.dispose();
    }
    for (final controller in controllers) {
      controller.dispose();
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rent Savings'),
        backgroundColor: _brown,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                children: [
                  const SizedBox(height: 120),
                  const Icon(Icons.cloud_off, size: 54, color: Colors.grey),
                  const SizedBox(height: 12),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
                  ),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ),
                ],
              )
            : _content(),
      ),
    );
  }

  Widget _content() {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryButtonColor = isDark ? _gold : _brown;
    final primaryButtonForeground = isDark ? Colors.black87 : Colors.white;
    final balance = _number(_data?['balance']);
    final availableBalance = _number(_data?['available_balance']);
    final lockedBalance = _number(_data?['locked_balance']);
    final nextUnlock = _data?['next_unlock_date']?.toString();
    final account = Map<String, dynamic>.from(_data?['account'] as Map? ?? {});
    final goal = _number(account['rent_goal']);
    final progress = (_number(_data?['progress']) / 100).clamp(0.0, 1.0);
    final transactions = List<dynamic>.from(
      _data?['transactions'] as List? ?? [],
    );
    final days = int.tryParse(_data?['days_remaining']?.toString() ?? '');

    String motivation = '🏡 Your future self will thank you for saving early.';
    if (progress >= 1) {
      motivation = '✅ Congratulations! You’ve reached your rent goal.';
    } else if (days != null && days >= 0 && days <= 10) {
      motivation = '🔔 Rent is due in $days days. Keep saving!';
    } else if (balance > 0) {
      motivation =
          '💰 You’re ${_number(_data?['progress']).toStringAsFixed(0)}% of the way to your rent goal.';
    }

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (_lastWithdraw != null) ...[
          _withdrawSummaryCard(_lastWithdraw!),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_brown, Color(0xFF8A6554)]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Remaining balance',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Text(
                _money(balance),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_lastWithdraw != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'COMPLETED • remaining ${_money(_lastWithdraw!['remaining_balance'] ?? balance)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _balanceDetail(
                      'Available',
                      _money(availableBalance),
                      Icons.lock_open_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _balanceDetail(
                      'Locked',
                      _money(lockedBalance),
                      Icons.lock_clock_outlined,
                    ),
                  ),
                ],
              ),
              if (lockedBalance > 0 && nextUnlock != null) ...[
                const SizedBox(height: 9),
                Text(
                  'Next unlock: ${nextUnlock.length >= 10 ? nextUnlock.substring(0, 10) : nextUnlock}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  backgroundColor: Colors.white24,
                  color: _gold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}% saved',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Goal ${_money(goal)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: isDark
              ? const Color(0xFF2B271B)
              : _gold.withValues(alpha: .14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? _gold.withValues(alpha: .35) : Colors.transparent,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: _brown),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    motivation,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _startingDeposit ? null : _deposit,
                icon: _startingDeposit
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add),
                label: Text(_startingDeposit ? 'Opening…' : 'Add Money'),
                style: FilledButton.styleFrom(
                  backgroundColor: primaryButtonColor,
                  foregroundColor: primaryButtonForeground,
                  disabledBackgroundColor: primaryButtonColor.withValues(
                    alpha: .55,
                  ),
                  disabledForegroundColor: primaryButtonForeground.withValues(
                    alpha: .8,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _handleWithdrawTap(
                  balance: balance,
                  availableBalance: availableBalance,
                  lockedBalance: lockedBalance,
                  nextUnlock: nextUnlock,
                ),
                icon: Icon(
                  availableBalance > 0
                      ? Icons.outbox_outlined
                      : lockedBalance > 0
                      ? Icons.lock_clock_outlined
                      : Icons.money_off_outlined,
                ),
                label: Text(
                  availableBalance > 0
                      ? 'Withdraw'
                      : lockedBalance > 0
                      ? 'Funds Locked'
                      : 'No Funds',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? _gold : _brown,
                  side: BorderSide(
                    color: availableBalance > 0 || lockedBalance > 0
                        ? (isDark ? _gold : _brown)
                        : colors.outline,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'A ${_money(_data?['withdrawal_fee'] ?? 28.5)} fee applies to every withdrawal.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.red.shade700,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _editGoal,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit rent goal and due date'),
          style: TextButton.styleFrom(foregroundColor: isDark ? _gold : _brown),
        ),
        const SizedBox(height: 16),
        const Text(
          'Activity',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (transactions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: const [
                  Icon(Icons.savings_outlined, size: 48, color: _brown),
                  SizedBox(height: 10),
                  Text(
                    'Your Rent Savings is Empty',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Every small deposit brings you closer to paying your rent on time.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ...transactions.map(_transactionTile),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _withdrawSummaryCard(Map<String, dynamic> result) {
    final status =
        (result['withdrawal_status'] ?? 'completed').toString().toLowerCase();
    final completed = status == 'completed';
    final amount = _number(result['withdrawn_amount']);
    final fee = _number(result['withdrawn_fee'] ?? result['withdrawal_fee'] ?? 28.5);
    final totalDeducted = _number(result['total_deducted'] ?? (amount + fee));
    final phone = (result['withdrawn_phone'] ?? '').toString();
    final operator =
        (result['withdrawn_operator'] ?? '').toString().toUpperCase();
    final remaining = _number(
      result['remaining_balance'] ?? result['balance'] ?? _data?['balance'],
    );
    return Material(
      color: completed ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  completed ? Icons.check_circle : Icons.hourglass_top,
                  color: completed ? Colors.green.shade700 : Colors.orange.shade800,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    completed
                        ? 'Withdrawal completed'
                        : 'Withdrawal ${status.toUpperCase()}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: completed
                          ? Colors.green.shade800
                          : Colors.orange.shade900,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _lastWithdraw = null),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            Text(
              '${_money(amount)} sent to $operator $phone',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Total deducted: ${_money(totalDeducted)}',
              style: TextStyle(
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'Remaining balance: ${_money(remaining)}',
              style: TextStyle(
                color: Colors.grey.shade900,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _balanceDetail(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _gold, size: 16),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _transactionTile(dynamic raw) {
    final item = Map<String, dynamic>.from(raw as Map);
    final deposit = item['type'] == 'deposit';
    final status = (item['status']?.toString() ?? 'pending').toLowerCase();
    final fee = _number(item['fee']);
    final phone = item['phone']?.toString() ?? '';
    final operator = (item['operator']?.toString() ?? '').toUpperCase();
    final statusColor = status == 'completed'
        ? Colors.green
        : status == 'failed'
            ? Colors.red
            : Colors.orange;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: deposit
              ? Colors.green.shade50
              : Colors.orange.shade50,
          child: Icon(
            deposit ? Icons.south_west : Icons.north_east,
            color: deposit ? Colors.green : Colors.orange,
          ),
        ),
        title: Text(
          deposit ? 'Savings deposit' : 'Withdrawal',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            item['created_at']?.toString() ?? '',
            if (!deposit && phone.isNotEmpty)
              'To ${operator.isNotEmpty ? '$operator ' : ''}$phone',
            if (fee > 0) 'K${fee.toStringAsFixed(2)} deduction',
            if (deposit && item['lock_until'] != null)
              'Locked until ${item['lock_until'].toString().length >= 10 ? item['lock_until'].toString().substring(0, 10) : item['lock_until']}',
          ].where((part) => part.trim().isNotEmpty).join(' • '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${deposit ? '+' : '-'}${_money(_number(item['amount']) + (deposit ? 0 : fee))}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: deposit ? Colors.green : Colors.orange,
              ),
            ),
            Text(
              status.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RentGoalDialog extends StatefulWidget {
  const _RentGoalDialog({
    required this.initialAmount,
    required this.initialTarget,
  });

  final double initialAmount;
  final DateTime? initialTarget;

  @override
  State<_RentGoalDialog> createState() => _RentGoalDialogState();
}

class _RentGoalDialogState extends State<_RentGoalDialog> {
  late final TextEditingController _amountController;
  DateTime? _target;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.initialAmount.toStringAsFixed(0),
    );
    _target = widget.initialTarget;
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    var initialDate = _target ?? today.add(const Duration(days: 30));
    if (initialDate.isBefore(today)) initialDate = today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
    );
    if (picked != null && mounted) setState(() => _target = picked);
  }

  void _save() {
    final parsed = double.tryParse(_amountController.text.trim());
    if (parsed == null || parsed <= 0) {
      setState(() => _amountError = 'Enter a rent goal greater than K0.');
      return;
    }
    Navigator.of(
      context,
    ).pop(<String, dynamic>{'amount': parsed, 'date': _target});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Set your rent goal'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (_amountError != null) setState(() => _amountError = null);
            },
            decoration: InputDecoration(
              labelText: 'Rent goal (K)',
              prefixText: 'K ',
              errorText: _amountError,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(
              _target == null
                  ? 'Choose rent due date'
                  : '${_target!.day}/${_target!.month}/${_target!.year}',
            ),
            onTap: _chooseDate,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save Goal')),
      ],
    );
  }
}
