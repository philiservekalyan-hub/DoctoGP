// lib/features/admin/presentation/admin_dashboard.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/services/admin_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';
import 'canonical_tests_screen.dart';
import 'chemists_admin_screen.dart';
import 'ads_admin_screen.dart';

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final clinicsAsync = ref.watch(allClinicsProvider);
    final chemistsAsync = ref.watch(allChemistsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(title: 'Admin Overview'),
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (user) => RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(allClinicsProvider);
              ref.invalidate(allChemistsProvider);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
  'Welcome, STAT Admin',
  style: AppTextStyles.h2,
),
                  const SizedBox(height: 4),
                  Text('Manage clinics, labs, and chemists on the platform',
                      style: AppTextStyles.bodyMuted),
                  const SizedBox(height: 24),

                  clinicsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (entities) {
                      final clinics =
                          entities.where((e) => !e.isLab).toList();
                      final labs = entities.where((e) => e.isLab).toList();
                      final active =
                          entities.where((e) => e.active).length;
                      final inactive = entities.length - active;

                      return Column(
                        children: [
                          Row(children: [
                            Expanded(
                              child: StatCard(
                                label: 'Clinics',
                                value: clinics.length
                                    .toString()
                                    .padLeft(2, '0'),
                                icon: Icons.local_hospital_rounded,
                                accent: AppColors.secondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: StatCard(
                                label: 'Labs',
                                value: labs.length
                                    .toString()
                                    .padLeft(2, '0'),
                                icon: Icons.science_rounded,
                                accent: AppColors.labAccent,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: StatCard(
                                label: 'Active',
                                value: active
                                    .toString()
                                    .padLeft(2, '0'),
                                icon: Icons.check_circle_rounded,
                                accent: AppColors.success,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: StatCard(
                                label: 'Inactive',
                                value: inactive
                                    .toString()
                                    .padLeft(2, '0'),
                                icon: Icons.pause_circle_rounded,
                                accent: AppColors.warning,
                              ),
                            ),
                          ]),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 24),
                  chemistsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (chemists) {
                      final active = chemists.where((c) => c.isActive).length;
                      final inactive = chemists.length - active;
                      final delivering =
                          chemists.where((c) => c.deliveryAvailable).length;

                      return Row(children: [
                        Expanded(
                          child: StatCard(
                            label: 'Chemists',
                            value: chemists.length
                                .toString()
                                .padLeft(2, '0'),
                            icon: Icons.local_pharmacy_rounded,
                            accent: AppColors.patientAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            label: 'Delivering',
                            value: delivering
                                .toString()
                                .padLeft(2, '0'),
                            icon: Icons.delivery_dining_rounded,
                            accent: AppColors.info,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            label: 'Inactive',
                            value: inactive
                                .toString()
                                .padLeft(2, '0'),
                            icon: Icons.pause_circle_rounded,
                            accent: AppColors.warning,
                          ),
                        ),
                      ]);
                    },
                  ),

                  const SizedBox(height: 28),
                  const SectionHeader(title: 'Manage'),
                  GlassCard(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CanonicalTestsScreen(),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.list_alt_rounded,
                                color: AppColors.primary, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text('Test catalogue',
                                    style: AppTextStyles.body),
                                const SizedBox(height: 2),
                                Text(
                                  'Create and manage canonical tests across all labs',
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.textMuted),
                        ]),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                  GlassCard(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ChemistsAdminScreen(),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.patientAccent.withOpacity(.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                                Icons.local_pharmacy_rounded,
                                color: AppColors.patientAccent,
                                size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text('Chemists',
                                    style: AppTextStyles.body),
                                const SizedBox(height: 2),
                                Text(
                                  'Add vetted pharmacies, set UPI, '
                                  'delivery range, and serviceable pincodes',
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.textMuted),
                        ]),
                      ),
                    ),
                  ),

const SizedBox(height: 10),
GlassCard(
  child: InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdsAdminScreen()),
    ),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.campaign_rounded,
              color: AppColors.info, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sponsored offers', style: AppTextStyles.body),
              const SizedBox(height: 2),
              Text(
                'Upload PNG creatives, schedule patient-dashboard ads, approve submissions',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      ]),
    ),
  ),
),

                  const SizedBox(height: 28),
                  const SectionHeader(title: 'Recent'),
                  clinicsAsync.when(
                    loading: () => const Center(
                        child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                          color: AppColors.primary),
                    )),
                    error: (e, _) => GlassCard(
                        child: Text('Error: $e',
                            style: const TextStyle(
                                color: AppColors.error))),
                    data: (entities) {
                      if (entities.isEmpty) {
                        return const GlassCard(
                          child: Text(
                            'No clinics or labs yet. Use the Create tab to add the first one.',
                            style:
                                TextStyle(color: AppColors.textMuted),
                          ),
                        );
                      }
                      return Column(
                        children: entities.take(3).map((c) {
                          final isLab = c.isLab;
                          final accent = isLab
                              ? AppColors.labAccent
                              : AppColors.secondary;
                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: 10),
                            child: GlassCard(
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          accent,
                                          accent.withOpacity(.6),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isLab
                                          ? Icons.science_rounded
                                          : Icons
                                              .local_hospital_rounded,
                                      color: AppColors.background,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(c.name,
                                            style: AppTextStyles.h3),
                                        Text(
                                            c.address ??
                                                'No address',
                                            style: AppTextStyles
                                                .caption),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}