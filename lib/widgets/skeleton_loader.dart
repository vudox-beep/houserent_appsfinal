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
    final base = widget.baseColor ?? Colors.grey.shade300;
    final highlight = widget.highlightColor ?? Colors.grey.shade100;

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
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(right: 16, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
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
