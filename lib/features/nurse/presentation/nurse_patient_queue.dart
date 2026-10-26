import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/services/dashboard_service.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';

class NursePatientQueue extends ConsumerWidget {
  const NursePatientQueue({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apptAsync = ref.watch(todayAppointmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(title: 'Patient Queue'),
      body: SafeArea(
        child: apptAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(
                icon: Icons.queue_rounded,
                title: 'No patients yet',
                subtitle:
                    'Today\'s appointments will appear here as they come in.',
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final a = list[i];
                final color = _statusColor(a.status);
                return GlassCard(
                  borderColor: color.withOpacity(0.4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(a.tokenLabel,
                            style: AppTextStyles.caption
                                .copyWith(color: color)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.patientName,
                                style: AppTextStyles.body),
                            const SizedBox(height: 2),
                            Text(
                              '${a.patientId} • ${DateFormat('hh:mm a').format(a.slot)}',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(a.statusLabel,
                            style: AppTextStyles.caption
                                .copyWith(color: color)),
                      ),
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

  Color _statusColor(AppointmentStatus s) {
    switch (s) {
      case AppointmentStatus.confirmed:
        return AppColors.success;
      case AppointmentStatus.checkedIn:
        return AppColors.info;
      case AppointmentStatus.inConsult:
        return AppColors.accent;
      case AppointmentStatus.completed:
        return AppColors.success;
      case AppointmentStatus.declined:
      case AppointmentStatus.cancelled:
        return AppColors.error;
      case AppointmentStatus.booked:
        return AppColors.warning;
      default:
        return AppColors.textMuted;
    }
  }
}