import 'package:flutter/material.dart';

class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;
  final Color? baseColor;
  final Color? highlightColor;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = widget.baseColor ?? (isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade300);
    final highlight = widget.highlightColor ?? (isDark ? const Color(0xFF3C3C3C) : Colors.grey.shade100);

    return AnimatedBuilder(
      animation: _controller,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: widget.borderRadius,
        ),
      ),
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment(-1.0 - (2 * _controller.value), -0.25),
              end: Alignment(1.0 - (2 * _controller.value), 0.25),
              colors: <Color>[base, highlight, base],
              stops: const <double>[0.2, 0.5, 0.8],
            ).createShader(rect);
          },
          child: child!,
        );
      },
    );
  }
}

class SkeletonPropertyCard extends StatelessWidget {
  const SkeletonPropertyCard({super.key, this.width = 320, this.height = 300});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(right: 16, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SkeletonBox(height: 165, borderRadius: BorderRadius.all(Radius.circular(12))),
          SizedBox(height: 14),
          SkeletonBox(height: 18, width: 200, borderRadius: BorderRadius.all(Radius.circular(8))),
          SizedBox(height: 10),
          SkeletonBox(height: 14, width: 140, borderRadius: BorderRadius.all(Radius.circular(8))),
          SizedBox(height: 14),
          SkeletonBox(height: 16, width: 90, borderRadius: BorderRadius.all(Radius.circular(8))),
        ],
      ),
    );
  }
}

class SkeletonPropertyCarousel extends StatelessWidget {
  final double height;
  final int itemCount;

  const SkeletonPropertyCarousel({super.key, this.height = 310, this.itemCount = 3});

  @override
  Widget build(BuildContext context) {
    final cardWidth = MediaQuery.of(context).size.width * 0.75 > 320
        ? 320.0
        : MediaQuery.of(context).size.width * 0.75;

    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: itemCount,
        itemBuilder: (context, index) => SkeletonPropertyCard(width: cardWidth),
      ),
    );
  }
}

class SkeletonTenantOverview extends StatelessWidget {
  const SkeletonTenantOverview({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          SkeletonBox(height: 30, width: 260),
          SizedBox(height: 10),
          SkeletonBox(height: 16, width: 200),
          SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(width: 220, child: SkeletonBox(height: 110)),
              SizedBox(width: 220, child: SkeletonBox(height: 110)),
              SizedBox(width: 220, child: SkeletonBox(height: 110)),
            ],
          ),
          SizedBox(height: 28),
          SkeletonBox(height: 280, borderRadius: BorderRadius.all(Radius.circular(12))),
        ],
      ),
    );
  }
}

class SkeletonTenantRentals extends StatelessWidget {
  const SkeletonTenantRentals({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, __) => const SkeletonBox(
        height: 220,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    );
  }
}

