// lib/features/doctor/presentation/consultation_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/models/consultation_model.dart';
import '../../../core/models/disposition.dart';
import '../../../core/models/icd10_code.dart';
import '../../../core/models/lab_order_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../domain/patient_history.dart';
import 'doctor_providers.dart';
import 'lab_order_create_screen.dart';
import 'widgets/icd10_search_field.dart';

final appointmentVitalsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>(
        (ref, appointmentDocId) {
  final collection = FirebaseFirestore.instance.collection('vitals');
  final query =
      collection.where('appointmentDocId', isEqualTo: appointmentDocId);
  return query.snapshots().map((snap) {
    final list = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      list.add(doc.data());
    }
    list.sort((a, b) {
      final ta = a['recordedAt'];
      final tb = b['recordedAt'];
      if (ta is! Timestamp || tb is! Timestamp) return 0;
      return tb.compareTo(ta);
    });
    return list;
  });
});

class ConsultationScreen extends ConsumerWidget {
  final AppointmentModel? appointment;
  final bool readOnly;

  const ConsultationScreen({
    super.key,
    this.appointment,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (appointment == null) return const _NoSelectionView();
    return _ConsultBody(
      appointment: appointment!,
      readOnly: readOnly,
    );
  }
}

// -----------------------------------------------------------------
// Empty state
// -----------------------------------------------------------------
class _NoSelectionView extends ConsumerWidget {
  const _NoSelectionView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(doctorTodayAppointmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Consultation')),
      body: SafeArea(
        child: queueAsync.when(
          loading: () => const Center(
              child:
                  CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(child: Text('$e')),
          data: (list) {
            final active = list
                .where((a) =>
                    a.status == AppointmentStatus.checkedIn ||
                    a.status == AppointmentStatus.inConsult)
                .toList()
              ..sort((a, b) => a.slot.compareTo(b.slot));

            if (active.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.medical_services_outlined,
                          size: 48, color: AppColors.textMuted),
                      const SizedBox(height: 16),
                      Text(
                        'No patient selected',
                        style: AppTextStyles.h3,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pick a patient from the Home tab to start a '
                        'consultation, or tap one from the list below.',
                        style: AppTextStyles.bodyMuted,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
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
                    child: GlassCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title:
                            Text(a.patientName, style: AppTextStyles.body),
                        subtitle: Text(
                            '${a.tokenLabel} • ${a.statusLabel}',
                            style: AppTextStyles.caption),
                        trailing:
                            const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          ref
                              .read(selectedAppointmentProvider.notifier)
                              .state = a;
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------
// Live consultation body
// -----------------------------------------------------------------
class _ConsultBody extends ConsumerStatefulWidget {
  final AppointmentModel appointment;
  final bool readOnly;
  const _ConsultBody({
    required this.appointment,
    required this.readOnly,
  });

  @override
  ConsumerState<_ConsultBody> createState() => _ConsultBodyState();
}

class _ConsultBodyState extends ConsumerState<_ConsultBody> {
  final _speech = stt.SpeechToText();
  bool _listening = false;
  bool _speechAvailable = false;
  String _rxBeforeDictation = '';

  final _rxController = TextEditingController();
  final _symptomsCtrl = TextEditingController();
  final _diagnosisCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _followUpCtrl = TextEditingController();
  final _meds = <_MedRow>[];

  // ── Phase 1 additions ──
  Icd10Code? _selectedIcd;
  Disposition? _selectedDisposition;

  bool _saving = false;
  bool _initialized = false;
  bool _openingLabOrder = false;

  @override
  void dispose() {
    _speech.stop();
    _rxController.dispose();
    _symptomsCtrl.dispose();
    _diagnosisCtrl.dispose();
    _notesCtrl.dispose();
    _followUpCtrl.dispose();
    for (final m in _meds) {
      m.dispose();
    }
    super.dispose();
  }

  void _hydrate(ConsultationModel? c) {
    if (_initialized) return;
    if (c != null) {
      _rxController.text = c.rx ?? '';
      _symptomsCtrl.text = c.symptoms ?? '';
      _diagnosisCtrl.text = c.diagnosis ?? '';
      _notesCtrl.text = c.notes ?? '';
      _followUpCtrl.text = c.followUpPlan ?? '';

      // ── Hydrate ICD-10 from the draft ──
      if ((c.diagnosisCode ?? '').isNotEmpty &&
          (c.diagnosisText ?? '').isNotEmpty) {
        _selectedIcd = Icd10Code(
          code: c.diagnosisCode!,
          description: c.diagnosisText!,
        );
      }

      // ── Hydrate disposition ──
      _selectedDisposition = dispositionFromString(c.disposition);

      for (final m in c.medications) {
        _meds.add(_MedRow()
          ..name.text = m.name
          ..dose.text = m.dose
          ..frequency.text = m.frequency
          ..duration.text = m.duration);
      }
    }
    _initialized = true;
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    if (!_speechAvailable) {
      final ok = await _speech.initialize(
        onError: (e) {
          if (!mounted) return;
          setState(() => _listening = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Voice error: ${e.errorMsg}'),
            backgroundColor: AppColors.error,
          ));
        },
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _listening = false);
          }
        },
      );
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Speech recognition is not available. Check microphone permission.'),
            backgroundColor: AppColors.error,
          ));
        }
        return;
      }
      _speechAvailable = true;
    }

