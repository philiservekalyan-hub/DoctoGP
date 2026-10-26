import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/services/dashboard_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';

class NurseDashboard extends ConsumerWidget {
  const NurseDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final apptAsync = ref.watch(todayAppointmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(title: 'Nurse Dashboard'),
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (user) => RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async =>
                ref.invalidate(todayAppointmentsProvider),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Hello, ${user?.name.split(" ").first ?? "there"}',
                      style: AppTextStyles.h1),
                  const SizedBox(height: 4),
                  Text('Ready for today\'s patients?',
                      style: AppTextStyles.bodyMuted),
                  const SizedBox(height: 24),

                  // Stats
                  Row(children: [
                    Expanded(
                      child: StatCard(
                        label: 'Waiting',
                        value: apptAsync.when(
                          data: (l) => l
                              .where((a) =>
                                  a.status ==
                                      AppointmentStatus.checkedIn ||
                                  a.status ==
                                      AppointmentStatus.confirmed)
                              .length
                              .toString()
                              .padLeft(2, '0'),
                          loading: () => '—',
                          error: (_, __) => '—',
                        ),
                        icon: Icons.hourglass_top_rounded,
                        accent: AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        label: 'In Consult',
                        value: apptAsync.when(
                          data: (l) => l
                              .where((a) =>
                                  a.status ==
                                  AppointmentStatus.inConsult)
                              .length
                              .toString()
                              .padLeft(2, '0'),
                          loading: () => '—',
                          error: (_, __) => '—',
                        ),
                        icon: Icons.medical_services_rounded,
                        accent: AppColors.doctorAccent,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: StatCard(
                        label: 'Completed',
                        value: apptAsync.when(
                          data: (l) => l
                              .where((a) =>
                                  a.status ==
                                  AppointmentStatus.completed)
                              .length
                              .toString()
                              .padLeft(2, '0'),
                          loading: () => '—',
                          error: (_, __) => '—',
                        ),
                        icon: Icons.check_circle_outline_rounded,
                        accent: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(child: SizedBox()),
                  ]),

                  const SizedBox(height: 28),
                  const SectionHeader(title: 'Quick Actions'),
                  _quickActions(context),

                  const SizedBox(height: 28),
                  const SectionHeader(title: 'Today\'s Snapshot'),
                  _todaySnapshot(apptAsync),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickActions(BuildContext context) {
    final actions = [
      _Action(
        icon: Icons.monitor_heart_outlined,
        label: 'Record Vitals',
        color: AppColors.nurseAccent,
        onTap: () {},
      ),
      _Action(
        icon: Icons.queue_rounded,
        label: 'View Queue',
        color: AppColors.info,
        onTap: () {},
      ),
      _Action(
        icon: Icons.medication_outlined,
        label: 'Medication Log',
        color: AppColors.accent,
        onTap: () {},
      ),
      _Action(
        icon: Icons.assignment_outlined,
        label: 'Notes',
        color: AppColors.secondary,
        onTap: () {},
      ),
    ];

    return GridView.builder(
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  itemCount: actions.length,
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    mainAxisExtent: 96,       
  ),
  itemBuilder: (_, i) {
    final a = actions[i];
    return GlassCard(
      onTap: a.onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(a.icon, color: a.color, size: 24),
          Flexible(
            child: Text(
              a.label,
              style: AppTextStyles.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  },
);
}

  Widget _todaySnapshot(AsyncValue<List<AppointmentModel>> apptAsync) {
    return apptAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return const GlassCard(
            child: Text('No appointments scheduled today.',
                style: TextStyle(color: AppColors.textMuted)),
          );
        }
        final preview = list.take(3).toList();
        return Column(
          children: preview
              .map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                AppColors.nurseAccent.withOpacity(0.2),
                            child: Text(
                              a.patientName.isNotEmpty
                                  ? a.patientName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  color: AppColors.nurseAccent),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(a.patientName,
                                    style: AppTextStyles.body),
                                Text(a.tokenLabel,
                                    style: AppTextStyles.caption),
                              ],
                            ),
                          ),
                          Text(a.statusLabel,
                              style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _Action {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  _Action({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}