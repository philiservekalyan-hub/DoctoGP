// lib/features/admin/presentation/canonical_tests_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/lab_test_model.dart';
import '../../../core/services/canonical_test_service.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';
import 'create_canonical_test_screen.dart';

class CanonicalTestsScreen extends ConsumerStatefulWidget {
  const CanonicalTestsScreen({super.key});

  @override
  ConsumerState<CanonicalTestsScreen> createState() =>
      _CanonicalTestsScreenState();
}

class _CanonicalTestsScreenState
    extends ConsumerState<CanonicalTestsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  LabTestCategory? _categoryFilter;
  bool _showInactive = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final testsAsync = ref.watch(allCanonicalTestsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ClinicAppBar(
        title: 'Test catalogue',
        showBackButton: true,
        extraActions: [
          IconButton(
            tooltip: _showInactive ? 'Hide inactive' : 'Show inactive',
            icon: Icon(
              _showInactive
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _showInactive = !_showInactive),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: () => _openCreate(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New test'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search by code or name',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _categoryChips(),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: testsAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary)),
                error: (e, _) => Center(
                    child: Text('Failed: $e',
                        style: const TextStyle(
                            color: AppColors.error))),
                data: (all) {
                  final filtered = _applyFilters(all);
                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.science_outlined,
                      title: all.isEmpty
                          ? 'No tests in the catalogue'
                          : 'No tests match these filters',
                      subtitle: all.isEmpty
                          ? 'Tap "New test" to create the first entry.'
                          : 'Try clearing the search or filter.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _testRow(context, filtered[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<CanonicalTestModel> _applyFilters(List<CanonicalTestModel> all) {
    var list = all;
    if (!_showInactive) {
      list = list.where((t) => t.active).toList();
    }
    if (_categoryFilter != null) {
      list = list
          .where((t) => t.category == _categoryFilter)
          .toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((t) =>
              t.codeLower.contains(q) ||
              t.nameLower.contains(q))
          .toList();
    }
    // Alphabetical by code
    list = [...list]..sort((a, b) => a.code.compareTo(b.code));
    return list;
  }

  Widget _categoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color:
                selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _testRow(BuildContext context, CanonicalTestModel t) {
    final inactive = !t.active;
    return Opacity(
      opacity: inactive ? 0.55 : 1,
      child: GlassCard(
        borderColor: inactive
            ? AppColors.textMuted.withOpacity(.3)
            : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openEdit(context, t),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      t.code,
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (inactive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withOpacity(.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Inactive',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.category_rounded,
                      size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(t.category.label,
                      style: AppTextStyles.caption),
                  const SizedBox(width: 10),
                  Icon(Icons.science_outlined,
                      size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(t.sampleType.label,
                      style: AppTextStyles.caption),
                  if (t.fastingRequired) ...[
                    const SizedBox(width: 10),
                    Icon(Icons.no_food_rounded,
                        size: 12, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text('Fasting',
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.warning)),
                  ],
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openCreate(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CreateCanonicalTestScreen(),
      ),
    );
  }

  void _openEdit(BuildContext context, CanonicalTestModel t) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateCanonicalTestScreen(existing: t),
      ),
    );
  }
}