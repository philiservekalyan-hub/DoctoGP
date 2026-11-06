// lib/features/lab/presentation/lab_test_catalog_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import 'canonical_test_picker_sheet.dart';
import 'local_test_editor_screen.dart';
import 'package_editor_screen.dart';

final _catalogProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, labClinicId) {
  return ref
      .read(labServiceProvider)
      .watchLabTests(labClinicId: labClinicId, includeInactive: true)
      .map((tests) => tests
          .map((t) => <String, dynamic>{
                'offeringId': t.id,
                'code': t.code,
                'name': t.name,
                'category': t.category,
                'sampleType': t.sampleType,
                'fastingRequired': t.fastingRequired,
                'turnaroundHours': t.turnaroundHours,
                'active': t.active,
                'testId': t.testId,
                'isLocal': t.isLocal,
                'localCode': t.localCode,
                'localName': t.localName,
                'localCategory': t.localCategory,
                'mrp': t.mrp,
                'offerPrice': t.offerPrice,
                'discountPercent': t.discountPercent,
                'displayName': t.displayName,
              })
          .toList());
});

final _packagesProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, labClinicId) {
  return ref.read(labServiceProvider).watchPackages(labClinicId);
});

class LabTestCatalogScreen extends ConsumerWidget {
  const LabTestCatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('My catalogue')),
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

          final isOwner = user?.role == UserRole.owner ||
              user?.role == UserRole.admin;

          final testsAsync = ref.watch(_catalogProvider(labClinicId));
          final packagesAsync = ref.watch(_packagesProvider(labClinicId));

          return Stack(
            children: [
              RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async {
                  ref.invalidate(_catalogProvider(labClinicId));
                  ref.invalidate(_packagesProvider(labClinicId));
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    packagesAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) => const SizedBox.shrink(),
                      data: (packages) {
                        if (packages.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: 4, bottom: 8),
                              child: Text('Packages',
                                  style: AppTextStyles.caption.copyWith(
                                      fontWeight: FontWeight.w600)),
                            ),
                            for (final pkg in packages)
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 10),
                                child: _PackageCard(
                                  package: pkg,
                                  labClinicId: labClinicId,
                                  isOwner: isOwner,
                                ),
                              ),
                            const SizedBox(height: 16),
                          ],
                        );
                      },
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text('Tests',
                          style: AppTextStyles.caption
                              .copyWith(fontWeight: FontWeight.w600)),
                    ),
                    testsAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primary)),
                      ),
                      error: (e, _) => GlassCard(
                          child: Text('Failed: $e',
                              style: const TextStyle(
                                  color: AppColors.error))),
                      data: (tests) {
                        if (tests.isEmpty) {
                          return const EmptyState(
                            icon: Icons.list_alt_rounded,
                            title: 'No tests yet',
                            subtitle:
                                'Tap the + button to add tests from the master dictionary, create a local test, or build a package.',
                          );
                        }
                        return Column(children: [
                          for (final t in tests)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _OfferingCard(
                                offering: t,
                                labClinicId: labClinicId,
                                isOwner: isOwner,
                              ),
                            ),
                        ]);
                      },
                    ),
                  ],
                ),
              ),
              if (isOwner)
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: FloatingActionButton.extended(
                    onPressed: () =>
                        _openAddMenu(context, ref, labClinicId),
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openAddMenu(
      BuildContext context, WidgetRef ref, String labClinicId) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.library_add_rounded,
                  color: AppColors.primary),
              title: const Text('Add from master dictionary'),
              subtitle: const Text(
                  'Pick tests from the platform catalogue'),
              onTap: () => Navigator.pop(context, 'canonical'),
            ),
            ListTile(
              leading: const Icon(Icons.add_box_outlined,
                  color: AppColors.warning),
              title: const Text('Create local test'),
              subtitle: const Text(
                  'A lab-specific test not in the master dictionary'),
              onTap: () => Navigator.pop(context, 'local'),
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined,
                  color: AppColors.info),
              title: const Text('Create package'),
              subtitle: const Text(
                  'Bundle several tests into one priced package'),
              onTap: () => Navigator.pop(context, 'package'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == null || !context.mounted) return;

    switch (choice) {
      case 'canonical':
  final chosen = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        CanonicalTestPickerSheet(labClinicId: labClinicId),
  );
  if (chosen == null || chosen.isEmpty) break;

  // Filter out tests already in the catalogue so we can tell
  // the user exactly how many were added vs skipped.
  final dupes = await ref
      .read(labServiceProvider)
      .whichTestIdsAlreadyExist(
        labClinicId: labClinicId,
        testIds: chosen,
      );
  final fresh = chosen.where((id) => !dupes.contains(id)).toList();

  if (fresh.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'All selected tests are already in your catalogue.'),
      ));
    }
    break;
  }

  try {
    await ref.read(labServiceProvider).addOfferings(
          labClinicId: labClinicId,
          testIds: fresh,
        );
    if (context.mounted) {
      final skippedMsg =
          dupes.isNotEmpty ? ' (${dupes.length} already present)' : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '${fresh.length} test${fresh.length == 1 ? '' : 's'} added$skippedMsg.'),
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
  break;

      case 'local':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LocalTestEditorScreen(labClinicId: labClinicId),
        ));
        break;
      case 'package':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PackageEditorScreen(labClinicId: labClinicId),
        ));
        break;
    }
  }
}

