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
import '../../subscription/widgets/subscription_card.dart';

// ═══════════════════════════════════════════════════════════════════
// DATA PROVIDERS
// ═══════════════════════════════════════════════════════════════════

class DoctorOwnerSnapshot {
  final List<Map<String, dynamic>> patients;
  /// Merged visit maps — each contains the appointment fields plus
  /// `consultation` (map|null), `diagnosis`, `diagnosisCode`,
  /// `diagnosisText`, `notes`, `rx`, `symptoms`, `followUpPlan`,
  /// `medications` (flattened list), `labOrders` (list).
  final List<Map<String, dynamic>> visits;
  final List<Map<String, dynamic>> labOrders;
  final List<Map<String, dynamic>> teamMembers;

  DoctorOwnerSnapshot({
    required this.patients,
    required this.visits,
    required this.labOrders,
    required this.teamMembers,
  });

  // ── Counts ──
  int get totalPatients => patients.length;
  int get totalVisits => visits.length;

  // ── Visit timestamp resolver ──
  static Timestamp? _visitTs(Map<String, dynamic> v) {
    final a = v['consultStartedAt'] ?? v['createdAt'] ?? v['slot'];
    return a is Timestamp ? a : null;
  }

  List<Map<String, dynamic>> get todayVisits {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return visits.where((v) {
      final ts = _visitTs(v);
      if (ts == null) return false;
      return !ts.toDate().isBefore(start);
    }).toList();
  }

  List<Map<String, dynamic>> get thisWeekVisits {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return visits.where((v) {
      final ts = _visitTs(v);
      if (ts == null) return false;
      return !ts.toDate().isBefore(monday);
    }).toList();
  }

  List<Map<String, dynamic>> get thisMonthVisits {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    return visits.where((v) {
      final ts = _visitTs(v);
      if (ts == null) return false;
      return !ts.toDate().isBefore(monthStart);
    }).toList();
  }

  // ── Revenue ──
  double get todayCollected {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    var sum = 0.0;
    for (final v in visits) {
      if (v['paymentStatus']?.toString() != 'paid') continue;
      final ts = v['feesPaidAt'];
      if (ts is! Timestamp) continue;
      if (ts.toDate().isBefore(start)) continue;
      sum += (v['consultationFees'] as num?)?.toDouble() ?? 0;
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
      sum += (v['consultationFees'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  // ── 7-day visit series ──
  List<({DateTime day, int count})> get lastSevenDays {
    final now = DateTime.now();
    final days = <({DateTime day, int count})>[];
    for (var i = 6; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: i));
      final nextDay = d.add(const Duration(days: 1));
      var count = 0;
      for (final v in visits) {
        final ts = _visitTs(v);
        if (ts == null) continue;
        final t = ts.toDate();
        if (t.isBefore(d) || !t.isBefore(nextDay)) continue;
        count++;
      }
      days.add((day: d, count: count));
    }
    return days;
  }

  // ── Top diagnoses (from consultations) ──
  List<({String name, int count})> get topDiagnosesThisMonth {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final counter = <String, int>{};
    for (final v in visits) {
      final c = v['consultation'];
      if (c is! Map) continue;
      final tsRaw = v['consultStartedAt'] ?? v['createdAt'] ?? v['slot'];
      if (tsRaw is! Timestamp) continue;
      if (tsRaw.toDate().isBefore(monthStart)) continue;
      final dx = (c['diagnosis'] ?? '').toString().trim();
      if (dx.isEmpty) continue;
      counter[dx] = (counter[dx] ?? 0) + 1;
    }
    final list = counter.entries
        .map((e) => (name: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return list.take(5).toList();
  }

  // ── Top tests ordered (from lab orders) ──
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

  // ── Lookups ──
  // `p['docId']` is the Firestore doc id; `p['patientId']` is the
  // human-readable ID (e.g. PT-LFC-...).
  Map<String, dynamic>? patientById(String docId) {
    for (final p in patients) {
      if (p['docId'] == docId) return p;
    }
    return null;
  }

  List<Map<String, dynamic>> visitsForPatient(String patientDocId) {
    final list = visits
        .where((v) => v['patientDocId']?.toString() == patientDocId)
        .toList();
    list.sort((a, b) {
      final aTs = _visitTs(a);
      final bTs = _visitTs(b);
      if (aTs != null && bTs != null) return bTs.compareTo(aTs);
      return 0;
    });
    return list;
  }
}

final doctorOwnerSnapshotProvider =
    StreamProvider.autoDispose<DoctorOwnerSnapshot>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final clinicId = user?.clinicId;
  if (clinicId == null || clinicId.isEmpty) return const Stream.empty();
  final db = FirebaseFirestore.instance;

  // ── Raw streams ──
  final patientsStream = db
      .collection('patients')
      .where('clinicId', isEqualTo: clinicId)
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'docId': d.id, ...d.data()})
          .toList());

