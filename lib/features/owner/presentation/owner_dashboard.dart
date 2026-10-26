import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';

class OwnerDashboard extends ConsumerWidget {
  const OwnerDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(title: 'Owner Dashboard'),
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (user) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome, ${user?.name.split(" ").first ?? "Owner"}',
                    style: AppTextStyles.h1),
                const SizedBox(height: 4),
                Text('Manage your clinic and team',
                    style: AppTextStyles.bodyMuted),
                const SizedBox(height: 24),
                Row(children: const [
                  Expanded(
                    child: StatCard(
                      label: 'Team Members',
                      value: '—',
                      icon: Icons.people_rounded,
                      accent: AppColors.secondary,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      label: 'Pending Invites',
                      value: '—',
                      icon: Icons.hourglass_top_rounded,
                      accent: AppColors.warning,
                    ),
                  ),
                ]),
                const SizedBox(height: 28),
                const GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Getting Started',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 8),
                      Text(
                        'Use the Team tab to invite receptionists, doctors, nurses, and lab technicians to your clinic.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}