// -----------------------------------------------------------------
// Offering card — dual price display
// -----------------------------------------------------------------

class _OfferingCard extends ConsumerWidget {
  final Map<String, dynamic> offering;
  final String labClinicId;
  final bool isOwner;
  const _OfferingCard({
    required this.offering,
    required this.labClinicId,
    required this.isOwner,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = offering['active'] != false;
    final isLocal = offering['isLocal'] == true;
    final code = (offering['code'] ?? '').toString();
    final name = (offering['name'] ?? '').toString();
    final category = (offering['category'] ?? 'other').toString();
    final sampleType = (offering['sampleType'] ?? 'other').toString();
    final fasting = offering['fastingRequired'] == true;
    final tat = offering['turnaroundHours'];
    final price = offering['price'];
    final mrp = offering['mrp'] as num?;
    final offer = offering['offerPrice'] as num?;
    final discountPercent = offering['discountPercent'];

    final iconColor = isLocal ? AppColors.warning : AppColors.info;

    return GlassCard(
      borderColor: active
          ? iconColor.withOpacity(.35)
          : AppColors.cardBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (active ? iconColor : AppColors.textMuted)
                    .withOpacity(.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isLocal ? Icons.science_outlined : Icons.biotech_rounded,
                color: active ? iconColor : AppColors.textMuted,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    if (isLocal)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('Local',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                    if (code.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(code,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            )),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text(
                    '$category • $sampleType'
                    '${fasting ? " • fasting" : ""}'
                    '${tat != null ? " • ~${tat}h" : ""}',
                    style: AppTextStyles.caption,
                  ),
                  if (!active) ...[
                    const SizedBox(height: 4),
                    Text('Inactive',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.error)),
                  ],
                ],
              ),
            ),
            if (isOwner)
              IconButton(
                tooltip: 'Edit',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _OfferingPricingEditor(
                      labClinicId: labClinicId,
                      offering: offering,
                    ),
                  ),
                ),
                icon: const Icon(Icons.edit_rounded,
                    color: AppColors.textMuted, size: 20),
              ),
          ]),
          const SizedBox(height: 8),
          _priceRow(mrp, offer, discountPercent, price),
        ],
      ),
    );
  }

  Widget _priceRow(num? mrp, num? offer, dynamic discountPercent, dynamic price) {
    // Legacy fallback: some old offerings may have `price` but not `mrp`
    final effectiveMrp = mrp ?? price;
    final effectiveOffer = offer ?? price;

    if (effectiveMrp == null && effectiveOffer == null) {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.textMuted.withOpacity(.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text('Set price',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            )),
      );
    }

    final hasDiscount =
        effectiveMrp != null &&
        effectiveOffer != null &&
        effectiveMrp > effectiveOffer;
    final pct = discountPercent as int? ?? 0;

    return Row(children: [
      if (hasDiscount) ...[
        Text(
          '₹${(effectiveMrp as num).toStringAsFixed(0)}',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textMuted,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        const SizedBox(width: 6),
      ],
      Text(
        '₹${(effectiveOffer as num).toStringAsFixed(0)}',
        style: AppTextStyles.body.copyWith(
          color: AppColors.success,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (hasDiscount && pct > 0) ...[
        const SizedBox(width: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('$pct% off',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w700,
              )),
        ),
      ],
    ]);
  }
}

// -----------------------------------------------------------------
// Package card — computed price display
// -----------------------------------------------------------------

