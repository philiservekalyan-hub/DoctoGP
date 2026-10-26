// lib/features/admin/presentation/clinics_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/services/admin_service.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';

class ClinicsListScreen extends ConsumerWidget {
  const ClinicsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicsAsync = ref.watch(allClinicsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(title: 'Clinics & Labs'),
      body: SafeArea(
        child: clinicsAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (clinics) {
            if (clinics.isEmpty) {
              return const EmptyState(
                icon: Icons.local_hospital_outlined,
                title: 'No clinics or labs yet',
                subtitle:
                    'Create the first clinic or lab from the Create tab.',
              );
            }

            // Clinics first, then labs; alphabetical within each group
            final sorted = [...clinics]..sort((a, b) {
                if (a.isLab != b.isLab) return a.isLab ? 1 : -1;
                return a.name
                    .toLowerCase()
                    .compareTo(b.name.toLowerCase());
              });

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final c = sorted[i];
                final active = c.active;
                final isLab = c.isLab;
                final accent =
                    isLab ? AppColors.labAccent : AppColors.secondary;

                return GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: active
                                  ? LinearGradient(
                                      colors: [
                                        accent,
                                        accent.withOpacity(0.6),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : const LinearGradient(
                                      colors: [
                                        AppColors.textMuted,
                                        AppColors.cardBorder
                                      ],
                                    ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isLab
                                  ? Icons.science_rounded
                                  : Icons.local_hospital_rounded,
                              color: AppColors.background,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Flexible(
                                    child: Text(c.name,
                                        style: AppTextStyles.h3,
                                        overflow:
                                            TextOverflow.ellipsis),
                                  ),
                                  const SizedBox(width: 8),
                                  _typeChip(isLab, accent),
                                ]),
                                const SizedBox(height: 2),
                                Text(
                                  c.clinicCode ?? c.id,
                                  style: AppTextStyles.caption.copyWith(
                                    color: accent,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: active,
                            activeThumbColor: accent,
                            onChanged: (v) => ref
                                .read(adminServiceProvider)
                                .toggleClinicActive(c.id, v),
                          ),
                        ],
                      ),
                      if (c.address != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 14, color: AppColors.textMuted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(c.address!,
                                  style: AppTextStyles.caption),
                            ),
                          ],
                        ),
                      ],
                      if (c.phone != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined,
                                size: 14, color: AppColors.textMuted),
                            const SizedBox(width: 6),
                            Text(c.phone!,
                                style: AppTextStyles.caption),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _typeChip(bool isLab, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withOpacity(.13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isLab ? 'LAB' : 'CLINIC',
        style: AppTextStyles.caption.copyWith(
          color: accent,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}