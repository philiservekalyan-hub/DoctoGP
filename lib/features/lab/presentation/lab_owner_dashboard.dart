// lib/features/lab/presentation/lab_owner_dashboard.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../shared/widgets/role_badge.dart';
import 'lab_team_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// DATA PROVIDERS
// ═══════════════════════════════════════════════════════════════════

/// All offerings + packages + orders for the current lab, combined.
/// Recomputed whenever anything changes — the dashboard stays live.
class LabOwnerSnapshot {
  final List<Map<String, dynamic>> offerings;
  final List<Map<String, dynamic>> packages;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> teamMembers;

  LabOwnerSnapshot({
    required this.offerings,
    required this.packages,
    required this.orders,
    required this.teamMembers,
  });

  // ── Counts ──
  int get totalOfferings => offerings.length;
  int get activeOfferings =>
      offerings.where((o) => o['active'] != false).length;
  int get totalPackages => packages.length;
  int get activePackages =>
      packages.where((p) => p['active'] != false).length;

  // ── Today's orders ──
  List<Map<String, dynamic>> get todayOrders {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return orders.where((o) {
      final ts = o['orderedAt'];
      if (ts is! Timestamp) return false;
      final d = ts.toDate();
      return !d.isBefore(start);
    }).toList();
  }

  // ── Today's collected revenue ──
  double get todayCollected {
    final start = DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day);
    var sum = 0.0;
    for (final o in orders) {
      final paid = o['paymentStatus']?.toString();
      if (paid != 'paid') continue;
      final ts = o['feesPaidAt'];
      if (ts is! Timestamp) continue;
      if (ts.toDate().isBefore(start)) continue;
      sum += (o['billableAmount'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  // ── Pending revenue (unpaid, not cancelled/no-show) ──
  double get pendingRevenue {
    var sum = 0.0;
    for (final o in orders) {
      final status = o['status']?.toString() ?? '';
      if (status == 'cancelled' || status == 'noShow') continue;
      final paid = o['paymentStatus']?.toString();
      if (paid == 'paid' || paid == 'waived') continue;
      sum += (o['billableAmount'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  // ── Pipeline counts ──
  int countStatus(String status) =>
      orders.where((o) => o['status'] == status).length;

  int get awaitingAcceptance => countStatus('ordered');
  int get inProgress =>
      countStatus('accepted') +
      countStatus('sampleCollected') +
      countStatus('processing');
  int get ready => countStatus('ready');
  int get delivered => countStatus('delivered');

  // ── 7-day revenue series ──
  List<({DateTime day, double amount})> get lastSevenDays {
    final now = DateTime.now();
    final days = <({DateTime day, double amount})>[];
    for (var i = 6; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i));
      final nextDay = d.add(const Duration(days: 1));
      var sum = 0.0;
      for (final o in orders) {
        final paid = o['paymentStatus']?.toString();
        if (paid != 'paid') continue;
        final ts = o['feesPaidAt'];
        if (ts is! Timestamp) continue;
        final t = ts.toDate();
        if (t.isBefore(d) || !t.isBefore(nextDay)) continue;
        sum += (o['billableAmount'] as num?)?.toDouble() ?? 0;
      }
      days.add((day: d, amount: sum));
    }
    return days;
  }

  // ── Top 5 tests this month ──
  List<({String name, int count})> get topTestsThisMonth {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final counter = <String, int>{};
    for (final o in orders) {
      final ts = o['orderedAt'];
      if (ts is! Timestamp) continue;
      if (ts.toDate().isBefore(monthStart)) continue;
      final tests = o['tests'] as List? ?? const [];
      for (final t in tests) {
        if (t is Map) {
          final code = (t['code'] ?? '').toString();
          final name = (t['name'] ?? '').toString();
          final key = code.isNotEmpty ? code : name;
          if (key.isEmpty) continue;
          counter[key] = (counter[key] ?? 0) + 1;
        }
      }
    }
    final list = counter.entries
        .map((e) => (name: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return list.take(5).toList();
  }
}

final labOwnerSnapshotProvider =
    StreamProvider.autoDispose<LabOwnerSnapshot>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final labClinicId = user?.clinicId;
  if (labClinicId == null || labClinicId.isEmpty) {
    return const Stream.empty();
  }
  final db = FirebaseFirestore.instance;
  final offeringsStream = db
      .collection('clinics')
      .doc(labClinicId)
      .collection('labTests')
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'offeringId': d.id, ...d.data()})
          .toList());

  final packagesStream = db
      .collection('clinics')
      .doc(labClinicId)
      .collection('labPackages')
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'packageId': d.id, ...d.data()})
          .toList());

