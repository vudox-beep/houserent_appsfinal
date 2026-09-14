import 'package:flutter/material.dart';

/// Shared SENT / BEEP pulse overlay used on driver + client maps.
class PriceBeepOverlay extends StatelessWidget {
  const PriceBeepOverlay({
    super.key,
    required this.pulse,
    required this.amount,
    required this.secondsLeft,
    this.sentFlash = false,
    this.sentLabel = 'SENT',
    this.beepLabel = 'BEEP',
    this.bannerSent = 'Price sent',
    this.bannerWaiting = 'Waiting for response',
    this.onCancel,
    this.showAmount = true,
    this.showTimer = true,
    /// When true, dim/pulse do not block map pan/zoom (banner stays tappable).
    this.allowMapGestures = false,
  });

  final Animation<double> pulse;
  final double amount;
  final int secondsLeft;
  final bool sentFlash;
  final String sentLabel;
  final String beepLabel;
  final String bannerSent;
  final String bannerWaiting;
  final VoidCallback? onCancel;
  final bool showAmount;
  final bool showTimer;
  final bool allowMapGestures;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    final dimAndPulse = Stack(
      alignment: Alignment.center,
      children: [
        Container(
          color: Colors.black.withValues(alpha: allowMapGestures ? 0.12 : 0.28),
        ),
        AnimatedBuilder(
          animation: pulse,
          builder: (context, _) {
            final t = pulse.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                for (final lag in [0.0, 0.33, 0.66])
                  Opacity(
                    opacity: (1 - ((t + lag) % 1.0)).clamp(0.0, 1.0) * 0.85,
                    child: Transform.scale(
                      scale: 0.55 + (((t + lag) % 1.0) * 1.7),
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFFC107),
                            width: 5,
                          ),
                        ),
                      ),
                    ),
                  ),
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A).withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFFC107),
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFC107).withValues(alpha: 0.45),
                        blurRadius: 28,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        sentFlash ? sentLabel : beepLabel,
                        style: const TextStyle(
                          color: Color(0xFFFFC107),
                          fontWeight: FontWeight.w900,
                          fontSize: 26,
                          letterSpacing: 1.2,
                        ),
                      ),
                      if (showAmount) ...[
                        const SizedBox(height: 4),
                        Text(
                          'K ${amount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                          ),
                        ),
                      ],
                      if (!sentFlash && showTimer)
                        Text(
                          '${secondsLeft}s',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        if (allowMapGestures)
          IgnorePointer(child: dimAndPulse)
        else
          dimAndPulse,
        Positioned(
          top: top + 70,
          left: 16,
          right: 16,
          child: Material(
            color: sentFlash ? const Color(0xFFFFC107) : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    sentFlash
                        ? Icons.check_circle_rounded
                        : Icons.notifications_active_rounded,
                    color: sentFlash
                        ? Colors.black
                        : const Color(0xFFFFC107),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      sentFlash
                          ? bannerSent
                          : (showAmount
                              ? '$bannerWaiting · K ${amount.toStringAsFixed(0)}'
                              : bannerWaiting),
                      style: TextStyle(
                        color: sentFlash ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (onCancel != null)
                    TextButton(
                      onPressed: onCancel,
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: (sentFlash ? Colors.black : Colors.white)
                              .withValues(alpha: 0.8),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
