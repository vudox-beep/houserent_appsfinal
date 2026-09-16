import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 42});

  static const String assetPath =
      'assets/images/1e0cdcd7-6334-49dd-9cda-28d2d6930619.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: 'HouseRent Africa logo',
        errorBuilder: (context, error, stackTrace) {
          return SizedBox(
            width: size,
            height: size,
            child: Icon(
              Icons.home_work_rounded,
              size: size * 0.72,
              color: const Color(0xFF5A3D31),
            ),
          );
        },
      ),
    );
  }
}

class AppBrand extends StatelessWidget {
  const AppBrand({
    super.key,
    this.logoSize = 34,
    this.textColor,
    this.fontSize = 20,
  });

  final double logoSize;
  final Color? textColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'HouseRent Africa',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ],
    );
  }
}
