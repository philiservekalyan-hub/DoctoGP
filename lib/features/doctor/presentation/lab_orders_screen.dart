// lib/features/doctor/presentation/lab_orders_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/lab_order_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import 'lab_order_create_screen.dart';
import 'lab_order_history_screen.dart';

final doctorLabOrdersProvider =
    StreamProvider.autoDispose<List<LabOrderModel>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref
      .read(labServiceProvider)
      .watchDoctorOrders(doctorDocId: user.uid);
});

class LabOrdersScreen extends ConsumerWidget {
  const LabOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(doctorLabOrdersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Lab orders'),
        actions: [
          IconButton(
            tooltip: 'New order',
            onPressed: () => _openCreate(context),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text('$e',
                style: const TextStyle(color: AppColors.error))),
        data: (orders) {
          if (orders.isEmpty) {
            return Column(
              children: [
                const Expanded(
                  child: EmptyState(
                    icon: Icons.science_outlined,
                    title: 'No lab orders yet',
                    subtitle:
                        'Orders you create will appear here with live status.',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openCreate(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Create first order'),
                    ),
                  ),
                ),
              ],
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async =>
                ref.invalidate(doctorLabOrdersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: 10),
              itemBuilder: (_, i) => _OrderRow(order: orders[i]),
            ),
          );
        },
      ),
    );
  }

  void _openCreate(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => const LabOrderCreateScreen()),
    );
  }
}

class _OrderRow extends ConsumerWidget {
  final LabOrderModel order;
  const _OrderRow({required this.order});

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
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      borderColor: _statusColor.withOpacity(0.35),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LabOrderHistoryScreen(
              patientDocId: order.patientDocId,
            ),
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
              child: Icon(
                order.status == LabOrderStatus.ready
                    ? Icons.description_rounded
                    : Icons.science_outlined,
                color: _statusColor,
                size: 20,
              ),
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
                    '${order.patientName} • ${order.labName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption,
                  ),
                  if (order.orderedAt != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('EEE, dd MMM • hh:mm a')
                          .format(order.orderedAt!),
                      style: AppTextStyles.caption,
                    ),
                  ],
                ],
              ),
            ),
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
}