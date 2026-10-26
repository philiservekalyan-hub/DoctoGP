// lib/features/doctor/presentation/widgets/icd10_search_field.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/models/icd10_code.dart';

/// Bundled search field for ICD-10 codes.
///
/// Loads `assets/data/icd10_fallback.json` once on first use, then
/// filters client-side. No network, no download, no service.
///
/// Phase 2 upgrade path: replace the local `_allCodes` list with a
/// list populated by an `Icd10Service` that downloads the full set
/// from Firebase Storage. Everything else — the widget, its search
/// ranking, its UI — stays exactly the same.
class Icd10SearchField extends StatefulWidget {
  final Icd10Code? initial;
  final ValueChanged<Icd10Code> onSelected;
  final String label;
  final bool readOnly;

  const Icd10SearchField({
    super.key,
    this.initial,
    required this.onSelected,
    this.label = 'Diagnosis (ICD-10)',
    this.readOnly = false,
  });

  @override
  State<Icd10SearchField> createState() => _Icd10SearchFieldState();
}

class _Icd10SearchFieldState extends State<Icd10SearchField> {
  static List<Icd10Code>? _cachedCodes;

  Icd10Code? _selected;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    if (_cachedCodes == null) _loadCodes();
  }

  @override
  void didUpdateWidget(covariant Icd10SearchField old) {
    super.didUpdateWidget(old);
    if (widget.initial != old.initial) _selected = widget.initial;
  }

  Future<void> _loadCodes() async {
    if (_cachedCodes != null) return;
    setState(() => _loading = true);
    try {
      final raw =
          await rootBundle.loadString('assets/data/icd10_fallback.json');
      _cachedCodes = (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>()
          .map(Icd10Code.fromJson)
          .toList();
    } catch (_) {
      _cachedCodes = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPicker() async {
    if (widget.readOnly || _cachedCodes == null) return;
    final picked = await showModalBottomSheet<Icd10Code>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _Icd10PickerSheet(
        allCodes: _cachedCodes!,
        initial: _selected,
      ),
    );
    if (picked != null) {
      setState(() => _selected = picked);
      widget.onSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AppTextStyles.caption),
        const SizedBox(height: 6),
        InkWell(
          onTap: (widget.readOnly || _loading) ? null : _openPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(children: [
              const Icon(Icons.search_rounded,
                  size: 18, color: AppColors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _selected == null
                      ? (_loading
                          ? 'Loading codes…'
                          : 'Tap to search ICD-10 code')
                      : '${_selected!.code} — ${_selected!.description}',
                  style: _selected == null
                      ? AppTextStyles.body
                          .copyWith(color: AppColors.textMuted)
                      : AppTextStyles.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.readOnly)
                const Icon(Icons.lock_outline,
                    size: 14, color: AppColors.textMuted),
            ]),
          ),
        ),
      ],
    );
  }
}

class _Icd10PickerSheet extends StatefulWidget {
  final List<Icd10Code> allCodes;
  final Icd10Code? initial;
  const _Icd10PickerSheet({
    required this.allCodes,
    this.initial,
  });

  @override
  State<_Icd10PickerSheet> createState() => _Icd10PickerSheetState();
}

class _Icd10PickerSheetState extends State<_Icd10PickerSheet> {
  final _search = TextEditingController();
  List<Icd10Code> _results = const [];

  @override
  void initState() {
    super.initState();
    _runSearch('');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _runSearch(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _results = widget.allCodes.take(30).toList());
      return;
    }
    final exact = <Icd10Code>[];
    final codePrefix = <Icd10Code>[];
    final descPrefix = <Icd10Code>[];
    final descContains = <Icd10Code>[];
    for (final c in widget.allCodes) {
      if (c.codeLower == query) {
        exact.add(c);
      } else if (c.codeLower.startsWith(query)) {
        codePrefix.add(c);
      } else if (c.descriptionLower.startsWith(query)) {
        descPrefix.add(c);
      } else if (c.descriptionLower.contains(query)) {
        descContains.add(c);
      }
    }
    setState(() {
      _results = <Icd10Code>[
        ...exact,
        ...codePrefix,
        ...descPrefix,
        ...descContains,
      ].take(50).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
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
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Select diagnosis',
                  style: AppTextStyles.h3),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search by code or description',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _search.clear();
                            _runSearch('');
                          },
                        ),
                ),
                onChanged: _runSearch,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: _results.isEmpty
                  ? const Center(
                      child: Text('No matches',
                          style: TextStyle(color: Colors.grey)),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: _results.length,
                      itemBuilder: (_, i) {
                        final c = _results[i];
                        return ListTile(
                          title: Text(c.description,
                              style: AppTextStyles.body),
                          subtitle: Text(c.code,
                              style: AppTextStyles.caption.copyWith(
                                  fontWeight: FontWeight.w600)),
                          trailing: widget.initial?.code == c.code
                              ? const Icon(Icons.check,
                                  color: AppColors.success)
                              : null,
                          onTap: () => Navigator.of(context).pop(c),
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