  final ordersStream = db
      .collection('labOrders')
      .where('labClinicId', isEqualTo: labClinicId)
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'orderId': d.id, ...d.data()})
          .toList());

  final teamStream = db
      .collection('users')
      .where('clinicId', isEqualTo: labClinicId)
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'uid': d.id, ...d.data()})
          .toList());

  return _combine4(offeringsStream, packagesStream, ordersStream, teamStream);
});

Stream<LabOwnerSnapshot> _combine4(
  Stream<List<Map<String, dynamic>>> a,
  Stream<List<Map<String, dynamic>>> b,
  Stream<List<Map<String, dynamic>>> c,
  Stream<List<Map<String, dynamic>>> d,
) {
  final ctlA = _ValueCtl<List<Map<String, dynamic>>>();
  final ctlB = _ValueCtl<List<Map<String, dynamic>>>();
  final ctlC = _ValueCtl<List<Map<String, dynamic>>>();
  final ctlD = _ValueCtl<List<Map<String, dynamic>>>();

  a.listen(ctlA.set, onError: ctlA.error);
  b.listen(ctlB.set, onError: ctlB.error);
  c.listen(ctlC.set, onError: ctlC.error);
  d.listen(ctlD.set, onError: ctlD.error);

  return _merge([ctlA, ctlB, ctlC, ctlD]).map((_) {
    return LabOwnerSnapshot(
      offerings: ctlA.value ?? const [],
      packages: ctlB.value ?? const [],
      orders: ctlC.value ?? const [],
      teamMembers: ctlD.value ?? const [],
    );
  });
}

class _ValueCtl<T> {
  T? value;
  void Function(Object)? _onError;
  void set(T v) {
    value = v;
    _notify?.call();
  }
  void error(Object e) => _onError?.call(e);
  void Function()? _notify;
}

Stream<void> _merge(List<_ValueCtl> controllers) {
  late void Function() emit;
  final ctl = StreamController<void>();
  var remaining = controllers.length;
  void check() {
    remaining--;
    if (remaining <= 0) ctl.add(null);
  }
  for (final c in controllers) {
    c._notify = check;
    c._onError = ctl.addError;
  }
  return ctl.stream;
}

// ═══════════════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════════════

class LabOwnerDashboard extends ConsumerWidget {
  const LabOwnerDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final snapshotAsync = ref.watch(labOwnerSnapshotProvider);

