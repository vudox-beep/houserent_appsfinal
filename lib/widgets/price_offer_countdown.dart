import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Price offer popup — inDrive-style Decline + yellow Accept with loading fill.
///
/// When [waitingOnly] is true (driver side), shows a waiting card with the
/// same yellow progress button while the client responds.
Future<bool?> showPriceOfferCountdown({
  required BuildContext context,
  required String title,
  required String subtitle,
  required double amount,
  Duration duration = const Duration(seconds: 30),
  String acceptLabel = 'Accept',
  String declineLabel = 'Decline',
  bool waitingOnly = false,
  String? imageUrl,
  /// When waiting, poll each second:
  /// `true` = accepted, `false` = declined, `null` = still waiting.
  Future<bool?> Function()? checkAccepted,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: !waitingOnly,
    barrierLabel: 'Price offer',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, anim, secondary) {
      return _PriceOfferCountdownDialog(
        title: title,
        subtitle: subtitle,
        amount: amount,
        duration: duration,
        acceptLabel: acceptLabel,
        declineLabel: declineLabel,
        waitingOnly: waitingOnly,
        imageUrl: imageUrl,
        checkAccepted: checkAccepted,
      );
    },
    transitionBuilder: (ctx, anim, secondary, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return ScaleTransition(
        scale: Tween<double>(begin: 0.9, end: 1).animate(curved),
        child: FadeTransition(opacity: anim, child: child),
      );
    },
  );
}

class _PriceOfferCountdownDialog extends StatefulWidget {
  const _PriceOfferCountdownDialog({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.duration,
    required this.acceptLabel,
    required this.declineLabel,
    required this.waitingOnly,
    this.imageUrl,
    this.checkAccepted,
  });

  final String title;
  final String subtitle;
  final double amount;
  final Duration duration;
  final String acceptLabel;
  final String declineLabel;
  final bool waitingOnly;
  final String? imageUrl;
  final Future<bool?> Function()? checkAccepted;

  @override
  State<_PriceOfferCountdownDialog> createState() =>
      _PriceOfferCountdownDialogState();
}

class _PriceOfferCountdownDialogState extends State<_PriceOfferCountdownDialog>
    with SingleTickerProviderStateMixin {
  static const _sheet = Color(0xFF1C1C1E);
  static const _muted = Color(0xFF2C2C2E);
  static const _yellow = Color(0xFFFFC107);
  static const _yellowDeep = Color(0xFFE6A800);

  late final AnimationController _ring;
  Timer? _tick;
  int _secondsLeft = 0;
  bool _settled = false;

  void _finish(bool? value) {
    if (_settled || !mounted) return;
    _settled = true;
    _tick?.cancel();
    _tick = null;
    Navigator.of(context, rootNavigator: true).pop(value);
  }

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.duration.inSeconds;
    _ring = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || _settled) return;
      setState(() => _secondsLeft = math.max(0, _secondsLeft - 1));
      if (widget.checkAccepted != null) {
        try {
          final status = await widget.checkAccepted!();
          if (!mounted || _settled) return;
          if (status == true) {
            _finish(true);
            return;
          }
          if (status == false) {
            _finish(false);
            return;
          }
        } catch (_) {}
      }
      if (_secondsLeft <= 0) {
        _finish(null);
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 340,
            margin: const EdgeInsets.symmetric(horizontal: 18),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            decoration: BoxDecoration(
              color: _sheet,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if ((widget.imageUrl ?? '').trim().isNotEmpty) ...[
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: _muted,
                        backgroundImage: NetworkImage(widget.imageUrl!.trim()),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'K ${widget.amount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 34,
                        letterSpacing: -0.8,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${_secondsLeft}s',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontWeight: FontWeight.w800,
                          fontSize: 26,
                          height: 1,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _yellow.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.waitingOnly
                                ? Icons.hourglass_top_rounded
                                : Icons.thumb_up_alt_rounded,
                            size: 14,
                            color: _yellow,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            widget.waitingOnly ? 'Waiting' : 'Your fare',
                            style: const TextStyle(
                              color: _yellow,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (widget.waitingOnly)
                  _CountdownFillButton(
                    label: 'Waiting for client…',
                    progress: _ring,
                    onTap: null,
                    enabled: false,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: Material(
                            color: _muted,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: _settled ? null : () => _finish(false),
                              child: Center(
                                child: Text(
                                  widget.declineLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _CountdownFillButton(
                          label: widget.acceptLabel,
                          progress: _ring,
                          onTap: _settled ? null : () => _finish(true),
                          enabled: !_settled,
                        ),
                      ),
                    ],
                  ),
                if (widget.waitingOnly) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _settled ? null : () => _finish(null),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Yellow Accept / Waiting button with neat left→right countdown fill.
class _CountdownFillButton extends StatelessWidget {
  const _CountdownFillButton({
    required this.label,
    required this.progress,
    required this.onTap,
    required this.enabled,
  });

  final String label;
  final Animation<double> progress;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          return PriceCountdownAcceptButton(
            label: label,
            fill: progress.value.clamp(0.0, 1.0),
            onTap: enabled ? onTap : null,
          );
        },
      ),
    );
  }
}

/// Public yellow Accept button with loading fill (0→1 left to right).
class PriceCountdownAcceptButton extends StatelessWidget {
  const PriceCountdownAcceptButton({
    super.key,
    required this.label,
    required this.fill,
    this.onTap,
    this.height = 48,
  });

  final String label;
  final double fill;
  final VoidCallback? onTap;
  final double height;

  static const _yellow = Color(0xFFFFC107);
  static const _yellowDeep = Color(0xFFE6A800);

  @override
  Widget build(BuildContext context) {
    final f = fill.clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: _yellow),
              FractionallySizedBox(
                widthFactor: f,
                alignment: Alignment.centerLeft,
                child: const ColoredBox(color: _yellowDeep),
              ),
              if (f > 0.02 && f < 0.98)
                Align(
                  alignment: Alignment(-1 + 2 * f, 0),
                  child: Container(
                    width: 10,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.0),
                          Colors.white.withValues(alpha: 0.35),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Self-running Accept button with a 30s yellow fill (for driver offer cards).
class PriceTimedAcceptButton extends StatefulWidget {
  const PriceTimedAcceptButton({
    super.key,
    required this.onAccept,
    this.label = 'Accept',
    this.duration = const Duration(seconds: 30),
    this.height = 48,
  });

  final VoidCallback onAccept;
  final String label;
  final Duration duration;
  final double height;

  @override
  State<PriceTimedAcceptButton> createState() => _PriceTimedAcceptButtonState();
}

class _PriceTimedAcceptButtonState extends State<PriceTimedAcceptButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return PriceCountdownAcceptButton(
          label: widget.label,
          fill: _ctrl.value,
          height: widget.height,
          onTap: widget.onAccept,
        );
      },
    );
  }
}

