// lib/features/doctor/presentation/patient_search_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/glass_card.dart';
import 'patient_history_screen.dart';

/// Clinic-scoped prefix search on `fullName`, keyed by (clinicId, query).
///
/// Uses a single-field Firestore query (no composite index) with a
/// case-insensitive `startAt/endAt` range on `fullName`. If the clinic
/// uses a pre-normalized `fullNameLower` field, swap the field name —
/// otherwise this works against `fullName` directly.
final patientSearchProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({String clinicId, String query})>(
        (ref, key) {
  final q = key.query.trim();
  if (q.isEmpty || key.clinicId.isEmpty) return const Stream.empty();

  // Firestore is case-sensitive on `fullName`; use the same range trick
  // used by reception (`q` and `q\uf8ff`), then filter client-side for
  // case-insensitivity + substring matches.
  final lowered = q.toLowerCase();

  return FirebaseFirestore.instance
      .collection('patients')
      .where('clinicId', isEqualTo: key.clinicId)
      .limit(200)
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'docId': d.id, ...d.data()})
          .where((p) {
            final name = '${p['fullName'] ?? ''}'.toLowerCase();
            final pid = '${p['patientId'] ?? ''}'.toLowerCase();
            final phone = '${p['phone'] ?? ''}'.toLowerCase();
            return name.contains(lowered) ||
                pid.contains(lowered) ||
                phone.contains(lowered);
          })
          .take(30)
          .toList());
});

class PatientSearchScreen extends ConsumerStatefulWidget {
  const PatientSearchScreen({super.key});
  @override
  ConsumerState<PatientSearchScreen> createState() =>
      _PatientSearchScreenState();
}

class _PatientSearchScreenState extends ConsumerState<PatientSearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: TextField(
          autofocus: true,
          style: AppTextStyles.body,
          decoration: const InputDecoration(
            hintText: 'Search by name, ID, or phone…',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      body: userAsync.when(
        loading: () => const Center(
            child:
                CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('$e')),
        data: (user) {
          final clinicId = user?.clinicId ?? '';
          final results = ref.watch(patientSearchProvider(
              (clinicId: clinicId, query: _query)));

          return results.when(
            loading: () => const Center(
                child: CircularProgressIndicator(
                    color: AppColors.primary)),
            error: (e, _) => Center(
                child: Text('Failed: $e',
                    style:
                        const TextStyle(color: AppColors.error))),
            data: (patients) {
              if (_query.trim().isEmpty) {
                return Center(
                  child: Text('Start typing a patient name',
                      style: AppTextStyles.bodyMuted),
                );
              }
              if (patients.isEmpty) {
                return Center(
                  child: Text('No patients match "$_query"',
                      style: AppTextStyles.bodyMuted),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: patients.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final p = patients[i];
                  final name = (p['fullName'] ?? '') as String;
                  final code = (p['patientId'] ?? '') as String;
                  return GlassCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(name, style: AppTextStyles.body),
                      subtitle:
                          Text(code, style: AppTextStyles.caption),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textMuted),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PatientHistoryScreen(
                            patientDocId: p['docId'] as String,
                            patientNameHint: name,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}