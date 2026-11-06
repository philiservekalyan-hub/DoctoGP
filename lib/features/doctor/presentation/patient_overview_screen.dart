// lib/features/doctor/presentation/patient_overview_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/models/consultation_model.dart';
import '../../../core/models/disposition.dart';
import '../../../core/models/lab_order_model.dart';
import '../../../core/models/patient_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../domain/patient_history.dart';
import 'doctor_providers.dart';

class PatientOverviewScreen extends ConsumerWidget {
  final PatientModel patient;
  const PatientOverviewScreen({super.key, required this.patient});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync =
        ref.watch(patientHistoryProvider(patient.docId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(patient.fullName),
      ),
      body: historyAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$e',
                style: const TextStyle(color: AppColors.error)),
          ),
        ),
        data: (history) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            _ProfileSection(patient: patient),
            _AllergiesSection(patient: patient),
            _ChronicConditionsSection(patient: patient),
            _CurrentMedicationsSection(patient: patient),
            _PastMedicalSection(patient: patient),
            _LifestyleSection(patient: patient),
            _DoctorNotesSection(patient: patient),
            _VisitHistorySection(history: history),
            _LabOrdersSection(history: history),
          ],
        ),
      ),
      bottomNavigationBar: _StartBar(patient: patient),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Sections
// ─────────────────────────────────────────────────────────────────

class _ProfileSection extends StatelessWidget {
  final PatientModel patient;
  const _ProfileSection({required this.patient});

  @override
  Widget build(BuildContext context) {
    final initial = patient.fullName.isNotEmpty
        ? patient.fullName[0].toUpperCase()
        : '?';
    return GlassCard(
      borderColor: AppColors.doctorAccent.withOpacity(.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 26,
              backgroundColor:
                  AppColors.doctorAccent.withOpacity(.15),
              child: Text(initial,
                  style: AppTextStyles.h3
                      .copyWith(color: AppColors.doctorAccent)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(patient.fullName, style: AppTextStyles.h2),
                  const SizedBox(height: 3),
                  Text('${patient.patientId} • ${patient.phone}',
                      style: AppTextStyles.caption),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _infoRow('Gender', patient.gender),
          if (patient.dob != null)
            _infoRow(
              'Date of birth',
              '${DateFormat('dd MMM yyyy').format(patient.dob!)} '
              '(${_age(patient.dob!)} yrs)',
            ),
          if (patient.bloodGroup != null &&
              patient.bloodGroup!.isNotEmpty)
            _infoRow('Blood group', patient.bloodGroup!),
          if (patient.email != null && patient.email!.isNotEmpty)
            _infoRow('Email', patient.email!),
          if (patient.address != null && patient.address!.isNotEmpty)
            _infoRow('Address',
                [patient.address, patient.city, patient.pincode]
                    .whereType<String>()
                    .where((s) => s.isNotEmpty)
                    .join(', ')),
          if (patient.emergencyContactName != null &&
              patient.emergencyContactName!.isNotEmpty)
            _infoRow(
              'Emergency contact',
              [
                patient.emergencyContactName,
                patient.emergencyContactPhone,
              ].whereType<String>().where((s) => s.isNotEmpty).join(' • '),
            ),
        ],
      ),
    );
  }

  String _age(DateTime dob) {
    final now = DateTime.now();
    var years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return '$years';
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: AppTextStyles.caption),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.bodyMuted),
          ),
        ],
      ),
    );
  }
}

class _AllergiesSection extends StatelessWidget {
  final PatientModel patient;
  const _AllergiesSection({required this.patient});

