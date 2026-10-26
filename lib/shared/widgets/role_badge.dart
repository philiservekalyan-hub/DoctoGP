import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

class RoleBadge extends StatelessWidget {
  final String label;
  final Color color;
  const RoleBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 0.8,
        ),
      ),
    );
  }
}