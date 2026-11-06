// lib/features/doctor/presentation/consult_tab.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/widgets/glass_card.dart';
import 'doctor_providers.dart';
import 'emergency_patient_search_screen.dart';

/// Tab 1 of the doctor shell when no appointment is selected.
///
/// Primary view: today's active appointment queue (checked-in /
/// in-consult), sorted by queue position. This is the normal
/// reception-driven flow.
///
/// Secondary action: an "Emergency" button (FAB + AppBar icon)
/// that opens the patient search → 360° overview → start walk-in
/// consultation flow.
class ConsultTab extends ConsumerWidget {
  const ConsultTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(doctorTodayAppointmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Consultation'),
        actions: [
          IconButton(
            tooltip: 'Emergency patient',
            icon: const Icon(Icons.person_search_rounded,
                color: AppColors.error),
            onPressed: () => _openEmergencySearch(context),
          ),
        ],
      ),
      body: SafeArea(
        child: queueAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('$e',
                  style: const TextStyle(color: AppColors.error)),
            ),
          ),
          data: (all) {
            final active = all
                .where((a) =>
                    a.status == AppointmentStatus.checkedIn ||
                    a.status == AppointmentStatus.inConsult)
                .toList()
              ..sort((a, b) {
                // inConsult first, then by token
                if (a.status == AppointmentStatus.inConsult &&
                    b.status != AppointmentStatus.inConsult) {
                  return -1;
                }
                if (b.status == AppointmentStatus.inConsult &&
                    a.status != AppointmentStatus.inConsult) {
                  return 1;
                }
                return a.tokenNumber.compareTo(b.tokenNumber);
              });

            if (active.isEmpty) {
              return _EmptyState(
                onEmergency: () => _openEmergencySearch(context),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Ready to consult', style: AppTextStyles.h2),
                const SizedBox(height: 4),
                Text(
                  'Pick a checked-in patient to start or resume.',
                  style: AppTextStyles.bodyMuted,
                ),
                const SizedBox(height: 16),
                for (final a in active)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _QueueTile(appointment: a),
                  ),
                const SizedBox(height: 80), // space for FAB
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEmergencySearch(context),
        backgroundColor: AppColors.error,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.emergency_rounded),
        label: const Text('Emergency'),
      ),
    );
  }

  void _openEmergencySearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const EmergencyPatientSearchScreen(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Queue tile
// ─────────────────────────────────────────────────────────────────
class _QueueTile extends ConsumerWidget {
  final AppointmentModel appointment;
  const _QueueTile({required this.appointment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isInConsult =
        appointment.status == AppointmentStatus.inConsult;
    final color = isInConsult ? AppColors.warning : AppColors.info;

    return GlassCard(
      borderColor: color.withOpacity(.35),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          ref.read(selectedAppointmentProvider.notifier).state =
              appointment;
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                appointment.tokenLabel,
                style: AppTextStyles.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appointment.patientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${appointment.patientId} • ${appointment.statusLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(.13),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isInConsult ? 'Resume' : 'Start',
                style: AppTextStyles.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onEmergency;
  const _EmptyState({required this.onEmergency});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.medical_services_outlined,
                size: 56, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text('No patients in queue',
                style: AppTextStyles.h3, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Checked-in patients from reception will appear here.\n'
              'For an emergency patient without an appointment, tap '
              'the red button below.',
              style: AppTextStyles.bodyMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onEmergency,
              icon: const Icon(Icons.person_search_rounded,
                  color: AppColors.error),
              label: const Text('Search emergency patient',
                  style: TextStyle(color: AppColors.error)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: AppColors.error.withOpacity(.4)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}