  @override
  Widget build(BuildContext context) {
    if (patient.allergies.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Allergies'),
          const SizedBox(height: 8),
          GlassCard(
            borderColor: AppColors.error.withOpacity(.35),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: patient.allergies.map((a) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(a,
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600)),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChronicConditionsSection extends StatelessWidget {
  final PatientModel patient;
  const _ChronicConditionsSection({required this.patient});

  @override
  Widget build(BuildContext context) {
    if (patient.chronicConditions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Chronic conditions'),
          const SizedBox(height: 8),
          GlassCard(
            borderColor: AppColors.warning.withOpacity(.35),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: patient.chronicConditions.map((c) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(c,
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600)),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentMedicationsSection extends StatelessWidget {
  final PatientModel patient;
  const _CurrentMedicationsSection({required this.patient});

  @override
  Widget build(BuildContext context) {
    final meds = patient.currentMedications
        .map((m) => Medication.fromMap(m))
        .where((m) => m.name.isNotEmpty)
        .toList();
    if (meds.isEmpty &&
        (patient.currentMedicationNotes ?? '').isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Current medications'),
          const SizedBox(height: 8),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (meds.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: meds.map((m) {
                      final label = [
                        m.name,
                        m.dose,
                        m.frequency,
                        m.duration,
                      ].where((s) => s.isNotEmpty).join(' · ');
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.info.withOpacity(.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(label,
                            style: AppTextStyles.caption.copyWith(
                                color: AppColors.info,
                                fontWeight: FontWeight.w600)),
                      );
                    }).toList(),
                  ),
                if ((patient.currentMedicationNotes ?? '').isNotEmpty) ...[
                  if (meds.isNotEmpty) const SizedBox(height: 10),
                  Text(patient.currentMedicationNotes!,
                      style: AppTextStyles.bodyMuted),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PastMedicalSection extends StatelessWidget {
  final PatientModel patient;
  const _PastMedicalSection({required this.patient});

  @override
  Widget build(BuildContext context) {
    final items = <(String, List<Map<String, dynamic>>)>[
      ('Past medical history', patient.pastMedicalHistory),
      ('Past surgeries', patient.pastSurgeries),
      ('Past treatments', patient.pastTreatments),
    ].where((e) => e.$2.isNotEmpty).toList();

    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Past medical history'),
          const SizedBox(height: 8),
          for (final (title, list) in items) ...[
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.label),
                  const SizedBox(height: 6),
                  ...list.map((m) {
                    final label = m.entries
                        .where((e) => e.value != null &&
                            e.value.toString().isNotEmpty)
                        .map((e) =>
                            '${_title(e.key)}: ${e.value}')
                        .join(' · ');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.circle,
                              size: 6, color: AppColors.textMuted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(label,
                                style: AppTextStyles.bodyMuted),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  String _title(String key) {
    if (key.isEmpty) return key;
    return key[0].toUpperCase() + key.substring(1);
  }
}

class _LifestyleSection extends StatelessWidget {
  final PatientModel patient;
  const _LifestyleSection({required this.patient});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[];
    if ((patient.smoking ?? '').isNotEmpty) {
      rows.add(('Smoking', patient.smoking!));
    }
    if ((patient.alcohol ?? '').isNotEmpty) {
      rows.add(('Alcohol', patient.alcohol!));
    }
    if ((patient.diet ?? '').isNotEmpty) {
      rows.add(('Diet', patient.diet!));
    }
    if ((patient.activityLevel ?? '').isNotEmpty) {
      rows.add(('Activity level', patient.activityLevel!));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Lifestyle'),
          const SizedBox(height: 8),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      SizedBox(
                        width: 110,
                        child: Text(label,
                            style: AppTextStyles.caption),
                      ),
                      Expanded(
                        child: Text(value,
                            style: AppTextStyles.bodyMuted),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorNotesSection extends StatelessWidget {
  final PatientModel patient;
  const _DoctorNotesSection({required this.patient});

  @override
  Widget build(BuildContext context) {
    if ((patient.doctorNotes ?? '').isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Doctor notes'),
          const SizedBox(height: 8),
          GlassCard(child: Text(patient.doctorNotes!,
              style: AppTextStyles.bodyMuted)),
        ],
      ),
    );
  }
}

class _VisitHistorySection extends StatelessWidget {
  final PatientHistory history;
  const _VisitHistorySection({required this.history});

  @override
  Widget build(BuildContext context) {
    final timeline = history.timeline;
    if (timeline.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Visit history'),
          const SizedBox(height: 8),
          for (final e in timeline.take(30))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TimelineCard(entry: e),
            ),
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  final HistoryEntry entry;
  const _TimelineCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = entry.consult;
    final a = entry.visit;
    final title = c != null
        ? (c.chiefComplaint?.trim().isNotEmpty == true
            ? c.chiefComplaint!
            : 'Consultation')
        : (a?.chiefComplaint?.trim().isNotEmpty == true
            ? a!.chiefComplaint!
            : 'Visit');
    final isConsult = c != null;
    final disp = c != null
        ? dispositionFromString(c.disposition)
        : null;

    return GlassCard(
      borderColor: (isConsult ? AppColors.doctorAccent : AppColors.info)
          .withOpacity(.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              isConsult
                  ? Icons.medical_services_outlined
                  : Icons.event_note_rounded,
              size: 16,
              color: isConsult
                  ? AppColors.doctorAccent
                  : AppColors.info,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                DateFormat('dd MMM yyyy · hh:mm a')
                    .format(entry.when),
                style: AppTextStyles.caption,
              ),
            ),
            if (disp != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:
                      AppColors.doctorAccent.withOpacity(.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(disp.label,
                    style: AppTextStyles.caption.copyWith(
                        color: AppColors.doctorAccent,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 6),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body
                  .copyWith(fontWeight: FontWeight.w600)),
          if (c != null) ...[
            if ((c.diagnosisCode ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(c.diagnosisCode!,
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.info,
                          fontWeight: FontWeight.w700,
                          fontSize: 10)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(c.diagnosisText ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption),
                ),
              ]),
            ],
            if (c.medications.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final m in c.medications.take(4))
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(.10),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${m.name}${m.dose.isNotEmpty ? ' · ${m.dose}' : ''}',
                      style: AppTextStyles.caption
                          .copyWith(fontSize: 10),
                    ),
                  ),
              ]),
            ],
          ],
        ],
      ),
    );
  }
}

class _LabOrdersSection extends StatelessWidget {
  final PatientHistory history;
  const _LabOrdersSection({required this.history});

  @override
  Widget build(BuildContext context) {
    final orders = history.labOrders;
    if (orders.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Lab orders'),
          const SizedBox(height: 8),
          for (final o in orders.take(20))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LabOrderRow(order: o),
            ),
        ],
      ),
    );
  }
}

class _LabOrderRow extends StatelessWidget {
  final LabOrderModel order;
  const _LabOrderRow({required this.order});

  Color get _statusColor {
    switch (order.status) {
      case LabOrderStatus.ready:
      case LabOrderStatus.delivered:
        return AppColors.success;
      case LabOrderStatus.processing:
        return AppColors.warning;
      case LabOrderStatus.cancelled:
      case LabOrderStatus.noShow:
        return AppColors.error;
      default:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: _statusColor.withOpacity(.35),
      child: Row(children: [
        Icon(Icons.science_outlined, color: _statusColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.testsSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body,
              ),
              const SizedBox(height: 2),
              Text(
                [
                  order.labName,
                  if (order.orderedAt != null)
                    DateFormat('dd MMM')
                        .format(order.orderedAt!),
                ].join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _statusColor.withOpacity(.13),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(order.statusLabel,
              style: AppTextStyles.caption
                  .copyWith(color: _statusColor)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Start consultation bar
// ─────────────────────────────────────────────────────────────────
class _StartBar extends ConsumerStatefulWidget {
  final PatientModel patient;
  const _StartBar({required this.patient});

  @override
  ConsumerState<_StartBar> createState() => _StartBarState();
}

class _StartBarState extends ConsumerState<_StartBar> {
  bool _busy = false;

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final user = await ref.read(currentUserProvider.future);
      if (user == null || user.clinicId == null) {
        throw StateError('No clinic linked.');
      }

      final active = await _findActiveAppointment(
        doctorDocId: user.uid,
        patientDocId: widget.patient.docId,
      );

      if (active != null) {
        // Use existing appointment
        if (active.status == AppointmentStatus.checkedIn) {
          await ref
              .read(appointmentServiceProvider)
              .startConsult(active.docId);
        }
        ref.read(selectedAppointmentProvider.notifier).state = active;
      } else {
        // Create walk-in appointment
        final appt = await ref
            .read(appointmentServiceProvider)
            .bookWalkInConsultation(
              clinicId: user.clinicId!,
              patientDocId: widget.patient.docId,
              patientId: widget.patient.patientId,
              patientName: widget.patient.fullName,
              patientPhone: widget.patient.phone,
              doctorDocId: user.uid,
              doctorName: user.name,
            );
        ref.read(selectedAppointmentProvider.notifier).state = appt;
      }

      ref.read(doctorTabProvider.notifier).state = 1;

      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not start consultation: $e'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<AppointmentModel?> _findActiveAppointment({
    required String doctorDocId,
    required String patientDocId,
  }) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    final snap = await ref
        .read(appointmentServiceProvider)
        .watchDoctorQueue(doctorDocId: doctorDocId, date: now)
        .first;

    for (final a in snap) {
      if (a.patientDocId == patientDocId &&
          a.slot.isAfter(start) &&
          a.slot.isBefore(end) &&
          (a.status == AppointmentStatus.checkedIn ||
              a.status == AppointmentStatus.inConsult)) {
        return a;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
            top: BorderSide(color: AppColors.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _start,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(_busy
                ? 'Starting…'
                : 'Start consultation'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }
}