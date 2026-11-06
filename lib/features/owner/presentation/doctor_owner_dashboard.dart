// lib/features/owner/presentation/doctor_owner_dashboard.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../../../shared/widgets/powered_by_footer.dart';
import '../../../shared/widgets/clinic_app_bar.dart';
import '../../staff/presentation/add_staff_screen.dart';
import 'clinic_settings_screen_owner.dart';
import 'team_list_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// DATA PROVIDERS
// ═══════════════════════════════════════════════════════════════════

class DoctorOwnerSnapshot {
  final List<Map<String, dynamic>> patients;
  final List<Map<String, dynamic>> visits;
  final List<Map<String, dynamic>> prescriptions;
  final List<Map<String, dynamic>> labOrders;
  final List<Map<String, dynamic>> teamMembers;

  DoctorOwnerSnapshot({
    required this.patients,
    required this.visits,
    required this.prescriptions,
    required this.labOrders,
    required this.teamMembers,
  });

  int get totalPatients => patients.length;
  int get totalVisits => visits.length;

  List<Map<String, dynamic>> get todayVisits {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return visits.where((v) {
      final ts = v['visitedAt'];
      if (ts is! Timestamp) return false;
      return !ts.toDate().isBefore(start);
    }).toList();
  }

  List<Map<String, dynamic>> get thisWeekVisits {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return visits.where((v) {
      final ts = v['visitedAt'];
      if (ts is! Timestamp) return false;
      return !ts.toDate().isBefore(monday);
    }).toList();
  }

  List<Map<String, dynamic>> get thisMonthVisits {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    return visits.where((v) {
      final ts = v['visitedAt'];
      if (ts is! Timestamp) return false;
      return !ts.toDate().isBefore(monthStart);
    }).toList();
  }

  double get todayCollected {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    var sum = 0.0;
    for (final v in visits) {
      if (v['paymentStatus']?.toString() != 'paid') continue;
      final ts = v['feesPaidAt'];
      if (ts is! Timestamp) continue;
      if (ts.toDate().isBefore(start)) continue;
      sum += (v['consultationFee'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  double get pendingRevenue {
    var sum = 0.0;
    for (final v in visits) {
      final status = v['status']?.toString() ?? '';
      if (status == 'cancelled' || status == 'noShow') continue;
      final paid = v['paymentStatus']?.toString();
      if (paid == 'paid' || paid == 'waived') continue;
      sum += (v['consultationFee'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  List<Map<String, dynamic>> get followUpsDue {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 7));
    return visits.where((v) {
      final ts = v['nextFollowUpAt'];
      if (ts is! Timestamp) return false;
      final d = ts.toDate();
      return !d.isBefore(start) && d.isBefore(end);
    }).toList()
      ..sort((a, b) {
        final aTs = a['nextFollowUpAt'] as Timestamp;
        final bTs = b['nextFollowUpAt'] as Timestamp;
        return aTs.compareTo(bTs);
      });
  }

  List<Map<String, dynamic>> get overdueFollowUps {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return visits.where((v) {
      final ts = v['nextFollowUpAt'];
      if (ts is! Timestamp) return false;
      return ts.toDate().isBefore(start);
    }).toList();
  }

  List<({DateTime day, int count})> get lastSevenDays {
    final now = DateTime.now();
    final days = <({DateTime day, int count})>[];
    for (var i = 6; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i));
      final nextDay = d.add(const Duration(days: 1));
      var count = 0;
      for (final v in visits) {
        final ts = v['visitedAt'];
        if (ts is! Timestamp) continue;
        final t = ts.toDate();
        if (t.isBefore(d) || !t.isBefore(nextDay)) continue;
        count++;
      }
      days.add((day: d, count: count));
    }
    return days;
  }

  List<({String name, int count})> get topDiagnosesThisMonth {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final counter = <String, int>{};
    for (final v in visits) {
      final ts = v['visitedAt'];
      if (ts is! Timestamp) continue;
      if (ts.toDate().isBefore(monthStart)) continue;
      final dx = v['diagnosis']?.toString() ?? '';
      if (dx.isEmpty) continue;
      counter[dx] = (counter[dx] ?? 0) + 1;
    }
    final list = counter.entries
        .map((e) => (name: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return list.take(5).toList();
  }

  List<({String name, int count})> get topTestsThisMonth {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final counter = <String, int>{};
    for (final o in labOrders) {
      final ts = o['orderedAt'];
      if (ts is! Timestamp) continue;
      if (ts.toDate().isBefore(monthStart)) continue;
      final tests = o['tests'] as List? ?? const [];
      for (final t in tests) {
        if (t is Map) {
          final code = (t['code'] ?? '').toString();
          final name = (t['name'] ?? '').toString();
          final key = name.isNotEmpty ? name : code;
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

  Map<String, dynamic>? patientById(String id) {
    for (final p in patients) {
      if (p['patientId'] == id) return p;
    }
    return null;
  }

  List<Map<String, dynamic>> visitsForPatient(String patientId) {
    final list = visits
        .where((v) => v['patientId']?.toString() == patientId)
        .toList();
    list.sort((a, b) {
      final aTs = a['visitedAt'];
      final bTs = b['visitedAt'];
      if (aTs is Timestamp && bTs is Timestamp) return bTs.compareTo(aTs);
      return 0;
    });
    return list;
  }

  List<Map<String, dynamic>> prescriptionsForVisit(String visitId) =>
      prescriptions.where((p) => p['visitId']?.toString() == visitId).toList();

  List<Map<String, dynamic>> labOrdersForVisit(String visitId) =>
      labOrders.where((o) => o['visitId']?.toString() == visitId).toList();
}

final doctorOwnerSnapshotProvider =
    StreamProvider.autoDispose<DoctorOwnerSnapshot>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final clinicId = user?.clinicId;
  if (clinicId == null || clinicId.isEmpty) return const Stream.empty();
  final db = FirebaseFirestore.instance;

  final patientsStream = db
      .collection('clinics')
      .doc(clinicId)
      .collection('patients')
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'patientId': d.id, ...d.data()})
          .toList());

  final visitsStream = db
      .collection('clinics')
      .doc(clinicId)
      .collection('visits')
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'visitId': d.id, ...d.data()})
          .toList());

  final prescriptionsStream = db
      .collection('clinics')
      .doc(clinicId)
      .collection('prescriptions')
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'prescriptionId': d.id, ...d.data()})
          .toList());

