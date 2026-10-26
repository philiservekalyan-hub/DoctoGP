// lib/features/lab/presentation/lab_test_catalog_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/lab_test_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/labeled_field.dart';

const kLabTestCategories = [
  'Haematology',
  'Biochemistry',
  'Microbiology',
  'Serology',
  'Urine',
  'Imaging',
  'Pathology',
  'Other',
];

const kLabSampleTypes = [
  'Blood',
  'Urine',
  'Stool',
  'Swab',
  'Sputum',
  'Imaging',
  'Other',
];

class LabTestCatalogScreen extends ConsumerWidget {
  const LabTestCatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Test catalog')),
      body: userAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(child: Text('$e')),
        data: (user) {
          final labClinicId = user?.clinicId;

          if (labClinicId == null || labClinicId.isEmpty) {
            return const EmptyState(
              icon: Icons.science_outlined,
              title: 'No lab linked',
              subtitle:
                  'Your account is not linked to a lab yet. Ask the clinic owner to link you.',
            );
          }

          final testsAsync = ref.watch(_labTestsProvider(labClinicId));

          return Stack(
            children: [
              testsAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary)),
                error: (e, _) => Center(child: Text('$e')),
                data: (tests) {
                  if (tests.isEmpty) {
                    return const EmptyState(
                      icon: Icons.list_alt_rounded,
                      title: 'No tests yet',
                      subtitle: 'Add the first test your lab offers.',
                    );
                  }
                  return ListView.separated(
                    padding:
                        const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: tests.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (_, i) => _TestCard(
                      test: tests[i],
                      labClinicId: labClinicId,
                    ),
                  );
                },
              ),
              Positioned(
                right: 20,
                bottom: 20,
                child: FloatingActionButton.extended(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _TestEditorScreen(
                        labClinicId: labClinicId,
                        existing: null,
                      ),
                    ),
                  ),
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.background,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add test'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

final _labTestsProvider = StreamProvider.autoDispose
    .family<List<LabTestModel>, String>((ref, labClinicId) {
  return ref
      .read(labServiceProvider)
      .watchLabTests(labClinicId: labClinicId, includeInactive: true);
});

class _TestCard extends ConsumerWidget {
  final LabTestModel test;
  final String labClinicId;
  const _TestCard({
    required this.test,
    required this.labClinicId,
  });

  Future<void> _confirmDeactivate(
      BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Deactivate test', style: AppTextStyles.h3),
        content: Text(
          'Doctors will no longer see "${test.display}" when ordering. Existing orders are unaffected.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(labServiceProvider).deactivateLabTest(
            labClinicId: labClinicId,
            testDocId: test.docId,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Test deactivated.'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inactive = !test.active;
    return GlassCard(
      borderColor: inactive
          ? AppColors.cardBorder
          : AppColors.info.withOpacity(.35),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color:
                (inactive ? AppColors.textMuted : AppColors.info)
                    .withOpacity(.13),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.science_outlined,
              color: inactive ? AppColors.textMuted : AppColors.info,
              size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(test.display, style: AppTextStyles.body),
              const SizedBox(height: 3),
              Text(
                '${test.category} • ${test.sampleType}'
                '${test.fastingRequired ? " • fasting" : ""}'
                '${test.turnaroundHours != null ? " • ~${test.turnaroundHours}h" : ""}',
                style: AppTextStyles.caption,
              ),
              if (inactive) ...[
                const SizedBox(height: 4),
                Text('Inactive',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.error)),
              ],
            ],
          ),
        ),
        IconButton(
          tooltip: 'Edit',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _TestEditorScreen(
                labClinicId: labClinicId,
                existing: test,
              ),
            ),
          ),
          icon: const Icon(Icons.edit_rounded,
              color: AppColors.textMuted, size: 20),
        ),
        if (test.active)
          IconButton(
            tooltip: 'Deactivate',
            onPressed: () => _confirmDeactivate(context, ref),
            icon: const Icon(Icons.pause_circle_outline_rounded,
                color: AppColors.warning, size: 20),
          ),
      ]),
    );
  }
}

