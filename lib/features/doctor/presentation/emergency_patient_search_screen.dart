// lib/features/doctor/presentation/emergency_patient_search_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/models/patient_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';
import 'doctor_providers.dart';
import 'patient_overview_screen.dart';

/// Emergency patient flow:
///   1. Search patients (code / name / phone / email)
///   2. Tap a result → PatientOverviewScreen (360° view)
///   3. [Start consultation] → creates walk-in appointment and
///      sets `selectedAppointmentProvider` so the consult opens.
class EmergencyPatientSearchScreen extends ConsumerStatefulWidget {
  const EmergencyPatientSearchScreen({super.key});

  @override
  ConsumerState<EmergencyPatientSearchScreen> createState() =>
      _EmergencyPatientSearchScreenState();
}

class _EmergencyPatientSearchScreenState
    extends ConsumerState<EmergencyPatientSearchScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _searching = false;
  List<PatientModel> _results = const [];
  bool _hasSearched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value.trim());
    _debounce?.cancel();
    if (_query.length < 2) {
      setState(() {
        _results = const [];
        _hasSearched = false;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _runSearch);
  }

  Future<void> _runSearch() async {
    final user = await ref.read(currentUserProvider.future);
    if (user?.clinicId == null) return;

    setState(() => _searching = true);
    try {
      final results = await ref
          .read(patientServiceProvider)
          .search(_query, clinicId: user!.clinicId!);
      if (!mounted) return;
      setState(() {
        _results = results;
        _hasSearched = true;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Search failed: $e'),
            backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _openPatient(PatientModel patient) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PatientOverviewScreen(patient: patient),
      ),
    );
    // If the overview started a consultation, it will have popped
    // and set selectedAppointmentProvider → tab switches. The search
    // screen can be popped by the overview's popUntil.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Emergency patient'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: _onQueryChanged,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Search by code, name, phone, or email',
                  prefixIcon:
                      Icon(Icons.search, color: AppColors.textMuted),
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.length < 2) {
      return const _HintView();
    }
    if (_searching) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (!_hasSearched) {
      return const _HintView();
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No patients match "$_query"',
              style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _PatientTile(
        patient: _results[i],
        onTap: () => _openPatient(_results[i]),
      ),
    );
  }
}

class _HintView extends StatelessWidget {
  const _HintView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_search_rounded,
                size: 56, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text('Search for the patient',
                style: AppTextStyles.h3, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Type at least 2 characters to search by patient code, '
              'name, phone, or email.',
              style: AppTextStyles.bodyMuted,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientTile extends StatelessWidget {
  final PatientModel patient;
  final VoidCallback onTap;
  const _PatientTile({required this.patient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initial = patient.fullName.isNotEmpty
        ? patient.fullName[0].toUpperCase()
        : '?';
    return GlassCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(.15),
              child: Text(initial,
                  style: const TextStyle(color: AppColors.primary)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      patient.patientId,
                      patient.phone,
                      if (patient.email != null &&
                          patient.email!.isNotEmpty)
                        patient.email!,
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
    );
  }
}