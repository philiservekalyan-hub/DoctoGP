// lib/features/admin/presentation/link_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';

class LinkManagementScreen extends ConsumerStatefulWidget {
  const LinkManagementScreen({super.key});

  @override
  ConsumerState<LinkManagementScreen> createState() =>
      _LinkManagementScreenState();
}

class _LinkManagementScreenState
    extends ConsumerState<LinkManagementScreen> {
  String _mode = 'clinicToLab'; // or 'labToClinic'
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Link management')),
      body: Column(
        children: [
          _modeToggle(),
          const Divider(height: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _modeToggle() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppColors.surface,
      child: Row(children: [
        Expanded(
          child: ChoiceChip(
            label: const Text('Clinic → Labs'),
            selected: _mode == 'clinicToLab',
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: _mode == 'clinicToLab'
                  ? Colors.white
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            onSelected: (_) => setState(() {
              _mode = 'clinicToLab';
              _selectedId = null;
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ChoiceChip(
            label: const Text('Lab → Clinics'),
            selected: _mode == 'labToClinic',
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: _mode == 'labToClinic'
                  ? Colors.white
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            onSelected: (_) => setState(() {
              _mode = 'labToClinic';
              _selectedId = null;
            }),
          ),
        ),
      ]),
    );
  }

  Widget _body() {
    final sourceType = _mode == 'clinicToLab' ? 'clinic' : 'lab';
    final targetType = _mode == 'clinicToLab' ? 'lab' : 'clinic';
    final sourceAsync =
        ref.watch(_entitiesProvider(sourceType));

    return sourceAsync.when(
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(child: Text('$e')),
      data: (sources) {
        if (sources.isEmpty) {
          return EmptyState(
            icon: _mode == 'clinicToLab'
                ? Icons.local_hospital_outlined
                : Icons.science_outlined,
            title: 'No ${sourceType}s yet',
            subtitle:
                'Create a ${sourceType} first from the Create Entity screen.',
          );
        }

        if (_selectedId == null) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sources.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final e = sources[i];
              return GlassCard(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () =>
                      setState(() => _selectedId = e['id'] as String),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(.13),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _mode == 'clinicToLab'
                              ? Icons.local_hospital_outlined
                              : Icons.science_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                                (e['name'] ?? 'Unnamed').toString(),
                                style: AppTextStyles.body),
                            Text(
                                (e['clinicCode'] ?? '').toString(),
                                style: AppTextStyles.caption),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textMuted),
                    ]),
                  ),
                ),
              );
            },
          );
        }

        final source =
            sources.firstWhere((e) => e['id'] == _selectedId);
        return _sourceDetail(source, targetType);
      },
    );
  }

  Widget _sourceDetail(
      Map<String, dynamic> source, String targetType) {
    final sourceId = source['id'] as String;
    final sourceName = (source['name'] ?? 'Entity').toString();
    final isClinicToLab = _mode == 'clinicToLab';

    final linkedAsync = isClinicToLab
        ? ref.watch(_linkedLabsProvider(sourceId))
        : ref.watch(_linkedClinicsProvider(sourceId));

    return Column(
      children: [
        // Header with back
        Container(
          color: AppColors.surfaceElevated,
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => setState(() => _selectedId = null),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sourceName, style: AppTextStyles.h3),
                  Text(
                    isClinicToLab
                        ? 'Manage labs linked to this clinic'
                        : 'Manage clinics linked to this lab',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: linkedAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(
                    color: AppColors.primary)),
            error: (e, _) => Center(child: Text('$e')),
            data: (linked) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionHeader(
                    title:
                        'Linked ${targetType}s (${linked.length})'),
                const SizedBox(height: 8),
                ...linked.map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _linkedRow(l, source, isClinicToLab),
                    )),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _addLinkDialog(
                      source, targetType, linked),
                  icon: const Icon(Icons.add_rounded),
                  label: Text('Link a ${targetType}'),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _linkedRow(
    Map<String, dynamic> linked,
    Map<String, dynamic> source,
    bool isClinicToLab,
  ) {
    final displayName = isClinicToLab
        ? (linked['labName'] ?? 'Lab').toString()
        : (linked['clinicName'] ?? 'Clinic').toString();
    final linkedId = isClinicToLab
        ? linked['labClinicId'] as String
        : linked['clinicId'] as String;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.link_rounded,
                color: AppColors.success, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
              child:
                  Text(displayName, style: AppTextStyles.body)),
          IconButton(
            icon: const Icon(Icons.link_off_rounded,
                color: AppColors.error, size: 20),
            tooltip: 'Unlink',
            onPressed: () => _unlink(source, linkedId,
                isClinicToLab, displayName),
          ),
        ]),
      ),
    );
  }

  Future<void> _unlink(
    Map<String, dynamic> source,
    String linkedId,
    bool isClinicToLab,
    String linkedName,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Unlink ${isClinicToLab ? 'lab' : 'clinic'}',
            style: AppTextStyles.h3),
        content: Text(
          'Remove the link between '
          '"${(source['name'] ?? '').toString()}" and "$linkedName"?',
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
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final service = ref.read(labServiceProvider);
      if (isClinicToLab) {
        await service.unlinkClinicAndLab(
          clinicId: source['id'] as String,
          labClinicId: linkedId,
        );
      } else {
        // In lab→clinic mode, source is the lab, linkedId is the clinic
        await service.unlinkClinicAndLab(
          clinicId: linkedId,
          labClinicId: source['id'] as String,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Unlinked.'),
                backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _addLinkDialog(
    Map<String, dynamic> source,
    String targetType,
    List<Map<String, dynamic>> alreadyLinked,
  ) async {
    final sourceId = source['id'] as String;
    final sourceName = (source['name'] ?? 'Entity').toString();
    final isClinicToLab = _mode == 'clinicToLab';

    final linkedIds = alreadyLinked
        .map((l) => isClinicToLab
            ? l['labClinicId'] as String
            : l['clinicId'] as String)
        .toSet();

    final candidates = await ref
        .read(_entitiesProvider(targetType).future);
    final available = candidates
        .where((e) => !linkedIds.contains(e['id']))
        .toList();

    if (available.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'No more ${targetType}s available to link. Create one first.'),
            backgroundColor: AppColors.warning));
      }
      return;
    }

    if (!mounted) return;
    final chosen = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Link a $targetType', style: AppTextStyles.h3),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: available
                .map((e) => ListTile(
                      title: Text((e['name'] ?? '').toString(),
                          style: AppTextStyles.body),
                      subtitle: Text(
                          (e['clinicCode'] ?? '').toString(),
                          style: AppTextStyles.caption),
                      onTap: () => Navigator.pop(dctx, e),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('Cancel')),
        ],
      ),
    );

    if (chosen == null) return;

    final chosenId = chosen['id'] as String;
    final chosenName = (chosen['name'] ?? 'Entity').toString();

    try {
      final service = ref.read(labServiceProvider);
      if (isClinicToLab) {
        await service.linkClinicAndLab(
          clinicId: sourceId,
          clinicName: sourceName,
          labClinicId: chosenId,
          labName: chosenName,
        );
      } else {
        await service.linkClinicAndLab(
          clinicId: chosenId,
          clinicName: chosenName,
          labClinicId: sourceId,
          labName: sourceName,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Linked.'),
                backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }
}

// -----------------------------------------------------------------
// Providers
// -----------------------------------------------------------------

final _entitiesProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, type) {
  return ref.read(labServiceProvider).watchEntitiesByType(type);
});

final _linkedLabsProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, clinicId) {
  if (clinicId.isEmpty) return const Stream.empty();
  return ref.read(labServiceProvider).watchLinkedLabs(clinicId);
});

final _linkedClinicsProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, labClinicId) {
  if (labClinicId.isEmpty) return const Stream.empty();
  return ref.read(labServiceProvider).watchLinkedClinics(labClinicId);
});