    _rxBeforeDictation = _rxController.text;
    final prefix =
        _rxBeforeDictation.trim().isEmpty ? '' : '$_rxBeforeDictation ';

    setState(() => _listening = true);

    await _speech.listen(
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      cancelOnError: true,
      listenMode: stt.ListenMode.dictation,
      onResult: (result) {
        if (!mounted) return;
        final spoken = result.recognizedWords.trim();
        if (spoken.isEmpty) {
          _rxController.text = _rxBeforeDictation;
        } else {
          _rxController.text = '$prefix$spoken';
        }
        _rxController.selection = TextSelection.fromPosition(
          TextPosition(offset: _rxController.text.length),
        );
        setState(() {});
      },
    );
  }

  List<Medication> _collectMeds() => _meds
      .where((m) => m.name.text.trim().isNotEmpty)
      .map((m) => Medication(
            name: m.name.text.trim(),
            dose: m.dose.text.trim(),
            frequency: m.frequency.text.trim(),
            duration: m.duration.text.trim(),
          ))
      .toList();

  Future<void> _saveDraft() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final user = await ref.read(currentUserProvider.future);
      await ref.read(consultationServiceProvider).upsertDraft(
            appointment: widget.appointment,
            doctorName: user?.name ?? widget.appointment.doctorName,
            chiefComplaint: widget.appointment.chiefComplaint,
            symptoms: _symptomsCtrl.text.trim(),
            diagnosis: _diagnosisCtrl.text.trim(),
            diagnosisCode: _selectedIcd?.code,
            diagnosisText: _selectedIcd?.description,
            notes: _notesCtrl.text.trim(),
            rx: _rxController.text.trim(),
            followUpPlan: _followUpCtrl.text.trim(),
            medications: _collectMeds(),
            disposition: _selectedDisposition?.name,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Draft saved'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _orderTest() async {
    if (_openingLabOrder) return;
    setState(() => _openingLabOrder = true);
    try {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => LabOrderCreateScreen(
            preselectedPatientDocId: widget.appointment.patientDocId,
            preselectedAppointmentId: widget.appointment.docId,
          ),
        ),
      );
      if (result == true && mounted) {
        ref.invalidate(
            patientHistoryProvider(widget.appointment.patientDocId));
        setState(() {});
      }
    } finally {
      if (mounted) setState(() => _openingLabOrder = false);
    }
  }

  Future<void> _completeConsult() async {
    if (_saving) return;

    await _saveDraft();
    if (!mounted) return;

    final fees = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _FeesDialog(),
    );
    if (fees == null) return;

    setState(() => _saving = true);
    try {
      final user = await ref.read(currentUserProvider.future);
      if (user == null) throw StateError('No signed-in user');

      await ref.read(consultationServiceProvider).upsertDraft(
            appointment: widget.appointment,
            doctorName: user.name,
            chiefComplaint: widget.appointment.chiefComplaint,
            symptoms: _symptomsCtrl.text.trim(),
            diagnosis: _diagnosisCtrl.text.trim(),
            diagnosisCode: _selectedIcd?.code,
            diagnosisText: _selectedIcd?.description,
            notes: _notesCtrl.text.trim(),
            rx: _rxController.text.trim(),
            followUpPlan: _followUpCtrl.text.trim(),
            medications: _collectMeds(),
            disposition: _selectedDisposition?.name,
            endedAt: DateTime.now(),
          );

      await ref.read(appointmentServiceProvider).completeConsultation(
            appointmentDocId: widget.appointment.docId,
            fees: fees,
            doctorUid: user.uid,
          );

      if (!mounted) return;
      ref.read(selectedAppointmentProvider.notifier).state = null;
      ref.read(doctorTabProvider.notifier).state = 0;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Consultation completed · ₹${fees.toStringAsFixed(0)} added to billing'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not complete: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appt = widget.appointment;
    final isReadOnly = widget.readOnly ||
        appt.status == AppointmentStatus.completed;

    final draftAsync = ref.watch(consultationDraftProvider(appt.docId));
    draftAsync.whenData((c) => _hydrate(c));

    final historyAsync =
        ref.watch(patientHistoryProvider(appt.patientDocId));

    final initial = appt.patientName.isNotEmpty
        ? appt.patientName[0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appt.patientName, style: AppTextStyles.h3),
            Text(
              '${appt.patientId} • ${appt.tokenLabel} • '
              '${appt.slotPeriodLabel}',
              style: AppTextStyles.caption,
            ),
          ],
        ),
        actions: [
          if (!isReadOnly)
            TextButton.icon(
              onPressed: _saving ? null : _saveDraft,
              icon: const Icon(Icons.save_outlined,
                  size: 18, color: AppColors.info),
              label: const Text('Save',
                  style: TextStyle(color: AppColors.info)),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(patientHistoryProvider(appt.patientDocId));
          ref.invalidate(consultationDraftProvider(appt.docId));
          ref.invalidate(appointmentVitalsProvider(appt.docId));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -------- Patient header --------
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      CircleAvatar(
                        backgroundColor:
                            AppColors.doctorAccent.withOpacity(0.2),
                        child: Text(initial,
                            style: const TextStyle(
                                color: AppColors.doctorAccent)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(appt.patientName,
                                style: AppTextStyles.h3),
                            const SizedBox(height: 2),
                            Text(
                              [
                                appt.patientId,
                                appt.tokenNumber > 0
                                    ? appt.tokenLabel
                                    : null,
                                appt.slotPeriodLabel,
                              ]
                                  .whereType<String>()
                                  .where((s) => s.isNotEmpty)
                                  .join(' • '),
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                      if (appt.consultationFees != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (appt.paymentStatus ==
                                        PaymentStatus.paid
                                    ? AppColors.success
                                    : AppColors.warning)
                                .withOpacity(.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '₹${appt.consultationFees!.toStringAsFixed(0)} · '
                            '${appt.paymentStatusLabel}',
                            style: AppTextStyles.caption.copyWith(
                              color: appt.paymentStatus ==
                                      PaymentStatus.paid
                                  ? AppColors.success
                                  : AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 10),
                    Text('Chief Complaint', style: AppTextStyles.label),
                    const SizedBox(height: 6),
                    Text(
                      appt.chiefComplaint?.trim().isNotEmpty == true
                          ? appt.chiefComplaint!
                          : 'Not recorded',
                      style:
                          appt.chiefComplaint?.trim().isNotEmpty == true
                              ? AppTextStyles.body
                              : AppTextStyles.bodyMuted,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // -------- Vitals --------
              const SectionHeader(title: 'Vitals'),
              _VitalsSection(
                appointment: appt,
                readOnly: isReadOnly,
              ),

              const SizedBox(height: 24),

              // -------- Clinical fields --------
              _field('Symptoms', _symptomsCtrl,
                  maxLines: 2, readOnly: isReadOnly),

              // ── ICD-10 picker ──
              Icd10SearchField(
                initial: _selectedIcd,
                readOnly: isReadOnly,
                onSelected: (code) =>
                    setState(() => _selectedIcd = code),
              ),
              const SizedBox(height: 12),

              _field('Clinical impression / notes', _diagnosisCtrl,
                  maxLines: 2, readOnly: isReadOnly),
              _field('Consultation notes', _notesCtrl,
                  maxLines: 4, readOnly: isReadOnly),

              const SizedBox(height: 8),

              // ── Disposition picker ──
              _dispositionSelector(isReadOnly),
              const SizedBox(height: 16),

              // -------- Prescription --------
              const SectionHeader(title: 'Prescription'),
              const SizedBox(height: 8),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text('Write / dictate Rx',
                              style: AppTextStyles.label)),
                      IconButton(
                        onPressed: isReadOnly ? null : _toggleVoice,
                        icon: Icon(
                          _listening
                              ? Icons.mic_rounded
                              : Icons.mic_none_rounded,
                          color: isReadOnly
                              ? AppColors.textMuted
                              : (_listening
                                  ? AppColors.error
                                  : AppColors.primary),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _rxController,
                      maxLines: 5,
                      readOnly: isReadOnly,
                      style: const TextStyle(
                          color: AppColors.textPrimary),
                      decoration: const InputDecoration(
                        hintText:
                            'e.g. Paracetamol 500mg — 1 tab TID x 3 days',
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Note: Doctor must review all dictated text '
                      'before issuing.',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // -------- Structured medications --------
              Row(children: [
                const Expanded(
                    child: SectionHeader(title: 'Medications')),
                if (!isReadOnly)
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _meds.add(_MedRow())),
                    icon: const Icon(Icons.add_rounded,
                        size: 16, color: AppColors.info),
                    label: const Text('Add',
                        style: TextStyle(color: AppColors.info)),
                  ),
              ]),
              const SizedBox(height: 6),
              if (_meds.isEmpty)
                GlassCard(
                  child: Text('No structured medications added.',
                      style: AppTextStyles.bodyMuted),
                )
              else
                for (final m in _meds)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MedicationCard(
                      row: m,
                      readOnly: isReadOnly,
                      onRemove: () => setState(() {
                        m.dispose();
                        _meds.remove(m);
                      }),
                    ),
                  ),

              const SizedBox(height: 16),

              _field('Follow-up plan', _followUpCtrl,
                  maxLines: 2, readOnly: isReadOnly),

              const SizedBox(height: 20),

              // -------- Lab tests for this visit --------
              Row(children: [
                const Expanded(
                    child:
                        SectionHeader(title: 'Lab Tests — this visit')),
                TextButton.icon(
                  onPressed: (isReadOnly || _openingLabOrder)
                      ? null
                      : _orderTest,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Order'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.info,
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              _thisVisitLabs(historyAsync, appt),

              const SizedBox(height: 24),
              const SectionHeader(title: 'Past consultations'),
              const SizedBox(height: 8),
              _pastConsults(historyAsync, appt),

              const SizedBox(height: 28),

              // -------- Complete button --------
              if (!isReadOnly)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _completeConsult,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.background),
                          )
                        : const Icon(
                            Icons.check_circle_outline_rounded),
                    label: Text(_saving
                        ? 'Completing…'
                        : 'Complete Consultation'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.doctorAccent,
                      foregroundColor: AppColors.background,
                      padding:
                          const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                )
              else
                GlassCard(
                  borderColor:
                      AppColors.success.withOpacity(.35),
                  child: Row(children: const [
                    Icon(Icons.check_circle_rounded,
                        color: AppColors.success),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          'Consultation already completed',
                          style:
                              TextStyle(color: AppColors.success)),
                    ),
                  ]),
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dispositionSelector(bool isReadOnly) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Disposition', style: AppTextStyles.caption),
        const SizedBox(height: 6),
        GlassCard(
          child: Column(
            children: [
              for (final d in Disposition.values)
                RadioListTile<Disposition>(
                  value: d,
                  groupValue: _selectedDisposition,
                  onChanged: isReadOnly
                      ? null
                      : (v) => setState(
                          () => _selectedDisposition = v),
                  title: Text(d.label, style: AppTextStyles.body),
                  subtitle: Text(d.description,
                      style: AppTextStyles.caption),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.doctorAccent,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController c, {
    int maxLines = 3,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 6),
          GlassCard(
            child: TextField(
              controller: c,
              maxLines: maxLines,
              readOnly: readOnly,
              style: AppTextStyles.body,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thisVisitLabs(
      AsyncValue<PatientHistory> historyAsync, AppointmentModel a) {
    return historyAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(color: AppColors.info),
      ),
      error: (e, _) => Text('Lab error: $e',
          style: const TextStyle(color: AppColors.error)),
      data: (h) {
        final thisVisit = h.labOrders
    .where((o) =>
        o.appointmentId == a.docId &&
        !(o.status == LabOrderStatus.ready && !o.released))
    .toList();
        if (thisVisit.isEmpty) {
          return GlassCard(
            child: Row(children: [
              const Icon(Icons.science_outlined,
                  color: AppColors.textMuted, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No lab tests ordered for this visit yet.',
                  style: AppTextStyles.bodyMuted,
                ),
              ),
            ]),
          );
        }
        return Column(children: [
          for (final o in thisVisit)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LabOrderRow(order: o),
            ),
        ]);
      },
    );
  }

  Widget _pastConsults(
      AsyncValue<PatientHistory> historyAsync, AppointmentModel a) {
    return historyAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
            child:
                CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => GlassCard(
          child: Text('History failed: $e',
              style: const TextStyle(color: AppColors.error))),
      data: (h) {
        final past = h.consultations
            .where((c) => c.appointmentId != a.docId)
            .toList();
        if (past.isEmpty) {
          return GlassCard(
            child: Text('No prior consults on record.',
                style: AppTextStyles.bodyMuted),
          );
        }
        return Column(children: [
          for (final c in past.take(15))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PastConsultCard(c: c),
            ),
        ]);
      },
    );
  }
}

// -----------------------------------------------------------------
// One lab-order row
// -----------------------------------------------------------------
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
      case LabOrderStatus.accepted:
      case LabOrderStatus.sampleCollected:
        return AppColors.info;
      case LabOrderStatus.cancelled:
      case LabOrderStatus.noShow:
        return AppColors.error;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: _statusColor.withOpacity(.35),
      child: Row(children: [
        Icon(
          order.status == LabOrderStatus.ready
              ? Icons.description_rounded
              : Icons.science_outlined,
          color: _statusColor,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(order.testsSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body),
              const SizedBox(height: 2),
              Text(order.labName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption),
            ],
          ),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: _statusColor.withOpacity(.13),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(order.statusLabel,
              style:
                  AppTextStyles.caption.copyWith(color: _statusColor)),
        ),
      ]),
    );
  }
}

// -----------------------------------------------------------------
// Past consult card — now shows ICD-10 code + disposition
// -----------------------------------------------------------------
class _PastConsultCard extends StatelessWidget {
  final ConsultationModel c;
  const _PastConsultCard({required this.c});

  @override
  Widget build(BuildContext context) {
    final when = c.startedAt ?? c.createdAt;
    final disp = dispositionFromString(c.disposition);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.event_note_rounded,
                size: 16, color: AppColors.doctorAccent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                when == null
                    ? 'Consultation'
                    : DateFormat('dd MMM yyyy · hh:mm a').format(when),
                style: AppTextStyles.caption,
              ),
            ),
            if (disp != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.doctorAccent.withOpacity(.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(disp.label,
                    style: AppTextStyles.caption.copyWith(
                        color: AppColors.doctorAccent,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
          if ((c.diagnosisCode ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.local_hospital_outlined,
                  size: 14, color: AppColors.info),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${c.diagnosisCode} — ${c.diagnosisText ?? ''}',
                  style: AppTextStyles.body,
                ),
              ),
            ]),
          ] else if (c.diagnosis?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text('Diagnosis: ${c.diagnosis}',
                style: AppTextStyles.bodyMuted),
          ],
          if (c.symptoms?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text('Symptoms: ${c.symptoms}',
                style: AppTextStyles.bodyMuted),
          ],
          if (c.notes?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(c.notes!, style: AppTextStyles.bodyMuted),
          ],
          if (c.rx?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.medication_rounded,
                  size: 14, color: AppColors.info),
              const SizedBox(width: 4),
              Expanded(
                child: Text(c.rx!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption),
              ),
            ]),
          ],
          if (c.medications.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in c.medications)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${m.name} ${m.dose}'.trim(),
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.info),
                  ),
                ),
            ]),
          ],
          if (c.followUpPlan?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text('Follow-up: ${c.followUpPlan}',
                style: AppTextStyles.caption),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------
// Vitals section — unchanged
// -----------------------------------------------------------------
class _VitalBox extends StatelessWidget {
  final String label;
  final String value;
  const _VitalBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 6),
          Text(value, style: AppTextStyles.h3),
        ],
      ),
    );
  }
}