/// Result of a price negotiation — accepted / no response / declined.
enum PriceOfferResultKind { accepted, noResponse, declined, keptFare }

/// Neat dark result card (replaces plain snackbars for price outcomes).
Future<void> showPriceOfferResult({
  required BuildContext context,
  required PriceOfferResultKind kind,
  required double amount,
  String? title,
  String? subtitle,
  String primaryLabel = 'OK',
  VoidCallback? onPrimary,
}) {
  final cfg = switch (kind) {
    PriceOfferResultKind.accepted => (
        icon: Icons.check_circle_rounded,
        color: const Color(0xFFFFC107),
        title: title ?? 'Price accepted',
        subtitle: subtitle ?? 'Fare updated for this trip.',
      ),
    PriceOfferResultKind.noResponse => (
        icon: Icons.hourglass_empty_rounded,
        color: const Color(0xFFFFC107),
        title: title ?? 'No response',
        subtitle: subtitle ?? 'You can send another price anytime.',
      ),
    PriceOfferResultKind.declined => (
        icon: Icons.close_rounded,
        color: const Color(0xFFFF8A80),
        title: title ?? 'Price declined',
        subtitle: subtitle ?? 'Current fare stays the same.',
      ),
    PriceOfferResultKind.keptFare => (
        icon: Icons.lock_rounded,
        color: const Color(0xFF2F80FF),
        title: title ?? 'Keeping current fare',
        subtitle: subtitle ?? 'No change to the agreed price.',
      ),
  };

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Price result',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, anim, secondary) {
      return SafeArea(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: cfg.color.withValues(alpha: 0.55)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: cfg.color.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border: Border.all(color: cfg.color, width: 2),
                    ),
                    child: Icon(cfg.icon, color: cfg.color, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    cfg.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'K ${amount.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: cfg.color,
                      fontWeight: FontWeight.w900,
                      fontSize: 32,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cfg.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: _ResultFillButton(
                      label: primaryLabel,
                      color: cfg.color,
                      darkText: kind != PriceOfferResultKind.declined,
                      onTap: () {
                        Navigator.pop(ctx);
                        onPrimary?.call();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, secondary, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return ScaleTransition(
        scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
        child: FadeTransition(opacity: anim, child: child),
      );
    },
  );
}

class _ResultFillButton extends StatelessWidget {
  const _ResultFillButton({
    required this.label,
    required this.color,
    required this.darkText,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool darkText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: darkText ? Colors.black : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}
