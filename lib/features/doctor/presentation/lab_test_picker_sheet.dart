// lib/features/doctor/presentation/lab_test_picker_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';

class AggregatedTest {
  final String code;
  final String name;
  final String category;
  final String sampleType;
  final bool fastingRequired;
  final int? turnaroundHours;
  final List<String> offeringLabIds;
  final List<String> offeringLabNames;

  AggregatedTest({
    required this.code,
    required this.name,
    required this.category,
    required this.sampleType,
    required this.fastingRequired,
    required this.turnaroundHours,
    required this.offeringLabIds,
    required this.offeringLabNames,
  });

  String get key => '${code}_$name';
  String get display => code.isEmpty ? name : '$code — $name';
}

class LabTestPickerSheet extends ConsumerStatefulWidget {
  final String clinicId;
  final List<String> preselectedKeys;
  const LabTestPickerSheet({
    super.key,
    required this.clinicId,
    this.preselectedKeys = const [],
  });

  @override
  ConsumerState<LabTestPickerSheet> createState() =>
      _LabTestPickerSheetState();
}

class _LabTestPickerSheetState
    extends ConsumerState<LabTestPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _selectedKeys = {};

  List<AggregatedTest> _allTests = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedKeys.addAll(widget.preselectedKeys);
    _load();
  }

  Future<void> _load() async {
    try {
      final catalogs = await ref
          .read(labServiceProvider)
          .watchLinkedCatalogs(widget.clinicId)
          .first;

      final grouped = <String, AggregatedTest>{};

      for (final lab in catalogs) {
        for (final raw in lab.tests) {
          if (raw is! Map) continue;
          final code = (raw['code'] ?? '').toString();
          final name = (raw['name'] ?? '').toString();
          if (code.isEmpty && name.isEmpty) continue;

          final key = '${code}_$name';
          final existing = grouped[key];
          if (existing != null) {
            existing.offeringLabIds.add(lab.labClinicId);
            existing.offeringLabNames.add(lab.labName);
          } else {
            grouped[key] = AggregatedTest(
              code: code,
              name: name,
              category: (raw['category'] ?? 'Other').toString(),
              sampleType: (raw['sampleType'] ?? 'Blood').toString(),
              fastingRequired: raw['fastingRequired'] == true,
              turnaroundHours: raw['turnaroundHours'] is num
                  ? (raw['turnaroundHours'] as num).toInt()
                  : null,
              offeringLabIds: [lab.labClinicId],
              offeringLabNames: [lab.labName],
            );
          }
        }
      }

      final list = grouped.values.toList()
        ..sort((a, b) =>
            a.display.toLowerCase().compareTo(b.display.toLowerCase()));

      if (mounted) {
        setState(() {
          _allTests = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<AggregatedTest> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _allTests;
    return _allTests.where((t) {
      final haystack =
          '${t.code} ${t.name} ${t.category} ${t.sampleType}'.toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final selectedTests =
        _allTests.where((t) => _selectedKeys.contains(t.key)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child:
                        Text('Select tests', style: AppTextStyles.h3),
                  ),
                  if (_selectedKeys.isNotEmpty)
                    TextButton(
                      onPressed: () =>
                          setState(() => _selectedKeys.clear()),
                      child: const Text('Clear'),
                    ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, selectedTests),
                    child: Text(
                      'Done (${_selectedKeys.length})',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Search by code, name, or category',
                  prefixIcon:
                      Icon(Icons.search, color: AppColors.textMuted),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (selectedTests.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: selectedTests.take(6).map((t) {
                      return Chip(
                        label: Text(
                            t.code.isEmpty ? t.name : t.code,
                            style: const TextStyle(fontSize: 11)),
                        backgroundColor:
                            AppColors.primary.withOpacity(.15),
                        labelStyle:
                            const TextStyle(color: AppColors.primary),
                        deleteIcon:
                            const Icon(Icons.close, size: 12),
                        onDeleted: () => setState(
                            () => _selectedKeys.remove(t.key)),
                      );
                    }).toList(),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('Failed to load: $_error',
                                style: const TextStyle(
                                    color: AppColors.error)),
                          ),
                        )
                      : filtered.isEmpty
                          ? const Center(
                              child: Text(
                                  'No tests match your search',
                                  style: TextStyle(
                                      color: AppColors.textMuted)),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) => Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 8),
                                child: _TestRow(
                                  test: filtered[i],
                                  selected: _selectedKeys
                                      .contains(filtered[i].key),
                                  onToggle: () {
                                    setState(() {
                                      if (_selectedKeys.contains(
                                          filtered[i].key)) {
                                        _selectedKeys
                                            .remove(filtered[i].key);
                                      } else {
                                        _selectedKeys
                                            .add(filtered[i].key);
                                      }
                                    });
                                  },
                                ),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestRow extends StatelessWidget {
  final AggregatedTest test;
  final bool selected;
  final VoidCallback onToggle;

  const _TestRow({
    required this.test,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: selected
          ? AppColors.primary.withOpacity(.5)
          : AppColors.cardBorder,
      padding: const EdgeInsets.all(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onToggle,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: selected,
              onChanged: (_) => onToggle(),
              activeColor: AppColors.primary,
              side: const BorderSide(color: AppColors.textMuted),
            ),
            const SizedBox(width: 4),
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
                  const SizedBox(height: 4),
                  Text(
                    'Offered by ${test.offeringLabNames.join(", ")}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.info,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}