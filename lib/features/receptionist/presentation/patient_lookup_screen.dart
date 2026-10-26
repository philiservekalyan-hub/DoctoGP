import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/services/reception_stats_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../shared/widgets/clinic_app_bar.dart';
import '../../shared/reschedule_appointment_dialog.dart';

class PatientLookupScreen extends ConsumerWidget {
  final String patientDocId;
  final String patientName;
  const PatientLookupScreen({
    super.key,
    required this.patientDocId,
    required this.patientName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apptsAsync =
        ref.watch(patientAppointmentsProvider(patientDocId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ClinicAppBar(
        title: patientName,
        showBackButton: true,
      ),
      body: SafeArea(
        child: apptsAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (appts) {
            final now = DateTime.now();
            final future = appts
                .where((a) => a.slot.isAfter(now))
                .where((a) =>
                    a.status != AppointmentStatus.cancelled &&
                    a.status != AppointmentStatus.declined &&
                    a.status != AppointmentStatus.noShow)
                .toList()
              ..sort((a, b) => a.slot.compareTo(b.slot));
            final past = appts
                .where((a) => a.slot.isBefore(now))
                .toList()
              ..sort((a, b) => b.slot.compareTo(a.slot));

            // Distinct doctor history
            final doctors = <String, _DoctorVisit>{};
            for (final a in past) {
              if (a.doctorName.isEmpty) continue;
              final key = a.doctorDocId;
              doctors.putIfAbsent(
                  key,
                  () => _DoctorVisit(name: a.doctorName));
              doctors[key]!.visits++;
              if (a.slot.isAfter(doctors[key]!.lastVisit)) {
                doctors[key]!.lastVisit = a.slot;
              }
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryRow(context, appts.length, future.length,
                      past.length),
                  const SizedBox(height: 24),

                  if (future.isNotEmpty) ...[
                    const SectionHeader(title: 'Upcoming'),
                    ...future.map((a) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _futureCard(context, ref, a),
                        )),
                    const SizedBox(height: 20),
                  ],

                  if (doctors.isNotEmpty) ...[
                    const SectionHeader(title: 'Doctors seen'),
                    ...doctors.values.map((d) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            child: Row(children: [
                              const Icon(Icons.medical_services_rounded,
                                  color: AppColors.doctorAccent, size: 18),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text('Dr. ${d.name}',
                                      style: AppTextStyles.body)),
                              Text('${d.visits} visit${d.visits == 1 ? '' : 's'}',
                                  style: AppTextStyles.caption),
                            ]),
                          ),
                        )),
                    const SizedBox(height: 20),
                  ],

                  const SectionHeader(title: 'History'),
                  if (past.isEmpty)
                    GlassCard(
                        child: Text('No past visits',
                            style: AppTextStyles.caption))
                  else
                    ...past.map((a) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _historyRow(a),
                        )),
                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _summaryRow(
          BuildContext context, int total, int future, int past) =>
      Row(children: [
        Expanded(child: _miniStat('Total', '$total')),
        const SizedBox(width: 10),
        Expanded(child: _miniStat('Upcoming', '$future')),
        const SizedBox(width: 10),
        Expanded(child: _miniStat('Past', '$past')),
      ]);

  Widget _miniStat(String label, String value) => GlassCard(
        child: Column(
          children: [
            Text(value, style: AppTextStyles.h2),
            const SizedBox(height: 2),
            Text(label, style: AppTextStyles.caption),
          ],
        ),
      );

  Widget _futureCard(
          BuildContext context, WidgetRef ref, AppointmentModel a) =>
      GlassCard(
        borderColor: AppColors.info.withOpacity(0.4),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('EEE, dd MMM · hh:mm a').format(a.slot),
                    style: AppTextStyles.body),
                const SizedBox(height: 2),
                Text(
                  'Dr. ${a.doctorName.isEmpty ? 'Unassigned' : a.doctorName}'
                  ' • ${a.tokenLabel} • ${a.statusLabel}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              final changed =
                  await showRescheduleDialog(context, ref, a);
              if (changed) {
                ref.invalidate(
                    patientAppointmentsProvider(patientDocId));
              }
            },
            child: const Text('Edit'),
          ),
        ]),
      );

  Widget _historyRow(AppointmentModel a) => GlassCard(
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('dd MMM yyyy · hh:mm a').format(a.slot),
                    style: AppTextStyles.body),
                const SizedBox(height: 2),
                Text(
                  'Dr. ${a.doctorName.isEmpty ? '—' : a.doctorName}'
                  ' • ${a.statusLabel}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          Text(a.tokenLabel, style: AppTextStyles.caption),
        ]),
      );
}

class _DoctorVisit {
  final String name;
  int visits = 0;
  DateTime lastVisit = DateTime(1970);
  _DoctorVisit({required this.name});
}