import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Gradient? gradient;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.borderColor,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: gradient ?? AppColors.cardGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor ?? AppColors.cardBorder,
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}