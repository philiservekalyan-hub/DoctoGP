import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/models/ad_model.dart';

class AdStatusChip extends StatelessWidget {
  final AdStatus status;
  const AdStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      AdStatus.draft => (AppColors.textMuted.withOpacity(.15), AppColors.textMuted),
      AdStatus.pendingReview => (AppColors.warning.withOpacity(.18), AppColors.warning),
      AdStatus.approved => (AppColors.success.withOpacity(.18), AppColors.success),
      AdStatus.rejected => (AppColors.error.withOpacity(.18), AppColors.error),
      AdStatus.paused => (AppColors.info.withOpacity(.18), AppColors.info),
      AdStatus.archived => (AppColors.textMuted.withOpacity(.12), AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(status.label,
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}