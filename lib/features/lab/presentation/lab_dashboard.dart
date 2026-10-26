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
                    Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text('Lab operations',
                                style: AppTextStyles.bodyMuted),
                            const SizedBox(height: 4),
                            Text(user?.name ?? 'Lab',
                                style: AppTextStyles.h1),
                          ],
                        ),
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
                      IconButton(
                        tooltip: 'Logout',
                        onPressed: () => _confirmLogout(context),
                        icon: const Icon(Icons.logout_rounded,
                            color: AppColors.error),
                      ),
                      const RoleBadge(
                          label: 'Lab', color: AppColors.labAccent),
                    ]),
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
        return (label: 'Mark delivered', next: LabOrderStatus.delivered);
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