// lib/features/lab/presentation/canonical_test_picker_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/lab_test_model.dart';
import '../../../core/services/canonical_test_service.dart';

/// Multi-select picker for adding canonical tests to a lab's catalogue.
///
/// Returns the list of selected `testId`s when the user taps "Add".
/// Search and category chips narrow the list; selections persist across
/// chip changes so a lab can pick CBC from Haematology and LFT from
/// Biochemistry in one flow.
class CanonicalTestPickerSheet extends ConsumerStatefulWidget {
  final String labClinicId;
  const CanonicalTestPickerSheet({super.key, required this.labClinicId});

  @override
  ConsumerState<CanonicalTestPickerSheet> createState() =>
      _CanonicalTestPickerSheetState();
}

class _CanonicalTestPickerSheetState
    extends ConsumerState<CanonicalTestPickerSheet> {
  final _search = TextEditingController();
  final Set<String> _selected = {};
  String _query = '';
  LabTestCategory? _categoryFilter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final testsAsync = ref.watch(activeCanonicalTestsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Handle bar ──
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            // ── Header ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Text('Add tests', style: AppTextStyles.h3),
                const Spacer(),
                Text(
                  '${_selected.length} selected',
                  style: AppTextStyles.caption,
                ),
              ]),
            ),
            const SizedBox(height: 12),

            // ── Search ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search by code or name',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Category chips ──
            _categoryChips(),
            const SizedBox(height: 8),
            const Divider(height: 1),

            // ── Test list ──
            Expanded(
              child: testsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primary),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Failed to load tests: $e',
                      style: const TextStyle(color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                data: (all) {
                  final filtered = _applyFilters(all);
                  if (filtered.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off_rounded,
                                size: 48, color: AppColors.textMuted),
                            const SizedBox(height: 12),
                            Text(
                              all.isEmpty
                                  ? 'No tests in the master dictionary yet.\nAsk your admin to add some.'
                                  : 'No tests match your search.',
                              style: AppTextStyles.bodyMuted,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: scrollCtrl,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _row(filtered[i]),
                  );
                },
              ),
            ),

            // ── Bottom action bar ──
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  List<CanonicalTestModel> _applyFilters(
      List<CanonicalTestModel> all) {
    var list = all;
    if (_categoryFilter != null) {
      list = list.where((t) => t.category == _categoryFilter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((t) =>
              t.codeLower.contains(q) || t.nameLower.contains(q))
          .toList();
    }
    return list;
  }

  Widget _categoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        _chip(
          label: 'All',
          selected: _categoryFilter == null,
          onTap: () => setState(() => _categoryFilter = null),
        ),
        for (final c in LabTestCategory.values) ...[
          const SizedBox(width: 6),
          _chip(
            label: c.label,
            selected: _categoryFilter == c,
            onTap: () => setState(() => _categoryFilter = c),
          ),
        ],
      ]),
    );
  }

   Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _row(CanonicalTestModel t) {
    final isSel = _selected.contains(t.testId);
    return CheckboxListTile(
      value: isSel,
      onChanged: (v) {
        setState(() {
          if (v == true) {
            _selected.add(t.testId);
          } else {
            _selected.remove(t.testId);
          }
        });
      },
      title: Text(
        t.code.isEmpty ? t.name : '${t.code} — ${t.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.body,
      ),
      subtitle: Text(
        '${t.category.label} • ${t.sampleType.label}'
        '${t.fastingRequired ? " • fasting" : ""}',
        style: AppTextStyles.caption,
      ),
      activeColor: AppColors.primary,
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.cardBorder)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.toList()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  AppColors.primary.withOpacity(.3),
              disabledForegroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _selected.isEmpty
                  ? 'Select tests to add'
                  : 'Add ${_selected.length} test${_selected.length == 1 ? "" : "s"}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}