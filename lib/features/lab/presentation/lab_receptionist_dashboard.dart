// lib/features/lab/presentation/lab_receptionist_dashboard.dart
import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../../../shared/widgets/role_badge.dart';
import 'lab_order_detail_screen.dart';
import 'lab_walkin_order_screen.dart';
import 'sample_label_preview.dart';

// -----------------------------------------------------------------
// Data providers
// -----------------------------------------------------------------
final labReceptionOrdersProvider =
    StreamProvider.autoDispose<List<LabOrderModel>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final labClinicId = user?.clinicId;
  if (labClinicId == null || labClinicId.isEmpty) {
    return const Stream.empty();
  }
  return ref.read(labServiceProvider).watchLabOrders(
        labClinicId: labClinicId,
      );
});

final labReceptionOrdersForDayProvider =
    Provider.family<List<LabOrderModel>, DateTime?>((ref, day) {
  final async = ref.watch(labReceptionOrdersProvider);
  final all = async.valueOrNull ?? const <LabOrderModel>[];
  if (day == null) return all;
  final start = DateTime(day.year, day.month, day.day);
  final end = start.add(const Duration(days: 1));
  return all
      .where((o) {
        final t = o.orderedAt;
        if (t == null) return false;
        return !t.isBefore(start) && t.isBefore(end);
      })
      .toList();
});

// -----------------------------------------------------------------
// Dashboard
// -----------------------------------------------------------------
class LabReceptionistDashboard extends ConsumerStatefulWidget {
  const LabReceptionistDashboard({super.key});

  @override
  ConsumerState<LabReceptionistDashboard> createState() =>
      _LabReceptionistDashboardState();
}

