// lib/features/chemist/presentation/chemist_dashboard.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/prescription_order_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';
import '../../subscription/widgets/subscription_card.dart';
import 'chemist_order_detail_screen.dart';

/// Retrieves the linked chemist document ID from:
/// users/{uid}.linkedChemistDocId
final currentChemistDocIdProvider =
    FutureProvider.autoDispose<String?>((ref) async {
  debugPrint('[CHEMIST] Loading current user...');

  final user = await ref
      .watch(currentUserProvider.future)
      .timeout(const Duration(seconds: 15));

  if (user == null) {
    debugPrint('[CHEMIST] No authenticated user found.');
    return null;
  }

  debugPrint('[CHEMIST] Current UID: ${user.uid}');

  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get()
      .timeout(const Duration(seconds: 15));

  if (!doc.exists) {
    debugPrint('[CHEMIST] User document does not exist.');
    return null;
  }

  final raw = doc.data()?['linkedChemistDocId'] ?? '';

  final clean = raw
      .toString()
      .replaceAll('"', '')
      .trim();

  debugPrint('[CHEMIST] Linked chemist ID: $clean');

  if (clean.isEmpty) {
    debugPrint('[CHEMIST] No linkedChemistDocId found.');
    return null;
  }

  return clean;
});

final chemistOrdersProvider = StreamProvider.autoDispose
    .family<List<PrescriptionOrderModel>, String>(
  (ref, chemistDocId) {
    return ref
        .watch(chemistServiceProvider)
        .watchChemistOrders(chemistDocId);
  },
);

class ChemistDashboard extends ConsumerStatefulWidget {
  const ChemistDashboard({super.key});

  @override
  ConsumerState<ChemistDashboard> createState() =>
      _ChemistDashboardState();
}