class _VitalsSection extends ConsumerWidget {
  final AppointmentModel appointment;
  final bool readOnly;

  const _VitalsSection({
    required this.appointment,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vitalsAsync =
        ref.watch(appointmentVitalsProvider(appointment.docId));

    return vitalsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Could not load vitals: $e',
          style: const TextStyle(
              color: AppColors.error, fontSize: 12),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: const [
                Expanded(child: _VitalBox(label: 'BP', value: '—')),
                SizedBox(width: 10),
                Expanded(child: _VitalBox(label: 'Temp', value: '—')),
                SizedBox(width: 10),
                Expanded(child: _VitalBox(label: 'Pulse', value: '—')),
              ]),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'No vitals recorded for this visit yet.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted),
                ),
              ),
              if (!readOnly)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _DoctorVitalsCaptureScreen(
                            appointment: appointment,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Record vitals'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.doctorAccent,
                        side: BorderSide(
                          color: AppColors.doctorAccent
                              .withOpacity(0.4),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }

        final v = list.first;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                  child: _VitalBox(
                      label: 'BP',
                      value: _fmt(v['bp'], fallback: '—'))),
              const SizedBox(width: 10),
              Expanded(
                  child: _VitalBox(
                      label: 'Temp',
                      value: _fmt(v['temp'], suffix: '°F'))),
              const SizedBox(width: 10),
              Expanded(
                  child: _VitalBox(
                      label: 'Pulse',
                      value: _fmt(v['pulse'], suffix: 'bpm'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: _VitalBox(
                      label: 'SpO₂',
                      value: _fmt(v['spo2'], suffix: '%'))),
              const SizedBox(width: 10),
              Expanded(
                  child: _VitalBox(
                      label: 'Weight',
                      value: _fmt(v['weight'], suffix: 'kg'))),
              const SizedBox(width: 10),
              const Expanded(child: SizedBox()),
            ]),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _recordedByLine(v),
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        );
      },
    );
  }

  String _fmt(dynamic value, {String? suffix, String fallback = '—'}) {
    if (value == null) return fallback;
    final s = value.toString().trim();
    if (s.isEmpty || s == 'null') return fallback;
    return suffix == null ? s : '$s $suffix';
  }

  String _recordedByLine(Map<String, dynamic> v) {
    final name = (v['recordedByName'] as String?)?.trim() ?? '';
    final ts = v['recordedAt'];
    String when = '';
    if (ts is Timestamp) {
      final t = ts.toDate().toLocal();
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      when = ' at $hh:$mm';
    }
    return name.isEmpty ? 'Recorded$when' : 'Recorded$when by $name';
  }
}

