import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/lab_order_model.dart';
import '../../../core/models/lab_test_model.dart';
import '../../../core/models/patient_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/labeled_field.dart';

class LabWalkinOrderScreen extends ConsumerStatefulWidget {
  const LabWalkinOrderScreen({super.key});

  @override
  ConsumerState<LabWalkinOrderScreen> createState() =>
      _LabWalkinOrderScreenState();
}

class _LabWalkinOrderScreenState
    extends ConsumerState<LabWalkinOrderScreen> {
  PatientModel? _patient;
  final List<LabTestModel> _selectedTests = [];
  final _amountCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPatient() async {
    final user = await ref.read(currentUserProvider.future);
    if (user?.clinicId == null) return;
    final result = await Navigator.of(context).push<PatientModel>(
      MaterialPageRoute(
        builder: (_) =>
            _WalkInPatientPickerScreen(clinicId: user!.clinicId!),
      ),
    );
    if (result != null && mounted) setState(() => _patient = result);
  }

  Future<void> _pickTests(String labClinicId) async {
    final allTests = await ref
        .read(labServiceProvider)
        .watchLabTests(labClinicId: labClinicId)
        .first;
    if (!mounted) return;
    final result = await showModalBottomSheet<List<LabTestModel>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LabCatalogPickerSheet(
        allTests: allTests,
        preselected: _selectedTests,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedTests
          ..clear()
          ..addAll(result);
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_patient == null) {
      _snack('Pick a patient.', AppColors.error);
      return;
    }
    if (_selectedTests.isEmpty) {
      _snack('Select at least one test.', AppColors.error);
      return;
    }

    setState(() => _saving = true);
    try {
      final user = await ref.read(currentUserProvider.future);
      if (user == null || user.clinicId == null) {
        _snack('No lab linked to your account.', AppColors.error);
        return;
      }

      final amount = double.tryParse(_amountCtrl.text.trim());

      await ref.read(labServiceProvider).createOrder(
            referringClinicId: null, // walk-in
            labClinicId: user.clinicId!,
            labName: user.clinicName ?? 'Lab',
            patientDocId: _patient!.docId,
            patientId: _patient!.patientId,
            patientName: _patient!.fullName,
            patientPhone: _patient!.phone,
            doctorDocId: null, // walk-in
            doctorName: null,
            tests: _selectedTests
                .map((t) => LabTestItem(
                      code: t.code.isEmpty ? null : t.code,
                      name: t.name,
                    ))
                .toList(),
            instructions: _instructionsCtrl.text.trim().isEmpty
                ? null
                : _instructionsCtrl.text.trim(),
            billableAmount: amount,
          );

      if (!mounted) return;
      _snack('Walk-in order created.', AppColors.success);
      Navigator.of(context).pop(true);
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
      appBar: AppBar(title: const Text('New walk-in order')),
      body: userAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('$e')),
        data: (user) {
          final labClinicId = user?.clinicId ?? '';
          if (labClinicId.isEmpty) {
            return const Center(
                child: Text('No lab linked to this account.'));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Walk-in patient', style: AppTextStyles.h3),
              const SizedBox(height: 4),
              Text(
                'No referral — patient walked into the lab directly.',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 20),
              LabeledField(
                label: 'Patient',
                required: true,
                child: _patientPicker(),
              ),
              LabeledField(
                label: 'Tests',
                required: true,
                child: _testsPicker(labClinicId),
              ),
              LabeledField(
                label: 'Amount to collect (optional)',
                child: DarkTextField(
                  controller: _amountCtrl,
                  hint: 'e.g. 500',
                ),
              ),
              LabeledField(
                label: 'Instructions (optional)',
                child: DarkTextField(
                  controller: _instructionsCtrl,
                  hint: 'e.g. Fasting sample, 8–10 hrs',
                  maxLines: 3,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                      _saving ? 'Creating...' : 'Create walk-in order'),
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
                        Text(
                            '${_patient!.patientId} • ${_patient!.phone}',
                            style: AppTextStyles.caption),
                      ],
                    ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted),
          ]),
        ),
      );

  Widget _testsPicker(String labClinicId) {
    if (_selectedTests.isEmpty) {
      return GestureDetector(
        onTap: () => _pickTests(labClinicId),
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
              child: Text('Tap to select tests from your catalog',
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
              label: Text(
                  t.code.isEmpty ? t.name : '${t.code} — ${t.name}'),
              backgroundColor: AppColors.info.withOpacity(.12),
              labelStyle: const TextStyle(
                  color: AppColors.info, fontSize: 12),
              side: BorderSide(
                  color: AppColors.info.withOpacity(.4)),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () =>
                  setState(() => _selectedTests.remove(t)),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _pickTests(labClinicId),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Add more tests'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.info,
            textStyle: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------
// Walk-in patient picker
// -----------------------------------------------------------------
class _WalkInPatientPickerScreen extends ConsumerStatefulWidget {
  final String clinicId;
  const _WalkInPatientPickerScreen({required this.clinicId});

  @override
  ConsumerState<_WalkInPatientPickerScreen> createState() =>
      _WalkInPatientPickerScreenState();
}

class _WalkInPatientPickerScreenState
    extends ConsumerState<_WalkInPatientPickerScreen> {
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
                        title:
                            Text(p.fullName, style: AppTextStyles.body),
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

// -----------------------------------------------------------------
// Catalog picker — selects LabTestModel objects directly.
// No dependency on an `id` field.
// -----------------------------------------------------------------
class _LabCatalogPickerSheet extends StatefulWidget {
  final List<LabTestModel> allTests;
  final List<LabTestModel> preselected;

  const _LabCatalogPickerSheet({
    required this.allTests,
    required this.preselected,
  });

  @override
  State<_LabCatalogPickerSheet> createState() =>
      _LabCatalogPickerSheetState();
}

class _LabCatalogPickerSheetState
    extends State<_LabCatalogPickerSheet> {
  late final List<LabTestModel> _selected;
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    _selected = [...widget.preselected];
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _isSelected(LabTestModel t) => _selected.contains(t);

  void _toggle(LabTestModel t) {
    setState(() {
      if (_selected.contains(t)) {
        _selected.remove(t);
      } else {
        _selected.add(t);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.allTests
        : widget.allTests.where((t) {
            final s = _q.toLowerCase();
            return t.code.toLowerCase().contains(s) ||
                t.name.toLowerCase().contains(s);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Text('Select tests', style: AppTextStyles.h3),
                const Spacer(),
                Text('${_selected.length} selected',
                    style: AppTextStyles.caption),
              ]),
            ),
            const SizedBox(height: 12),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _q = v.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search by code or name',
                  prefixIcon: Icon(Icons.search,
                      color: AppColors.textMuted),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('No tests match',
                          style: TextStyle(
                              color: AppColors.textMuted)))
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final t = filtered[i];
                        return CheckboxListTile(
                          value: _isSelected(t),
                          onChanged: (_) => _toggle(t),
                          title: Text(
                              t.code.isEmpty
                                  ? t.name
                                  : '${t.code} — ${t.name}',
                              style: AppTextStyles.body),
                          subtitle: t.sampleType.isNotEmpty
                              ? Text(t.sampleType,
                                  style: AppTextStyles.caption)
                              : null,
                          activeColor: AppColors.info,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_selected),
                  child: Text(
                      'Add ${_selected.length} test${_selected.length == 1 ? '' : 's'}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}