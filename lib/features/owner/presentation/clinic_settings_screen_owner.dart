import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/services/clinic_service.dart';
import '../../../shared/widgets/clinic_app_bar.dart';

class OwnerClinicSettingsScreen extends ConsumerWidget {
  const OwnerClinicSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicAsync = ref.watch(currentClinicProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(title: 'Clinic'),
      body: SafeArea(
        child: clinicAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (clinic) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (clinic == null)
                const Text('Clinic not found',
                    style: TextStyle(color: AppColors.textMuted))
              else ...[
                Text(clinic.name, style: AppTextStyles.h1),
                const SizedBox(height: 8),
                Text(clinic.address ?? 'No address',
                    style: AppTextStyles.bodyMuted),
                const SizedBox(height: 4),
                Text(clinic.phone ?? 'No phone',
                    style: AppTextStyles.bodyMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}