class _ChemistDashboardState extends ConsumerState<ChemistDashboard>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  String _filter = 'new';

  @override
  void initState() {
    super.initState();

    _tabCtrl = TabController(length: 3, vsync: this);

    _tabCtrl.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    if (_tabCtrl.indexIsChanging) return;

    final newFilter = ['new', 'active', 'history'][_tabCtrl.index];

    if (_filter != newFilter && mounted) {
      setState(() {
        _filter = newFilter;
      });
    }
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_handleTabChange);
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshOrders(String chemistDocId) async {
    debugPrint('[CHEMIST] Refreshing orders...');

    ref.invalidate(chemistOrdersProvider(chemistDocId));

    try {
      await ref
          .read(chemistOrdersProvider(chemistDocId).future)
          .timeout(const Duration(seconds: 25));

      debugPrint('[CHEMIST] Orders refresh completed.');
    } catch (e) {
      debugPrint('[CHEMIST] Refresh failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final chemistDocIdAsync = ref.watch(currentChemistDocIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(title: 'Chemist orders'),
      body: SafeArea(
        child: Column(
          children: [
            // -------------------------------------------------
            // TABS
            // -------------------------------------------------
            Container(
              color: AppColors.surface,
              child: TabBar(
                controller: _tabCtrl,
                indicatorColor: AppColors.primary,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textMuted,
                tabs: const [
                  Tab(text: 'New'),
                  Tab(text: 'Active'),
                  Tab(text: 'History'),
                ],
              ),
            ),

            // -------------------------------------------------
            // DASHBOARD CONTENT
            // -------------------------------------------------
            Expanded(
              child: chemistDocIdAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),

                error: (e, stack) => _ErrorView(
                  message: 'Unable to load chemist account: $e',
                  onRetry: () {
                    ref.invalidate(currentChemistDocIdProvider);
                  },
                ),

                data: (chemistDocId) {
                  if (chemistDocId == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No chemist linked to this account. '
                          'Ask your clinic admin to link your login '
                          'to a chemist record.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMuted,
                        ),
                      ),
                    );
                  }

                  final ordersAsync = ref.watch(
                    chemistOrdersProvider(chemistDocId),
                  );

                  // ── Subscription card + order list ──
                  // The card is shown above the order list so chemist
                  // owners can see plan status / renew without leaving
                  // the orders screen. If you want to gate it to owners
                  // only, wrap in: if (user?.isOwner == true)
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: SubscriptionCard(
                          entityType: 'chemist',
                          entityIdOverride: chemistDocId,
                          productLabel: 'Chemist',
                        ),
                      ),
                      Expanded(
                        child: ordersAsync.when(
                          loading: () => const Center(
                            child: CircularProgressIndicator(),
                          ),

                          error: (e, stack) => _ErrorView(
                            message: 'Unable to load orders: $e',
                            onRetry: () {
                              ref.invalidate(
                                chemistOrdersProvider(chemistDocId),
                              );
                            },
                          ),

                          data: (orders) {
                            final filtered = _filterOrders(orders);

                            if (filtered.isEmpty) {
                              return RefreshIndicator(
                                color: AppColors.primary,
                                onRefresh: () =>
                                    _refreshOrders(chemistDocId),
                                child: ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  children: [
                                    SizedBox(
                                      height: MediaQuery.of(context)
                                              .size
                                              .height *
                                          0.25,
                                      child: Center(
                                        child: Text(
                                          'No $_filter orders.',
                                          style: AppTextStyles.bodyMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return RefreshIndicator(
                              color: AppColors.primary,
                              onRefresh: () =>
                                  _refreshOrders(chemistDocId),
                              child: ListView.separated(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(16),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, i) {
                                  return _OrderCard(
                                    order: filtered[i],
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Separates orders into New, Active and History.
  List<PrescriptionOrderModel> _filterOrders(
    List<PrescriptionOrderModel> orders,
  ) {
    return orders.where((order) {
      switch (_filter) {
        case 'new':
          return order.status == PrescriptionOrderStatus.placed;

        case 'active':
          return order.status == PrescriptionOrderStatus.accepted ||
              order.status == PrescriptionOrderStatus.billed ||
              order.status ==
                  PrescriptionOrderStatus.paidPendingVerification ||
              order.status == PrescriptionOrderStatus.paid ||
              order.status == PrescriptionOrderStatus.preparing ||
              order.status ==
                  PrescriptionOrderStatus.outForDelivery;

        case 'history':
          return order.status == PrescriptionOrderStatus.delivered ||
              order.status == PrescriptionOrderStatus.cancelled ||
              order.status == PrescriptionOrderStatus.rejected;

        default:
          return false;
      }
    }).toList();
  }
}

// =============================================================
// ERROR VIEW
// =============================================================

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// ORDER CARD
// =============================================================

class _OrderCard extends StatelessWidget {
  final PrescriptionOrderModel order;

  const _OrderCard({
    required this.order,
  });

  Color get _color {
    switch (order.status) {
      case PrescriptionOrderStatus.placed:
        return AppColors.warning;

      case PrescriptionOrderStatus.accepted:
        return AppColors.info;

      case PrescriptionOrderStatus.billed:
        return AppColors.patientAccent;

      case PrescriptionOrderStatus.paidPendingVerification:
        return AppColors.info;

      case PrescriptionOrderStatus.paid:
        return AppColors.success;

      case PrescriptionOrderStatus.preparing:
      case PrescriptionOrderStatus.outForDelivery:
        return AppColors.info;

      case PrescriptionOrderStatus.delivered:
        return AppColors.success;

      case PrescriptionOrderStatus.cancelled:
      case PrescriptionOrderStatus.rejected:
        return AppColors.error;

      case PrescriptionOrderStatus.unknown:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: _color.withOpacity(.4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChemistOrderDetailScreen(
                orderId: order.docId,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _color.withOpacity(.13),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      order.statusLabel,
                      style: AppTextStyles.caption.copyWith(
                        color: _color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '#${order.orderNumber}',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Text(
                order.patientName,
                style: AppTextStyles.body,
              ),

              const SizedBox(height: 2),

              Text(
                '${order.patientPhone} • ${order.items.length} item'
                '${order.items.length == 1 ? '' : 's'}',
                style: AppTextStyles.caption,
              ),

              const SizedBox(height: 4),

              Text(
                DateFormat('dd MMM, hh:mm a').format(order.placedAt),
                style: AppTextStyles.caption,
              ),

              if (order.totalAmount != null) ...[
                const SizedBox(height: 6),
                Text(
                  '₹${order.totalAmount!.toStringAsFixed(0)}',
                  style: AppTextStyles.h3.copyWith(
                    color: AppColors.success,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}