class _TestEditorScreen extends ConsumerStatefulWidget {
  final String labClinicId;
  final LabTestModel? existing;
  const _TestEditorScreen({
    required this.labClinicId,
    this.existing,
  });

  @override
  ConsumerState<_TestEditorScreen> createState() =>
      _TestEditorScreenState();
}

class _TestEditorScreenState extends ConsumerState<_TestEditorScreen> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _tatCtrl;
  String _category = 'Other';
  String _sampleType = 'Blood';
  bool _fasting = false;
  bool _active = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _codeCtrl = TextEditingController(text: e?.code ?? '');
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _tatCtrl = TextEditingController(
        text: e?.turnaroundHours?.toString() ?? '');
    _category = e?.category ?? 'Other';
    _sampleType = e?.sampleType ?? 'Blood';
    _fasting = e?.fastingRequired ?? false;
    _active = e?.active ?? true;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _tatCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final code = _codeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Name is required.', AppColors.error);
      return;
    }
    if (code.isEmpty && name.isEmpty) {
      _snack('Enter at least a code or a name.', AppColors.error);
      return;
    }

    setState(() => _saving = true);
    try {
      final service = ref.read(labServiceProvider);
      final tat = int.tryParse(_tatCtrl.text.trim());
      if (widget.existing == null) {
        await service.createLabTest(
          labClinicId: widget.labClinicId,
          code: code,
          name: name,
          category: _category,
          sampleType: _sampleType,
          fastingRequired: _fasting,
          turnaroundHours: tat,
        );
      } else {
        await service.updateLabTest(
          labClinicId: widget.labClinicId,
          testDocId: widget.existing!.docId,
          code: code,
          name: name,
          category: _category,
          sampleType: _sampleType,
          fastingRequired: _fasting,
          turnaroundHours: tat,
          active: _active,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      _snack('Saved.', AppColors.success);
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
    final editing = widget.existing != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar:
          AppBar(title: Text(editing ? 'Edit test' : 'Add test')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          LabeledField(
            label: 'Code',
            required: true,
            child: DarkTextField(
              controller: _codeCtrl,
              hint: 'e.g. CBC',
            ),
          ),
          LabeledField(
            label: 'Name',
            required: true,
            child: DarkTextField(
              controller: _nameCtrl,
              hint: 'e.g. Complete Blood Count',
            ),
          ),
          LabeledField(
            label: 'Category',
            child: DropdownButtonFormField<String>(
              value: _category,
              dropdownColor: AppColors.surfaceElevated,
              decoration: const InputDecoration(),
              items: kLabTestCategories
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c,
                            style: const TextStyle(
                                color: AppColors.textPrimary)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _category = v);
              },
            ),
          ),
          LabeledField(
            label: 'Sample type',
            child: DropdownButtonFormField<String>(
              value: _sampleType,
              dropdownColor: AppColors.surfaceElevated,
              decoration: const InputDecoration(),
              items: kLabSampleTypes
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c,
                            style: const TextStyle(
                                color: AppColors.textPrimary)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _sampleType = v);
              },
            ),
          ),
          LabeledField(
            label: 'Turnaround hours (optional)',
            child: DarkTextField(
              controller: _tatCtrl,
              hint: 'e.g. 24',
              keyboardType: TextInputType.number,
            ),
          ),
          Row(children: [
            Expanded(
              child: CheckboxListTile(
                value: _fasting,
                onChanged: (v) =>
                    setState(() => _fasting = v ?? false),
                title: const Text('Fasting required',
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 14)),
                activeColor: AppColors.primary,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          ]),
          if (editing)
            CheckboxListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v ?? true),
              title: const Text('Active',
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 14)),
              subtitle: const Text(
                  'Inactive tests are hidden from the doctor\'s picker.',
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 11)),
              activeColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving...' : 'Save'),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}