class _LabReceptionistDashboardState
    extends ConsumerState<LabReceptionistDashboard> {
  final _searchCtrl = TextEditingController();
  DateTime? _dayFilter = DateTime.now();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Lab reception', style: AppTextStyles.h3),
        actions: [
          IconButton(
            tooltip: 'New walk-in order',
            onPressed: () => _openNewWalkin(context),
            icon: const Icon(Icons.add_circle_outline_rounded,
                color: AppColors.labAccent),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(labReceptionOrdersProvider),
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.textSecondary, size: 20),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.logout_rounded,
                color: AppColors.error),
          ),
        ],
      ),
      body: SafeArea(
        child: userAsync.when(
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
                    'Your account is not yet linked to a lab. Contact your lab owner.',
              );
            }
            final ordersAsync = ref.watch(labReceptionOrdersProvider);

            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () async {
                ref.invalidate(labReceptionOrdersProvider);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(context, user?.name ?? 'Lab reception'),
                    const SizedBox(height: 20),
                    _searchBar(context),
                    const SizedBox(height: 20),
                    _needsAttention(context, ordersAsync),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Today at a glance'),
                    _glanceGrid(ordersAsync),
                    const SizedBox(height: 24),
                    _daySwitcher(),
                    const SizedBox(height: 8),
                    _ordersByStage(context, ordersAsync),
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

  Widget _header(BuildContext context, String name) {
    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome back,', style: AppTextStyles.bodyMuted),
            const SizedBox(height: 4),
            Text(name, style: AppTextStyles.h1),
          ],
        ),
      ),
      const RoleBadge(
          label: 'Lab reception', color: AppColors.labAccent),
    ]);
  }

  Widget _searchBar(BuildContext context) {
    return TextField(
      controller: _searchCtrl,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search lab order by patient name, phone, or ID',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(
          icon: const Icon(Icons.arrow_forward_rounded),
          onPressed: () {
            final q = _searchCtrl.text.trim();
            if (q.isNotEmpty) _openSearchResults(context, q);
          },
        ),
      ),
      onSubmitted: (q) {
        if (q.trim().isNotEmpty) _openSearchResults(context, q.trim());
      },
    );
  }

  void _openSearchResults(BuildContext context, String q) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _LabOrderSearchResults(query: q),
      ),
    );
  }

  Future<void> _openNewWalkin(BuildContext context) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const LabWalkinOrderScreen(),
      ),
    );
    if (created == true) {
      ref.invalidate(labReceptionOrdersProvider);
    }
  }

  Widget _needsAttention(
      BuildContext context, AsyncValue<List<LabOrderModel>> ordersAsync) {
    final all = ordersAsync.valueOrNull ?? const <LabOrderModel>[];
    final items = <Widget>[];

    final awaitingRelease = all.where((o) =>
        o.awaitingRelease &&
        (o.paymentStatus == LabPaymentStatus.paid ||
            o.paymentStatus == LabPaymentStatus.waived));
    if (awaitingRelease.isNotEmpty) {
      items.add(_attentionTile(
        context,
        icon: Icons.lock_open_rounded,
        color: AppColors.success,
        title:
            '${awaitingRelease.length} report${awaitingRelease.length == 1 ? '' : 's'} ready to release',
        subtitle: 'Payment settled — tap to release to patient',
        onTap: () => setState(() => _dayFilter = null),
      ));
    }

    final unpaidReady = all.where((o) =>
        o.awaitingRelease &&
        o.paymentStatus == LabPaymentStatus.unpaid &&
        (o.billableAmount ?? 0) > 0);
    if (unpaidReady.isNotEmpty) {
      final total = unpaidReady.fold<double>(
          0, (s, o) => s + (o.billableAmount ?? 0));
      items.add(_attentionTile(
        context,
        icon: Icons.currency_rupee_rounded,
        color: AppColors.error,
        title:
            '${unpaidReady.length} report${unpaidReady.length == 1 ? '' : 's'} awaiting payment',
        subtitle:
            '₹${total.toStringAsFixed(0)} outstanding — collect to release',
        onTap: () => setState(() => _dayFilter = null),
      ));
    }

    final missingAmount = all.where((o) =>
        o.billableAmount == null &&
        o.status != LabOrderStatus.cancelled &&
        o.status != LabOrderStatus.noShow);
    if (missingAmount.isNotEmpty) {
      items.add(_attentionTile(
        context,
        icon: Icons.edit_note_rounded,
        color: AppColors.warning,
        title:
            '${missingAmount.length} order${missingAmount.length == 1 ? '' : 's'} missing an amount',
        subtitle: 'Set the fee before collection',
        onTap: () => setState(() => _dayFilter = null),
      ));
    }

    final readyStale = all.where((o) =>
        o.status == LabOrderStatus.ready &&
        o.released &&
        o.reportReadyAt != null &&
        DateTime.now().difference(o.reportReadyAt!).inHours >= 24);
    if (readyStale.isNotEmpty) {
      items.add(_attentionTile(
        context,
        icon: Icons.notifications_active_rounded,
        color: AppColors.info,
        title:
            '${readyStale.length} report${readyStale.length == 1 ? '' : 's'} ready but not collected',
        subtitle: 'Follow up with the patient',
        onTap: () => setState(() => _dayFilter = null),
      ));
    }

    if (items.isEmpty) {
      return GlassCard(
        child: Row(children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: AppColors.success, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Nothing needs your attention right now',
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textSecondary)),
          ),
        ]),
      );
    }

    return Column(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        items[i],
      ]
    ]);
  }

  Widget _attentionTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      GlassCard(
        borderColor: color.withOpacity(0.4),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.body),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted),
          ]),
        ),
      );

  Widget _glanceGrid(AsyncValue<List<LabOrderModel>> ordersAsync) {
    final todayOrders =
        ref.watch(labReceptionOrdersForDayProvider(_todayStart));
    final all = ordersAsync.valueOrNull ?? const <LabOrderModel>[];

    int countIn(List<LabOrderModel> xs, LabOrderStatus s) =>
        xs.where((o) => o.status == s).length;

    final awaitingSample = countIn(all, LabOrderStatus.ordered) +
        countIn(all, LabOrderStatus.accepted);
    final inProgress = countIn(all, LabOrderStatus.sampleCollected) +
        countIn(all, LabOrderStatus.processing);
    final awaitingReleaseCount =
        all.where((o) => o.awaitingRelease).length;
    final readyReleased = all
        .where((o) => o.status == LabOrderStatus.ready && o.released)
        .length;
    final deliveredToday =
        countIn(todayOrders, LabOrderStatus.delivered);
    final unpaidCount = all
        .where((o) =>
            o.paymentStatus == LabPaymentStatus.unpaid &&
            (o.billableAmount ?? 0) > 0)
        .length;
    final totalOpen = awaitingSample +
        inProgress +
        awaitingReleaseCount +
        readyReleased;

    final tiles = [
      _GlanceTile(
        label: 'Awaiting sample',
        value: awaitingSample.toString().padLeft(2, '0'),
        icon: Icons.pending_actions_rounded,
        color: AppColors.warning,
      ),
      _GlanceTile(
        label: 'In progress',
        value: inProgress.toString().padLeft(2, '0'),
        icon: Icons.biotech_rounded,
        color: AppColors.info,
      ),
      _GlanceTile(
        label: 'To release',
        value: awaitingReleaseCount.toString().padLeft(2, '0'),
        icon: Icons.lock_open_rounded,
        color: AppColors.success,
      ),
      _GlanceTile(
        label: 'Ready',
        value: readyReleased.toString().padLeft(2, '0'),
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.success,
      ),
      _GlanceTile(
        label: 'Unpaid',
        value: unpaidCount.toString().padLeft(2, '0'),
        icon: Icons.currency_rupee_rounded,
        color: AppColors.error,
      ),
      _GlanceTile(
        label: 'Total open',
        value: totalOpen.toString().padLeft(2, '0'),
        icon: Icons.list_alt_rounded,
        color: AppColors.primary,
      ),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.05,
      children: tiles.map(_glanceCard).toList(),
    );
  }

  DateTime get _todayStart {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Widget _glanceCard(_GlanceTile t) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 70,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(t.icon, color: t.color, size: 18),
              const SizedBox(height: 4),
              Text(
                t.value,
                style: AppTextStyles.h2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                t.label,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );

  Widget _daySwitcher() {
    return Row(children: [
      const Expanded(child: SectionHeader(title: 'Orders by stage')),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () {
              final d = _dayFilter ?? _todayStart;
              setState(() =>
                  _dayFilter = d.subtract(const Duration(days: 1)));
            },
          ),
          TextButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _dayFilter ?? DateTime.now(),
                firstDate:
                    DateTime.now().subtract(const Duration(days: 365)),
                lastDate:
                    DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _dayFilter = picked);
            },
            child: Text(_dayFilter == null
                ? 'All dates'
                : DateFormat('EEE, dd MMM').format(_dayFilter!)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () {
              final d = _dayFilter ?? _todayStart;
              setState(
                  () => _dayFilter = d.add(const Duration(days: 1)));
            },
          ),
          if (_dayFilter != null)
            IconButton(
              tooltip: 'Clear filter',
              icon: const Icon(Icons.close_rounded,
                  color: AppColors.textMuted),
              onPressed: () => setState(() => _dayFilter = null),
            ),
        ],
      ),
    ]);
  }

  Widget _ordersByStage(
      BuildContext context, AsyncValue<List<LabOrderModel>> ordersAsync) {
    return ordersAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
            child:
                CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => GlassCard(
        child: Text('Failed to load orders: $e',
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (_) {
  final all = ordersAsync.valueOrNull ?? const <LabOrderModel>[];
  // Only the "Delivered" section respects the date filter.
  final delivered = _dayFilter == null
      ? all.where((o) => o.status == LabOrderStatus.delivered).toList()
      : ref.watch(labReceptionOrdersForDayProvider(_dayFilter))
          .where((o) => o.status == LabOrderStatus.delivered)
          .toList();

  final awaitingRelease =
      all.where((o) => o.awaitingRelease).toList();
  final readyReleased = all
      .where((o) => o.status == LabOrderStatus.ready && o.released)
      .toList();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stageSection(context, title: 'New (awaiting acceptance)',
          statuses: [LabOrderStatus.ordered], orders: all),
      const SizedBox(height: 20),
      _stageSection(context, title: 'Awaiting sample',
          statuses: [LabOrderStatus.accepted], orders: all),
      const SizedBox(height: 20),
      _stageSection(context, title: 'In progress',
          statuses: [LabOrderStatus.sampleCollected, LabOrderStatus.processing],
          orders: all),
      const SizedBox(height: 20),
      _customStageSection(context, title: 'Reports awaiting release',
          orders: awaitingRelease),
      const SizedBox(height: 20),
      _customStageSection(context, title: 'Ready for pickup',
          orders: readyReleased),
      const SizedBox(height: 20),
      _customStageSection(context, title: 'Delivered', orders: delivered),
    ],
  );
},
    );
  }

  Widget _stageSection(
    BuildContext context, {
    required String title,
    required List<LabOrderStatus> statuses,
    required List<LabOrderModel> orders,
  }) {
    final list =
        orders.where((o) => statuses.contains(o.status)).toList();
    return _customStageSection(context, title: title, orders: list);
  }

  Widget _customStageSection(
    BuildContext context, {
    required String title,
    required List<LabOrderModel> orders,
  }) {
    final list = [...orders]..sort((a, b) {
        final at =
            a.orderedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt =
            b.orderedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(title, style: AppTextStyles.label),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${list.length}',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.primary)),
          ),
        ]),
        const SizedBox(height: 8),
        if (list.isEmpty)
          GlassCard(
            child: Row(children: [
              const Icon(Icons.inbox_outlined,
                  color: AppColors.textMuted, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Nothing here right now',
                    style: AppTextStyles.bodyMuted),
              ),
            ]),
          )
        else
          for (final o in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LabOrderRow(order: o, onChanged: () {
                ref.invalidate(labReceptionOrdersProvider);
              }),
            ),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Logout', style: AppTextStyles.h3),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (ok != true) return;
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
}

