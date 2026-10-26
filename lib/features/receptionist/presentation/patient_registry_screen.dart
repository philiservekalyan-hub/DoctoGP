import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/patient_model.dart';
import '../../../core/services/patient_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/empty_state.dart';
import 'add_patient_screen.dart';
import 'book_appointment_screen.dart';
import '../../../core/providers/service_providers.dart';

final _patientsStreamProvider =
    StreamProvider.autoDispose<List<PatientModel>>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null || user.clinicId == null) {
    yield [];
    return;
  }
  yield* ref
      .read(patientServiceProvider)
      .watchPatients(clinicId: user.clinicId!);
});

class PatientRegistryScreen extends ConsumerStatefulWidget {
  const PatientRegistryScreen({super.key});

  @override
  ConsumerState<PatientRegistryScreen> createState() =>
      _PatientRegistryScreenState();
}

class _PatientRegistryScreenState
    extends ConsumerState<PatientRegistryScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openAddPatient() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddPatientScreen()),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Patient added successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _openBookAppointment(PatientModel patient) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            BookAppointmentScreen(preselectedPatient: patient),
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Appointment booked'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(_patientsStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Patient Registry'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddPatient,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add Patient'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              style: const TextStyle(color: AppColors.textPrimary),
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: const InputDecoration(
                hintText: 'Search by name or PT-2026-0001',
                prefixIcon: Icon(Icons.search_rounded,
                    color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: patientsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primary),
                ),
                error: (e, _) => Center(
                  child: Text('Error: $e',
                      style: TextStyle(color: AppColors.error)),
                ),
                data: (patients) {
                  final filtered = _query.isEmpty
                      ? patients
                      : patients.where((p) {
                          final q = _query.toLowerCase();
                          return p.fullName
                                  .toLowerCase()
                                  .contains(q) ||
                              p.patientId
                                  .toLowerCase()
                                  .contains(q) ||
                              p.phone.contains(_query);
                        }).toList();

                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.people_outline_rounded,
                      title: _query.isEmpty
                          ? 'No patients yet'
                          : 'No matches found',
                      subtitle: _query.isEmpty
                          ? 'Tap "Add Patient" to register the first patient.'
                          : 'Try a different name or ID.',
                    );
                  }

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      return GlassCard(
                        onTap: () => _openBookAppointment(p),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.receptionAccent
                                  .withOpacity(0.2),
                              child: Text(
                                p.fullName.isNotEmpty
                                    ? p.fullName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    color: AppColors.receptionAccent,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(p.fullName,
                                      style: AppTextStyles.h3),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          p.patientId,
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(p.phone,
                                          style: AppTextStyles.caption),
                                    ],
                                  ),
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
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}