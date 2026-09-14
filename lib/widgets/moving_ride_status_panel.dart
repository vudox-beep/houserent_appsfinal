import 'package:flutter/material.dart';

/// Yango-style live ride bottom panel (dark sheet with person / contact / safety).
class MovingRideStatusPanel extends StatelessWidget {
  const MovingRideStatusPanel({
    super.key,
    required this.headline,
    required this.personName,
    this.personImageUrl,
    this.vehicleLabel,
    this.plate,
    this.ratingLabel,
    this.amountLabel,
    this.subtitle,
    this.pickupLabel,
    this.dropoffLabel,
    this.phoneLabel,
    this.onContact,
    this.contactLabel = 'Contact',
    this.onSafety,
    this.safetyLabel = 'Trip',
    this.onPrimary,
    this.primaryLabel,
    this.primaryIcon,
    this.onSecondary,
    this.secondaryLabel,
    this.onNavigate,
    this.navigateLabel = 'Navigate',
    this.onCancel,
    this.cancelLabel = 'Cancel ride',
    this.onNotes,
    this.notesHint = 'Any pickup notes?',
    this.onMinimize,
    this.compact = false,
    this.minimized = false,
  });

  final String headline;
  final String personName;
  final String? personImageUrl;
  final String? vehicleLabel;
  final String? plate;
  final String? ratingLabel;
  final String? amountLabel;
  final String? subtitle;
  final String? pickupLabel;
  final String? dropoffLabel;
  final String? phoneLabel;
  final VoidCallback? onContact;
  final String contactLabel;
  final VoidCallback? onSafety;
  final String safetyLabel;
  final VoidCallback? onPrimary;
  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;
  final VoidCallback? onNavigate;
  final String navigateLabel;
  final VoidCallback? onCancel;
  final String cancelLabel;
  final VoidCallback? onNotes;
  final String notesHint;
  final VoidCallback? onMinimize;
  final bool compact;
  /// Slim bar only — tap to expand again.
  final bool minimized;

  static const Color _sheet = Color(0xFF1A1A1A);
  static const Color _lime = Color(0xFFFFC107);
  static const Color _muted = Color(0xFF2A2A2A);

