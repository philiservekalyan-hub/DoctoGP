// lib/features/lab/presentation/lab_dashboard.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/lab_order_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../shared/widgets/role_badge.dart';
import 'lab_order_detail_screen.dart';
import 'lab_test_catalog_screen.dart';
import 'scan_sample_sheet.dart';

final _labOrdersProvider =
    StreamProvider.autoDispose<List<LabOrderModel>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final labClinicId = user?.clinicId;
  if (labClinicId == null || labClinicId.isEmpty) {
    return const Stream.empty();
  }
  return ref.read(labServiceProvider).watchLabOrders(
        labClinicId: labClinicId,
        deptId: user?.deptId,
      );
});

class LabDashboard extends ConsumerWidget {
  const LabDashboard({super.key});

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Logout', style: AppTextStyles.h3),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    try {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      context.go('/login');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not sign out: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _openScanner(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<ScanResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ScanSampleSheet(),
    );

    if (result == null || !context.mounted) return;

    // Look up the order containing this sampleId.
    final orders = ref.read(_labOrdersProvider).valueOrNull ??
        const <LabOrderModel>[];
    LabOrderModel? matched;
    for (final o in orders) {
      for (final g in o.sampleGroups) {
        if (g.sampleIds.contains(result.barcode)) {
          matched = o;
          break;
        }
      }
      if (matched != null) break;
    }

    if (!context.mounted) return;

    if (matched == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No order found for ${result.barcode}'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    await _showMatchedOrder(context, ref, matched);
  }

  Future<void> _showMatchedOrder(
    BuildContext context,
    WidgetRef ref,
    LabOrderModel order,
  ) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.science_rounded,
                  color: AppColors.labAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Matched order', style: AppTextStyles.h3),
              ),
              IconButton(
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
            const SizedBox(height: 8),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.testsSummary, style: AppTextStyles.body),
                  const SizedBox(height: 4),
                  Text(
                    '${order.patientName} • ${order.patientId}',
                    style: AppTextStyles.caption,
                  ),
                  const SizedBox(height: 4),
                  Text('Status: ${order.statusLabel}',
                      style: AppTextStyles.caption),
                  if (order.sampleGroups.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Sample: ${order.allSampleIds.join(', ')}',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (order.status == LabOrderStatus.sampleCollected)
              ElevatedButton.icon(
                onPressed: () async {
                  final nav = Navigator.of(sheetContext);
                  try {
                    await ref
                        .read(labServiceProvider)
                        .updateStatus(order.docId, LabOrderStatus.processing);
                    if (context.mounted) {
                      nav.pop();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            '${order.patientName} — processing started'),
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
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start processing'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.labAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              )
            else if (order.status == LabOrderStatus.processing)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LabOrderDetailScreen(order: order),
                  ));
                },
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Upload report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.labAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              )
            else
              Text(
                'This order is in "${order.statusLabel}" stage — '
                'no action available from scan.',
                style: AppTextStyles.bodyMuted,
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(child: Text('$e')),
          data: (user) {
            final labClinicId = user?.clinicId;
            if (labClinicId == null || labClinicId.isEmpty) {
              return Scaffold(
                backgroundColor: AppColors.background,
                appBar: AppBar(
                  title: const Text('Lab'),
                  actions: [
                    IconButton(
                      tooltip: 'Logout',
                      onPressed: () => _confirmLogout(context),
                      icon: const Icon(Icons.logout_rounded,
                          color: AppColors.error),
                    ),
                  ],
                ),
                body: const EmptyState(
                  icon: Icons.science_outlined,
                  title: 'No lab linked',
                  subtitle:
                      'Your account is not yet linked to a lab. Contact your clinic owner, or sign out and try another account.',
                ),
              );
            }

            // ── Gates for the "back to owner dashboard" icon ──
            final isOwner = user?.role == 'owner';
            final canPractise = user?.canPractise == true;

            final ordersAsync = ref.watch(_labOrdersProvider);

            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async => ref.invalidate(_labOrdersProvider),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Title row: name + badge on top ──
                    Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text('Lab operations',
                                style: AppTextStyles.bodyMuted),
                            const SizedBox(height: 4),
                            Text(
                              user?.name ?? 'Lab',
                              style: AppTextStyles.h3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const RoleBadge(
                          label: 'Lab', color: AppColors.labAccent),
                    ]),
                    const SizedBox(height: 8),

                    // ── Icon row: actions on their own line ──
                    // Splitting from the title avoids the Row-overflow
                    // that was clipping the last icon off the right edge
                    // on 360 dp phones.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Scan sample',
                          onPressed: () => _openScanner(context, ref),
                          icon: const Icon(
                              Icons.qr_code_scanner_rounded,
                              color: AppColors.labAccent),
                        ),
                        IconButton(
                          tooltip: 'Test catalog',
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    const LabTestCatalogScreen()),
                          ),
                          icon: const Icon(Icons.list_alt_rounded,
                              color: AppColors.labAccent),
                        ),
                        if (isOwner && canPractise)
                          IconButton(
                            tooltip: 'Back to owner dashboard',
                            onPressed: () {
                              if (context.canPop()) {
                                context.pop();
                              } else {
                                context.go('/lab');
                              }
                            },
                            icon: const Icon(
                              Icons.admin_panel_settings_rounded,
                              color: AppColors.labAccent,
                            ),
                          ),
                        IconButton(
                          tooltip: 'Logout',
                          onPressed: () => _confirmLogout(context),
                          icon: const Icon(Icons.logout_rounded,
                              color: AppColors.error),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    _stats(ordersAsync),
                    const SizedBox(height: 28),

                    const SectionHeader(title: 'New orders'),
                    _ordersByStatus(
                        context, ref, ordersAsync, LabOrderStatus.ordered),
                    const SizedBox(height: 20),

                    const SectionHeader(title: 'In progress'),
                    _ordersByStatus(
                      context,
                      ref,
                      ordersAsync,
                      LabOrderStatus.accepted,
                      extraStatuses: [
                        LabOrderStatus.sampleCollected,
                        LabOrderStatus.processing,
                      ],
                    ),
                    const SizedBox(height: 20),

                    const SectionHeader(title: 'Ready for delivery'),
                    _ordersByStatus(context, ref, ordersAsync,
                        LabOrderStatus.ready),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _stats(AsyncValue<List<LabOrderModel>> async) {
    final orders = async.valueOrNull ?? const <LabOrderModel>[];
    int count(LabOrderStatus s) =>
        orders.where((o) => o.status == s).length;
    final processing = count(LabOrderStatus.accepted) +
        count(LabOrderStatus.sampleCollected) +
        count(LabOrderStatus.processing);

    return Column(children: [
      Row(children: [
        Expanded(
          child: StatCard(
            label: 'New orders',
            value: count(LabOrderStatus.ordered)
                .toString()
                .padLeft(2, '0'),
            icon: Icons.inbox_rounded,
            accent: AppColors.labAccent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            label: 'Processing',
            value: processing.toString().padLeft(2, '0'),
            icon: Icons.biotech_rounded,
            accent: AppColors.warning,
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: StatCard(
            label: 'Ready',
            value: count(LabOrderStatus.ready)
                .toString()
                .padLeft(2, '0'),
            icon: Icons.check_circle_outline_rounded,
            accent: AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: StatCard(
            label: 'Delivered',
            value: count(LabOrderStatus.delivered)
                .toString()
                .padLeft(2, '0'),
            icon: Icons.local_shipping_outlined,
            accent: AppColors.info,
          ),
        ),
      ]),
    ]);
  }

  Widget _ordersByStatus(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<LabOrderModel>> async,
    LabOrderStatus primary, {
    List<LabOrderStatus> extraStatuses = const [],
  }) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
            child:
                CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => GlassCard(
        child: Text('Failed: $e',
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (orders) {
        final statuses = [primary, ...extraStatuses];
        final list =
            orders.where((o) => statuses.contains(o.status)).toList();
        if (list.isEmpty) {
          return GlassCard(
            child: Row(children: [
              const Icon(Icons.inbox_outlined,
                  color: AppColors.textMuted, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text('No orders in this stage',
                    style: AppTextStyles.bodyMuted),
              ),
            ]),
          );
        }
        return Column(
          children: list
              .map((o) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LabOrderRow(order: o),
                  ))
              .toList(),
        );
      },
    );
  }
}

// -----------------------------------------------------------------
// One row per lab order with the next-step action
// -----------------------------------------------------------------
class _LabOrderRow extends ConsumerWidget {
  final LabOrderModel order;
  const _LabOrderRow({required this.order});

  Color get _statusColor {
    switch (order.status) {
      case LabOrderStatus.ordered:
        return AppColors.labAccent;
      case LabOrderStatus.accepted:
      case LabOrderStatus.sampleCollected:
        return AppColors.info;
      case LabOrderStatus.processing:
        return AppColors.warning;
      case LabOrderStatus.ready:
        return AppColors.success;
      case LabOrderStatus.delivered:
        return AppColors.success;
      case LabOrderStatus.cancelled:
      case LabOrderStatus.noShow:
        return AppColors.error;
      default:
        return AppColors.textMuted;
    }
  }

  ({String label, LabOrderStatus next})? get _nextStep {
    switch (order.status) {
      case LabOrderStatus.ordered:
        return (label: 'Accept', next: LabOrderStatus.accepted);
      case LabOrderStatus.accepted:
        return (
          label: 'Sample collected',
          next: LabOrderStatus.sampleCollected,
        );
      case LabOrderStatus.sampleCollected:
        return (
          label: 'Start processing',
          next: LabOrderStatus.processing,
        );
      case LabOrderStatus.processing:
        return null;
      case LabOrderStatus.ready:
        return null;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final step = _nextStep;

    return GlassCard(
      borderColor: _statusColor.withOpacity(0.35),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LabOrderDetailScreen(order: order),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.science_outlined,
                  color: _statusColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.testsSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body),
                  const SizedBox(height: 3),
                  Text(
                    '${order.patientName} • ${order.patientId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption,
                  ),
                  if (order.orderedAt != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('dd MMM • hh:mm a')
                          .format(order.orderedAt!),
                      style: AppTextStyles.caption,
                    ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (order.status == LabOrderStatus.processing)
                  IconButton(
                    tooltip: 'Upload report',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            LabOrderDetailScreen(order: order),
                      ),
                    ),
                    icon: const Icon(Icons.upload_file_rounded,
                        color: AppColors.labAccent, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                if (step != null)
                  ElevatedButton(
                    onPressed: () => _advance(context, ref, step),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _statusColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    child: Text(step.label),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: _statusColor.withOpacity(.13),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(order.statusLabel,
                        style: AppTextStyles.caption
                            .copyWith(color: _statusColor)),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _advance(
    BuildContext context,
    WidgetRef ref,
    ({String label, LabOrderStatus next}) step,
  ) async {
    try {
      await ref
          .read(labServiceProvider)
          .updateStatus(order.docId, step.next);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${order.patientName} — ${step.label.toLowerCase()}'),
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
}