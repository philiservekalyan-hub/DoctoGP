// lib/features/lab/presentation/package_editor_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';

/// Fetch the selected offerings (from catalog/main so prices are
/// included) for the live preview.
typedef _OfferingPriceKey = ({
  String labClinicId,
  List<String> offeringIds,
});

final _selectedOfferingsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, _OfferingPriceKey>((ref, key) async {
  if (key.offeringIds.isEmpty) return const [];
  final catSnap = await FirebaseFirestore.instance
      .collection('clinics')
      .doc(key.labClinicId)
      .collection('catalog')
      .doc('main')
      .get();
  final allTests =
      (catSnap.data()?['tests'] as List?)?.cast<Map>() ?? const [];
  final byOfferingId = <String, Map<String, dynamic>>{};
  for (final t in allTests) {
    final m = Map<String, dynamic>.from(t);
    if (m['isPackage'] == true) continue;
    final id = (m['offeringId'] ?? '').toString();
    if (id.isNotEmpty) byOfferingId[id] = m;
  }
  return key.offeringIds
      .map((id) => byOfferingId[id])
      .whereType<Map<String, dynamic>>()
      .toList();
});

class PackageEditorScreen extends ConsumerStatefulWidget {
  final String labClinicId;
  final Map<String, dynamic>? existing;

  const PackageEditorScreen({
    super.key,
    required this.labClinicId,
    this.existing,
  });

  bool get isEdit => existing != null;

  @override
  ConsumerState<PackageEditorScreen> createState() =>
      _PackageEditorScreenState();
}