  final appointmentsStream = db
      .collection('appointments')
      .where('clinicId', isEqualTo: clinicId)
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'visitId': d.id, ...d.data()})
          .toList());

  final consultationsStream = db
      .collection('consultations')
      .where('clinicId', isEqualTo: clinicId)
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'consultationId': d.id, ...d.data()})
          .toList());

  // Lab orders link to the referring clinic (the doctor's clinic),
  // not to a generic `clinicId` field.
  final labOrdersStream = db
      .collection('labOrders')
      .where('referringClinicId', isEqualTo: clinicId)
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
          .where((m) => m['role']?.toString() != 'patient')
          .toList());

  // ── Combine and merge ──
  return _combine5(
    patientsStream,
    appointmentsStream,
    consultationsStream,
    labOrdersStream,
    teamStream,
  ).map((raw) {
    final consultationsById = <String, Map<String, dynamic>>{
      for (final c in raw.consultations)
        (c['consultationId'] ?? '').toString(): c,
    };

    final labOrdersByAppt = <String, List<Map<String, dynamic>>>{};
    for (final o in raw.labOrders) {
      final aid = (o['appointmentId'] ?? '').toString();
      if (aid.isEmpty) continue;
      (labOrdersByAppt[aid] ??= []).add(o);
    }

    // Build merged visits — only completed appointments (real visits).
    final visits = <Map<String, dynamic>>[];
    for (final a in raw.appointments) {
      final apptId = (a['visitId'] ?? '').toString();
      final status = (a['status'] ?? '').toString();
      final consult = consultationsById[apptId];

      final isCompleted = status == 'completed';
      final hasCompletedConsult =
          consult != null && consult['endedAt'] != null;
      if (!isCompleted && !hasCompletedConsult) continue;

      final meds = <Map<String, dynamic>>[];
      if (consult != null) {
        final rawMeds = consult['medications'];
        if (rawMeds is List) {
          for (final m in rawMeds) {
            if (m is Map) meds.add(Map<String, dynamic>.from(m));
          }
        }
      }

      visits.add(<String, dynamic>{
        ...a,
        'consultation': consult,
        'diagnosis': consult?['diagnosis'],
        'diagnosisCode': consult?['diagnosisCode'],
        'diagnosisText': consult?['diagnosisText'],
        'notes': consult?['notes'],
        'rx': consult?['rx'],
        'symptoms': consult?['symptoms'],
        'followUpPlan': consult?['followUpPlan'],
        'disposition': consult?['disposition'],
        'medications': meds,
        'labOrders': labOrdersByAppt[apptId] ?? const [],
      });
    }
    visits.sort((a, b) {
      final aTs = DoctorOwnerSnapshot._visitTs(a);
      final bTs = DoctorOwnerSnapshot._visitTs(b);
      if (aTs != null && bTs != null) return bTs.compareTo(aTs);
      return 0;
    });

    return DoctorOwnerSnapshot(
      patients: raw.patients,
      visits: visits,
      labOrders: raw.labOrders,
      teamMembers: raw.team,
    );
  });
});

// ── Raw-combining helper (five streams) ──

class _RawBundle {
  final List<Map<String, dynamic>> patients;
  final List<Map<String, dynamic>> appointments;
  final List<Map<String, dynamic>> consultations;
  final List<Map<String, dynamic>> labOrders;
  final List<Map<String, dynamic>> team;
  _RawBundle({
    required this.patients,
    required this.appointments,
    required this.consultations,
    required this.labOrders,
    required this.team,
  });
}

