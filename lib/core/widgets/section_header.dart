import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title shrinks to fit if the row is narrow — ellipsis instead
          // of pushing the action off screen.
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.h3,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: GestureDetector(
                onTap: onAction,
                child: Text(
                  action!,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}