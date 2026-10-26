import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/models/disposition.dart';
import '../../../core/models/lab_order_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../domain/patient_history.dart';
import 'doctor_providers.dart';
import 'lab_order_history_screen.dart';

final patientHistoryProvider =
    StreamProvider.autoDispose.family<PatientHistory, String>((ref, id) {
  return ref.read(patientHistoryServiceProvider).watchPatientHistory(id);
});

class PatientHistoryScreen extends ConsumerWidget {
  final String patientDocId;
  final String? patientNameHint;

  const PatientHistoryScreen({
    super.key,
    required this.patientDocId,
    this.patientNameHint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(patientHistoryProvider(patientDocId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: historyAsync.maybeWhen(
          data: (h) => Text(h.patientName, style: AppTextStyles.h3),
          orElse: () =>
              Text(patientNameHint ?? 'Patient history',
                  style: AppTextStyles.h3),
        ),
      ),
      body: historyAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text('Failed: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (h) => RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async =>
              ref.invalidate(patientHistoryProvider(patientDocId)),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryCard(h),
                const SizedBox(height: 16),
                _resumeButton(context, ref, h),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Last visit'),
                const SizedBox(height: 8),
                _lastVisitCard(h),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Active tests ordered'),
                const SizedBox(height: 8),
                _activeTests(context, h),
                const SizedBox(height: 24),
                const SectionHeader(title: 'Timeline'),
                const SizedBox(height: 8),
                _timeline(h),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resumeButton(
      BuildContext context, WidgetRef ref, PatientHistory h) {
    AppointmentModel? live;
    for (final a in h.appointments) {
      if (a.status == AppointmentStatus.checkedIn ||
          a.status == AppointmentStatus.inConsult) {
        live = a;
        break;
      }
    }
    if (live == null) return const SizedBox.shrink();

    return GlassCard(
      borderColor: AppColors.doctorAccent.withOpacity(.4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          ref.read(selectedAppointmentProvider.notifier).state = live;
          ref.read(doctorTabProvider.notifier).state = 1;
          Navigator.of(context).popUntil((r) => r.isFirst);
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.doctorAccent.withOpacity(.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: AppColors.doctorAccent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Resume in-progress consultation',
                      style: AppTextStyles.body),
                  const SizedBox(height: 2),
                  Text(live.statusLabel, style: AppTextStyles.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }

  Widget _summaryCard(PatientHistory h) {
    final totalVisits = h.appointments
        .where((a) => a.status == AppointmentStatus.completed)
        .length;
    final totalTests = h.allTests.length;

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
              child: Text(
                _initials(h.patientName),
                style: AppTextStyles.h3
                    .copyWith(color: AppColors.doctorAccent),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.patientName, style: AppTextStyles.h2),
                  const SizedBox(height: 3),
                  Text('ID: ${h.patientCode}',
                      style: AppTextStyles.caption),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _metric('Visits', '$totalVisits')),
            Expanded(child: _metric('Tests', '$totalTests')),
            Expanded(
              child: _metric(
                'Pending',
                '${h.pendingTests.length}',
                color: h.pendingTests.isEmpty
                    ? AppColors.success
                    : AppColors.warning,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: AppTextStyles.h2
                .copyWith(color: color ?? AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Widget _lastVisitCard(PatientHistory h) {
    final last = h.lastConsultation;
    final visit = h.lastVisit;

    if (last == null && visit == null) {
      return GlassCard(
        child: Column(children: [
          const Icon(Icons.history_toggle_off_rounded,
              size: 34, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text('No previous visits', style: AppTextStyles.h3),
          const SizedBox(height: 4),
          Text('This will be the first consultation.',
              style: AppTextStyles.bodyMuted),
        ]),
      );
    }

    final when = last?.startedAt ?? last?.createdAt ?? visit!.slot;
    final disp = dispositionFromString(last?.disposition);

    return GlassCard(
      borderColor: AppColors.info.withOpacity(.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.event_note_rounded,
                size: 18, color: AppColors.info),
            const SizedBox(width: 8),
            Text(
              DateFormat('EEE, dd MMM yyyy • hh:mm a').format(when),
              style: AppTextStyles.caption,
            ),
            const Spacer(),
            if (disp != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.doctorAccent.withOpacity(.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  disp.label,
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.doctorAccent,
                      fontWeight: FontWeight.w600),
                ),
              ),
          ]),
          if (visit?.consultationFees != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Fees ₹${visit!.consultationFees!.toStringAsFixed(0)} · '
                '${visit.paymentStatusLabel}',
                style: AppTextStyles.caption.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (last != null) ...[
            _field('Chief complaint', last.chiefComplaint),

            // ── ICD-10 coded diagnosis, with free-text fallback ──
            if ((last.diagnosisCode ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              _icdField(last.diagnosisCode!, last.diagnosisText),
            ] else if (last.diagnosis?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              _field('Diagnosis', last.diagnosis),
            ],

            if (last.symptoms?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              _field('Symptoms', last.symptoms),
            ],
            if (last.vitals.isNotEmpty) ...[
              const SizedBox(height: 10),
              _field(
                'Vitals',
                last.vitals.entries
                    .map((e) => '${e.key}: ${e.value}')
                    .join('  •  '),
              ),
            ],
            const SizedBox(height: 10),
            _field("Doctor's note", last.notes),
            if (last.rx != null && last.rx!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _field('Prescription', last.rx!),
            ],
            if (last.medications.isNotEmpty) ...[
              const SizedBox(height: 10),
              _field(
                'Medications',
                last.medications
                    .map((m) =>
                        '${m.name} ${m.dose} ${m.frequency}'.trim())
                    .join('  •  '),
              ),
            ],
            if (last.followUpPlan != null &&
                last.followUpPlan!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              _field('Follow-up plan', last.followUpPlan!),
            ],
          ] else ...[
            _field('Chief complaint',
                visit!.chiefComplaint ?? 'Not recorded'),
            const SizedBox(height: 10),
            _field('Status', visit.statusLabel),
          ],
        ],
      ),
    );
  }

  Widget _field(String label, String? value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.caption
                .copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          (value == null || value.trim().isEmpty) ? '—' : value,
          style: AppTextStyles.body,
        ),
      ],
    );
  }

  /// ICD-10 coded diagnosis — code in a pill, description below.
  Widget _icdField(String code, String? description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Diagnosis (ICD-10)',
            style: AppTextStyles.caption
                .copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                code,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.info,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                description ?? '',
                style: AppTextStyles.body,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _activeTests(BuildContext context, PatientHistory h) {
    // ── Report-release gate ──
    // Only show lab orders whose report is either:
    //   - NOT yet ready (in-progress pipeline), OR
    //   - ready AND released by the receptionist.
    //
    // Excludes reports that are in `ready` state but unreleased — the
    // patient and doctor should not see them until the receptionist
    // has settled payment and released.
    final visible = h.pendingTests.where((o) {
      if (o.status == LabOrderStatus.ready && !o.released) return false;
      return true;
    }).toList();

    if (visible.isEmpty) {
      return GlassCard(
        child: Text('No active lab orders for this patient.',
            style: AppTextStyles.bodyMuted),
      );
    }
    return Column(
      children: visible
          .map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _labRow(context, h, o),
              ))
          .toList(),
    );
  }

  Widget _labRow(
      BuildContext context, PatientHistory h, LabOrderModel o) {
    final color = switch (o.status) {
      LabOrderStatus.ready => AppColors.success,
      LabOrderStatus.processing => AppColors.warning,
      LabOrderStatus.cancelled || LabOrderStatus.noShow =>
        AppColors.error,
      _ => AppColors.info,
    };
    final dateLabel = o.orderedAt == null
        ? '—'
        : DateFormat('dd MMM').format(o.orderedAt!);
    return GlassCard(
      borderColor: color.withOpacity(.35),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LabOrderHistoryScreen(
              patientDocId: h.patientDocId,
            ),
          ),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withOpacity(.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.science_outlined, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.testsSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body),
                const SizedBox(height: 2),
                Text('${o.labName} • $dateLabel',
                    style: AppTextStyles.caption),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(.13),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(o.statusLabel,
                style:
                    AppTextStyles.caption.copyWith(color: color)),
          ),
        ]),
      ),
    );
  }

  Widget _timeline(PatientHistory h) {
    final entries = h.timeline;
    if (entries.isEmpty) {
      return GlassCard(
        child: Text('No consultation history yet.',
            style: AppTextStyles.bodyMuted),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          _timelineTile(entries[i], isLast: i == entries.length - 1),
      ],
    );
  }

  Widget _timelineTile(HistoryEntry e, {required bool isLast}) {
    final isConsult = e.consult != null;
    final title = isConsult
        ? (e.consult!.chiefComplaint?.trim().isNotEmpty == true
            ? e.consult!.chiefComplaint!
            : 'Consultation')
        : (e.visit!.chiefComplaint ?? e.visit!.statusLabel);
    final subtitle = isConsult
        ? (e.consult!.notes ?? 'No notes')
        : '${e.visit!.statusLabel} • '
            '${(e.visit!.type ?? '').replaceAll('_', ' ')}';

    final dotColor =
        isConsult ? AppColors.doctorAccent : AppColors.info;

    final icdCode = isConsult ? e.consult!.diagnosisCode : null;
    final icdText = isConsult ? e.consult!.diagnosisText : null;
    final disp = isConsult
        ? dispositionFromString(e.consult!.disposition)
        : null;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            if (!isLast)
              Expanded(
                child: Container(width: 2, color: AppColors.surface),
              ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: GlassCard(
                borderColor: dotColor.withOpacity(.25),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(
                        DateFormat('dd MMM yyyy • hh:mm a')
                            .format(e.when),
                        style: AppTextStyles.caption,
                      ),
                      const Spacer(),
                      if (disp != null) ...[
                        Text(
                          disp.label,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.doctorAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        isConsult ? 'Consult' : 'Visit',
                        style: AppTextStyles.caption.copyWith(
                          color: dotColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.h3),

                    // ── ICD-10 chip on timeline tile ──
                    if ((icdCode ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.info.withOpacity(.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            icdCode!,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.info,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            icdText ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption,
                          ),
                        ),
                      ]),
                    ],

                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMuted),
                    if (isConsult &&
                        (e.consult!.rx?.isNotEmpty ?? false)) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.medication_rounded,
                            size: 13, color: AppColors.info),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            e.consult!.rx!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption,
                          ),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}