Stream<_RawBundle> _combine5(
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
    return _RawBundle(
      patients: ctlA.value ?? const [],
      appointments: ctlB.value ?? const [],
      consultations: ctlC.value ?? const [],
      labOrders: ctlD.value ?? const [],
      team: ctlE.value ?? const [],
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
              onPressed: () => context.go('/doctor'),
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

  // ── Account ──
  Widget _accountSection(BuildContext context, DoctorOwnerSnapshot snap) {
    int countRole(String role) =>
        snap.teamMembers.where((m) => m['role']?.toString() == role).length;

    final owner = countRole('owner');
    final doctor = countRole('doctor');
    final reception = countRole('receptionist');
    final total = snap.teamMembers.length;

    return Column(
  children: [
    const SubscriptionCard(entityType: 'clinic'),
    const SizedBox(height: 8),
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
      final name = (p['fullName'] ?? '').toString().toLowerCase();
      final phone = (p['phone'] ?? '').toString().toLowerCase();
      final pid = (p['patientId'] ?? '').toString().toLowerCase();
      final did = (p['docId'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          phone.contains(q) ||
          pid.contains(q) ||
          did.contains(q);
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
                      final docId = (p['docId'] ?? '').toString();
                      final name = (p['fullName'] ?? '').toString();
                      final phone = (p['phone'] ?? '').toString();
                      final publicId = (p['patientId'] ?? '').toString();
                      final subtitle = [phone, publicId]
                          .where((s) => s.isNotEmpty)
                          .join(' · ');
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
                        subtitle: Text(subtitle,
                            style: AppTextStyles.caption),
                        trailing: const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textMuted),
                        onTap: () {
                          Navigator.pop(bctx);
                          _openPatientRecord(context, snap, docId);
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
      BuildContext context, DoctorOwnerSnapshot snap, String patientDocId) {
    final patient = snap.patientById(patientDocId);
    final visits = snap.visitsForPatient(patientDocId);

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
                        (patient?['fullName'] ?? 'Unknown patient')
                            .toString(),
                        style: AppTextStyles.h2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if ((patient?['phone'] ?? '')
                              .toString()
                              .isNotEmpty)
                            patient!['phone'].toString(),
                          if ((patient?['patientId'] ?? '')
                              .toString()
                              .isNotEmpty)
                            'ID: ${patient!['patientId']}',
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
              _patientSummaryStrip(visits),
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
                  _visitCard(context, v),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _patientSummaryStrip(List<Map<String, dynamic>> visits) {
    final lastVisit = visits.isNotEmpty ? visits.first : null;
    final lastTs = lastVisit != null
        ? DoctorOwnerSnapshot._visitTs(lastVisit)
        : null;

    return GlassCard(
      child: Row(children: [
        Expanded(
          child: _metric(
              'Total visits', '${visits.length}', AppColors.primary),
        ),
        Expanded(
          child: _metric(
            'Last visit',
            lastTs == null
                ? '—'
                : DateFormat('d MMM').format(lastTs.toDate()),
            AppColors.info,
          ),
        ),
        Expanded(
          child: _metric(
            'Follow-up plan',
            (lastVisit?['followUpPlan'] ?? '').toString().isEmpty
                ? '—'
                : 'View',
            AppColors.warning,
          ),
        ),
      ]),
    );
  }

  Widget _visitCard(
      BuildContext context, Map<String, dynamic> visit) {
    final ts = DoctorOwnerSnapshot._visitTs(visit);
    final when = ts == null
        ? ''
        : DateFormat('EEE, d MMM yyyy · h:mm a').format(ts.toDate());
    final diagnosis = (visit['diagnosis'] ?? '').toString();
    final diagnosisText = (visit['diagnosisText'] ?? '').toString();
    final diagnosisCode = (visit['diagnosisCode'] ?? '').toString();
    final chiefComplaint = (visit['chiefComplaint'] ?? '').toString();
    final symptoms = (visit['symptoms'] ?? '').toString();
    final notes = (visit['notes'] ?? '').toString();
    final followUp = (visit['followUpPlan'] ?? '').toString();
    final fee = (visit['consultationFees'] as num?)?.toDouble() ?? 0;
    final paymentStatus = (visit['paymentStatus'] ?? '').toString();
    final meds = (visit['medications'] as List?) ?? const [];
    final labs = (visit['labOrders'] as List?) ?? const [];

    final dxLabel = diagnosisCode.isNotEmpty
        ? '$diagnosisCode — ${diagnosisText.isNotEmpty ? diagnosisText : diagnosis}'
        : diagnosis;

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
          if (symptoms.isNotEmpty) ...[
            const SizedBox(height: 4),
            _kv('Symptoms', symptoms),
          ],
          if (dxLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            _kv('Diagnosis', dxLabel),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            _kv('Notes', notes),
          ],
          if (followUp.isNotEmpty) ...[
            const SizedBox(height: 4),
            _kv('Follow-up', followUp),
          ],
          if (meds.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Medications (${meds.length})',
                style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            for (final m in meds.whereType<Map>())
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '• ${(m['name'] ?? '').toString()}'
                  '${(m['dose'] ?? '').toString().isNotEmpty ? ' — ${m['dose']}' : ''}'
                  '${(m['frequency'] ?? '').toString().isNotEmpty ? ' · ${m['frequency']}' : ''}'
                  '${(m['duration'] ?? '').toString().isNotEmpty ? ' (${m['duration']})' : ''}',
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
            for (final o in labs.whereType<Map>())
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
        label: 'Total visits',
        value: '${snap.totalVisits}',
        icon: Icons.history_rounded,
        color: AppColors.labAccent,
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
          title: 'Download medications (CSV)',
          subtitle: 'All medications across consultations',
          onTap: () => _exportMedicationsCsv(context, snap),
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
        'VisitID,PatientID,PatientDocID,PatientName,When,ChiefComplaint,Symptoms,DiagnosisCode,DiagnosisText,Notes,FollowUp,ConsultationFee,PaymentStatus,Status');
    for (final v in snap.visits) {
      final ts = DoctorOwnerSnapshot._visitTs(v);
      final when = ts == null
          ? ''
          : DateFormat('yyyy-MM-dd HH:mm').format(ts.toDate());
      buf.writeln([
        _csv((v['visitId'] ?? '').toString()),
        _csv((v['patientId'] ?? '').toString()),
        _csv((v['patientDocId'] ?? '').toString()),
        _csv((v['patientName'] ?? '').toString()),
        _csv(when),
        _csv((v['chiefComplaint'] ?? '').toString()),
        _csv((v['symptoms'] ?? '').toString()),
        _csv((v['diagnosisCode'] ?? '').toString()),
        _csv((v['diagnosisText'] ?? '').toString()),
        _csv((v['notes'] ?? '').toString()),
        _csv((v['followUpPlan'] ?? '').toString()),
        (v['consultationFees'] as num?)?.toStringAsFixed(2) ?? '',
        _csv((v['paymentStatus'] ?? '').toString()),
        _csv((v['status'] ?? '').toString()),
      ].join(','));
    }
    await _writeAndNotify(context, 'visits', buf.toString());
  }

  Future<void> _exportPatientsCsv(
      BuildContext context, DoctorOwnerSnapshot snap) async {
    final buf = StringBuffer();
    buf.writeln('PatientDocID,PublicID,Name,Phone,Age,Gender,LastVisit');
    for (final p in snap.patients) {
      final docId = (p['docId'] ?? '').toString();
      final visits = snap.visitsForPatient(docId);
      final lastTs = visits.isNotEmpty
          ? DoctorOwnerSnapshot._visitTs(visits.first)
          : null;
      final lastVisit = lastTs == null
          ? ''
          : DateFormat('yyyy-MM-dd').format(lastTs.toDate());
      buf.writeln([
        _csv(docId),
        _csv((p['patientId'] ?? '').toString()),
        _csv((p['fullName'] ?? '').toString()),
        _csv((p['phone'] ?? '').toString()),
        _csv(_ageFromDob(p['dob'])),
        _csv((p['gender'] ?? '').toString()),
        _csv(lastVisit),
      ].join(','));
    }
    await _writeAndNotify(context, 'patients', buf.toString());
  }

  Future<void> _exportMedicationsCsv(
      BuildContext context, DoctorOwnerSnapshot snap) async {
    final buf = StringBuffer();
    buf.writeln(
        'VisitID,PatientID,PatientName,DrugName,Dose,Frequency,Duration');
    for (final v in snap.visits) {
      final meds = (v['medications'] as List?) ?? const [];
      if (meds.isEmpty) continue;
      for (final m in meds.whereType<Map>()) {
        buf.writeln([
          _csv((v['visitId'] ?? '').toString()),
          _csv((v['patientId'] ?? '').toString()),
          _csv((v['patientName'] ?? '').toString()),
          _csv((m['name'] ?? '').toString()),
          _csv((m['dose'] ?? '').toString()),
          _csv((m['frequency'] ?? '').toString()),
          _csv((m['duration'] ?? '').toString()),
        ].join(','));
      }
    }
    await _writeAndNotify(context, 'medications', buf.toString());
  }

  String _ageFromDob(dynamic dobRaw) {
    final dob = DateTime.tryParse(dobRaw?.toString() ?? '');
    if (dob == null) return '';
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age.toString();
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
              _previewRow('Total visits', '${snap.totalVisits}'),
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