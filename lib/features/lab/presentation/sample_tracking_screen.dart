import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/glass_card.dart';

class SampleTrackingScreen extends StatelessWidget {
  const SampleTrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stages = ['Ordered', 'Collected', 'Processing', 'Ready'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Sample Tracking')),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final current = i + 1;
          return GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sample #S-${200 + i}',
                    style: AppTextStyles.h3),
                const SizedBox(height: 4),
                Text('Patient: Rahul Mehta',
                    style: AppTextStyles.bodyMuted),
                const SizedBox(height: 16),
                Row(
                  children: List.generate(stages.length, (idx) {
                    final active = idx <= current;
                    return Expanded(
                      child: Column(
                        children: [
                          Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.labAccent
                                  : AppColors.cardBorder,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            stages[idx],
                            style: AppTextStyles.caption.copyWith(
                              color: active
                                  ? AppColors.textPrimary
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}