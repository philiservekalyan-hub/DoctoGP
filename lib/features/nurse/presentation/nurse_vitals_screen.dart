import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/services/dashboard_service.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/labeled_field.dart';
import '../../../shared/widgets/clinic_app_bar.dart';
import '../../../app/router.dart';

/// Fetches and caches a clinic document by ID.
/// Reused across screens; one read per clinic per app session.

class NurseVitalsScreen extends ConsumerStatefulWidget {
  const NurseVitalsScreen({super.key});
  @override
  ConsumerState<NurseVitalsScreen> createState() =>
      _NurseVitalsScreenState();
}

class _NurseVitalsScreenState extends ConsumerState<NurseVitalsScreen> {
  AppointmentModel? _selected;
  bool _saving = false;

  final _bp = TextEditingController();
  final _temp = TextEditingController();
  final _pulse = TextEditingController();
  final _weight = TextEditingController();
  final _spo2 = TextEditingController();

  @override
  void dispose() {
    _bp.dispose();
    _temp.dispose();
    _pulse.dispose();
    _weight.dispose();
    _spo2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final apptAsync = ref.watch(todayAppointmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(title: 'Record Vitals'),
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
                icon: Icons.monitor_heart_outlined,
                title: 'No patients waiting',
                subtitle:
                    'Vitals can be recorded once a patient is checked in.',
              );
            }
            if (_selected == null) return _patientSelector(list);
            return _vitalsForm();
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Patient selector
  // ─────────────────────────────────────────────────────────────
  Widget _patientSelector(List<AppointmentModel> list) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final a = list[i];
        return GlassCard(
          onTap: () => setState(() => _selected = a),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.nurseAccent.withOpacity(0.2),
                child: Text(
                  a.patientName.isNotEmpty
                      ? a.patientName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(color: AppColors.nurseAccent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.patientName, style: AppTextStyles.body),
                    Text('${a.patientId} • ${a.tokenLabel}',
                        style: AppTextStyles.caption),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Vitals form
  // ─────────────────────────────────────────────────────────────
  Widget _vitalsForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        GlassCard(
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.nurseAccent.withOpacity(0.2),
                child: Text(
                  _selected!.patientName.isNotEmpty
                      ? _selected!.patientName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(color: AppColors.nurseAccent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selected!.patientName, style: AppTextStyles.h3),
                    Text(
                      '${_selected!.patientId} • ${_selected!.tokenLabel}'
                      '${_selected!.doctorName.isNotEmpty ? " • ${_selected!.doctorName}" : ""}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed:
                    _saving ? null : () => setState(() => _selected = null),
                child: const Text('Change',
                    style: TextStyle(color: AppColors.primary)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        LabeledField(
          label: 'Blood Pressure',
          child: DarkTextField(
            controller: _bp,
            hint: 'e.g. 120/80',
            icon: Icons.favorite_outline,
          ),
        ),
        LabeledField(
          label: 'Temperature (°F)',
          child: DarkTextField(
            controller: _temp,
            hint: 'e.g. 98.6',
            keyboardType: TextInputType.number,
            icon: Icons.thermostat_outlined,
          ),
        ),
        LabeledField(
          label: 'Pulse (bpm)',
          child: DarkTextField(
            controller: _pulse,
            hint: 'e.g. 78',
            keyboardType: TextInputType.number,
            icon: Icons.monitor_heart_outlined,
          ),
        ),
        LabeledField(
          label: 'SpO₂ (%)',
          child: DarkTextField(
            controller: _spo2,
            hint: 'e.g. 98',
            keyboardType: TextInputType.number,
            icon: Icons.air_outlined,
          ),
        ),
        LabeledField(
          label: 'Weight (kg)',
          child: DarkTextField(
            controller: _weight,
            hint: 'e.g. 72',
            keyboardType: TextInputType.number,
            icon: Icons.scale_outlined,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _saveVitals,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Vitals'),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Save — fully linked across patient / doctor / clinic / visit
  // ─────────────────────────────────────────────────────────────
  Future<void> _saveVitals() async {
    final a = _selected;
    if (a == null) return;

    final hasAny = [
      _bp.text,
      _temp.text,
      _pulse.text,
      _spo2.text,
      _weight.text,
    ].any((v) => v.trim().isNotEmpty);

    if (!hasAny) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one vital sign')),
      );
      return;
    }

    final user = ref.read(currentUserProvider).valueOrNull;

    setState(() => _saving = true);
    try {
      // ── Fetch clinic doc (cached per session via clinicProvider) ──
      final clinicCode = user?.clinicCode ?? '';
final clinicDisplayName = user?.clinicName ?? '';

      final payload = <String, dynamic>{
        // ── Linkage ──
        'appointmentDocId': a.docId, 
        'appointmentCode': a.appointmentCode,
        'patientDocId': a.patientDocId,
        'patientId': a.patientId,
        'patientName': a.patientName,
        'patientPhone': a.patientPhone,
        'doctorDocId': a.doctorDocId,
        'doctorName': a.doctorName,
        'clinicId': a.clinicId,
        'clinicCode': clinicCode,           // e.g. "DGP-CLN-38685"
        'clinicDisplayName': clinicDisplayName, // e.g. "Lifeline"
        'chiefComplaint': a.chiefComplaint,
        'type': a.type,
        'tokenLabel': a.tokenLabel,

        // ── Audit ──
        'recordedByUid': user?.uid,
        'recordedByName': user?.name,
        'recordedAt': FieldValue.serverTimestamp(),

        // ── Clinical ──
        'bp': _bp.text.trim().isEmpty ? null : _bp.text.trim(),
        'temp': double.tryParse(_temp.text.trim()),
        'pulse': int.tryParse(_pulse.text.trim()),
        'spo2': int.tryParse(_spo2.text.trim()),
        'weight': double.tryParse(_weight.text.trim()),
      };

      //  top-level /vitals, matches the rule
await FirebaseFirestore.instance.collection('vitals').add(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vitals saved'),
          backgroundColor: AppColors.success,
        ),
      );

      _bp.clear();
      _temp.clear();
      _pulse.clear();
      _spo2.clear();
      _weight.clear();
      setState(() => _selected = null);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: ${e.message ?? e.code}'),
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}