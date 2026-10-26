// lib/core/widgets/form_section.dart
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

class FormSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final List<Widget> children;
  final bool initiallyExpanded;

  const FormSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.accent = AppColors.primary,
    this.initiallyExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context)
              .copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            iconColor: accent,
            collapsedIconColor: AppColors.textMuted,
            backgroundColor: AppColors.surface,
            collapsedBackgroundColor: AppColors.surface,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            title: Text(title, style: AppTextStyles.h3),
            children: children,
          ),
        ),
      ),
    );
  }
}