// -----------------------------------------------------------------
// Doctor-side vitals capture — unchanged
// -----------------------------------------------------------------
class _DoctorVitalsCaptureScreen extends ConsumerStatefulWidget {
  final AppointmentModel appointment;
  const _DoctorVitalsCaptureScreen({required this.appointment});

  @override
  ConsumerState<_DoctorVitalsCaptureScreen> createState() =>
      _DoctorVitalsCaptureScreenState();
}

class _DoctorVitalsCaptureScreenState
    extends ConsumerState<_DoctorVitalsCaptureScreen> {
  final _bp = TextEditingController();
  final _temp = TextEditingController();
  final _pulse = TextEditingController();
  final _spo2 = TextEditingController();
  final _weight = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _bp.dispose();
    _temp.dispose();
    _pulse.dispose();
    _spo2.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final hasAny = [
      _bp.text,
      _temp.text,
      _pulse.text,
      _spo2.text,
      _weight.text,
    ].any((s) => s.trim().isNotEmpty);

    if (!hasAny) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one vital sign')),
      );
      return;
    }

    final user = ref.read(currentUserProvider).valueOrNull;
    final a = widget.appointment;

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'appointmentDocId': a.docId,
        'appointmentCode': a.appointmentCode,
        'patientDocId': a.patientDocId,
        'patientId': a.patientId,
        'patientName': a.patientName,
        'patientPhone': a.patientPhone,
        'doctorDocId': a.doctorDocId,
        'doctorName': a.doctorName,
        'clinicId': a.clinicId,
        'clinicCode': user?.clinicCode ?? '',
        'clinicDisplayName': user?.clinicName ?? '',
        'chiefComplaint': a.chiefComplaint,
        'type': a.type,
        'tokenLabel': a.tokenLabel,
        'recordedByUid': user?.uid,
        'recordedByName': user?.name,
        'recordedByRole': 'doctor',
        'recordedAt': FieldValue.serverTimestamp(),
        'bp': _bp.text.trim().isEmpty ? null : _bp.text.trim(),
        'temp': double.tryParse(_temp.text.trim()),
        'pulse': int.tryParse(_pulse.text.trim()),
        'spo2': int.tryParse(_spo2.text.trim()),
        'weight': double.tryParse(_weight.text.trim()),
      };

      await FirebaseFirestore.instance.collection('vitals').add(payload);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vitals saved'),
          backgroundColor: AppColors.success,
        ),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: ${e.message ?? e.code}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Record Vitals')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(a.patientName, style: AppTextStyles.h3),
            const SizedBox(height: 4),
            Text('${a.patientId} • ${a.tokenLabel}',
                style: AppTextStyles.caption),
            const SizedBox(height: 20),
            _field('Blood Pressure', _bp, 'e.g. 120/80'),
            _field('Temperature (°F)', _temp, 'e.g. 98.6', number: true),
            _field('Pulse (bpm)', _pulse, 'e.g. 78', number: true),
            _field('SpO₂ (%)', _spo2, 'e.g. 98', number: true),
            _field('Weight (kg)', _weight, 'e.g. 72', number: true),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.doctorAccent,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.background,
                        ),
                      )
                    : const Text('Save Vitals'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl,
    String hint, {
    bool number = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.label),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            keyboardType: number
                ? TextInputType.number
                : TextInputType.text,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------
// Fees dialog — unchanged
// -----------------------------------------------------------------
class _FeesDialog extends StatefulWidget {
  const _FeesDialog();
  @override
  State<_FeesDialog> createState() => _FeesDialogState();
}

class _FeesDialogState extends State<_FeesDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.trim());
    if (v == null || v <= 0) {
      setState(() => _error = 'Enter a valid amount greater than 0');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Consultation fees', style: AppTextStyles.h3),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          'This amount will appear on the receptionist\'s billing '
          'screen against this patient.',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: AppTextStyles.body,
          decoration: InputDecoration(
            prefixText: '₹ ',
            hintText: 'e.g. 500',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
          ),
          child: const Text('Complete & send to billing'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------
// Medication card — unchanged
// -----------------------------------------------------------------
class _MedicationCard extends StatelessWidget {
  final _MedRow row;
  final bool readOnly;
  final VoidCallback onRemove;

  const _MedicationCard({
    required this.row,
    required this.readOnly,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: AppColors.info.withOpacity(.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.medication_rounded,
                size: 16, color: AppColors.info),
            const SizedBox(width: 6),
            Text('Medication',
                style: AppTextStyles.caption
                    .copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            if (!readOnly)
              IconButton(
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: AppColors.error),
              ),
          ]),

          _labeledField(
            label: 'Name',
            hint: 'e.g. Paracetamol 500mg',
            controller: row.name,
            readOnly: readOnly,
          ),
          const SizedBox(height: 10),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _labeledField(
                  label: 'Dose',
                  hint: 'e.g. 1 tab',
                  controller: row.dose,
                  readOnly: readOnly,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _labeledField(
                  label: 'Frequency',
                  hint: 'e.g. TID',
                  controller: row.frequency,
                  readOnly: readOnly,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _labeledField(
                  label: 'Duration',
                  hint: 'e.g. 3 days',
                  controller: row.duration,
                  readOnly: readOnly,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _labeledField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool readOnly,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 4),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTextStyles.caption
                  .copyWith(color: AppColors.textMuted),
              border: InputBorder.none,
              isCollapsed: true,
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------
// Med-row controllers
// -----------------------------------------------------------------
class _MedRow {
  final name = TextEditingController();
  final dose = TextEditingController();
  final frequency = TextEditingController();
  final duration = TextEditingController();
  void dispose() {
    name.dispose();
    dose.dispose();
    frequency.dispose();
    duration.dispose();
  }
}