class _PackageEditorScreenState
    extends ConsumerState<PackageEditorScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _tatCtrl;
  late final TextEditingController _notesCtrl;

  final Set<String> _selectedOfferingIds = {};
  bool _active = true;
  bool _saving = false;
  String? _nameError;
  String? _testsError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: (e?['name'] ?? '').toString());
    _descCtrl =
        TextEditingController(text: (e?['description'] ?? '').toString());
    _tatCtrl = TextEditingController(
      text: e?['turnaroundHours']?.toString() ?? '',
    );
    _notesCtrl =
        TextEditingController(text: (e?['notes'] ?? '').toString());

    if (e != null) {
      final ids = (e['includedTestOfferingIds'] as List?)
              ?.cast<String>() ??
          const <String>[];
      _selectedOfferingIds.addAll(ids);
      _active = e['active'] != false;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _tatCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _nameError = null;
      _testsError = null;
    });

    final name = _nameCtrl.text.trim();
    var hasError = false;
    if (name.length < 3) {
      setState(() =>
          _nameError = 'Name must be at least 3 characters.');
      hasError = true;
    }
    if (_selectedOfferingIds.isEmpty) {
      setState(() =>
          _testsError = 'Select at least one test for this package.');
      hasError = true;
    }
    if (hasError) return;

    setState(() => _saving = true);
    try {
      final service = ref.read(labServiceProvider);
      final tat = int.tryParse(_tatCtrl.text.trim());
      final notes = _notesCtrl.text.trim().isEmpty
          ? null
          : _notesCtrl.text.trim();
      final description = _descCtrl.text.trim().isEmpty
          ? null
          : _descCtrl.text.trim();

      if (widget.isEdit) {
        await service.updatePackage(
          labClinicId: widget.labClinicId,
          packageId: (widget.existing!['packageId'] ?? '').toString(),
          name: name,
          description: description,
          offeringIds: _selectedOfferingIds.toList(),
          turnaroundHours: tat,
          active: _active,
          notes: notes,
        );
      } else {
        await service.createPackage(
          labClinicId: widget.labClinicId,
          name: name,
          description: description,
          offeringIds: _selectedOfferingIds.toList(),
          turnaroundHours: tat,
          notes: notes,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(widget.isEdit
            ? 'Package updated.'
            : 'Package created.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTests() async {
    final offeringList = await ref
        .read(labServiceProvider)
        .watchLabTests(
            labClinicId: widget.labClinicId, includeInactive: false)
        .first;
    final pickerList = offeringList
        .map((t) => <String, dynamic>{
              'offeringId': t.id,
              'code': t.code,
              'name': t.name,
              'category': t.category,
              'sampleType': t.sampleType,
            })
        .toList();
    if (!mounted) return;
    if (pickerList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Add tests to your catalogue first before building a package.'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }
    final chosen = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TestPickerSheet(
        offerings: pickerList,
        preselected: _selectedOfferingIds,
      ),
    );
    if (chosen != null && mounted) {
      setState(() {
        _selectedOfferingIds
          ..clear()
          ..addAll(chosen);
      });
    }
  }

  Future<void> _deletePackage() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete package?', style: AppTextStyles.h3),
        content: const Text(
          'The package will be removed from your catalogue. '
          'Orders placed with it remain intact.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await ref.read(labServiceProvider).deletePackage(
            labClinicId: widget.labClinicId,
            packageId:
                (widget.existing!['packageId'] ?? '').toString(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Package deleted.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Edit package' : 'Create package'),
        actions: [
          if (widget.isEdit)
            IconButton(
              tooltip: 'Delete package',
              onPressed: _saving ? null : _deletePackage,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GlassCard(
              borderColor: AppColors.accent.withOpacity(.35),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppColors.accent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Package pricing is calculated automatically: '
                    'MRP = sum of the included tests\' MRP, and '
                    'offer price = sum of their offer prices.',
                    style: AppTextStyles.caption,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            _label('Package name'),
            _input(
              controller: _nameCtrl,
              hint: 'e.g. Full Body Checkup',
              errorText: _nameError,
            ),

            _label('Description (optional)'),
            _input(
              controller: _descCtrl,
              hint: 'e.g. Comprehensive annual screening',
              maxLines: 3,
            ),

            _label('Turnaround hours (optional)'),
            _input(
              controller: _tatCtrl,
              hint: 'e.g. 48',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),

            _label('Included tests'),
            if (_testsError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_testsError!,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.error)),
              ),
            _includedTestsSection(),

            _label('Notes for clinic (optional)'),
            _input(
              controller: _notesCtrl,
              hint: 'e.g. Report available in 2 working days',
              maxLines: 3,
            ),

            if (widget.isEdit) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Active', style: AppTextStyles.body),
                subtitle: Text(
                  'Inactive packages are hidden from the doctor picker.',
                  style: AppTextStyles.caption,
                ),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                activeColor: AppColors.primary,
              ),
            ],

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(widget.isEdit
                        ? 'Save changes'
                        : 'Create package'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _includedTestsSection() {
    if (_selectedOfferingIds.isEmpty) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _pickTests,
        child: GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.info),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tap to pick tests for this package',
                  style: AppTextStyles.body
                      .copyWith(color: AppColors.textMuted),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted),
            ]),
          ),
        ),
      );
    }

    final offeringsAsync = ref.watch(_selectedOfferingsProvider((
      labClinicId: widget.labClinicId,
      offeringIds: _selectedOfferingIds.toList(),
    )));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            child: Row(children: [
              Text(
                '${_selectedOfferingIds.length} test${_selectedOfferingIds.length == 1 ? "" : "s"} selected',
                style: AppTextStyles.body
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: _pickTests,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.info,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 0),
                  tapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Change',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        offeringsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(color: AppColors.primary),
          ),
          error: (e, _) => GlassCard(
              child: Text('Failed: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (offerings) {
            final allHavePrice =
                offerings.every((o) => o['mrp'] != null);
            double sumMrp = 0;
            double sumOffer = 0;
            for (final o in offerings) {
              sumMrp += (o['mrp'] as num?)?.toDouble() ?? 0;
              sumOffer += (o['offerPrice'] as num?)?.toDouble() ?? 0;
            }
            final hasDiscount = allHavePrice && sumOffer < sumMrp;
            final discountPercent = allHavePrice && sumMrp > 0
                ? ((sumMrp - sumOffer) / sumMrp * 100).round()
                : 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final t in offerings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(children: [
                          Expanded(
                            child: Text(
                              '${t['code'] ?? ''} — ${t['name'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body,
                            ),
                          ),
                          if (t['mrp'] != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '₹${(t['mrp'] as num).toStringAsFixed(0)}',
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.textMuted),
                            ),
                          ] else
                            Text(
                              'no price',
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.warning),
                            ),
                        ]),
                      ),
                    ),
                  ),
                if (!allHavePrice)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: GlassCard(
                      borderColor: AppColors.warning.withOpacity(.4),
                      child: Row(children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppColors.warning, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Some tests in this package don\'t have a price. '
                            'Set their individual prices first so the '
                            'package price can be calculated.',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.warning),
                          ),
                        ),
                      ]),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: GlassCard(
                      borderColor: AppColors.success.withOpacity(.35),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          const Icon(Icons.receipt_long_rounded,
                              color: AppColors.success, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Computed package price',
                                style: AppTextStyles.body
                                    .copyWith(
                                        fontWeight: FontWeight.w600)),
                          ),
                          if (hasDiscount) ...[
                            Text(
                              '₹${sumMrp.toStringAsFixed(0)}',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textMuted,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            '₹${sumOffer.toStringAsFixed(0)}',
                            style: AppTextStyles.h3
                                .copyWith(color: AppColors.success),
                          ),
                          if (hasDiscount) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.success.withOpacity(.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('$discountPercent% off',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700,
                                  )),
                            ),
                          ],
                        ]),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(s, style: AppTextStyles.caption),
      );

  Widget _input({
    required TextEditingController controller,
    required String hint,
    String? errorText,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return GlassCard(
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: AppTextStyles.body,
        decoration: InputDecoration(
          hintText: hint,
          errorText: errorText,
          border: InputBorder.none,
          isCollapsed: true,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------
// Test picker sheet
// -----------------------------------------------------------------

class _TestPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> offerings;
  final Set<String> preselected;
  const _TestPickerSheet({
    required this.offerings,
    required this.preselected,
  });

  @override
  State<_TestPickerSheet> createState() => _TestPickerSheetState();
}

class _TestPickerSheetState extends State<_TestPickerSheet> {
  final _search = TextEditingController();
  late final Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = {...widget.preselected};
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filtered() {
    if (_query.isEmpty) return widget.offerings;
    final q = _query.toLowerCase();
    return widget.offerings
        .where((t) =>
            (t['code'] ?? '')
                .toString()
                .toLowerCase()
                .contains(q) ||
            (t['name'] ?? '')
                .toString()
                .toLowerCase()
                .contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered();

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
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Text('Pick tests', style: AppTextStyles.h3),
                const Spacer(),
                Text('${_selected.length} selected',
                    style: AppTextStyles.caption),
              ]),
            ),
            const SizedBox(height: 12),
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
            const Divider(height: 1),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('No tests match',
                          style: TextStyle(color: Colors.grey)),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final t = filtered[i];
                        final id = (t['offeringId'] ?? '').toString();
                        final isSel = _selected.contains(id);
                        return CheckboxListTile(
                          value: isSel,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          }),
                          title: Text(
                            '${t['code'] ?? ''} — ${t['name'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body,
                          ),
                          subtitle: Text(
                            '${t['category'] ?? ''} • ${t['sampleType'] ?? ''}',
                            style: AppTextStyles.caption,
                          ),
                          activeColor: AppColors.primary,
                        );
                      },
                    ),
            ),
            SafeArea(
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(
                      top: BorderSide(color: AppColors.cardBorder)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).pop(_selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _selected.isEmpty
                          ? 'Select tests'
                          : 'Use ${_selected.length} test${_selected.length == 1 ? "" : "s"}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600),
                    ),
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