
// lib/features/doctor/presentation/lab_order_history_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router.dart'; // Restores currentUserProvider
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/lab_order_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';

class LabOrderHistoryScreen extends ConsumerStatefulWidget {
  final String? patientDocId;

  const LabOrderHistoryScreen({
    super.key,
    this.patientDocId,
  });

  @override
  ConsumerState<LabOrderHistoryScreen> createState() =>
      _LabOrderHistoryScreenState();
}

class _LabOrderHistoryScreenState
    extends ConsumerState<LabOrderHistoryScreen> {
  // Filters
  String? _labClinicId;
  Set<LabOrderStatus> _statuses = {};
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Lab order history'),
        actions: [
          IconButton(
            tooltip: 'Clear filters',
            onPressed: _hasFilters ? _clearFilters : null,
            icon: const Icon(Icons.filter_alt_off_outlined),
          ),
        ],
      ),
      body: userAsync.when(
        loading: () {
          debugPrint('[LAB HISTORY] Current user is LOADING');

          return const Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
            ),
          );
        },
        error: (e, stack) {
          debugPrint('[LAB HISTORY] CURRENT USER ERROR: $e');
          debugPrint('$stack');

          return Center(
            child: Text(
              'Unable to load current user: $e',
              style: const TextStyle(
                color: AppColors.error,
              ),
            ),
          );
        },
        data: (user) {
          if (user == null) {
            debugPrint('[LAB HISTORY] Current user is NULL');
            return const Center(
              child: Text('Please sign in to view lab orders.'),
            );
          }

          debugPrint('[LAB HISTORY] Current user loaded: ${user.uid}');

          final AsyncValue<List<LabOrderModel>> async = ref.watch(
  _filteredOrdersProvider((
    doctorDocId: user.uid,
    clinicId: user.clinicId ?? '',
    labClinicId: _labClinicId,
    statusesCsv: _statuses.map((s) => s.name).join(','),   
    from: _range?.start,
    to: _range?.end,
  )),
);

          return Column(
            children: [
              _filterBar(user.clinicId ?? ''),
              const Divider(height: 1),
              Expanded(
                child: async.when(
                  loading: () {
                    debugPrint(
                      '[LAB HISTORY] Orders provider is LOADING',
                    );

                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  },
                  error: (e, stack) {
                    debugPrint(
                      '[LAB HISTORY] PROVIDER ERROR: $e',
                    );
                    debugPrint(
                      '[LAB HISTORY] STACK TRACE: $stack',
                    );

                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Lab orders error: $e',
                          style: const TextStyle(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    );
                  },
                  data: (orders) {
                    debugPrint(
                      '[LAB HISTORY] Provider reached DATA state',
                    );
                    debugPrint(
                      '[LAB HISTORY] Signed-in UID: ${user.uid}',
                    );
                    debugPrint(
                      '[LAB HISTORY] Signed-in role: ${user.role}',
                    );
                    debugPrint(
                      '[LAB HISTORY] Signed-in clinic: ${user.clinicId}',
                    );
                    debugPrint(
                      '[LAB HISTORY] Query doctorDocId: ${user.uid}',
                    );
                    debugPrint(
                      '[LAB HISTORY] Lab filter: $_labClinicId',
                    );
                    debugPrint(
                      '[LAB HISTORY] Status filters: '
                      '${_statuses.map((s) => s.name).toList()}',
                    );
                    debugPrint(
                      '[LAB HISTORY] Date range: $_range',
                    );
                    debugPrint(
                      '[LAB HISTORY] Orders returned: ${orders.length}',
                    );

                    for (final o in orders) {
                      debugPrint(
                        '[LAB HISTORY] ${o.docId} | '
                        'doctor=${o.doctorDocId} | '
                        'lab=${o.labName} | '
                        'status=${o.statusLabel} | '
                        'tests=${o.tests.length} | '
                        'summary="${o.testsSummary}"',
                      );
                    }

                    debugPrint(
                      '[LAB HISTORY] END DATA DEBUG',
                    );

                    if (orders.isEmpty) {
                      return const EmptyState(
                        icon: Icons.history_rounded,
                        title: 'No orders match',
                        subtitle:
                            'Adjust filters or create a new lab order.',
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: orders.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return _HistoryRow(
                          order: orders[index],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  bool get _hasFilters =>
      _labClinicId != null ||
      _statuses.isNotEmpty ||
      _range != null;

  void _clearFilters() {
    setState(() {
      _labClinicId = null;
      _statuses.clear();
      _range = null;
    });
  }

  Widget _filterBar(String clinicId) {
    final labsAsync = ref.watch(
      _linkedLabsProvider(clinicId),
    );

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: lab selector and date range.
          Row(
            children: [
              Expanded(
                child: labsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (labs) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.cardBorder,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _labClinicId,
                        isExpanded: true,
                        hint: const Text(
                          'All labs',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        dropdownColor: AppColors.surfaceElevated,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All labs'),
                          ),
                          ...labs.map(
                            (lab) => DropdownMenuItem<String?>(
                              value: lab['labClinicId'] as String,
                              child: Text(
                                lab['labName'] as String,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _labClinicId = value;
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                ),
                label: Text(
                  _range == null
                      ? 'Any date'
                      : '${DateFormat('dd MMM').format(_range!.start)}'
                          ' – '
                          '${DateFormat('dd MMM').format(_range!.end)}',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _range == null
                      ? AppColors.textSecondary
                      : AppColors.primary,
                  side: BorderSide(
                    color: _range == null
                        ? AppColors.cardBorder
                        : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: status filters.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: LabOrderStatus.values
                  .where(
                    (status) => status != LabOrderStatus.unknown,
                  )
                  .map((status) {
                final selected = _statuses.contains(status);

                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(
                      _statusLabel(status),
                      style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                    selected: selected,
                    onSelected: (value) {
                      setState(() {
                        if (value) {
                          _statuses.add(status);
                        } else {
                          _statuses.remove(status);
                        }
                      });
                    },
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceElevated,
                    side: BorderSide(
                      color: selected
                          ? AppColors.primary
                          : AppColors.cardBorder,
                    ),
                    checkmarkColor: Colors.white,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(
        const Duration(days: 365),
      ),
      lastDate: DateTime.now(),
      initialDateRange: _range,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: AppColors.background,
            surface: AppColors.surfaceElevated,
          ),
        ),
        child: child!,
      ),
    );

    if (range != null && mounted) {
      setState(() {
        _range = range;
      });
    }
  }

  String _statusLabel(LabOrderStatus status) {
    switch (status) {
      case LabOrderStatus.ordered:
        return 'Ordered';
      case LabOrderStatus.accepted:
        return 'Accepted';
      case LabOrderStatus.sampleCollected:
        return 'Sample collected';
      case LabOrderStatus.processing:
        return 'Processing';
      case LabOrderStatus.ready:
        return 'Ready';
      case LabOrderStatus.delivered:
        return 'Delivered';
      case LabOrderStatus.cancelled:
        return 'Cancelled';
      case LabOrderStatus.noShow:
        return 'No-show';
      case LabOrderStatus.unknown:
        return '';
    }
  }
}

// -----------------------------------------------------------------
// Filtered orders provider
// -----------------------------------------------------------------

typedef _FilterKey = ({
  String doctorDocId,
  String clinicId,
  String? labClinicId,
  String statusesCsv,       
  DateTime? from,
  DateTime? to,
});

final _filteredOrdersProvider = StreamProvider.autoDispose
    .family<List<LabOrderModel>, _FilterKey>((ref, key) {
  // Parse the CSV back into a Set of statuses.
  final statusSet = key.statusesCsv.isEmpty
      ? const <LabOrderStatus>{}
      : key.statusesCsv
          .split(',')
          .map((s) => LabOrderStatus.values.firstWhere(
                (e) => e.name == s,
                orElse: () => LabOrderStatus.unknown,
              ))
          .toSet();

  return ref
      .read(labServiceProvider)
      .watchDoctorOrders(doctorDocId: key.doctorDocId)
      .map((orders) {
    var list = orders;

    if (key.labClinicId != null && key.labClinicId!.isNotEmpty) {
      list = list.where((o) => o.labClinicId == key.labClinicId).toList();
    }
    if (statusSet.isNotEmpty) {
      list = list.where((o) => statusSet.contains(o.status)).toList();
    }
    if (key.from != null) {
      list = list
          .where((o) => o.orderedAt != null && !o.orderedAt!.isBefore(key.from!))
          .toList();
    }
    if (key.to != null) {
      final endOfDay = DateTime(key.to!.year, key.to!.month, key.to!.day, 23, 59, 59);
      list = list
          .where((o) => o.orderedAt != null && !o.orderedAt!.isAfter(endOfDay))
          .toList();
    }
    return list;
  });
});

final _linkedLabsProvider =
    StreamProvider.autoDispose
        .family<List<Map<String, dynamic>>, String>(
  (ref, clinicId) {
    if (clinicId.isEmpty) {
      debugPrint(
        '[LAB HISTORY] Clinic ID is empty; skipping linked labs query.',
      );
      return const Stream.empty();
    }

    return ref
        .read(labServiceProvider)
        .watchLinkedLabs(clinicId);
  },
);

// -----------------------------------------------------------------
// History row and detail sheet
// -----------------------------------------------------------------

class _HistoryRow extends StatelessWidget {
  final LabOrderModel order;

  const _HistoryRow({
    required this.order,
  });

  Color get _statusColor {
    switch (order.status) {
      case LabOrderStatus.ordered:
        return AppColors.textMuted;
      case LabOrderStatus.accepted:
      case LabOrderStatus.sampleCollected:
        return AppColors.info;
      case LabOrderStatus.processing:
        return AppColors.warning;
      case LabOrderStatus.ready:
      case LabOrderStatus.delivered:
        return AppColors.success;
      case LabOrderStatus.cancelled:
      case LabOrderStatus.noShow:
        return AppColors.error;
      case LabOrderStatus.unknown:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: _statusColor.withOpacity(0.35),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetail(context, order),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.testsSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor.withOpacity(.13),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      order.statusLabel,
                      style: AppTextStyles.caption.copyWith(
                        color: _statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${order.patientName} • ${order.labName}',
                style: AppTextStyles.caption,
              ),
              if (order.orderedAt != null) ...[
                const SizedBox(height: 3),
                Text(
                  DateFormat('EEE, dd MMM yyyy • hh:mm a')
                      .format(order.orderedAt!),
                  style: AppTextStyles.caption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, LabOrderModel order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (_) => _OrderDetailSheet(order: order),
    );
  }
}

class _OrderDetailSheet extends StatelessWidget {
  final LabOrderModel order;

  const _OrderDetailSheet({
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Lab order',
              style: AppTextStyles.h3,
            ),
            const SizedBox(height: 4),
            Text(
              'Patient: ${order.patientName}',
              style: AppTextStyles.body,
            ),
            Text(
              'Lab: ${order.labName}',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 14),
            Text(
              'Tests',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 6),
            ...order.tests.map(
              (test) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(
                      Icons.science_outlined,
                      color: AppColors.info,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        test.label,
                        style: AppTextStyles.body,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (order.instructions != null &&
                order.instructions!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Instructions',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: 4),
              Text(
                order.instructions!,
                style: AppTextStyles.bodyMuted,
              ),
            ],
            if (order.referralNotes != null &&
                order.referralNotes!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Clinical notes',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: 4),
              Text(
                order.referralNotes!,
                style: AppTextStyles.bodyMuted,
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'Timeline',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 6),
            _timelineRow('Ordered', order.orderedAt),
            _timelineRow('Accepted', order.acceptedAt),
            _timelineRow(
              'Sample collected',
              order.sampleCollectedAt,
            ),
            _timelineRow(
              'Processing',
              order.processingStartedAt,
            ),
            _timelineRow(
              'Report ready',
              order.reportReadyAt,
            ),
            _timelineRow('Delivered', order.deliveredAt),
            if (order.cancelledAt != null)
              _timelineRow('Cancelled', order.cancelledAt),
            if (order.noShowAt != null)
              _timelineRow('No-show', order.noShowAt),
            if (order.reportUrl != null &&
                order.reportUrl!.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final url = Uri.tryParse(order.reportUrl!);

                    if (url != null) {
                      await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Open report'),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _timelineRow(String label, DateTime? at) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            at == null
                ? Icons.radio_button_unchecked
                : Icons.radio_button_checked,
            size: 14,
            color: at == null
                ? AppColors.textMuted
                : AppColors.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.body,
            ),
          ),
          Text(
            at == null
                ? '—'
                : DateFormat('dd MMM • hh:mm a').format(at),
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}