// -----------------------------------------------------------------
// Supporting widgets
// -----------------------------------------------------------------
class _GlanceTile {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _GlanceTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _LabOrderRow extends ConsumerWidget {
  final LabOrderModel order;
  final VoidCallback onChanged;

  const _LabOrderRow({required this.order, required this.onChanged});

  Color get _statusColor {
    switch (order.status) {
      case LabOrderStatus.ordered:
        return AppColors.labAccent;
      case LabOrderStatus.accepted:
        return AppColors.warning;
      case LabOrderStatus.sampleCollected:
      case LabOrderStatus.processing:
        return AppColors.info;
      case LabOrderStatus.ready:
        return order.released ? AppColors.success : AppColors.warning;
      case LabOrderStatus.delivered:
        return AppColors.success;
      case LabOrderStatus.cancelled:
      case LabOrderStatus.noShow:
        return AppColors.error;
      default:
        return AppColors.textMuted;
    }
  }

  ({String label, LabOrderStatus next})? get _receptionistAction {
    switch (order.status) {
      case LabOrderStatus.ordered:
        return (
          label: 'Forward to technician',
          next: LabOrderStatus.accepted
        );
      case LabOrderStatus.accepted:
        return (
          label: 'Sample collected',
          next: LabOrderStatus.sampleCollected
        );
      case LabOrderStatus.ready:
        if (order.released) {
          return (
            label: 'Mark delivered',
            next: LabOrderStatus.delivered
          );
        }
        return null;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = _receptionistAction;
    final referralLabel = order.isWalkIn
        ? 'Walk-in'
        : 'Dr. ${order.doctorName ?? '—'}';

    return GlassCard(
      borderColor: _statusColor.withOpacity(0.4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LabOrderDetailScreen(order: order),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _statusColor.withOpacity(.13),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      order.status == LabOrderStatus.ready
                          ? (order.released
                              ? Icons.description_rounded
                              : Icons.lock_outline_rounded)
                          : Icons.science_outlined,
                      color: _statusColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      order.testsSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    constraints: const BoxConstraints(maxWidth: 120),
                    decoration: BoxDecoration(
                      color: _statusColor.withOpacity(.13),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      order.statusLabel,
                      style: AppTextStyles.caption
                          .copyWith(color: _statusColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _menu(context, ref),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 34, top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${order.patientName} • ${order.patientId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  referralLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.caption,
                                ),
                              ),
                              if (order.orderedAt != null) ...[
                                Text('  ·  ',
                                    style: AppTextStyles.caption),
                                Text(
                                  DateFormat('dd MMM • hh:mm a')
                                      .format(order.orderedAt!),
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _feesRow(context, ref),
              if (order.awaitingRelease) ...[
                const SizedBox(height: 8),
                _releaseRow(context, ref),
              ],
              if (action != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      if (order.status == LabOrderStatus.ordered) {
                        _forward(context, ref);
                      } else {
                        _advance(context, ref, action);
                      }
                    },
                    icon: const Icon(Icons.arrow_forward_rounded,
                        size: 14),
                    label: Text(action.label),
                    style: TextButton.styleFrom(
                      foregroundColor: _statusColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _releaseRow(BuildContext context, WidgetRef ref) {
    final amount = order.billableAmount ?? 0;
    final isSettled =
        (order.paymentStatus == LabPaymentStatus.paid ||
                order.paymentStatus == LabPaymentStatus.waived) &&
            amount > 0;

    if (!isSettled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withOpacity(.3)),
        ),
        child: Row(children: [
          const Icon(Icons.lock_outline_rounded,
              size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              amount > 0
                  ? 'Collect ₹${amount.toStringAsFixed(0)} to release report'
                  : 'No price set — resolve in catalog or set manually',
              style:
                  AppTextStyles.caption.copyWith(color: AppColors.warning),
            ),
          ),
        ]),
      );
    }

    return Row(children: [
      const Icon(Icons.lock_open_rounded,
          size: 16, color: AppColors.success),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Payment settled — ready to release',
          style:
              AppTextStyles.caption.copyWith(color: AppColors.success),
        ),
      ),
      const SizedBox(width: 8),
      ElevatedButton.icon(
        onPressed: () => _release(context, ref),
        icon: const Icon(Icons.lock_open_rounded, size: 14),
        label: const Text('Release'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ]);
  }

  Future<void> _release(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Release report?', style: AppTextStyles.h3),
        content: Text(
          'Release the report for ${order.patientName} to the '
          'patient and referring doctor? This makes it visible '
          'everywhere in the app.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Release'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref.read(labServiceProvider).releaseReport(
            orderId: order.docId,
            releasedByUid: user.uid,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Report released · ${order.patientName} can now view it'),
        backgroundColor: AppColors.success,
      ));
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not release: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Widget _feesRow(BuildContext context, WidgetRef ref) {
    final amount = order.billableAmount;
    final isPaid = order.paymentStatus == LabPaymentStatus.paid;
    final isWaived = order.paymentStatus == LabPaymentStatus.waived;
    final isSettled = isPaid || isWaived;
    final isCancelled = order.status == LabOrderStatus.cancelled ||
        order.status == LabOrderStatus.noShow;

    final color = isSettled
        ? AppColors.success
        : (amount == null ? AppColors.warning : AppColors.error);
    final label = isWaived
        ? '${amount?.toStringAsFixed(0) ?? '—'} · Waived'
        : isPaid
            ? '${amount?.toStringAsFixed(0) ?? '—'} · Paid'
            : amount == null
                ? 'Amount not set'
                : '₹${amount.toStringAsFixed(0)} · Unpaid';

    final actions = <Widget>[
      if (!isSettled && !isCancelled) ...[
        if (amount == null)
          _compactTextButton(
            context: context,
            label: 'Set amount',
            color: AppColors.info,
            onTap: () => _openSetAmountDialog(context, ref),
          )
        else ...[
          _compactTextButton(
            context: context,
            label: 'Mark paid',
            color: AppColors.success,
            onTap: () => _markPaid(context, ref),
          ),
          _compactTextButton(
            context: context,
            label: 'Waive',
            color: AppColors.textMuted,
            onTap: () => _waive(context, ref),
          ),
        ],
      ],
    ];

    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.currency_rupee_rounded,
                size: 12, color: AppColors.textMuted),
            const SizedBox(width: 2),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
        ),
        if (actions.isNotEmpty)
          Wrap(
            spacing: 0,
            runSpacing: 0,
            children: actions,
          ),
      ],
    );
  }

  Widget _compactTextButton({
    required BuildContext context,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }

  Future<void> _openSetAmountDialog(
      BuildContext context, WidgetRef ref) async {
    final amount = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SetAmountDialog(),
    );
    if (amount == null) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref.read(labServiceProvider).setBillableAmount(
            orderId: order.docId,
            amount: amount,
            setByUid: user.uid,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Amount set · ₹${amount.toStringAsFixed(0)} · ${order.patientName}'),
        backgroundColor: AppColors.success,
      ));
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to set amount: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _markPaid(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref.read(labServiceProvider).markLabFeesPaid(
            orderId: order.docId,
            collectedByUid: user.uid,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Payment collected · ₹${order.billableAmount!.toStringAsFixed(0)} · ${order.patientName}'),
        backgroundColor: AppColors.success,
      ));
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _waive(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Waive fees?', style: AppTextStyles.h3),
        content: Text(
          'Waive ₹${order.billableAmount!.toStringAsFixed(0)} for '
          '${order.patientName}? This cannot be undone.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Waive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref.read(labServiceProvider).waiveLabFees(
            orderId: order.docId,
            collectedByUid: user.uid,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fees waived · ${order.patientName}'),
        backgroundColor: AppColors.success,
      ));
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

    Widget _menu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded,
          color: AppColors.textMuted, size: 18),
      color: AppColors.surface,
      onSelected: (value) async {
        switch (value) {
          case 'reprint_labels':
            await _reprintLabels(context, ref);
            break;
          case 'cancel':
            await _run(
              context,
              'Cancelled',
              () => ref
                  .read(labServiceProvider)
                  .cancelOrder(order.docId, byRole: 'receptionist'),
            );
            break;
          case 'no_show':
            await _run(
              context,
              'Marked no-show',
              () => ref.read(labServiceProvider).markNoShow(order.docId),
            );
            break;
        }
      },
      itemBuilder: (_) => [
        if (order.sampleGroups.isNotEmpty)
          const PopupMenuItem(
            value: 'reprint_labels',
            child: _MenuRow(
              icon: Icons.print_rounded,
              label: 'Reprint sample labels',
              color: AppColors.info,
            ),
          ),
        if (order.status != LabOrderStatus.delivered &&
            order.status != LabOrderStatus.cancelled &&
            order.status != LabOrderStatus.noShow)
          const PopupMenuItem(
            value: 'cancel',
            child: _MenuRow(
              icon: Icons.cancel_outlined,
              label: 'Cancel order',
              color: AppColors.error,
            ),
          ),
        if (order.status == LabOrderStatus.accepted)
          const PopupMenuItem(
            value: 'no_show',
            child: _MenuRow(
              icon: Icons.person_off_outlined,
              label: 'Mark patient no-show',
              color: AppColors.error,
            ),
          ),
      ],
    );
  }

  Future<void> _reprintLabels(BuildContext context, WidgetRef ref) async {
    if (order.sampleGroups.isEmpty) return;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SampleLabelsPreviewSheet(
        order: order,
        groups: order.sampleGroups,
        collectedAt: order.sampleCollectedAt ?? DateTime.now(),
      ),
    );
  }

  Future<void> _forward(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref.read(labServiceProvider).forwardToTechnician(
            orderId: order.docId,
            forwardedByUid: user.uid,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${order.patientName} — forwarded to lab technician'),
        backgroundColor: AppColors.success,
      ));
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

 Future<void> _advance(
    BuildContext context,
    WidgetRef ref,
    ({String label, LabOrderStatus next}) action,
  ) async {
    // Capture navigator context BEFORE awaiting, so it survives the
    // post-write rebuild that disposes this row widget.
    final navContext = Navigator.of(context, rootNavigator: true).context;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      await ref
          .read(labServiceProvider)
          .updateStatus(order.docId, action.next);

      scaffoldMessenger.showSnackBar(SnackBar(
        content:
            Text('${order.patientName} — ${action.label.toLowerCase()}'),
        backgroundColor: AppColors.success,
      ));

      onChanged();

      if (action.next == LabOrderStatus.sampleCollected) {
        // Small delay so the stream-rebuild disposes this row first;
        // then we open the sheet on the (still-mounted) navigator.
        await Future.delayed(const Duration(milliseconds: 300));
        if (!navContext.mounted) return;
        await _maybePrintSampleLabel(navContext, ref);
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  /// Reads the fresh order doc to pick up sampleGroups assigned by
  /// updateStatus, then opens the multi-label print preview.
  Future<void> _maybePrintSampleLabel(
    BuildContext context, // ← this is now the navigator's context
    WidgetRef ref,
  ) async {
    final updated = await FirebaseFirestore.instance
        .collection('labOrders')
        .doc(order.docId)
        .get();
    final fresh = LabOrderModel.fromMap(order.docId, updated.data() ?? {});

    if (fresh.sampleGroups.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sample IDs were not generated.'),
        backgroundColor: AppColors.warning,
      ));
      return;
    }

    if (!context.mounted) return;
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SampleLabelsPreviewSheet(
        order: fresh,
        groups: fresh.sampleGroups,
        collectedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    String label,
    Future<void> Function() fn,
  ) async {
    try {
      await fn();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${order.patientName} — $label'),
        backgroundColor: AppColors.success,
      ));
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }
}

