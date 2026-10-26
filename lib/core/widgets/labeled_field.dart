// lib/core/widgets/labeled_field.dart
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  final bool required;

  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (required)
              const Text(' *',
                  style: TextStyle(
                      color: AppColors.error, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 8),
        child,
        const SizedBox(height: 16),
      ],
    );
  }
}

class DarkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final int? maxLines;
  final TextInputType? keyboardType;
  final IconData? icon;
  final String? Function(String?)? validator;

  const DarkTextField({
    super.key,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.icon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: icon != null
            ? Icon(icon, color: AppColors.textMuted, size: 20)
            : null,
      ),
    );
  }
}