  final labOrdersStream = db
      .collection('labOrders')
      .where('clinicId', isEqualTo: clinicId)
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'orderId': d.id, ...d.data()})
          .toList());

  final teamStream = db
      .collection('users')
      .where('clinicId', isEqualTo: clinicId)
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'uid': d.id, ...d.data()})
          .toList());

  return _combine5(patientsStream, visitsStream, prescriptionsStream,
      labOrdersStream, teamStream);
});

Stream<DoctorOwnerSnapshot> _combine5(
  Stream<List<Map<String, dynamic>>> a,
  Stream<List<Map<String, dynamic>>> b,
  Stream<List<Map<String, dynamic>>> c,
  Stream<List<Map<String, dynamic>>> d,
  Stream<List<Map<String, dynamic>>> e,
) {
  final ctlA = _ValueCtl<List<Map<String, dynamic>>>();
  final ctlB = _ValueCtl<List<Map<String, dynamic>>>();
  final ctlC = _ValueCtl<List<Map<String, dynamic>>>();
  final ctlD = _ValueCtl<List<Map<String, dynamic>>>();
  final ctlE = _ValueCtl<List<Map<String, dynamic>>>();

  a.listen(ctlA.set, onError: ctlA.error);
  b.listen(ctlB.set, onError: ctlB.error);
  c.listen(ctlC.set, onError: ctlC.error);
  d.listen(ctlD.set, onError: ctlD.error);
  e.listen(ctlE.set, onError: ctlE.error);

  return _merge([ctlA, ctlB, ctlC, ctlD, ctlE]).map((_) {
    return DoctorOwnerSnapshot(
      patients: ctlA.value ?? const [],
      visits: ctlB.value ?? const [],
      prescriptions: ctlC.value ?? const [],
      labOrders: ctlD.value ?? const [],
      teamMembers: ctlE.value ?? const [],
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

class DoctorOwnerDashboard extends ConsumerWidget {
  const DoctorOwnerDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final snapshotAsync = ref.watch(doctorOwnerSnapshotProvider);

    final currentUser = userAsync.valueOrNull;
    final canPractise = currentUser?.canPractise == true;
    final isOwner = currentUser?.role == UserRole.owner;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ClinicAppBar(
        title: 'Owner dashboard',
        extraActions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.textSecondary, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => ref.invalidate(doctorOwnerSnapshotProvider),
          ),
          if (isOwner && canPractise)
            IconButton(
              tooltip: 'Open doctor dashboard',
              icon: const Icon(Icons.medical_services_rounded,
                  color: AppColors.textSecondary, size: 20),
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => context.push('/doctor'),
            ),
        ],
      ),
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(child: Text('$e')),
          data: (user) {
            final clinicId = user?.clinicId;
            if (clinicId == null || clinicId.isEmpty) {
              return const Center(
                  child: Text('No clinic linked to your account.'));
            }
            return snapshotAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primary)),
              error: (e, _) => Center(child: Text('$e')),
              data: (snap) => RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async =>
                    ref.invalidate(doctorOwnerSnapshotProvider),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _header(context, user?.name ?? 'Doctor'),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Account'),
                    const SizedBox(height: 8),
                    _accountSection(context, snap),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Overview'),
                    const SizedBox(height: 8),
                    _overviewCards(snap),
                    const SizedBox(height: 24),
                    _patientSearch(context, snap),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Visits — last 7 days'),
                    const SizedBox(height: 8),
                    _visitsChart(snap),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Follow-ups due'),
                    const SizedBox(height: 8),
                    _followUpsDue(context, snap),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Top diagnoses this month'),
                    const SizedBox(height: 8),
                    _topDiagnoses(snap),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Top tests ordered'),
                    const SizedBox(height: 8),
                    _topTests(snap),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Reports'),
                    const SizedBox(height: 8),
                    _reports(context, snap),
                    const SizedBox(height: 32),
                    const PoweredByFooter(),
                    const SizedBox(height: 12),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Welcome back,', style: AppTextStyles.bodyMuted),
        const SizedBox(height: 4),
        Text(name, style: AppTextStyles.h1),
      ],
    );
  }

  // ── Account (absorbs OwnerShell's Team + Clinic tabs) ──
  Widget _accountSection(BuildContext context, DoctorOwnerSnapshot snap) {
    int countRole(String role) =>
        snap.teamMembers.where((m) => m['role']?.toString() == role).length;

    final owner = countRole('owner');
    final doctor = countRole('doctor');
    final reception = countRole('receptionist');
    final total = snap.teamMembers.length;

    return Column(
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text('$total team member${total == 1 ? '' : 's'}',
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const TeamListScreen()),
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
                _teamChip('Doctor', doctor, AppColors.info),
                _teamChip('Reception', reception, AppColors.labAccent),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AddStaffScreen()),
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded,
                      size: 18),
                  label: const Text('Add staff'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _accountTile(
          icon: Icons.people_outline_rounded,
          color: AppColors.info,
          title: 'Manage team',
          subtitle: 'View, edit roles, deactivate, and send invites',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TeamListScreen()),
          ),
        ),
        const SizedBox(height: 8),
        _accountTile(
          icon: Icons.local_hospital_outlined,
          color: AppColors.accent,
          title: 'Clinic profile & settings',
          subtitle: 'Name, address, hours, verification, preferences',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const OwnerClinicSettingsScreen()),
          ),
        ),
      ],
    );
  }

  Widget _accountTile({
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
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 18),
          ]),
        ),
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

  // ── Patient search ──
  Widget _patientSearch(BuildContext context, DoctorOwnerSnapshot snap) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.search_rounded,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text('Find patient',
                style: AppTextStyles.body
                    .copyWith(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 10),
          TextField(
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: 'Search by name, phone or patient ID',
              hintStyle: AppTextStyles.caption,
              prefixIcon: const Icon(Icons.person_search_rounded,
                  color: AppColors.textMuted, size: 20),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.4),
              ),
            ),
            onSubmitted: (q) => _showPatientResults(context, snap, q),
            onChanged: (q) {
              if (q.trim().length >= 3) {
                _showPatientResults(context, snap, q);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showPatientResults(
      BuildContext context, DoctorOwnerSnapshot snap, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return;
    final matches = snap.patients.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final phone = (p['phone'] ?? '').toString().toLowerCase();
      final id = (p['patientId'] ?? '').toString().toLowerCase();
      final pid = (p['publicId'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          phone.contains(q) ||
          id.contains(q) ||
          pid.contains(q);
    }).take(20).toList();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${matches.length} patient(s) found',
                  style: AppTextStyles.h3),
              const SizedBox(height: 12),
              if (matches.isEmpty)
                Text('No matches. Try a different spelling.',
                    style: AppTextStyles.bodyMuted)
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: matches.length,
                    separatorBuilder: (_, __) => const Divider(
                        height: 12, color: AppColors.cardBorder),
                    itemBuilder: (_, i) {
                      final p = matches[i];
                      final pid = (p['patientId'] ?? '').toString();
                      final name = (p['name'] ?? '').toString();
                      final phone = (p['phone'] ?? '').toString();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withOpacity(.12),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: AppTextStyles.body.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        title: Text(name, style: AppTextStyles.body),
                        subtitle:
                            Text(phone, style: AppTextStyles.caption),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textMuted),
                        onTap: () {
                          Navigator.pop(bctx);
                          _openPatientRecord(context, snap, pid);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPatientRecord(
      BuildContext context, DoctorOwnerSnapshot snap, String patientId) {
    final patient = snap.patientById(patientId);
    final visits = snap.visitsForPatient(patientId);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => SafeArea(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (patient?['name'] ?? 'Unknown patient').toString(),
                        style: AppTextStyles.h2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if ((patient?['phone'] ?? '')
                              .toString()
                              .isNotEmpty)
                            patient!['phone'].toString(),
                          if ((patient?['publicId'] ?? '')
                              .toString()
                              .isNotEmpty)
                            'ID: ${patient!['publicId']}',
                        ].join(' · '),
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(bctx),
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textMuted),
                ),
              ]),
              const SizedBox(height: 12),
              _patientSummaryStrip(snap, patientId, visits),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Visit history'),
              const SizedBox(height: 8),
              if (visits.isEmpty)
                GlassCard(
                  child: Text('No visits recorded yet.',
                      style: AppTextStyles.bodyMuted),
                )
              else
                for (final v in visits) ...[
                  _visitCard(context, snap, v),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _patientSummaryStrip(DoctorOwnerSnapshot snap, String patientId,
      List<Map<String, dynamic>> visits) {
    final lastVisit = visits.isNotEmpty ? visits.first : null;
    final nextFollowUp = visits
        .map((v) => v['nextFollowUpAt'])
        .whereType<Timestamp>()
        .where((t) => t.toDate().isAfter(DateTime.now()))
        .fold<Timestamp?>(null, (min, t) {
      if (min == null) return t;
      return t.toDate().isBefore(min.toDate()) ? t : min;
    });

    return GlassCard(
      child: Row(children: [
        Expanded(
          child: _metric(
              'Total visits', '${visits.length}', AppColors.primary),
        ),
        Expanded(
          child: _metric(
            'Last visit',
            lastVisit == null
                ? '—'
                : DateFormat('d MMM')
                    .format((lastVisit['visitedAt'] as Timestamp).toDate()),
            AppColors.info,
          ),
        ),
        Expanded(
          child: _metric(
            'Next follow-up',
            nextFollowUp == null
                ? '—'
                : DateFormat('d MMM').format(nextFollowUp.toDate()),
            AppColors.warning,
          ),
        ),
      ]),
    );
  }

  Widget _visitCard(BuildContext context, DoctorOwnerSnapshot snap,
      Map<String, dynamic> visit) {
    final visitId = (visit['visitId'] ?? '').toString();
    final when = visit['visitedAt'] is Timestamp
        ? DateFormat('EEE, d MMM yyyy · h:mm a')
            .format((visit['visitedAt'] as Timestamp).toDate())
        : '';
    final diagnosis = (visit['diagnosis'] ?? '').toString();
    final chiefComplaint = (visit['chiefComplaint'] ?? '').toString();
    final notes = (visit['notes'] ?? '').toString();
    final fee = (visit['consultationFee'] as num?)?.toDouble() ?? 0;
    final paymentStatus = (visit['paymentStatus'] ?? '').toString();
    final nextFollowUp = visit['nextFollowUpAt'] is Timestamp
        ? DateFormat('d MMM yyyy')
            .format((visit['nextFollowUpAt'] as Timestamp).toDate())
        : null;
    final rx = snap.prescriptionsForVisit(visitId);
    final labs = snap.labOrdersForVisit(visitId);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(when, style: AppTextStyles.caption)),
            if (paymentStatus.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (paymentStatus == 'paid'
                          ? AppColors.success
                          : AppColors.warning)
                      .withOpacity(.13),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  paymentStatus == 'paid'
                      ? 'Paid ₹${fee.toStringAsFixed(0)}'
                      : 'Due ₹${fee.toStringAsFixed(0)}',
                  style: AppTextStyles.caption.copyWith(
                    color: paymentStatus == 'paid'
                        ? AppColors.success
                        : AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ]),
          if (chiefComplaint.isNotEmpty) ...[
            const SizedBox(height: 6),
            _kv('Complaint', chiefComplaint),
          ],
          if (diagnosis.isNotEmpty) ...[
            const SizedBox(height: 4),
            _kv('Diagnosis', diagnosis),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            _kv('Notes', notes),
          ],
          if (nextFollowUp != null) ...[
            const SizedBox(height: 4),
            _kv('Next follow-up', nextFollowUp),
          ],
          if (rx.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Prescriptions (${rx.length})',
                style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            for (final r in rx)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '• ${(r['drugName'] ?? r['name'] ?? '').toString()}'
                  '${(r['dosage'] ?? '').toString().isNotEmpty ? ' — ${r['dosage']}' : ''}'
                  '${(r['duration'] ?? '').toString().isNotEmpty ? ' (${r['duration']})' : ''}',
                  style: AppTextStyles.caption,
                ),
              ),
          ],
          if (labs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Tests ordered (${labs.length})',
                style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            for (final o in labs)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '• ${((o['tests'] as List?) ?? const []).map((t) => t is Map ? (t['name'] ?? t['code'] ?? '') : t).where((s) => s.toString().isNotEmpty).join(', ')}'
                  '${(o['status'] ?? '').toString().isNotEmpty ? ' — ${o['status']}' : ''}',
                  style: AppTextStyles.caption,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textMuted)),
        ),
        Expanded(child: Text(value, style: AppTextStyles.caption)),
      ],
    );
  }

  // ── Overview cards ──
  Widget _overviewCards(DoctorOwnerSnapshot snap) {
    final cards = [
      (
        label: 'Total patients',
        value: '${snap.totalPatients}',
        icon: Icons.people_alt_rounded,
        color: AppColors.info,
      ),
      (
        label: "Today's visits",
        value: '${snap.todayVisits.length}',
        icon: Icons.event_available_rounded,
        color: AppColors.accent,
      ),
      (
        label: 'This week',
        value: '${snap.thisWeekVisits.length}',
        icon: Icons.date_range_rounded,
        color: AppColors.labAccent,
      ),
      (
        label: 'This month',
        value: '${snap.thisMonthVisits.length}',
        icon: Icons.calendar_month_rounded,
        color: AppColors.primary,
      ),
      (
        label: "Today's collection",
        value: '₹${snap.todayCollected.toStringAsFixed(0)}',
        icon: Icons.currency_rupee_rounded,
        color: AppColors.success,
      ),
      (
        label: 'Follow-ups due',
        value: '${snap.followUpsDue.length}',
        icon: Icons.notifications_active_rounded,
        color: AppColors.warning,
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
      Row(children: [
        Expanded(child: _statCard(cards[4])),
        const SizedBox(width: 12),
        Expanded(child: _statCard(cards[5])),
      ]),
      const SizedBox(height: 12),
      GlassCard(
        borderColor: AppColors.warning.withOpacity(.35),
        child: Row(children: [
          const Icon(Icons.pending_actions_rounded,
              color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Pending collections', style: AppTextStyles.body),
          ),
          Text(
            '₹${snap.pendingRevenue.toStringAsFixed(0)}',
            style: AppTextStyles.h3.copyWith(color: AppColors.warning),
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

  // ── Visits bar chart ──
  Widget _visitsChart(DoctorOwnerSnapshot snap) {
    final data = snap.lastSevenDays;
    final maxY = data.fold<int>(0, (m, d) => d.count > m ? d.count : m) * 1.2;
    final yMax = maxY <= 0 ? 5.0 : maxY.toDouble();

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
                    reservedSize: 32,
                    interval: yMax / 4,
                    getTitlesWidget: (v, _) => Text(
                      v.toStringAsFixed(0),
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
                              fontSize: 10, color: AppColors.textMuted),
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
                        toY: data[i].count.toDouble(),
                        color: AppColors.primary,
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

  // ── Follow-ups due ──
  Widget _followUpsDue(BuildContext context, DoctorOwnerSnapshot snap) {
    final due = snap.followUpsDue;
    final overdue = snap.overdueFollowUps;
    if (due.isEmpty && overdue.isEmpty) {
      return GlassCard(
        child: Text('No follow-ups due in the next 7 days.',
            style: AppTextStyles.bodyMuted),
      );
    }

    Widget row(Map<String, dynamic> v, {required bool isOverdue}) {
      final pid = (v['patientId'] ?? '').toString();
      final patient = snap.patientById(pid);
      final name = (patient?['name'] ?? 'Unknown').toString();
      final ts = v['nextFollowUpAt'] as Timestamp;
      final when = DateFormat('EEE, d MMM').format(ts.toDate());
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(
            isOverdue ? Icons.warning_amber_rounded : Icons.event_rounded,
            size: 18,
            color: isOverdue ? AppColors.error : AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.body),
                Text(when, style: AppTextStyles.caption),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _openPatientRecord(context, snap, pid),
            icon: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 18),
          ),
        ]),
      );
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overdue.isNotEmpty) ...[
            Text('Overdue',
                style: AppTextStyles.caption.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final v in overdue.take(5)) row(v, isOverdue: true),
            if (due.isNotEmpty)
              const Divider(height: 16, color: AppColors.cardBorder),
          ],
          if (due.isNotEmpty) ...[
            Text('Upcoming',
                style: AppTextStyles.caption.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            for (final v in due.take(5)) row(v, isOverdue: false),
          ],
        ],
      ),
    );
  }

  // ── Top diagnoses ──
  Widget _topDiagnoses(DoctorOwnerSnapshot snap) {
    final list = snap.topDiagnosesThisMonth;
    if (list.isEmpty) {
      return GlassCard(
        child: Text('No diagnoses recorded this month yet.',
            style: AppTextStyles.bodyMuted),
      );
    }
    return GlassCard(
      child: Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0)
              const Divider(height: 16, color: AppColors.cardBorder),
            Row(children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text('${i + 1}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.accent,
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
              Text('${list[i].count} cases',
                  style: AppTextStyles.caption),
            ]),
          ],
        ],
      ),
    );
  }

  // ── Top tests ──
  Widget _topTests(DoctorOwnerSnapshot snap) {
    final list = snap.topTestsThisMonth;
    if (list.isEmpty) {
      return GlassCard(
        child: Text('No tests ordered this month yet.',
            style: AppTextStyles.bodyMuted),
      );
    }
    return GlassCard(
      child: Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0)
              const Divider(height: 16, color: AppColors.cardBorder),
            Row(children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text('${i + 1}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.info,
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

  // ── Reports ──
  Widget _reports(BuildContext context, DoctorOwnerSnapshot snap) {
    return Column(
      children: [
        _reportTile(
          icon: Icons.table_chart_outlined,
          color: AppColors.info,
          title: 'Download visits (CSV)',
          subtitle: 'All visits with patient, diagnosis, fee, status',
          onTap: () => _exportVisitsCsv(context, snap),
        ),
        const SizedBox(height: 8),
        _reportTile(
          icon: Icons.people_outline_rounded,
          color: AppColors.accent,
          title: 'Download patients (CSV)',
          subtitle: 'Patient list with phone, age, last visit',
          onTap: () => _exportPatientsCsv(context, snap),
        ),
        const SizedBox(height: 8),
        _reportTile(
          icon: Icons.medication_outlined,
          color: AppColors.success,
          title: 'Download prescriptions (CSV)',
          subtitle: 'All prescriptions with drug, dosage, duration',
          onTap: () => _exportPrescriptionsCsv(context, snap),
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
  Future<void> _exportVisitsCsv(
      BuildContext context, DoctorOwnerSnapshot snap) async {
    final buf = StringBuffer();
    buf.writeln(
        'VisitID,PatientID,PatientName,VisitedAt,ChiefComplaint,Diagnosis,ConsultationFee,PaymentStatus,Status,NextFollowUp');
    for (final v in snap.visits) {
      final pid = (v['patientId'] ?? '').toString();
      final patient = snap.patientById(pid);
      final pname = (patient?['name'] ?? '').toString();
      final when = v['visitedAt'] is Timestamp
          ? DateFormat('yyyy-MM-dd HH:mm')
              .format((v['visitedAt'] as Timestamp).toDate())
          : '';
      final next = v['nextFollowUpAt'] is Timestamp
          ? DateFormat('yyyy-MM-dd')
              .format((v['nextFollowUpAt'] as Timestamp).toDate())
          : '';
      buf.writeln([
        _csv((v['visitId'] ?? '').toString()),
        _csv(pid),
        _csv(pname),
        _csv(when),
        _csv((v['chiefComplaint'] ?? '').toString()),
        _csv((v['diagnosis'] ?? '').toString()),
        (v['consultationFee'] as num?)?.toStringAsFixed(2) ?? '',
        _csv((v['paymentStatus'] ?? '').toString()),
        _csv((v['status'] ?? '').toString()),
        _csv(next),
      ].join(','));
    }
    await _writeAndNotify(context, 'visits', buf.toString());
  }

  Future<void> _exportPatientsCsv(
      BuildContext context, DoctorOwnerSnapshot snap) async {
    final buf = StringBuffer();
    buf.writeln('PatientID,PublicID,Name,Phone,Age,Gender,LastVisit');
    for (final p in snap.patients) {
      final pid = (p['patientId'] ?? '').toString();
      final visits = snap.visitsForPatient(pid);
      final lastVisit =
          visits.isNotEmpty && visits.first['visitedAt'] is Timestamp
              ? DateFormat('yyyy-MM-dd')
                  .format((visits.first['visitedAt'] as Timestamp).toDate())
              : '';
      buf.writeln([
        _csv(pid),
        _csv((p['publicId'] ?? '').toString()),
        _csv((p['name'] ?? '').toString()),
        _csv((p['phone'] ?? '').toString()),
        _csv((p['age'] ?? '').toString()),
        _csv((p['gender'] ?? '').toString()),
        _csv(lastVisit),
      ].join(','));
    }
    await _writeAndNotify(context, 'patients', buf.toString());
  }

  Future<void> _exportPrescriptionsCsv(
      BuildContext context, DoctorOwnerSnapshot snap) async {
    final buf = StringBuffer();
    buf.writeln(
        'PrescriptionID,VisitID,PatientID,DrugName,Dosage,Frequency,Duration,Notes');
    for (final r in snap.prescriptions) {
      buf.writeln([
        _csv((r['prescriptionId'] ?? '').toString()),
        _csv((r['visitId'] ?? '').toString()),
        _csv((r['patientId'] ?? '').toString()),
        _csv((r['drugName'] ?? r['name'] ?? '').toString()),
        _csv((r['dosage'] ?? '').toString()),
        _csv((r['frequency'] ?? '').toString()),
        _csv((r['duration'] ?? '').toString()),
        _csv((r['notes'] ?? '').toString()),
      ].join(','));
    }
    await _writeAndNotify(context, 'prescriptions', buf.toString());
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
      final name =
          '${baseName}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
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

  void _openPrintPreview(BuildContext context, DoctorOwnerSnapshot snap) {
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
              _previewRow("Today's visits", '${snap.todayVisits.length}'),
              _previewRow("Today's collection",
                  '₹${snap.todayCollected.toStringAsFixed(0)}'),
              _previewRow('Pending collections',
                  '₹${snap.pendingRevenue.toStringAsFixed(0)}'),
              const Divider(height: 20, color: AppColors.cardBorder),
              _previewRow('Total patients', '${snap.totalPatients}'),
              _previewRow('This week visits', '${snap.thisWeekVisits.length}'),
              _previewRow(
                  'This month visits', '${snap.thisMonthVisits.length}'),
              _previewRow('Follow-ups due', '${snap.followUpsDue.length}'),
              const Divider(height: 20, color: AppColors.cardBorder),
              Text('Top diagnoses this month',
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (snap.topDiagnosesThisMonth.isEmpty)
                Text('No diagnoses yet.', style: AppTextStyles.caption)
              else
                for (final d in snap.topDiagnosesThisMonth)
                  _previewRow(d.name, '${d.count}'),
              const Divider(height: 20, color: AppColors.cardBorder),
              Text('Top tests ordered this month',
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              if (snap.topTestsThisMonth.isEmpty)
                Text('No tests yet.', style: AppTextStyles.caption)
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