// -----------------------------------------------------------------
// Set-amount dialog
// -----------------------------------------------------------------
class _SetAmountDialog extends StatefulWidget {
  const _SetAmountDialog();
  @override
  State<_SetAmountDialog> createState() => _SetAmountDialogState();
}

class _SetAmountDialogState extends State<_SetAmountDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.trim());
    if (v == null || v <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Set amount', style: AppTextStyles.h3),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          'Amount the patient should pay for this order.',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            prefixText: '₹ ',
            hintText: 'e.g. 500',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.info,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------
// Search results
// -----------------------------------------------------------------
class _LabOrderSearchResults extends ConsumerWidget {
  final String query;
  const _LabOrderSearchResults({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(labReceptionOrdersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Results · $query', style: AppTextStyles.h3),
      ),
      body: SafeArea(
        child: ordersAsync.when(
          loading: () => const Center(
              child:
                  CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (all) {
            final q = query.trim().toLowerCase();
            final results = all.where((o) {
              final name = o.patientName.toLowerCase();
              final pid = o.patientId.toLowerCase();
              final phone = (o.patientPhone ?? '').toLowerCase();
              return name.contains(q) ||
                  pid.contains(q) ||
                  phone.contains(q);
            }).toList()
              ..sort((a, b) {
                final at = a.orderedAt ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                final bt = b.orderedAt ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                return bt.compareTo(at);
              });

            if (results.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_off_rounded,
                          size: 48, color: AppColors.textMuted),
                      const SizedBox(height: 12),
                      Text('No orders matched "$query"',
                          style: AppTextStyles.bodyMuted,
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: results.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _LabOrderRow(
                order: results[i],
                onChanged: () {
                  ref.invalidate(labReceptionOrdersProvider);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------
// Menu row
// -----------------------------------------------------------------
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Text(label,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 13)),
    ]);
  }
}