class _PackageCard extends ConsumerWidget {
  final Map<String, dynamic> package;
  final String labClinicId;
  final bool isOwner;
  const _PackageCard({
    required this.package,
    required this.labClinicId,
    required this.isOwner,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = (package['name'] ?? '').toString();
    final summary = (package['includedTestSummary'] ?? '').toString();
    final count =
        (package['includedTestOfferingIds'] as List?)?.length ?? 0;
    final mrp = package['computedMrp'] as num?;
    final offer = package['computedOfferPrice'] as num?;
    final discountPercent = package['computedDiscountPercent'] as int? ?? 0;

    return GlassCard(
      borderColor: AppColors.accent.withOpacity(.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.inventory_2_outlined,
                  color: AppColors.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Package',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text('$count test${count == 1 ? '' : 's'}'
                      '${summary.isNotEmpty ? " • $summary" : ""}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption),
                ],
              ),
            ),
            if (isOwner)
              IconButton(
                tooltip: 'Edit',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PackageEditorScreen(
                      labClinicId: labClinicId,
                      existing: package,
                    ),
                  ),
                ),
                icon: const Icon(Icons.edit_rounded,
                    color: AppColors.textMuted, size: 20),
              ),
          ]),
          const SizedBox(height: 8),
          if (mrp == null || offer == null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 12, color: AppColors.warning),
                const SizedBox(width: 4),
                Text('Set prices on all tests to compute package price',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600,
                    )),
              ]),
            )
          else
            Row(children: [
              if (discountPercent > 0) ...[
                Text(
                  '₹${mrp.toStringAsFixed(0)}',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textMuted,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                '₹${offer.toStringAsFixed(0)}',
                style: AppTextStyles.body.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (discountPercent > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(.15),
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
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------
// Offering pricing editor — MRP + offer price
// -----------------------------------------------------------------

class _OfferingPricingEditor extends ConsumerStatefulWidget {
  final String labClinicId;
  final Map<String, dynamic> offering;
  const _OfferingPricingEditor({
    required this.labClinicId,
    required this.offering,
  });

  @override
  ConsumerState<_OfferingPricingEditor> createState() =>
      _OfferingPricingEditorState();
}

class _OfferingPricingEditorState
    extends ConsumerState<_OfferingPricingEditor> {
  late final TextEditingController _mrpCtrl;
  late final TextEditingController _offerCtrl;
  late final TextEditingController _tatCtrl;
  late bool _active;
  bool _saving = false;
  String? _mrpError;
  String? _offerError;

  @override
  void initState() {
    super.initState();
    final mrp = widget.offering['mrp'] as num?;
    final offer = widget.offering['offerPrice'] as num?;
    _mrpCtrl = TextEditingController(
        text: mrp != null ? mrp.toStringAsFixed(0) : '');
    _offerCtrl = TextEditingController(
        text: offer != null ? offer.toStringAsFixed(0) : '');
    _tatCtrl = TextEditingController(
        text: widget.offering['turnaroundHours']?.toString() ?? '');
    _active = widget.offering['active'] != false;
  }

  @override
  void dispose() {
    _mrpCtrl.dispose();
    _offerCtrl.dispose();
    _tatCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _mrpError = null;
      _offerError = null;
    });

    final mrp = double.tryParse(_mrpCtrl.text.trim());
    final offerRaw = _offerCtrl.text.trim();
    final offer =
        offerRaw.isEmpty ? null : double.tryParse(offerRaw);

    var hasError = false;
    if (mrp == null || mrp <= 0) {
      setState(() => _mrpError = 'Enter MRP greater than 0.');
      hasError = true;
    }
    if (offerRaw.isNotEmpty && (offer == null || offer <= 0)) {
      setState(() =>
          _offerError = 'Enter a valid offer price or leave blank.');
      hasError = true;
    }
    if (offer != null && mrp != null && offer > mrp) {
      setState(() => _offerError = 'Offer price cannot exceed MRP.');
      hasError = true;
    }
    if (hasError) return;

    setState(() => _saving = true);
    try {
      await ref.read(labServiceProvider).updateOffering(
            labClinicId: widget.labClinicId,
            offeringId:
                (widget.offering['offeringId'] ?? '').toString(),
            mrp: mrp!,
            offerPrice: offer,
            turnaroundHours: int.tryParse(_tatCtrl.text.trim()),
            active: _active,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Saved.'),
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
    final code = (widget.offering['code'] ?? '').toString();
    final name = (widget.offering['name'] ?? '').toString();
    final mrp = double.tryParse(_mrpCtrl.text.trim());
    final offer = double.tryParse(_offerCtrl.text.trim());
    final effectiveOffer = offer ?? mrp;
    final hasDiscount =
        mrp != null && effectiveOffer != null && mrp > effectiveOffer;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Edit offering')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (code.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(code,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(name,
                        style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  'Clinical fields are managed centrally. Set your own MRP and offer price here.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('MRP (₹)', style: AppTextStyles.caption),
          const SizedBox(height: 6),
          GlassCard(
            child: TextField(
              controller: _mrpCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}),
              style: AppTextStyles.body,
              decoration: InputDecoration(
                hintText: 'e.g. 500',
                errorText: _mrpError,
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Offer price (₹, optional)',
              style: AppTextStyles.caption),
          const SizedBox(height: 6),
          GlassCard(
            child: TextField(
              controller: _offerCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}),
              style: AppTextStyles.body,
              decoration: InputDecoration(
                hintText: 'Leave blank for no discount',
                errorText: _offerError,
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          if (hasDiscount)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  const Icon(Icons.local_offer_rounded,
                      color: AppColors.success, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '₹${mrp!.toStringAsFixed(0)} → ₹${effectiveOffer!.toStringAsFixed(0)}'
                    '  •  ${((mrp - effectiveOffer) / mrp * 100).round()}% off',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 16),
          Text('Turnaround hours (optional)',
              style: AppTextStyles.caption),
          const SizedBox(height: 6),
          GlassCard(
            child: TextField(
              controller: _tatCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              style: AppTextStyles.body,
              decoration: const InputDecoration(
                hintText: 'e.g. 24',
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Active', style: AppTextStyles.body),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            activeColor: AppColors.primary,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}