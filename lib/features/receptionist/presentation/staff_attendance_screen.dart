import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/glass_card.dart';

class StaffAttendanceScreen extends StatelessWidget {
  const StaffAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final staff = [
      ('Anita Rao', 'Receptionist', true),
      ('Vikram Joshi', 'Lab Tech', true),
      ('Sneha Kapoor', 'Nurse', false),
      ('Ravi Kumar', 'Support', true),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Staff Attendance')),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: staff.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final s = staff[i];
          return GlassCard(
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: s.$3
                      ? AppColors.success.withOpacity(0.2)
                      : AppColors.textMuted.withOpacity(0.2),
                  child: Text(s.$1[0],
                      style: TextStyle(
                          color: s.$3
                              ? AppColors.success
                              : AppColors.textMuted)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.$1, style: AppTextStyles.h3),
                      Text(s.$2, style: AppTextStyles.caption),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (s.$3 ? AppColors.success : AppColors.textMuted)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.$3 ? 'Present' : 'Absent',
                    style: AppTextStyles.caption.copyWith(
                      color: s.$3 ? AppColors.success : AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}