class SkeletonTenantTable extends StatelessWidget {
  const SkeletonTenantTable({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 440;

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNarrow) ...[
                const SkeletonBox(height: 26, width: 180),
                const SizedBox(height: 12),
                const SkeletonBox(
                  height: 42,
                  width: double.infinity,
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ] else ...[
                const Row(
                  children: [
                    SkeletonBox(height: 26, width: 180),
                    Spacer(),
                    SkeletonBox(height: 42, width: 160, borderRadius: BorderRadius.all(Radius.circular(8))),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: 7,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, __) => const SkeletonBox(
                    height: 52,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SkeletonProfile extends StatelessWidget {
  const SkeletonProfile({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          width: 600,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(height: 28, width: 180),
              SizedBox(height: 32),
              Center(
                child: SkeletonBox(
                  width: 120,
                  height: 120,
                  borderRadius: BorderRadius.all(Radius.circular(60)),
                ),
              ),
              SizedBox(height: 28),
              SkeletonBox(height: 54),
              SizedBox(height: 16),
              SkeletonBox(height: 54),
              SizedBox(height: 16),
              SkeletonBox(height: 54),
              SizedBox(height: 24),
              SkeletonBox(height: 50, width: 180, borderRadius: BorderRadius.all(Radius.circular(8))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Neat driver home skeleton — header, earnings, stats, trip card, CTAs.
class SkeletonDriverDashboard extends StatelessWidget {
  const SkeletonDriverDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF1C1C1C) : Colors.white;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SkeletonBox(
                  width: 44,
                  height: 44,
                  borderRadius: BorderRadius.circular(22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(height: 18, width: 140),
                      SizedBox(height: 8),
                      SkeletonBox(height: 12, width: 100),
                    ],
                  ),
                ),
                SkeletonBox(
                  width: 48,
                  height: 28,
                  borderRadius: BorderRadius.circular(999),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161616) : const Color(0xFF14171A),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(
                    height: 12,
                    width: 90,
                    baseColor: Color(0xFF2A2A2A),
                    highlightColor: Color(0xFF3A3A3A),
                  ),
                  SizedBox(height: 12),
                  SkeletonBox(
                    height: 34,
                    width: 160,
                    baseColor: Color(0xFF2A2A2A),
                    highlightColor: Color(0xFF3A3A3A),
                  ),
                  SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: SkeletonBox(
                          height: 14,
                          baseColor: Color(0xFF2A2A2A),
                          highlightColor: Color(0xFF3A3A3A),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: SkeletonBox(
                          height: 14,
                          baseColor: Color(0xFF2A2A2A),
                          highlightColor: Color(0xFF3A3A3A),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 96,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(height: 22, width: 22),
                        Spacer(),
                        SkeletonBox(height: 18, width: 48),
                        SizedBox(height: 6),
                        SkeletonBox(height: 12, width: 70),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 96,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(height: 22, width: 22),
                        Spacer(),
                        SkeletonBox(height: 18, width: 40),
                        SizedBox(height: 6),
                        SkeletonBox(height: 12, width: 80),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const SkeletonBox(height: 16, width: 110),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SkeletonBox(
                        height: 22,
                        width: 90,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      const Spacer(),
                      const SkeletonBox(height: 18, width: 56),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const SkeletonBox(height: 16, width: 140),
                  const SizedBox(height: 10),
                  const SkeletonBox(height: 12, width: double.infinity),
                  const SizedBox(height: 6),
                  const SkeletonBox(height: 12, width: 200),
                  const SizedBox(height: 16),
                  SkeletonBox(
                    height: 48,
                    width: double.infinity,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SkeletonBox(
                          height: 44,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SkeletonBox(
                        width: 44,
                        height: 44,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SkeletonBox(
              height: 52,
              width: double.infinity,
              borderRadius: BorderRadius.circular(16),
            ),
            const SizedBox(height: 10),
            SkeletonBox(
              height: 48,
              width: double.infinity,
              borderRadius: BorderRadius.circular(16),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trip / job details loading skeleton.
class SkeletonTripDetails extends StatelessWidget {
  const SkeletonTripDetails({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    Widget block({required List<Widget> children}) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        block(
          children: const [
            SkeletonBox(height: 14, width: 88),
            SizedBox(height: 14),
            SkeletonBox(
              height: 140,
              width: double.infinity,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
            SizedBox(height: 14),
            SkeletonBox(height: 16, width: double.infinity),
            SizedBox(height: 8),
            SkeletonBox(height: 16, width: 220),
            SizedBox(height: 14),
            SkeletonBox(height: 22, width: 120),
          ],
        ),
        const SizedBox(height: 12),
        block(
          children: const [
            SkeletonBox(height: 16, width: 140),
            SizedBox(height: 14),
            Row(
              children: [
                SkeletonBox(
                  height: 48,
                  width: 48,
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(height: 16, width: 150),
                      SizedBox(height: 8),
                      SkeletonBox(height: 12, width: 100),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        block(
          children: const [
            SkeletonBox(height: 16, width: 100),
            SizedBox(height: 12),
            SkeletonBox(height: 54, width: double.infinity),
            SizedBox(height: 10),
            SkeletonBox(height: 54, width: double.infinity),
          ],
        ),
        const SizedBox(height: 16),
        const SkeletonBox(
          height: 52,
          width: double.infinity,
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        const SizedBox(height: 10),
        const SkeletonBox(
          height: 48,
          width: double.infinity,
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ],
    );
  }
}

class SkeletonDealerOverview extends StatelessWidget {
  const SkeletonDealerOverview({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        const SkeletonBox(
          height: 140,
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        const SizedBox(height: 18),
        Row(
          children: const [
            Expanded(
              child: SkeletonBox(
                height: 96,
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SkeletonBox(
                height: 96,
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: const [
            Expanded(
              child: SkeletonBox(
                height: 96,
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SkeletonBox(
                height: 96,
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const SkeletonBox(height: 22, width: 160),
        const SizedBox(height: 12),
        const SkeletonBox(
          height: 72,
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        const SizedBox(height: 10),
        const SkeletonBox(
          height: 72,
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        const SizedBox(height: 10),
        const SkeletonBox(
          height: 72,
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ],
    );
  }
}

class SkeletonDealerProperties extends StatelessWidget {
  const SkeletonDealerProperties({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => const SkeletonBox(
        height: 64,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    );
  }
}

class SkeletonDealerLeads extends StatelessWidget {
  const SkeletonDealerLeads({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const SkeletonBox(
        height: 96,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    );
  }
}

class SkeletonDealerTenants extends StatelessWidget {
  const SkeletonDealerTenants({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SkeletonBox(
          height: 44,
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        const SizedBox(height: 16),
        Row(
          children: const [
            Expanded(
              child: SkeletonBox(
                height: 88,
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SkeletonBox(
                height: 88,
                borderRadius: BorderRadius.all(Radius.circular(14)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SkeletonBox(height: 22, width: 140),
        const SizedBox(height: 12),
        ...List.generate(
          5,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: SkeletonBox(
              height: 78,
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }
}

class SkeletonDealerPayments extends StatelessWidget {
  const SkeletonDealerPayments({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => const SkeletonBox(
        height: 68,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    );
  }
}

class SkeletonDealerSubscription extends StatelessWidget {
  const SkeletonDealerSubscription({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          const SkeletonBox(height: 32, width: 220),
          const SizedBox(height: 12),
          const SkeletonBox(height: 16, width: 280),
          const SizedBox(height: 48),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            alignment: WrapAlignment.center,
            children: const [
              SizedBox(
                width: 280,
                child: SkeletonBox(
                  height: 320,
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
              ),
              SizedBox(
                width: 280,
                child: SkeletonBox(
                  height: 320,
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SkeletonDealerMaintenance extends StatelessWidget {
  const SkeletonDealerMaintenance({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const SkeletonBox(
        height: 110,
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    );
  }
}

class SkeletonDealerReferral extends StatelessWidget {
  const SkeletonDealerReferral({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        SkeletonBox(
          height: 180,
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        SizedBox(height: 24),
        SkeletonBox(height: 20, width: 150),
        SizedBox(height: 12),
        SkeletonBox(
          height: 50,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        SizedBox(height: 24),
        SkeletonBox(height: 20, width: 120),
        SizedBox(height: 12),
        SkeletonBox(
          height: 72,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        SizedBox(height: 10),
        SkeletonBox(
          height: 72,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        SizedBox(height: 10),
        SkeletonBox(
          height: 72,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ],
    );
  }
}