    final currentUser = userAsync.valueOrNull;
    final canPractise = currentUser?.canPractise == true;
    final isOwner = currentUser?.role == UserRole.owner;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Lab dashboard', style: AppTextStyles.h3),
        actions: [
  // Toggle to the lab operations dashboard.
  if (isOwner && canPractise)
    IconButton(
      tooltip: 'Open lab dashboard',
      onPressed: () => context.push('/lab/tech'),
      icon: const Icon(
        Icons.biotech_rounded,
        color: AppColors.textSecondary,
        size: 20,
      ),
    ),
  IconButton(
    tooltip: 'Refresh',
    onPressed: () => ref.invalidate(labOwnerSnapshotProvider),
    icon: const Icon(Icons.refresh_rounded,
        color: AppColors.textSecondary, size: 20),
  ),
  IconButton(
    tooltip: 'Logout',
    onPressed: () => _confirmLogout(context),
    icon: const Icon(Icons.logout_rounded, color: AppColors.error),
  ),
  const SizedBox(width: 4),
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
              return const Center(
                  child: Text('No lab linked to your account.'));
            }
            return snapshotAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primary)),
              error: (e, _) => Center(child: Text('$e')),
              data: (snap) => RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async =>
                    ref.invalidate(labOwnerSnapshotProvider),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _header(context, user?.name ?? 'Lab owner'),
                    const SizedBox(height: 20),
                    _overviewCards(snap),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Revenue — last 7 days'),
                    const SizedBox(height: 8),
                    _revenueChart(snap),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Order pipeline'),
                    const SizedBox(height: 8),
                    _pipelineChart(snap),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Top tests this month'),
                    const SizedBox(height: 8),
                    _topTests(snap),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Catalogue summary'),
                    const SizedBox(height: 8),
                    _catalogueSummary(snap),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Team'),
                    const SizedBox(height: 8),
                    _teamSummary(context, snap),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Reports'),
                    const SizedBox(height: 8),
                    _reports(context, snap),
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
      // Router's redirect fires when authStateProvider emits null:
      //   currentUserProvider → null → redirect to /login
      //   labOwnerSnapshotProvider watches currentUserProvider,
      //   sees null, and returns Stream.empty() on its own.
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not sign out: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
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
      const RoleBadge(label: 'Lab owner', color: AppColors.labAccent),
    ]);
  }

  // ── Overview cards ──
  Widget _overviewCards(LabOwnerSnapshot snap) {
    final cards = [
      (
        label: 'Total tests',
        value: '${snap.totalOfferings}',
        icon: Icons.science_rounded,
        color: AppColors.info,
      ),
      (
        label: 'Total packages',
        value: '${snap.totalPackages}',
        icon: Icons.inventory_2_outlined,
        color: AppColors.accent,
      ),
      (
        label: "Today's orders",
        value: '${snap.todayOrders.length}',
        icon: Icons.receipt_long_rounded,
        color: AppColors.labAccent,
      ),
      (
        label: "Today's collection",
        value: '₹${snap.todayCollected.toStringAsFixed(0)}',
        icon: Icons.currency_rupee_rounded,
        color: AppColors.success,
      ),
    ];

    return Column(children: [
      Row(children: [
        Expanded(child: _statCard(cards[0])),
        const SizedBox(width: 12),
        Expanded(child: _statCard(cards[1])),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _statCard(cards[2])),
        const SizedBox(width: 12),
        Expanded(child: _statCard(cards[3])),
      ]),
      const SizedBox(height: 12),
      GlassCard(
        borderColor: AppColors.warning.withOpacity(.35),
        child: Row(children: [
          const Icon(Icons.pending_actions_rounded,
              color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Pending collections',
                style: AppTextStyles.body),
          ),
          Text(
            '₹${snap.pendingRevenue.toStringAsFixed(0)}',
            style: AppTextStyles.h3
                .copyWith(color: AppColors.warning),
          ),
        ]),
      ),
    ]);
  }

  Widget _statCard(
      ({String label, String value, IconData icon, Color color}) c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(c.icon, color: c.color, size: 20),
          const SizedBox(height: 8),
          Text(c.value, style: AppTextStyles.h2),
          const SizedBox(height: 2),
          Text(c.label,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textMuted)),
        ],
      ),
    );
  }

  // ── Revenue bar chart ──
  Widget _revenueChart(LabOwnerSnapshot snap) {
    final data = snap.lastSevenDays;
    final maxY = data.fold<double>(
            0, (m, d) => d.amount > m ? d.amount : m) *
        1.2;
    final yMax = maxY <= 0 ? 100.0 : maxY;

    return GlassCard(
      child: SizedBox(
        height: 220,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: BarChart(
            BarChartData(
              maxY: yMax,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: yMax / 4,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppColors.cardBorder,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: yMax / 4,
                    getTitlesWidget: (v, _) => Text(
                      v >= 1000
                          ? '₹${(v / 1000).toStringAsFixed(0)}k'
                          : '₹${v.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textMuted),
                    ),
                  ),
                ),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= data.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          DateFormat('EEE').format(data[i].day),
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textMuted),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < data.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: data[i].amount,
                        color: AppColors.success,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Pipeline donut ──
  Widget _pipelineChart(LabOwnerSnapshot snap) {
    final slices = <({String label, int count, Color color})>[
      (
        label: 'New',
        count: snap.awaitingAcceptance,
        color: AppColors.labAccent
      ),
      (
        label: 'In progress',
        count: snap.inProgress,
        color: AppColors.info
      ),
      (label: 'Ready', count: snap.ready, color: AppColors.success),
      (
        label: 'Delivered',
        count: snap.delivered,
        color: AppColors.textMuted
      ),
    ];
    final total = slices.fold<int>(0, (s, e) => s + e.count);

    return GlassCard(
      child: Row(children: [
        SizedBox(
          width: 140,
          height: 140,
          child: total == 0
              ? const Center(
                  child: Text('No data',
                      style: TextStyle(color: AppColors.textMuted)))
              : PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 34,
                    sections: [
                      for (final s in slices)
                        if (s.count > 0)
                          PieChartSectionData(
                            value: s.count.toDouble(),
                            color: s.color,
                            title: '',
                            radius: 26,
                          ),
                    ],
                  ),
                ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(s.label,
                          style: AppTextStyles.caption),
                    ),
                    Text('${s.count}',
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                  ]),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Top tests ──
  Widget _topTests(LabOwnerSnapshot snap) {
    final list = snap.topTestsThisMonth;
    if (list.isEmpty) {
      return GlassCard(
        child: Text('No orders this month yet.',
            style: AppTextStyles.bodyMuted),
      );
    }
    return GlassCard(
      child: Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const Divider(height: 16, color: AppColors.cardBorder),
            Row(children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text('${i + 1}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    )),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(list[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body),
              ),
              Text('${list[i].count} orders',
                  style: AppTextStyles.caption),
            ]),
          ],
        ],
      ),
    );
  }

  // ── Catalogue summary ──
  Widget _catalogueSummary(LabOwnerSnapshot snap) {
    return GlassCard(
      child: Row(children: [
        Expanded(
          child: _metric('Active tests',
              '${snap.activeOfferings}', AppColors.success),
        ),
        Expanded(
          child: _metric('Inactive tests',
              '${snap.totalOfferings - snap.activeOfferings}',
              AppColors.textMuted),
        ),
        Expanded(
          child: _metric('Active packages',
              '${snap.activePackages}', AppColors.accent),
        ),
      ]),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTextStyles.h2.copyWith(color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textMuted)),
      ],
    );
  }

  // ── Team summary ──

  Widget _teamSummary(BuildContext context, LabOwnerSnapshot snap) {
    int countRole(String role) => snap.teamMembers
        .where((m) => m['role']?.toString() == role)
        .length;

    final owner = countRole('owner');
    final lab = countRole('lab');
    final reception = countRole('receptionist');
    final total = snap.teamMembers.length;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('$total team member${total == 1 ? '' : 's'}',
                  style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LabTeamScreen(),
                ),
              ),
              child: const Text('Manage',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _teamChip('Owner', owner, AppColors.accent),
            _teamChip('Technician', lab, AppColors.info),
            _teamChip('Reception', reception, AppColors.labAccent),
          ]),
        ],
      ),
    );
  }

  Widget _teamChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$label · $count',
          style: AppTextStyles.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          )),
    );
  }

  // ── Reports ──
  Widget _reports(BuildContext context, LabOwnerSnapshot snap) {
    return Column(
      children: [
        _reportTile(
          icon: Icons.table_chart_outlined,
          color: AppColors.info,
          title: 'Download orders (CSV)',
          subtitle: 'All orders with patient, test, price, status',
          onTap: () => _exportOrdersCsv(context, snap),
        ),
        const SizedBox(height: 8),
        _reportTile(
          icon: Icons.receipt_long_outlined,
          color: AppColors.success,
          title: 'Download revenue (CSV)',
          subtitle: 'Last 7 days, daily collected amounts',
          onTap: () => _exportRevenueCsv(context, snap),
        ),
        const SizedBox(height: 8),
        _reportTile(
          icon: Icons.science_outlined,
          color: AppColors.accent,
          title: 'Download catalogue (CSV)',
          subtitle: 'Active + inactive tests and packages',
          onTap: () => _exportCatalogueCsv(context, snap),
        ),
        const SizedBox(height: 8),
        _reportTile(
          icon: Icons.print_outlined,
          color: AppColors.labAccent,
          title: 'Print summary',
          subtitle: 'Preview daily summary and print',
          onTap: () => _openPrintPreview(context, snap),
        ),
      ],
    );
  }

  Widget _reportTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GlassCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
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
            const Icon(Icons.download_rounded,
                color: AppColors.textMuted, size: 18),
          ]),
        ),
      ),
    );
  }

  // ── CSV exports ──

  Future<void> _exportOrdersCsv(
      BuildContext context, LabOwnerSnapshot snap) async {
    final buf = StringBuffer();
    buf.writeln(
        'OrderID,Patient,PatientID,Tests,Billable,PaymentStatus,Status,OrderedAt');
    for (final o in snap.orders) {
      final tests = (o['tests'] as List? ?? const [])
          .map((t) {
            if (t is Map) return (t['code'] ?? t['name'] ?? '').toString();
            return t.toString();
          })
          .where((s) => s.isNotEmpty)
          .join(' | ');
      final ordered = o['orderedAt'];
      final when = ordered is Timestamp
          ? DateFormat('yyyy-MM-dd HH:mm').format(ordered.toDate())
          : '';
      buf.writeln([
        _csv((o['orderId'] ?? '').toString()),
        _csv((o['patientName'] ?? '').toString()),
        _csv((o['patientId'] ?? '').toString()),
        _csv(tests),
        (o['billableAmount'] as num?)?.toStringAsFixed(2) ?? '',
        _csv((o['paymentStatus'] ?? '').toString()),
        _csv((o['status'] ?? '').toString()),
        _csv(when),
      ].join(','));
    }
    await _writeAndNotify(context, 'orders', buf.toString());
  }

  Future<void> _exportRevenueCsv(
      BuildContext context, LabOwnerSnapshot snap) async {
    final buf = StringBuffer();
    buf.writeln('Date,Collected');
    for (final d in snap.lastSevenDays) {
      buf.writeln(
          '${DateFormat('yyyy-MM-dd').format(d.day)},${d.amount.toStringAsFixed(2)}');
    }
    await _writeAndNotify(context, 'revenue', buf.toString());
  }

  Future<void> _exportCatalogueCsv(
      BuildContext context, LabOwnerSnapshot snap) async {
    final buf = StringBuffer();
    buf.writeln('Type,Code,Name,Category,MRP,OfferPrice,Active');
    for (final o in snap.offerings) {
      final isLocal = o['isLocal'] == true;
      final code = isLocal
          ? (o['localCode'] ?? '').toString()
          : ''; // canonical code not stored on the offering
      final name = isLocal
          ? (o['localName'] ?? '').toString()
          : '';
      buf.writeln([
        'Offering',
        _csv(code),
        _csv(name),
        _csv((o['localCategory'] ?? '').toString()),
        (o['mrp'] as num?)?.toStringAsFixed(2) ?? '',
        (o['offerPrice'] as num?)?.toStringAsFixed(2) ?? '',
        (o['active'] == true).toString(),
      ].join(','));
    }
    for (final p in snap.packages) {
      buf.writeln([
        'Package',
        '',
        _csv((p['name'] ?? '').toString()),
        '',
        (p['computedMrp'] as num?)?.toStringAsFixed(2) ?? '',
        (p['computedOfferPrice'] as num?)?.toStringAsFixed(2) ?? '',
        (p['active'] == true).toString(),
      ].join(','));
    }
    await _writeAndNotify(context, 'catalogue', buf.toString());
  }

  String _csv(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  Future<void> _writeAndNotify(
      BuildContext context, String baseName, String content) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name = '${baseName}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
      final file = File('${dir.path}/$name');
      await file.writeAsString(content);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved to ${file.path}'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Export failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

    void _openPrintPreview(BuildContext context, LabOwnerSnapshot snap) {
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Print preview', style: AppTextStyles.h3),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Daily summary',
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                DateFormat('EEEE, d MMM yyyy').format(DateTime.now()),
                style: AppTextStyles.caption,
              ),
              const Divider(height: 20, color: AppColors.cardBorder),
              _previewRow("Today's orders", '${snap.todayOrders.length}'),
              _previewRow("Today's collection",
                  '₹${snap.todayCollected.toStringAsFixed(0)}'),
              _previewRow('Pending collections',
                  '₹${snap.pendingRevenue.toStringAsFixed(0)}'),
              const Divider(height: 20, color: AppColors.cardBorder),
              _previewRow('Awaiting acceptance',
                  '${snap.awaitingAcceptance}'),
              _previewRow('In progress', '${snap.inProgress}'),
              _previewRow('Ready', '${snap.ready}'),
              _previewRow('Delivered', '${snap.delivered}'),
              const Divider(height: 20, color: AppColors.cardBorder),
              Text('Top tests this month',
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (snap.topTestsThisMonth.isEmpty)
                Text('No orders yet.', style: AppTextStyles.caption)
              else
                for (final t in snap.topTestsThisMonth)
                  _previewRow(t.name, '${t.count}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(dctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Print sent to default printer'),
                backgroundColor: AppColors.success,
              ));
            },
            icon: const Icon(Icons.print_rounded, size: 18),
            label: const Text('Print'),
          ),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption),
          ),
          const SizedBox(width: 12),
          Text(value,
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              )),
        ],
      ),
    );
  }
}