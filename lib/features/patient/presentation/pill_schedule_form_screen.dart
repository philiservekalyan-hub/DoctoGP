// lib/features/patient/presentation/pill_schedule_form_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/glass_card.dart';
import 'patient_dashboard.dart';

class PillScheduleFormScreen extends ConsumerStatefulWidget {
  const PillScheduleFormScreen({super.key});

  @override
  ConsumerState<PillScheduleFormScreen> createState() =>
      _PillScheduleFormScreenState();
}

class _PillScheduleFormScreenState
    extends ConsumerState<PillScheduleFormScreen> {
  final _medName = TextEditingController();
  final _dose = TextEditingController();
  final _notes = TextEditingController();

  int _timesPerDay = 2;
  final List<TimeOfDay> _times = [
    const TimeOfDay(hour: 9, minute: 0),
    const TimeOfDay(hour: 21, minute: 0),
  ];
  int _graceMinutes = 30;
  DateTime _startDate = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _medName.dispose();
    _dose.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _times[index],
    );
    if (picked == null) return;
    setState(() => _times[index] = picked);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _startDate = picked);
  }

  Future<void> _save() async {
    if (_medName.text.trim().isEmpty) {
      _snack('Please enter the medication name');
      return;
    }
    if (_dose.text.trim().isEmpty) {
      _snack('Please enter the dose');
      return;
    }

    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final patient = ref.read(currentPatientProvider).valueOrNull;
      if (uid == null || patient == null) {
        throw 'Not signed in or patient profile missing';
      }
      final patientDocId = patient['patientDocId'] as String;
      final clinicId = patient['clinicId'] as String?;

      final db = FirebaseFirestore.instance;
      final scheduleRef = db.collection('pillSchedules').doc();
      final now = DateTime.now();

      final startAt = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
      );

      final timesStr = _times
          .take(_timesPerDay)
          .map((t) =>
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}')
          .toList();

      await scheduleRef.set({
        'patientDocId': patientDocId,
        'patientAuthUid': uid,
        'clinicId': clinicId,
        'medicationName': _medName.text.trim(),
        'dose': _dose.text.trim(),
        'frequency': _timesPerDay == 1
            ? 'once_daily'
            : _timesPerDay == 2
                ? 'twice_daily'
                : _timesPerDay == 3
                    ? 'thrice_daily'
                    : 'custom',
        'times': timesStr,
        'startDate': Timestamp.fromDate(startAt),
        'graceMinutes': _graceMinutes,
        'active': true,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'deviceId': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Generate dose documents for the next 7 days.
      final batch = db.batch();
      for (var dayOffset = 0; dayOffset < 7; dayOffset++) {
        final day = startAt.add(Duration(days: dayOffset));
        for (var i = 0; i < _timesPerDay; i++) {
          final t = _times[i];
          final scheduledAt =
              DateTime(day.year, day.month, day.day, t.hour, t.minute);
          if (scheduledAt.isBefore(now)) continue;
          final doseRef = db.collection('pillDoses').doc();
          batch.set(doseRef, {
            'scheduleId': scheduleRef.id,
            'patientDocId': patientDocId,
            'patientAuthUid': uid,
            'medicationName': _medName.text.trim(),
            'dose': _dose.text.trim(),
            'scheduledAt': Timestamp.fromDate(scheduledAt),
            'graceUntil': Timestamp.fromDate(
                scheduledAt.add(Duration(minutes: _graceMinutes))),
            'status': 'pending',
            'confirmedBy': null,
            'confirmedAt': null,
            'escalation': {
              'notifiedAt': null,
              'notifiedVia': null,
              'emergencyContactId': null,
            },
            'notes': null,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Medication schedule saved'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      setState(() => _saving = false);
      _snack('Could not save: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Add medication', style: AppTextStyles.h3),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _field('Medication name', _medName, hint: 'e.g. Metformin'),
            const SizedBox(height: 14),
            _field('Dose', _dose, hint: 'e.g. 500 mg'),
            const SizedBox(height: 20),

            Text('Times per day', style: AppTextStyles.caption),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final n in [1, 2, 3, 4])
                ChoiceChip(
                  label: Text('$n'),
                  selected: _timesPerDay == n,
                  onSelected: (_) => setState(() {
                    _timesPerDay = n;
                    while (_times.length < n) {
                      _times.add(TimeOfDay(
                          hour: 9 + _times.length * 4, minute: 0));
                    }
                  }),
                ),
            ]),
            const SizedBox(height: 16),

            Text('Times', style: AppTextStyles.caption),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < _timesPerDay; i++)
                ActionChip(
                  avatar: const Icon(Icons.access_time_rounded, size: 16),
                  label: Text(_times[i].format(context)),
                  onPressed: () => _pickTime(i),
                ),
            ]),
            const SizedBox(height: 16),

            Text('Grace period (before marking missed)',
                style: AppTextStyles.caption),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final m in [15, 30, 60, 120])
                ChoiceChip(
                  label: Text('$m min'),
                  selected: _graceMinutes == m,
                  onSelected: (_) => setState(() => _graceMinutes = m),
                ),
            ]),
            const SizedBox(height: 16),

            Text('Start date', style: AppTextStyles.caption),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickStartDate,
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: Text(
                  '${_startDate.day}/${_startDate.month}/${_startDate.year}'),
            ),
            const SizedBox(height: 20),

            _field('Notes (optional)', _notes,
                hint: 'e.g. Take with food', maxLines: 2),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save schedule'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: AppTextStyles.body,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}