  @override
  Widget build(BuildContext context) {
    final initial =
        personName.trim().isNotEmpty ? personName.trim()[0].toUpperCase() : '?';

    if (minimized) {
      return Material(
        color: _sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: InkWell(
          onTap: onMinimize,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFC107),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          [
                            personName.split(' ').first,
                            if (amountLabel != null) amountLabel!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, compact ? 10 : 12, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: GestureDetector(
                  onTap: onMinimize,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      if (onMinimize != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 8),
                          child: Text(
                            'Tap to minimize',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
              Text(
                headline,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.4,
                  height: 1.15,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (vehicleLabel != null && vehicleLabel!.isNotEmpty)
                          Text(
                            vehicleLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        if (plate != null &&
                            plate!.isNotEmpty &&
                            plate != 'null') ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _muted,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              plate!.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                        if (amountLabel != null && amountLabel!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            amountLabel!,
                            style: const TextStyle(
                              color: Color(0xFFFFC107),
                              fontWeight: FontWeight.w900,
                              fontSize: 40,
                              letterSpacing: -1,
                            ),
                          ),
                        ],
                        if (phoneLabel != null &&
                            phoneLabel!.isNotEmpty &&
                            phoneLabel != 'null') ...[
                          const SizedBox(height: 6),
                          Text(
                            phoneLabel!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    width: 88,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _muted,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.local_shipping_rounded,
                      color: Colors.white70,
                      size: 34,
                    ),
                  ),
                ],
              ),
              if ((pickupLabel != null && pickupLabel!.isNotEmpty) ||
                  (dropoffLabel != null && dropoffLabel!.isNotEmpty)) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: _muted,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      if (pickupLabel != null && pickupLabel!.isNotEmpty)
                        _routeRow(
                          color: const Color(0xFF2F80FF),
                          label: 'PICKUP',
                          value: pickupLabel!,
                        ),
                      if (pickupLabel != null &&
                          pickupLabel!.isNotEmpty &&
                          dropoffLabel != null &&
                          dropoffLabel!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      if (dropoffLabel != null && dropoffLabel!.isNotEmpty)
                        _routeRow(
                          color: const Color(0xFFE53935),
                          label: 'DESTINATION',
                          value: dropoffLabel!,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _circleAction(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: const Color(0xFF3A3A3A),
                            backgroundImage:
                                (personImageUrl != null &&
                                        personImageUrl!.trim().isNotEmpty)
                                    ? NetworkImage(personImageUrl!)
                                    : null,
                            child: (personImageUrl == null ||
                                    personImageUrl!.trim().isEmpty)
                                ? Text(
                                    initial,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 20,
                                    ),
                                  )
                                : null,
                          ),
                          if (ratingLabel != null && ratingLabel!.isNotEmpty)
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF8A00),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                    Text(
                                      ratingLabel!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      label: personName.split(' ').first,
                    ),
                  ),
                  Expanded(
                    child: _circleAction(
                      onTap: onContact,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: _lime,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.phone_rounded,
                          color: Colors.black,
                          size: 26,
                        ),
                      ),
                      label: contactLabel,
                    ),
                  ),
                  Expanded(
                    child: _circleAction(
                      onTap: onSafety,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: _lime,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          color: Colors.black,
                          size: 26,
                        ),
                      ),
                      label: safetyLabel,
                    ),
                  ),
                ],
              ),
              if (onNotes != null) ...[
                const SizedBox(height: 16),
                Material(
                  color: _muted,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    onTap: onNotes,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              notesHint,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if ((onSecondary != null && secondaryLabel != null) ||
                  onNavigate != null ||
                  (onPrimary != null && primaryLabel != null) ||
                  onCancel != null) ...[
                const SizedBox(height: 16),
                // Horizontal: Complete · Navigate · Continue · Cancel
                Row(
                  children: [
                    if (onSecondary != null && secondaryLabel != null)
                      Expanded(
                        child: _circleAction(
                          onTap: onSecondary,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: _lime,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              secondaryLabel!.toLowerCase().contains('complete')
                                  ? Icons.check_rounded
                                  : Icons.list_alt_rounded,
                              color: Colors.black,
                              size: 26,
                            ),
                          ),
                          label: _shortActionLabel(secondaryLabel!),
                        ),
                      ),
                    if (onNavigate != null)
                      Expanded(
                        child: _circleAction(
                          onTap: onNavigate,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: _lime,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.near_me_rounded,
                              color: Colors.black,
                              size: 26,
                            ),
                          ),
                          label: _shortActionLabel(navigateLabel),
                        ),
                      ),
                    if (onPrimary != null && primaryLabel != null)
                      Expanded(
                        child: _circleAction(
                          onTap: onPrimary,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: _lime,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              primaryIcon ?? Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 26,
                            ),
                          ),
                          label: _shortActionLabel(primaryLabel!),
                        ),
                      ),
                    if (onCancel != null)
                      Expanded(
                        child: _circleAction(
                          onTap: onCancel,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.red.shade400,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          label: _shortActionLabel(cancelLabel),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _shortActionLabel(String label) {
    final t = label.trim();
    // Keep labels neat under the circles (e.g. "Complete move" → "Complete").
    if (t.toLowerCase().startsWith('complete')) return 'Complete';
    if (t.toLowerCase().startsWith('navigate')) return 'Navigate';
    if (t.toLowerCase().startsWith('continue')) return 'Continue';
    if (t.toLowerCase().startsWith('start')) return 'Start';
    if (t.toLowerCase().startsWith('cancel')) return 'Cancel';
    if (t.toLowerCase().startsWith('all ')) return 'Requests';
    return t.length > 12 ? '${t.substring(0, 11)}…' : t;
  }

  Widget _routeRow({
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(Icons.circle, size: 10, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _circleAction({
    required Widget child,
    required String label,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          child,
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
