// lib/features/doctor/presentation/lab_order_create_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/lab_order_model.dart';
import '../../../core/models/patient_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/labeled_field.dart';
import 'lab_test_picker_sheet.dart';

class LabOrderCreateScreen extends ConsumerStatefulWidget {
  final String? preselectedPatientDocId;
  final String? preselectedAppointmentId;
  const LabOrderCreateScreen({
    super.key,
    this.preselectedPatientDocId,
    this.preselectedAppointmentId,
  });

  @override
  ConsumerState<LabOrderCreateScreen> createState() =>
      _LabOrderCreateScreenState();
}

class _LabOrderCreateScreenState
    extends ConsumerState<LabOrderCreateScreen> {
  PatientModel? _patient;
  final List<AggregatedTest> _selectedTests = [];
  String? _labClinicId;
  String _labName = '';
  final _instructionsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPreselectedPatient();
  }

  Future<void> _loadPreselectedPatient() async {
    final id = widget.preselectedPatientDocId;
    if (id == null || id.isEmpty) return;
    final p = await ref.read(patientServiceProvider).getPatientByDocId(id);
    if (mounted && p != null) setState(() => _patient = p);
  }

  @override
  void dispose() {
    _instructionsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPatient() async {
    // If the caller preselected a patient, the picker is a no-op —
    // we don't want the doctor to accidentally switch patients mid-flow.
    if (widget.preselectedPatientDocId != null &&
        widget.preselectedPatientDocId!.isNotEmpty) {
      return;
    }
    final user = await ref.read(currentUserProvider.future);
    if (user?.clinicId == null) return;
    final result = await Navigator.of(context).push<PatientModel>(
      MaterialPageRoute(
        builder: (_) => _PatientPickerScreen(clinicId: user!.clinicId!),
      ),
    );
    if (result != null && mounted) setState(() => _patient = result);
  }

  Future<void> _pickTests() async {
    final user = await ref.read(currentUserProvider.future);
    if (user?.clinicId == null) return;

    final result = await showModalBottomSheet<List<AggregatedTest>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LabTestPickerSheet(
        clinicId: user!.clinicId!,
        preselectedKeys: _selectedTests.map((t) => t.key).toList(),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedTests
          ..clear()
          ..addAll(result);
        _labClinicId = null;
        _labName = '';
      });
    }
  }

  // -----------------------------------------------------------------
  // Idempotency guard: same appointment + same patient + same lab +
  // same test set within the last 15 seconds = already placed.
  // -----------------------------------------------------------------
  Future<bool> _recentDuplicateExists({
    required String referringClinicId,
    required String labClinicId,
    required String patientDocId,
    required List<LabTestItem> tests,
    required String? appointmentId,
  }) async {
    if (appointmentId == null || appointmentId.isEmpty) return false;

    final since =
        Timestamp.fromDate(DateTime.now().subtract(const Duration(seconds: 15)));

    final snap = await FirebaseFirestore.instance
        .collection('labOrders')
        .where('appointmentId', isEqualTo: appointmentId)
        .where('patientDocId', isEqualTo: patientDocId)
        .where('labClinicId', isEqualTo: labClinicId)
        .where('orderedAt', isGreaterThan: since)
        .limit(5)
        .get();

    if (snap.docs.isEmpty) return false;

    // Compare the test sets. Order-insensitive, name-insensitive
    // (trim + lower), so a duplicate tap on the same chip selection
    // always collapses to the same set.
    String canon(List<LabTestItem> xs) {
      final s = xs
          .map((t) => (t.code ?? t.name).trim().toLowerCase())
          .toList()
        ..sort();
      return s.join('|');
    }

    final wanted = canon(tests);
    for (final d in snap.docs) {
      final m = d.data();
      final raw = m['tests'];
      final existing = <LabTestItem>[];
      if (raw is List) {
        for (final t in raw) {
          if (t is Map) {
            existing
                .add(LabTestItem.fromMap(Map<String, dynamic>.from(t)));
          } else if (t is String) {
            existing.add(LabTestItem(name: t));
          }
        }
      }
      if (canon(existing) == wanted) return true;
    }
    return false;
  }

  Future<void> _save() async {
    // Guard 1 — synchronous re-entry check (blocks same-frame double tap
    // before the rebuild disables the button).
    if (_saving) return;

    if (_patient == null) {
      return _snack('Pick a patient.', AppColors.error);
    }
    if (_selectedTests.isEmpty) {
      return _snack('Add at least one test.', AppColors.error);
    }
    if (_labClinicId == null) {
      return _snack('Pick a lab.', AppColors.error);
    }

    setState(() => _saving = true);
    try {
      final user = await ref.read(currentUserProvider.future);
      if (user == null || user.clinicId == null) {
        return _snack('No clinic linked.', AppColors.error);
      }

      final tests = _selectedTests
          .map((t) => LabTestItem(
                code: t.code.isEmpty ? null : t.code,
                name: t.name,
              ))
          .toList();

      // Guard 2 — idempotency check.
      final dup = await _recentDuplicateExists(
        referringClinicId: user.clinicId!,
        labClinicId: _labClinicId!,
        patientDocId: _patient!.docId,
        tests: tests,
        appointmentId: widget.preselectedAppointmentId,
      );
      if (dup) {
        if (mounted) Navigator.of(context).pop(true);
        _snack('Order already placed.', AppColors.success);
        return;
      }

      await ref.read(labServiceProvider).createOrder(
            referringClinicId: user.clinicId!,
            labClinicId: _labClinicId!,
            labName: _labName,
            patientDocId: _patient!.docId,
            patientId: _patient!.patientId,
            patientName: _patient!.fullName,
            patientPhone: _patient!.phone,
            patientEmail: _patient!.email,
            patientGender: _patient!.gender,
            patientDob: _patient!.dob,
            patientBloodGroup: _patient!.bloodGroup,
            referringClinicName: user.clinicName,
            referringClinicPatientDocId: _patient!.docId,
            doctorDocId: user.uid,
            doctorName: user.name,
            tests: tests,
            instructions: _instructionsCtrl.text.trim().isEmpty
                ? null
                : _instructionsCtrl.text.trim(),
            referralNotes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
            appointmentId: widget.preselectedAppointmentId,
            billableAmount: null,
          );

      _snack('Lab order sent.', AppColors.success);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Failed: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('New lab order')),
      body: userAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('$e')),
        data: (user) {
          final clinicId = user?.clinicId ?? '';
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              LabeledField(
                label: 'Patient',
                required: true,
                child: _patientPicker(),
              ),
              LabeledField(
                label: 'Tests',
                required: true,
                child: _testsPicker(),
              ),
              LabeledField(
                label: 'Lab',
                required: true,
                child: _labPicker(clinicId),
              ),
              LabeledField(
                label: 'Instructions (optional)',
                child: DarkTextField(
                  controller: _instructionsCtrl,
                  hint: 'e.g. Fasting sample, 8–10 hrs',
                ),
              ),
              LabeledField(
                label: 'Clinical notes (optional)',
                child: DarkTextField(
                  controller: _notesCtrl,
                  hint: 'Anything the lab should know',
                  maxLines: 3,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  // Button disabled while saving (Guard 3 — UI).
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Sending...' : 'Send to lab'),
                ),
              ),
              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _patientPicker() => GestureDetector(
        onTap: _pickPatient,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Row(children: [
            const Icon(Icons.person_search_outlined,
                color: AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: _patient == null
                  ? const Text('Tap to select patient',
                      style: TextStyle(color: AppColors.textMuted))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_patient!.fullName,
                            style: AppTextStyles.body),
                        Text('${_patient!.patientId} • ${_patient!.phone}',
                            style: AppTextStyles.caption),
                      ],
                    ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted),
          ]),
        ),
      );

  Widget _testsPicker() {
    if (_selectedTests.isEmpty) {
      return GestureDetector(
        onTap: _pickTests,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: const Row(children: [
            Icon(Icons.science_outlined, color: AppColors.info),
            SizedBox(width: 12),
            Expanded(
              child: Text('Tap to search and select tests',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted),
          ]),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _selectedTests.map((t) {
            return Chip(
              label: Text(t.code.isEmpty ? t.name : '${t.code} — ${t.name}'),
              backgroundColor: AppColors.info.withOpacity(.12),
              labelStyle:
                  const TextStyle(color: AppColors.info, fontSize: 12),
              side: BorderSide(color: AppColors.info.withOpacity(.4)),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () => setState(() {
                _selectedTests.remove(t);
                _labClinicId = null;
                _labName = '';
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _pickTests,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add more tests'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.info,
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _labPicker(String clinicId) {
    if (clinicId.isEmpty) {
      return const Text('No clinic linked.',
          style: TextStyle(color: AppColors.textMuted));
    }
    if (_selectedTests.isEmpty) {
      return const Text(
        'Select at least one test to see labs that offer it.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      );
    }

    final testKeysCsv = _selectedTests.map((t) => t.key).join('|');
    final labsAsync = ref.watch(_labsForTestsProvider((
      clinicId: clinicId,
      testKeysCsv: testKeysCsv,
    )));

    return labsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(color: AppColors.primary),
      ),
      error: (e, _) =>
          Text('$e', style: const TextStyle(color: AppColors.error)),
      data: (labs) {
        if (labs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(.1),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.warning.withOpacity(.3)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline,
                  color: AppColors.warning, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No single linked lab offers all selected tests. Deselect a test or place two separate orders.',
                  style: TextStyle(
                      color: AppColors.warning, fontSize: 12),
                ),
              ),
            ]),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _labClinicId,
              isExpanded: true,
              hint: const Text('Select lab',
                  style: TextStyle(color: AppColors.textMuted)),
              dropdownColor: AppColors.surfaceElevated,
              style: const TextStyle(color: AppColors.textPrimary),
              items: labs
                  .map((l) => DropdownMenuItem<String>(
                        value: l['labClinicId'] as String,
                        child: Text(l['labName'] as String),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                final l = labs.firstWhere((x) => x['labClinicId'] == v);
                setState(() {
                  _labClinicId = v;
                  _labName = l['labName'] as String;
                });
              },
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------
// Linked labs that offer ALL selected tests
// -----------------------------------------------------------------
typedef _LabsForTestsKey = ({String clinicId, String testKeysCsv});

/// Canonical key — normalized CODE only. Mirrors
/// `canonicalTestKey` in `lab_test_picker_sheet.dart` so both sides
/// of the match use the same string.
String _canonTestKey(String code) {
  return code
      .replaceAll('\u00A0', ' ')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
}

final _labsForTestsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, _LabsForTestsKey>((ref, key) async {
  // testKeysCsv is a '|'-joined list of AggregatedTest.key values.
  // By contract, AggregatedTest.key == normalized test CODE.
  final testCodes = key.testKeysCsv.isEmpty
      ? const <String>[]
      : key.testKeysCsv
          .split('|')
          .map(_canonTestKey)
          .where((s) => s.isNotEmpty)
          .toList();

  if (testCodes.isEmpty) return const <Map<String, dynamic>>[];

  final catalogs = await ref
      .read(labServiceProvider)
      .watchLinkedCatalogs(key.clinicId)
      .first;

  final offerings = <String, Set<String>>{};
  final labInfo = <String, Map<String, dynamic>>{};

  for (final lab in catalogs) {
    labInfo[lab.labClinicId] = {
      'labClinicId': lab.labClinicId,
      'labName': lab.labName,
    };
    for (final raw in lab.tests) {
      if (raw is! Map) continue;
      final code = (raw['code'] ?? raw['localCode'] ?? '').toString();
      if (code.isEmpty) continue;
      final ck = _canonTestKey(code);
      offerings.putIfAbsent(ck, () => <String>{}).add(lab.labClinicId);
    }
  }

  // Labs that offer ALL selected codes.
  Set<String>? intersection;
  for (final code in testCodes) {
    final labs = offerings[code] ?? const <String>{};
    intersection = intersection == null
        ? {...labs}
        : intersection.intersection(labs);
    if (intersection.isEmpty) break;
  }

  final result = <Map<String, dynamic>>[];
  for (final id in intersection ?? const <String>{}) {
    final info = labInfo[id];
    if (info != null) result.add(info);
  }
  result.sort((a, b) => (a['labName'] as String)
      .toLowerCase()
      .compareTo((b['labName'] as String).toLowerCase()));
  return result;
});

// -----------------------------------------------------------------
// Patient picker
// -----------------------------------------------------------------
class _PatientPickerScreen extends ConsumerStatefulWidget {
  final String clinicId;
  const _PatientPickerScreen({required this.clinicId});

  @override
  ConsumerState<_PatientPickerScreen> createState() =>
      _PatientPickerScreenState();
}

class _PatientPickerScreenState extends ConsumerState<_PatientPickerScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync =
        ref.watch(_patientsForClinicProvider(widget.clinicId));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Select Patient')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _q = v.trim()),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Search by name or PT-...',
                prefixIcon:
                    Icon(Icons.search, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: patientsAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary)),
                error: (e, _) => Center(
                    child: Text('$e',
                        style: const TextStyle(
                            color: AppColors.error))),
                data: (list) {
                  final filtered = _q.isEmpty
                      ? list
                      : list.where((p) {
                          final s = _q.toLowerCase();
                          return p.fullName.toLowerCase().contains(s) ||
                              p.patientId.toLowerCase().contains(s) ||
                              p.phone.contains(_q);
                        }).toList();
                  if (filtered.isEmpty) {
                    return const Center(
                        child: Text('No patients found',
                            style: TextStyle(
                                color: AppColors.textMuted)));
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      return ListTile(
                        tileColor: AppColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(
                              color: AppColors.cardBorder),
                        ),
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withOpacity(.15),
                          child: Text(
                            p.fullName.isNotEmpty
                                ? p.fullName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: AppColors.primary),
                          ),
                        ),
                        title: Text(p.fullName, style: AppTextStyles.body),
                        subtitle: Text('${p.patientId} • ${p.phone}',
                            style: AppTextStyles.caption),
                        onTap: () => Navigator.of(context).pop(p),
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

final _patientsForClinicProvider = StreamProvider.autoDispose
    .family<List<PatientModel>, String>((ref, clinicId) {
  return ref.read(patientServiceProvider).watchPatients(
        clinicId: clinicId,
      );
});