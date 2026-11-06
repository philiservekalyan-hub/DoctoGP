import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/models/appointment_request_model.dart';
import '../../../core/models/lab_order_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/appointment_request_service.dart';
import '../../../core/services/appointment_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../shared/widgets/role_badge.dart';

// -----------------------------------------------------------------
// Providers
// -----------------------------------------------------------------
final appointmentServiceProvider =
    Provider<AppointmentService>((ref) => AppointmentService());

final appointmentRequestServiceProvider =
    Provider<AppointmentRequestService>((ref) => AppointmentRequestService());

final patientRequestsProvider =
    StreamProvider.autoDispose<List<AppointmentRequestModel>>((ref) {
  final patient = ref.watch(currentPatientProvider).valueOrNull;
  if (patient == null || patient['isLabCustomer'] == true) {
    return const Stream.empty();
  }
  return ref
      .read(appointmentRequestServiceProvider)
      .watchPatientRequests(patient['patientDocId'] as String);
});

final doctorQueueProvider =
    StreamProvider.autoDispose.family<List<AppointmentModel>, String>(
        (ref, doctorDocId) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1));

  return FirebaseFirestore.instance
      .collection('appointments')
      .where('doctorDocId', isEqualTo: doctorDocId)
      .where('slot', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('slot', isLessThan: Timestamp.fromDate(end))
      .snapshots()
      .map((s) {
    final list = s.docs
        .map((d) => AppointmentModel.fromMap(d.id, d.data()))
        .where((a) =>
            a.status == AppointmentStatus.checkedIn ||
            a.status == AppointmentStatus.inConsult)
        .toList();
    list.sort((a, b) {
      if (a.status == AppointmentStatus.inConsult) return -1;
      if (b.status == AppointmentStatus.inConsult) return 1;
      final at = a.checkedInAt ?? a.slot;
      final bt = b.checkedInAt ?? b.slot;
      return at.compareTo(bt);
    });
    return list;
  });
});

final slotQueueProvider =
    StreamProvider.autoDispose.family<List<AppointmentModel>, String>(
        (ref, compositeKey) {
  final parts = compositeKey.split('|');
  if (parts.length != 2) return const Stream.empty();
  final doctorDocId = parts[0];
  final slotKey = parts[1];
  return ref
      .read(appointmentServiceProvider)
      .watchSlotQueue(doctorDocId: doctorDocId, slotKey: slotKey);
});

final patientLabOrdersProvider =
    StreamProvider.autoDispose<List<LabOrderModel>>((ref) {
  final userAsync = ref.watch(currentUserProvider);

  return userAsync.when(
    loading: () => const Stream.empty(),
    error: (_, __) => const Stream.empty(),
    data: (user) {
      if (user == null) return const Stream.empty();
      final db = FirebaseFirestore.instance;

      return db
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .asyncExpand((userSnap) {
        final data = userSnap.data() ?? {};
        final linkedPatientDocId =
            (data['linkedPatientDocId'] ?? '').toString();
        final linkedDisplayPatientId =
            (data['linkedDisplayPatientId'] ?? '').toString();
        final labClinicId = (data['clinicId'] ?? '').toString();

        if (linkedPatientDocId.isNotEmpty) {
          return db
              .collection('labOrders')
              .where('patientDocId', isEqualTo: linkedPatientDocId)
              .snapshots()
              .map(_toSortedOrders);
        }

        if (linkedDisplayPatientId.isNotEmpty && labClinicId.isNotEmpty) {
          return db
              .collection('labOrders')
              .where('labClinicId', isEqualTo: labClinicId)
              .where('patientId', isEqualTo: linkedDisplayPatientId)
              .where('released', isEqualTo: true)
              .snapshots()
              .map(_toSortedOrders);
        }

        return const Stream.empty();
      });
    },
  );
});

List<LabOrderModel> _toSortedOrders(
    QuerySnapshot<Map<String, dynamic>> snap) {
  final list = snap.docs
      .map((d) => LabOrderModel.fromMap(d.id, d.data()))
      .toList();
  list.sort((a, b) => (b.orderedAt ?? DateTime(2000))
      .compareTo(a.orderedAt ?? DateTime(2000)));
  return list;
}

// -----------------------------------------------------------------
// Resolves the current patient record.
//
// Priority:
//   1. Clinic patient (users.linkedPatientDocId) — preferred
//   2. Lab customer (users.linkedLabCustomerDocId) — fallback
//   3. patients by userId / docId / email — last resort
// -----------------------------------------------------------------
final currentPatientProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return null;
debugPrint('currentPatientProvider uid=${user.uid} email=${user.email}'); 
  final db = FirebaseFirestore.instance;
  final userDoc = await db.collection('users').doc(user.uid).get();
  final userData = userDoc.data() ?? {};

  // 1. Clinic patient record — preferred whenever present.
  final linkedPatientDocId = (userData['linkedPatientDocId'] ?? '')
    .toString()
    .replaceAll('"', '')
    .replaceAll(RegExp(r'\s'), '')   // strips trailing/NBSP/tab/CR/LF
    .trim();
if (linkedPatientDocId.isNotEmpty) {
  final p = await db.collection('patients').doc(linkedPatientDocId).get();
  debugPrint('currentPatientProvider: linkedPatientDocId=[$linkedPatientDocId] '
             'len=${linkedPatientDocId.length} exists=${p.exists}');
  if (p.exists) return _patientMap(p, user.uid);
  debugPrint('WARN: linkedPatientDocId set but patients doc missing — '
             'falling through to lab-customer path');
}

  // 2. Lab customer record — lab-only customer path.
  final linkedLabCustomerDocId =
      (userData['linkedLabCustomerDocId'] ?? '').toString();
  if (linkedLabCustomerDocId.isNotEmpty) {
    final c = await db
        .collection('labCustomers')
        .doc(linkedLabCustomerDocId)
        .get();
    if (c.exists) return _labCustomerMap(c, user.uid);

    final fallback = await db
        .collection('labCustomers')
        .where('linkedUserUid', isEqualTo: user.uid)
        .limit(1)
        .get();
    if (fallback.docs.isNotEmpty) {
      return _labCustomerMap(fallback.docs.first, user.uid);
    }
  }

  // 3. Fallback queries on `patients`.
  final byUid = await db
      .collection('patients')
      .where('userId', isEqualTo: user.uid)
      .limit(1)
      .get();
  if (byUid.docs.isNotEmpty) return _patientMap(byUid.docs.first, user.uid);

  final byDocId = await db.collection('patients').doc(user.uid).get();
  if (byDocId.exists) return _patientMap(byDocId, user.uid);

  final email = user.email?.trim().toLowerCase();
  if (email != null && email.isNotEmpty) {
    final byEmail = await db
        .collection('patients')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (byEmail.docs.isNotEmpty) {
      return _patientMap(byEmail.docs.first, user.uid);
    }
  }

  return null;
});

Map<String, dynamic> _patientMap(
    DocumentSnapshot<Map<String, dynamic>> doc, String authUid) {
  return <String, dynamic>{
    ...?doc.data(),
    'patientDocId': doc.id,
    'authUid': authUid,
    'patientId': doc.data()?['patientId'] ?? doc.id,
    'isLabCustomer': false,
  };
}

Map<String, dynamic> _labCustomerMap(
    DocumentSnapshot<Map<String, dynamic>> doc, String authUid) {
  final d = doc.data() ?? {};
  return <String, dynamic>{
    ...d,
    'patientDocId': doc.id,
    'authUid': authUid,
    'patientId': d['displayPatientId'] ?? doc.id,
    'fullName': d['fullName'] ?? '',
    'phone': d['phone'] ?? '',
    'email': d['email'] ?? '',
    'isLabCustomer': true,
  };
}

final patientAppointmentsProvider =
    StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  final patient = ref.watch(currentPatientProvider).valueOrNull;
  if (patient == null || patient['isLabCustomer'] == true) {
    return const Stream.empty();
  }
  return ref
      .read(appointmentServiceProvider)
      .watchPatientAppointments(patient['patientDocId'] as String);
});

final patientDocumentsProvider = StreamProvider.autoDispose<
    List<QueryDocumentSnapshot<Map<String, dynamic>>>>((ref) {
  final patient = ref.watch(currentPatientProvider).valueOrNull;
  if (patient == null || patient['isLabCustomer'] == true) {
    return const Stream.empty();
  }
  return FirebaseFirestore.instance
      .collection('patientDocuments')
      .where('patientDocId', isEqualTo: patient['patientDocId'])
      .snapshots()
      .map((s) => s.docs.toList()
        ..sort((a, b) => _asDate(b.data()['createdAt'])
            .compareTo(_asDate(a.data()['createdAt']))));
});

final patientInvoicesProvider = StreamProvider.autoDispose<
    List<QueryDocumentSnapshot<Map<String, dynamic>>>>((ref) {
  final patient = ref.watch(currentPatientProvider).valueOrNull;
  if (patient == null || patient['isLabCustomer'] == true) {
    return const Stream.empty();
  }
  return FirebaseFirestore.instance
      .collection('invoices')
      .where('patientDocId', isEqualTo: patient['patientDocId'])
      .snapshots()
      .map((s) => s.docs.toList()
        ..sort((a, b) => _asDate(b.data()['createdAt'])
            .compareTo(_asDate(a.data()['createdAt']))));
});

DateTime _asDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value) ?? DateTime(2000);
  return DateTime(2000);
}

String _dateLabel(DateTime date) => DateFormat('EEE, dd MMM yyyy').format(date);

String _money(dynamic amount) {
  final n = amount is num ? amount : num.tryParse('$amount') ?? 0;
  return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2)
      .format(n);
}

String _labStatusLabel(LabOrderStatus s) {
  switch (s) {
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
      return 'Unknown';
  }
}

Color _labStatusColor(LabOrderStatus s) {
  switch (s) {
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

// -----------------------------------------------------------------
// Dashboard
// -----------------------------------------------------------------
class PatientDashboard extends ConsumerStatefulWidget {
  const PatientDashboard({super.key});

  @override
  ConsumerState<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends ConsumerState<PatientDashboard> {
  String _selectedTabLabel = 'Overview';
  LabOrderStatus? _labFilter;

  static const _fullTabs = <({String label, IconData icon})>[
    (label: 'Overview', icon: Icons.dashboard_rounded),
    (label: 'Appointments', icon: Icons.event_available_rounded),
    (label: 'Queue', icon: Icons.people_alt_rounded),
    (label: 'Lab reports', icon: Icons.science_rounded),
    (label: 'Medical records', icon: Icons.medical_information_rounded),
    (label: 'Documents', icon: Icons.folder_copy_rounded),
    (label: 'Billing', icon: Icons.receipt_long_rounded),
    (label: 'Profile', icon: Icons.person_rounded),
  ];

  static const _labOnlyTabs = <({String label, IconData icon})>[
    (label: 'Overview', icon: Icons.dashboard_rounded),
    (label: 'Lab reports', icon: Icons.science_rounded),
    (label: 'Profile', icon: Icons.person_rounded),
  ];

  bool _isLabOnly(Map<String, dynamic> patient) =>
      patient['isLabCustomer'] == true;

  List<({String label, IconData icon})> _tabsFor(
          Map<String, dynamic> patient) =>
      _isLabOnly(patient) ? _labOnlyTabs : _fullTabs;

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final patientAsync = ref.watch(currentPatientProvider);
    final apptAsync = ref.watch(patientAppointmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => _errorState('Unable to load your account. $e'),
          data: (user) {
            if (user == null) return _errorState('Please sign in to continue.');
            return patientAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) =>
                  _errorState('Unable to load patient details. $e'),
              data: (patient) {
                if (patient == null) {
                  return _errorState(
                    'We could not find a patient profile or lab record linked '
                    'to this account. Ask your clinic or lab to add you.',
                  );
                }
                final name =
                    (patient['fullName'] ?? user.name ?? 'Patient').toString();
                final tabs = _tabsFor(patient);
                final currentLabel =
                    tabs.any((t) => t.label == _selectedTabLabel)
                        ? _selectedTabLabel
                        : 'Overview';

                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    ref.invalidate(currentPatientProvider);
                    ref.invalidate(patientAppointmentsProvider);
                    ref.invalidate(patientDocumentsProvider);
                    ref.invalidate(patientInvoicesProvider);
                    ref.invalidate(patientRequestsProvider);
                    ref.invalidate(patientLabOrdersProvider);
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _topBar(
                                name,
                                user.email ??
                                    patient['email']?.toString() ??
                                    '',
                              ),
                              const SizedBox(height: 22),
                              _navigation(tabs, currentLabel),
                              const SizedBox(height: 22),
                              switch (currentLabel) {
                                'Appointments' => _appointments(apptAsync,
                                    patient: patient),
                                'Queue' => _queue(apptAsync),
                                'Lab reports' => _labReports(),
                                'Medical records' =>
                                  _medicalRecords(patient),
                                'Documents' => _documents(patient),
                                'Billing' => _billing(),
                                'Profile' => _profile(patient),
                                _ => _overview(patient, name, apptAsync),
                              },
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _errorState(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.health_and_safety_rounded,
                size: 48, color: AppColors.patientAccent),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center, style: AppTextStyles.body),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                ref.invalidate(currentPatientProvider);
                ref.invalidate(currentUserProvider);
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ]),
        ),
      );

  Widget _topBar(String name, String email) => Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.patientAccent.withOpacity(.14),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.health_and_safety_rounded,
              color: AppColors.patientAccent, size: 27),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('STAT', style: AppTextStyles.h3),
            Text('Patient portal', style: AppTextStyles.caption),
          ]),
        ),
        IconButton(
          tooltip: 'Refresh dashboard',
          onPressed: () {
            ref.invalidate(currentPatientProvider);
            ref.invalidate(patientAppointmentsProvider);
            ref.invalidate(patientDocumentsProvider);
            ref.invalidate(patientInvoicesProvider);
            ref.invalidate(patientRequestsProvider);
            ref.invalidate(patientLabOrdersProvider);
          },
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          tooltip: 'Logout',
          onPressed: _confirmLogout,
          icon: const Icon(Icons.logout_rounded, color: AppColors.error),
        ),
        const RoleBadge(label: 'Patient', color: AppColors.patientAccent),
      ]);

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Logout', style: AppTextStyles.h3),
        content: const Text(
          'Are you sure you want to sign out of your patient portal?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (mounted) _toast('Could not sign out: $e', AppColors.error);
    }
  }

  Widget _navigation(
          List<({String label, IconData icon})> tabs, String current) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tabs.map((t) {
          final selected = t.label == current;
          return ChoiceChip(
            selected: selected,
            avatar: Icon(t.icon,
                size: 17,
                color: selected ? Colors.white : AppColors.textMuted),
            label: Text(t.label),
            labelStyle: TextStyle(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.surface,
            side: BorderSide(
                color: selected ? AppColors.primary : AppColors.cardBorder),
            onSelected: (_) => setState(() => _selectedTabLabel = t.label),
          );
        }).toList(),
      );

  // -----------------------------------------------------------------
  // Overview
  // -----------------------------------------------------------------
  Widget _overview(Map<String, dynamic> patient, String name,
      AsyncValue<List<AppointmentModel>> apptAsync) {
    if (_isLabOnly(patient)) {
      return _labOnlyOverview(patient, name);
    }

    final upcoming = apptAsync.valueOrNull == null
        ? null
        : _nextUpcoming(apptAsync.valueOrNull!);
    final totalAppointments = apptAsync.valueOrNull?.length;
    final allergies = _asStringList(patient['allergies']);
    final conditions = _asStringList(patient['chronicConditions']);
    final labOrders = ref.watch(patientLabOrdersProvider).valueOrNull ??
        const <LabOrderModel>[];
    final activeLabCount = labOrders
        .where((o) =>
            o.status != LabOrderStatus.delivered &&
            o.status != LabOrderStatus.cancelled &&
            o.status != LabOrderStatus.noShow)
        .length;
    final readyCount =
        labOrders.where((o) => o.status == LabOrderStatus.ready).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Good ${_greeting()},', style: AppTextStyles.bodyMuted),
      const SizedBox(height: 4),
      Text(name, style: AppTextStyles.h1),
      const SizedBox(height: 5),
      Text('Here is your personal health overview.',
          style: AppTextStyles.bodyMuted),
      const SizedBox(height: 20),
      _heroCard(),
      const SizedBox(height: 22),
      _bookAppointmentCard(patient),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(
            child: StatCard(
                label: 'Appointments',
                value: totalAppointments?.toString() ?? '—',
                icon: Icons.event_available_rounded,
                accent: AppColors.patientAccent)),
        const SizedBox(width: 10),
        Expanded(
            child: StatCard(
                label: 'Lab reports',
                value: activeLabCount.toString(),
                icon: Icons.science_rounded,
                accent: AppColors.info)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child: StatCard(
                label: 'Invoices',
                value: ref
                        .watch(patientInvoicesProvider)
                        .valueOrNull
                        ?.length
                        .toString() ??
                    '—',
                icon: Icons.receipt_long_rounded,
                accent: AppColors.success)),
        const SizedBox(width: 10),
        Expanded(
            child: StatCard(
                label: 'Blood group',
                value: (patient['bloodGroup'] ?? '—').toString(),
                icon: Icons.bloodtype_rounded,
                accent: AppColors.error)),
      ]),

      if (readyCount > 0) ...[
        const SizedBox(height: 14),
        GlassCard(
          borderColor: AppColors.success.withOpacity(.5),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _selectedTabLabel = 'Lab reports'),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.description_rounded,
                      color: AppColors.success, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$readyCount lab report${readyCount == 1 ? '' : 's'} ready',
                        style: AppTextStyles.body,
                      ),
                      const SizedBox(height: 2),
                      Text('Tap to view and download',
                          style: AppTextStyles.caption),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted),
              ]),
            ),
          ),
        ),
      ],

      const SizedBox(height: 24),
      const SectionHeader(title: 'Upcoming visit'),
      const SizedBox(height: 10),
      if (apptAsync.isLoading)
        const Center(
            child: Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator()))
      else if (apptAsync.hasError)
        _inlineError('Could not load appointments.')
      else if (upcoming == null)
        _emptyCard(Icons.event_available_rounded, 'No upcoming appointments',
            'Your upcoming visits will appear here.')
      else
        _slotStatusCard(upcoming, patient),
      const SizedBox(height: 22),
      const SectionHeader(title: 'Health alerts'),
      const SizedBox(height: 10),
      _healthFact(
          'Allergies',
          allergies.isEmpty ? 'None recorded' : allergies.join(', '),
          Icons.warning_amber_rounded,
          allergies.isEmpty ? AppColors.success : AppColors.warning),
      const SizedBox(height: 9),
      _healthFact(
          'Chronic conditions',
          conditions.isEmpty ? 'None recorded' : conditions.join(', '),
          Icons.monitor_heart_rounded,
          AppColors.info),
      const SizedBox(height: 22),
      const SectionHeader(title: 'Recent activity'),
      const SizedBox(height: 10),
      _recentActivity(apptAsync),
    ]);
  }

  Widget _labOnlyOverview(Map<String, dynamic> patient, String name) {
    final labOrders = ref.watch(patientLabOrdersProvider).valueOrNull ??
        const <LabOrderModel>[];
    final readyCount =
        labOrders.where((o) => o.status == LabOrderStatus.ready).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Welcome,', style: AppTextStyles.bodyMuted),
      const SizedBox(height: 4),
      Text(name, style: AppTextStyles.h1),
      const SizedBox(height: 6),
      Text('Your lab reports appear here.',
          style: AppTextStyles.bodyMuted),
      const SizedBox(height: 20),
      _heroCard(),
      const SizedBox(height: 22),
      Row(children: [
        Expanded(
            child: StatCard(
                label: 'Lab reports',
                value: labOrders.length.toString(),
                icon: Icons.science_rounded,
                accent: AppColors.info)),
        const SizedBox(width: 10),
        Expanded(
            child: StatCard(
                label: 'Ready',
                value: readyCount.toString(),
                icon: Icons.description_rounded,
                accent: AppColors.success)),
      ]),
      const SizedBox(height: 24),
      _infoBanner(
        'Have you visited a clinic? Once your clinic adds your medical '
        'history, appointments, and prescriptions will appear here too.',
        AppColors.info,
        Icons.info_outline_rounded,
      ),
    ]);
  }

  // -----------------------------------------------------------------
  // Book appointment
  // -----------------------------------------------------------------
  Widget _bookAppointmentCard(Map<String, dynamic> patient) {
    final reqAsync = ref.watch(patientRequestsProvider);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.event_available_rounded,
                color: AppColors.patientAccent),
            const SizedBox(width: 10),
            Expanded(
                child: Text('Need an appointment?', style: AppTextStyles.h3)),
          ]),
          const SizedBox(height: 8),
          Text(
            'Send a request. The clinic will assign a doctor, date, and time.',
            style: AppTextStyles.bodyMuted,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showBookAppointmentSheet(patient),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Request appointment'),
            ),
          ),
          const SizedBox(height: 14),
          reqAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (reqs) {
              final open = reqs
                  .where((r) => r.status == AppointmentRequestStatus.pending)
                  .toList();
              if (open.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 22),
                  Text('Pending requests',
                      style: AppTextStyles.caption
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...open.map(_pendingRequestTile),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _pendingRequestTile(AppointmentRequestModel r) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          const Icon(Icons.hourglass_top_rounded,
              size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.reason.isEmpty ? 'Appointment request' : r.reason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body),
                const SizedBox(height: 2),
                Text('Requested ${_dateLabel(r.requestedAt ?? DateTime.now())}',
                    style: AppTextStyles.caption),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _cancelRequest(r),
            child: const Text('Cancel'),
          ),
        ]),
      );

  Future<void> _showBookAppointmentSheet(Map<String, dynamic> patient) async {
    final reasonCtrl = TextEditingController();
    String timeOfDay = 'any';

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 22, 20, MediaQuery.of(context).viewInsets.bottom + 22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Request appointment', style: AppTextStyles.h3),
                const SizedBox(height: 6),
                Text(
                  'The receptionist will assign a doctor, date, and time. '
                  'You will see the details here once confirmed.',
                  style: AppTextStyles.bodyMuted,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Reason for visit',
                      hintText: 'e.g. Persistent headache for 3 days'),
                ),
                const SizedBox(height: 14),
                Text('Preferred time of day', style: AppTextStyles.caption),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['any', 'morning', 'afternoon', 'evening']
                      .map((v) => ChoiceChip(
                            label: Text(v[0].toUpperCase() + v.substring(1)),
                            selected: timeOfDay == v,
                            onSelected: (_) =>
                                setSheetState(() => timeOfDay = v),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                      child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          child: const Text('Cancel'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: ElevatedButton(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          child: const Text('Send request'))),
                ]),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != true) {
      reasonCtrl.dispose();
      return;
    }
    if (reasonCtrl.text.trim().isEmpty) {
      reasonCtrl.dispose();
      _toast('Please describe the reason for your visit.', AppColors.error);
      return;
    }

    try {
      await ref.read(appointmentRequestServiceProvider).createRequest(
            patientDocId: patient['patientDocId'] as String,
            patientId: '${patient['patientId'] ?? ''}',
            patientName: '${patient['fullName'] ?? 'Patient'}',
            patientPhone: '${patient['phone'] ?? ''}',
            clinicId: '${patient['clinicId'] ?? ''}',
            reason: reasonCtrl.text.trim(),
            preferredTimeOfDay: timeOfDay == 'any' ? null : timeOfDay,
          );
      if (mounted) _toast('Request sent to the clinic.', AppColors.success);
    } catch (e) {
      if (mounted) _toast('Could not send request: $e', AppColors.error);
    } finally {
      reasonCtrl.dispose();
    }
  }

  Future<void> _cancelRequest(AppointmentRequestModel r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Cancel request', style: AppTextStyles.h3),
        content:
            const Text('Do you want to withdraw this appointment request?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Keep')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(appointmentRequestServiceProvider)
          .cancelRequest(r.docId);
      if (mounted) _toast('Request withdrawn.', AppColors.success);
    } catch (e) {
      if (mounted) _toast('Could not cancel: $e', AppColors.error);
    }
  }

  Future<void> _showReAppointmentSheet(
      Map<String, dynamic> patient, AppointmentModel previous) async {
    final reasonCtrl = TextEditingController(
        text: previous.chiefComplaint ?? 'Follow-up for previous visit');

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 22, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Request re-appointment', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Reason')),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: const Text('Cancel'))),
            const SizedBox(width: 10),
            Expanded(
                child: ElevatedButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('Send request'))),
          ]),
        ]),
      ),
    );

    if (result != true) {
      reasonCtrl.dispose();
      return;
    }
    try {
      await ref.read(appointmentRequestServiceProvider).createRequest(
            patientDocId: patient['patientDocId'] as String,
            patientId: '${patient['patientId'] ?? ''}',
            patientName: '${patient['fullName'] ?? 'Patient'}',
            patientPhone: '${patient['phone'] ?? ''}',
            clinicId: '${patient['clinicId'] ?? ''}',
            reason: reasonCtrl.text.trim(),
            kind: 're_appointment',
          );
      if (mounted) _toast('Re-appointment request sent.', AppColors.success);
    } catch (e) {
      if (mounted) _toast('Could not send: $e', AppColors.error);
    } finally {
      reasonCtrl.dispose();
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  Widget _heroCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00BFA6), Color(0xFF00796B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: AppColors.primary.withOpacity(.18),
                blurRadius: 24,
                offset: const Offset(0, 9))
          ],
        ),
        child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.favorite_rounded, color: Colors.white, size: 23),
              SizedBox(height: 14),
              Text('Your health, all in one place',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 7),
              Text(
                  'Manage appointments, keep your medical documents close, and stay up to date with your care.',
                  style: TextStyle(color: Colors.white70, height: 1.4)),
            ]),
      );

  AppointmentModel? _nextUpcoming(List<AppointmentModel> list) {
    final now = DateTime.now();
    final floor = now.subtract(const Duration(hours: 12));

    final active = list.where((a) {
      if (a.status == AppointmentStatus.completed ||
          a.status == AppointmentStatus.cancelled ||
          a.status == AppointmentStatus.noShow ||
          a.status == AppointmentStatus.declined ||
          a.status == AppointmentStatus.onHold) {
        return false;
      }
      return a.slot.isAfter(floor);
    }).toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));

    return active.isEmpty ? null : active.first;
  }

  Widget _appointments(
    AsyncValue<List<AppointmentModel>> async, {
    Map<String, dynamic>? patient,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Appointments', style: AppTextStyles.h1),
          const SizedBox(height: 6),
          Text('Your scheduled and previous visits.',
              style: AppTextStyles.bodyMuted),
          const SizedBox(height: 18),
          async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _inlineError('Unable to load appointments: $e'),
            data: (items) {
              if (items.isEmpty) {
                return _emptyCard(
                    Icons.event_busy_rounded,
                    'No appointments yet',
                    'Appointments booked with your clinic will appear here.');
              }
              final sorted = [...items]
                ..sort((a, b) => b.slot.compareTo(a.slot));
              return Column(
                  children: sorted
                      .map((a) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _appointmentCard(a, patient: patient),
                          ))
                      .toList());
            },
          ),
        ],
      );

  Widget _queue(AsyncValue<List<AppointmentModel>> async) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Live queue', style: AppTextStyles.h1),
          const SizedBox(height: 6),
          Text('Queue details appear when the clinic checks you in.',
              style: AppTextStyles.bodyMuted),
          const SizedBox(height: 18),
          async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _inlineError('Unable to load queue: $e'),
            data: (items) {
              final active = items
                  .where((a) =>
                      a.status == AppointmentStatus.booked ||
                      a.status == AppointmentStatus.awaitingConfirmation ||
                      a.status == AppointmentStatus.confirmed ||
                      a.status == AppointmentStatus.checkedIn ||
                      a.status == AppointmentStatus.inConsult)
                  .toList()
                ..sort((a, b) => a.slot.compareTo(b.slot));
              if (active.isEmpty) {
                return _emptyCard(
                    Icons.people_alt_rounded,
                    'You are not in the queue',
                    'After the clinic checks you in, your active visit status will show here.');
              }
              return Column(
                  children: active
                      .map((a) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _queueCard(a),
                          ))
                      .toList());
            },
          ),
        ],
      );

  Widget _queueCard(AppointmentModel appt) {
    final queueAsync = ref.watch(doctorQueueProvider(appt.doctorDocId));

    return GlassCard(
      borderColor: appt.status == AppointmentStatus.inConsult
          ? AppColors.accent
          : AppColors.info.withOpacity(.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.confirmation_number_rounded,
                color: AppColors.patientAccent),
            const SizedBox(width: 9),
            Expanded(
                child: Text(
                    appt.tokenNumber > 0 ? appt.tokenLabel : 'Pending token',
                    style: AppTextStyles.h3)),
            _statusChip(appt),
          ]),
          const SizedBox(height: 10),
          Text(appt.doctorName, style: AppTextStyles.body),
          Text(DateFormat('dd MMM, hh:mm a').format(appt.slot),
              style: AppTextStyles.bodyMuted),
          const SizedBox(height: 12),
          queueAsync.when(
            loading: () => _infoBanner('Fetching queue position…',
                AppColors.info, Icons.hourglass_top_rounded),
            error: (_, __) => const SizedBox.shrink(),
            data: (queue) {
              final idx = queue.indexWhere((q) => q.docId == appt.docId);
              if (idx < 0) {
                return _infoBanner(
                    appt.status == AppointmentStatus.inConsult
                        ? 'It is your turn. Please proceed to the doctor.'
                        : 'You are checked in. Please watch for your token.',
                    AppColors.info,
                    Icons.notifications_active_rounded);
              }
              final position = idx + 1;
              final ahead = idx;

              if (appt.status == AppointmentStatus.inConsult) {
                return _infoBanner(
                    'It is your turn. Please proceed to the doctor.',
                    AppColors.accent,
                    Icons.campaign_rounded);
              }

              return _infoBanner(
                ahead == 0
                    ? "You're next. Please be ready."
                    : "You're #$position in the queue — $ahead ahead of you.",
                AppColors.info,
                Icons.people_alt_rounded,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _slotStatusCard(AppointmentModel appt, Map<String, dynamic> patient) {
    if (appt.slotKey == null || appt.doctorDocId.isEmpty) {
      return _appointmentCard(appt, compact: true, patient: patient);
    }

    final compositeKey = '${appt.doctorDocId}|${appt.slotKey}';
    final queueAsync = ref.watch(slotQueueProvider(compositeKey));

    return queueAsync.when(
      loading: () => _appointmentCard(appt, compact: true, patient: patient),
      error: (_, __) => _appointmentCard(appt, compact: true, patient: patient),
      data: (queue) {
        final total = queue.length;
        final myIndex = queue.indexWhere((q) => q.docId == appt.docId);
        final myPosition = myIndex >= 0 ? myIndex + 1 : null;

        AppointmentModel? present;
        for (final q in queue) {
          if (q.status == AppointmentStatus.inConsult) {
            present = q;
            break;
          }
        }
        present ??= queue
            .where((q) => q.status == AppointmentStatus.checkedIn)
            .fold<AppointmentModel?>(null, (best, q) {
          if (best == null) return q;
          final bt = best.checkedInAt ?? best.slot;
          final qt = q.checkedInAt ?? q.slot;
          return qt.isBefore(bt) ? q : best;
        });
        final presentLabel = present?.tokenLabel ?? '—';

        final checkedInCount = queue
            .where((q) =>
                q.status == AppointmentStatus.checkedIn ||
                q.status == AppointmentStatus.inConsult)
            .length;

        const avgMinutes = 15;
        final (slotStart, _) = AppointmentModel.slotWindow(
          appt.slot,
          appt.slotPeriod ?? 'morning',
        );
        final estimated = myPosition != null
            ? slotStart.add(Duration(minutes: (myPosition - 1) * avgMinutes))
            : null;

        final canCancel = appt.status == AppointmentStatus.booked ||
            appt.status == AppointmentStatus.awaitingConfirmation ||
            appt.status == AppointmentStatus.confirmed ||
            appt.status == AppointmentStatus.onHold;

        return GlassCard(
          borderColor: appt.status == AppointmentStatus.inConsult
              ? AppColors.accent
              : (appt.status == AppointmentStatus.checkedIn
                  ? AppColors.info
                  : AppColors.success.withOpacity(.4)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.patientAccent.withOpacity(.13),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(appt.tokenLabel,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.patientAccent)),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(appt.doctorName, style: AppTextStyles.h3)),
                _statusChip(appt),
              ]),
              const SizedBox(height: 6),
              Text(
                '${_periodLabel(appt.slotPeriod)} • '
                '${DateFormat('EEE, dd MMM yyyy').format(appt.slot)}',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: _metricTile(
                        'In this slot', '$total', Icons.people_alt_rounded)),
                const SizedBox(width: 8),
                Expanded(
                    child: _metricTile('Your number', appt.tokenLabel,
                        Icons.confirmation_number_rounded)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _metricTile('With doctor now', presentLabel,
                        Icons.meeting_room_rounded)),
                const SizedBox(width: 8),
                Expanded(
                    child: _metricTile('Checked in', '$checkedInCount',
                        Icons.how_to_reg_rounded)),
              ]),
              if (estimated != null) ...[
                const SizedBox(height: 8),
                _metricTile(
                  'Estimated check-in',
                  DateFormat('hh:mm a').format(estimated),
                  Icons.schedule_rounded,
                ),
              ],
              const SizedBox(height: 12),
              _infoBanner(
                _statusMessage(appt, myIndex, myPosition),
                appt.status == AppointmentStatus.inConsult
                    ? AppColors.accent
                    : (appt.status == AppointmentStatus.checkedIn
                        ? AppColors.info
                        : AppColors.success),
                appt.status == AppointmentStatus.inConsult
                    ? Icons.campaign_rounded
                    : (appt.status == AppointmentStatus.checkedIn
                        ? Icons.how_to_reg_rounded
                        : Icons.check_circle_outline_rounded),
              ),
              if (canCancel) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _cancelAppointment(appt),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancel appointment'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _statusMessage(
      AppointmentModel appt, int indexInQueue, int? position) {
    switch (appt.status) {
      case AppointmentStatus.inConsult:
        return "It's your turn now. Please proceed to the doctor.";
      case AppointmentStatus.checkedIn:
        if (indexInQueue == 0) return "You're next. Please be ready.";
        if (position != null) {
          return "You're #$position in the queue — ${indexInQueue} ahead of you.";
        }
        return 'You are checked in. Watch the queue for your turn.';
      case AppointmentStatus.awaitingConfirmation:
        return 'The clinic has asked you to confirm this visit.';
      case AppointmentStatus.confirmed:
        return 'Visit confirmed. Please arrive about 10 minutes early.';
      case AppointmentStatus.onHold:
        return 'This appointment is temporarily on hold. The clinic will be in touch.';
      case AppointmentStatus.booked:
        return 'Your appointment is booked. Arrive 10 minutes early.';
      default:
        return '';
    }
  }

  Widget _metricTile(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 15, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(label,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textMuted))),
            ]),
            const SizedBox(height: 6),
            Text(value, style: AppTextStyles.h3),
          ],
        ),
      );

  String _periodLabel(String? period) {
    switch (period) {
      case 'morning':
        return 'Morning (9:00 – 12:00)';
      case 'afternoon':
        return 'Afternoon (13:00 – 16:00)';
      case 'evening':
        return 'Evening (17:00 – 20:00)';
      default:
        return 'Scheduled';
    }
  }

  Widget _appointmentCard(
    AppointmentModel appt, {
    bool compact = false,
    Map<String, dynamic>? patient,
  }) {
    final needsConfirmation =
        appt.status == AppointmentStatus.awaitingConfirmation ||
            (appt.confirmationRequested &&
                appt.status == AppointmentStatus.booked);
    final canCancel = appt.status == AppointmentStatus.booked ||
        appt.status == AppointmentStatus.awaitingConfirmation ||
        appt.status == AppointmentStatus.confirmed ||
        appt.status == AppointmentStatus.onHold;

    return GlassCard(
      borderColor: needsConfirmation
          ? AppColors.warning
          : (appt.status == AppointmentStatus.confirmed
              ? AppColors.success
              : AppColors.cardBorder),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: AppColors.patientAccent.withOpacity(.13),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                    appt.tokenNumber > 0 ? appt.tokenLabel : 'Pending token',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.patientAccent))),
            const Spacer(),
            _statusChip(appt),
          ]),
          const SizedBox(height: 13),
          Text(appt.doctorName, style: AppTextStyles.h3),
          const SizedBox(height: 5),
          Text(DateFormat('EEE, dd MMM yyyy • hh:mm a').format(appt.slot),
              style: AppTextStyles.bodyMuted),
          if (appt.chiefComplaint != null &&
              appt.chiefComplaint!.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text('Reason: ${appt.chiefComplaint}',
                style: AppTextStyles.caption),
          ],
          if (needsConfirmation) ...[
            const SizedBox(height: 14),
            _infoBanner('The clinic needs you to confirm this visit.',
                AppColors.warning, Icons.notifications_active_rounded),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: ElevatedButton.icon(
                onPressed: () => _confirmAppointment(appt),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Confirm'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white),
              )),
              const SizedBox(width: 9),
              Expanded(
                  child: OutlinedButton.icon(
                onPressed: () => _declineAppointment(appt),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text("Can't come"),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error)),
              )),
            ]),
          ] else if (!compact &&
              appt.status == AppointmentStatus.confirmed) ...[
            const SizedBox(height: 12),
            _infoBanner(
                'Visit confirmed. Please arrive about 10 minutes early.',
                AppColors.success,
                Icons.check_circle_outline_rounded),
          ] else if (appt.status == AppointmentStatus.checkedIn) ...[
            const SizedBox(height: 12),
            _infoBanner(
                'You are checked in. Watch the queue for your turn.',
                AppColors.info,
                Icons.how_to_reg_rounded),
          ] else if (appt.status == AppointmentStatus.inConsult) ...[
            const SizedBox(height: 12),
            _infoBanner('It is your turn now. Please see the doctor.',
                AppColors.accent, Icons.campaign_rounded),
          ] else if (appt.status == AppointmentStatus.completed &&
              patient != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showReAppointmentSheet(patient, appt),
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('Request re-appointment'),
              ),
            ),
          ],
          if (canCancel) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _cancelAppointment(appt),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Cancel appointment'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // Lab reports
  // -----------------------------------------------------------------
  Widget _labReports() {
    final async = ref.watch(patientLabOrdersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lab reports', style: AppTextStyles.h1),
        const SizedBox(height: 6),
        Text('Track the tests your doctor ordered and download reports.',
            style: AppTextStyles.bodyMuted),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _statusFilterChip(null, 'All'),
            const SizedBox(width: 6),
            _statusFilterChip(LabOrderStatus.ordered, 'Ordered'),
            const SizedBox(width: 6),
            _statusFilterChip(LabOrderStatus.processing, 'Processing'),
            const SizedBox(width: 6),
            _statusFilterChip(LabOrderStatus.ready, 'Ready'),
            const SizedBox(width: 6),
            _statusFilterChip(LabOrderStatus.delivered, 'Delivered'),
          ]),
        ),
        const SizedBox(height: 16),
        async.when(
          loading: () => const Center(
              child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator())),
          error: (e, _) => _inlineError('Unable to load lab orders: $e'),
          data: (orders) {
            final filtered = _labFilter == null
                ? orders
                : orders.where((o) => o.status == _labFilter).toList();

            if (filtered.isEmpty) {
              return _emptyCard(
                Icons.science_outlined,
                orders.isEmpty ? 'No lab reports yet' : 'Nothing here',
                orders.isEmpty
                    ? 'When your doctor orders a lab test, or your lab shares a report with your email or phone, it will appear here.'
                    : 'No lab orders match the selected filter.',
              );
            }

            filtered.sort((a, b) {
              int rank(LabOrderModel o) => switch (o.status) {
                    LabOrderStatus.ready => 0,
                    LabOrderStatus.processing => 1,
                    LabOrderStatus.sampleCollected => 2,
                    LabOrderStatus.accepted => 3,
                    LabOrderStatus.ordered => 4,
                    LabOrderStatus.delivered => 5,
                    LabOrderStatus.cancelled => 6,
                    LabOrderStatus.noShow => 7,
                    LabOrderStatus.unknown => 8,
                  };
              final r = rank(a).compareTo(rank(b));
              if (r != 0) return r;
              final at = a.orderedAt ?? DateTime(2000);
              final bt = b.orderedAt ?? DateTime(2000);
              return bt.compareTo(at);
            });

            return Column(
              children: filtered
                  .map((o) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _labReportRow(o),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _statusFilterChip(LabOrderStatus? status, String label) {
    final selected = _labFilter == status;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.info,
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        fontSize: 12,
      ),
      side: BorderSide(
          color: selected ? AppColors.info : AppColors.cardBorder),
      onSelected: (_) => setState(() => _labFilter = status),
    );
  }

  Widget _labReportRow(LabOrderModel o) {
    final color = _labStatusColor(o.status);
    final testsSummary = o.tests.isEmpty
        ? 'Lab test'
        : o.tests.map((t) => t.code ?? t.name).join(', ');

    return GlassCard(
      borderColor: color.withOpacity(0.35),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openLabReportDetail(o),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    o.status == LabOrderStatus.ready
                        ? Icons.description_rounded
                        : Icons.science_outlined,
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(testsSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(o.labName, style: AppTextStyles.caption),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.13),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_labStatusLabel(o.status),
                      style: AppTextStyles.caption.copyWith(color: color)),
                ),
              ]),
              if (o.orderedAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Ordered ${DateFormat('EEE, dd MMM yyyy • hh:mm a').format(o.orderedAt!)}',
                  style: AppTextStyles.caption,
                ),
              ],
              if (o.status == LabOrderStatus.ready) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _openReport(o),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Download report'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
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

  void _openReport(LabOrderModel o) {
    final url = o.reportUrl;
    if (url == null || url.isEmpty) {
      _toast('Report not uploaded yet.', AppColors.error);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _toast('Invalid report URL.', AppColors.error);
      return;
    }
    launchUrl(uri, mode: LaunchMode.externalApplication).catchError((e) {
      if (mounted) _toast('Could not open report: $e', AppColors.error);
      return false;
    });
  }

  void _openLabReportDetail(LabOrderModel o) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _LabReportDetailSheet(order: o),
    );
  }

  Future<void> _cancelAppointment(AppointmentModel appt) async {
    final reasonCtrl = TextEditingController();

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 22, 20, MediaQuery.of(context).viewInsets.bottom + 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cancel appointment', style: AppTextStyles.h3),
            const SizedBox(height: 6),
            Text(
              'This will release your slot. Please let the clinic know if you can.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration:
                  const InputDecoration(labelText: 'Reason (optional)'),
            ),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('Keep it'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('Cancel appointment'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );

    if (confirm != true) {
      reasonCtrl.dispose();
      return;
    }

    try {
      await ref.read(appointmentServiceProvider).cancelAppointment(
            appt.docId,
            reason: reasonCtrl.text.trim().isEmpty
                ? null
                : reasonCtrl.text.trim(),
          );
      if (mounted) _toast('Appointment cancelled.', AppColors.success);
      ref.invalidate(patientAppointmentsProvider);
    } catch (e) {
      if (mounted) _toast('Could not cancel: $e', AppColors.error);
    } finally {
      reasonCtrl.dispose();
    }
  }

  Future<void> _confirmAppointment(AppointmentModel appt) async {
    try {
      await ref.read(appointmentServiceProvider).confirmAppointment(appt.docId);
      if (mounted) _toast('Appointment confirmed.', AppColors.success);
      ref.invalidate(patientAppointmentsProvider);
    } catch (e) {
      if (mounted) {
        _toast('Could not confirm appointment: $e', AppColors.error);
      }
    }
  }

  Future<void> _declineAppointment(AppointmentModel appt) async {
    final controller = TextEditingController();
    final shouldSubmit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 22, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 22),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Decline appointment', style: AppTextStyles.h3),
              const SizedBox(height: 7),
              Text('Let the clinic know why you cannot attend.',
                  style: AppTextStyles.bodyMuted),
              const SizedBox(height: 14),
              TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(hintText: 'Reason (optional)')),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pop(sheetContext, false),
                        child: const Text('Cancel'))),
                const SizedBox(width: 10),
                Expanded(
                    child: ElevatedButton(
                        onPressed: () =>
                            Navigator.pop(sheetContext, true),
                        child: const Text('Submit'))),
              ]),
            ]),
      ),
    );
    if (shouldSubmit != true) return;
    try {
      await ref.read(appointmentServiceProvider).declineAppointment(
          appt.docId,
          reason: controller.text.trim().isEmpty
              ? null
              : controller.text.trim());
      if (mounted) _toast('Appointment response sent.', AppColors.success);
      ref.invalidate(patientAppointmentsProvider);
    } catch (e) {
      if (mounted) _toast('Could not update appointment: $e', AppColors.error);
    } finally {
      controller.dispose();
    }
  }

  // -----------------------------------------------------------------
  // Medical records
  // -----------------------------------------------------------------
  Widget _medicalRecords(Map<String, dynamic> patient) {
    final medications = _asStringList(patient['currentMedications']);
    final allergies = _asStringList(patient['allergies']);
    final conditions = _asStringList(patient['chronicConditions']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Medical records', style: AppTextStyles.h1),
      const SizedBox(height: 6),
      Text('Health information currently saved in your patient profile.',
          style: AppTextStyles.bodyMuted),
      const SizedBox(height: 18),
      _recordCard('Basic health information', Icons.monitor_heart_rounded, [
        ('Blood group', patient['bloodGroup']),
        ('Date of birth', _formatDob(patient['dob'])),
        ('Gender', patient['gender']),
        ('Activity level', patient['activityLevel']),
      ]),
      const SizedBox(height: 12),
      _listRecordCard('Allergies', Icons.warning_amber_rounded, allergies,
          AppColors.warning),
      const SizedBox(height: 12),
      _listRecordCard('Chronic conditions', Icons.health_and_safety_rounded,
          conditions, AppColors.info),
      const SizedBox(height: 12),
      _listRecordCard('Current medications', Icons.medication_rounded,
          medications, AppColors.patientAccent),
      const SizedBox(height: 12),
      _recordCard('Lifestyle', Icons.directions_walk_rounded, [
        ('Smoking', patient['smoking']),
        ('Alcohol', patient['alcohol']),
        ('Emergency contact', patient['emergencyContactName']),
        ('Emergency phone', patient['emergencyContactPhone']),
      ]),
      const SizedBox(height: 14),
      _infoBanner(
          'This page displays information available in your profile. For corrections to clinical notes or diagnoses, contact your clinic.',
          AppColors.info,
          Icons.info_outline_rounded),
    ]);
  }

  String _formatDob(dynamic value) {
    if (value == null || '$value'.trim().isEmpty) return 'Not recorded';
    final date = DateTime.tryParse('$value');
    return date == null ? '$value' : DateFormat('dd MMM yyyy').format(date);
  }

  List<String> _asStringList(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const [];
  }

  Widget _recordCard(
          String title, IconData icon, List<(String, dynamic)> fields) =>
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: AppColors.patientAccent),
            const SizedBox(width: 9),
            Text(title, style: AppTextStyles.h3)
          ]),
          const SizedBox(height: 12),
          ...fields.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 145,
                          child:
                              Text(f.$1, style: AppTextStyles.bodyMuted)),
                      Expanded(
                          child: Text(
                              f.$2 == null || '${f.$2}'.trim().isEmpty
                                  ? 'Not recorded'
                                  : '${f.$2}',
                              style: AppTextStyles.body)),
                    ]),
              )),
        ]),
      );

  Widget _listRecordCard(
          String title, IconData icon, List<String> values, Color color) =>
      GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 9),
            Text(title, style: AppTextStyles.h3)
          ]),
          const SizedBox(height: 12),
          if (values.isEmpty)
            Text('No information recorded.', style: AppTextStyles.bodyMuted)
          else
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: values
                    .map((v) => Chip(
                        label: Text(v),
                        backgroundColor: color.withOpacity(.1),
                        side: BorderSide(color: color.withOpacity(.25))))
                    .toList()),
        ]),
      );

  // -----------------------------------------------------------------
  // Documents
  // -----------------------------------------------------------------
  Widget _documents(Map<String, dynamic> patient) {
    final async = ref.watch(patientDocumentsProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Documents', style: AppTextStyles.h1),
              const SizedBox(height: 6),
              Text('Upload and access your reports and files.',
                  style: AppTextStyles.bodyMuted)
            ])),
        ElevatedButton.icon(
            onPressed: () => _uploadDocument(patient),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Upload'))
      ]),
      const SizedBox(height: 18),
      _infoBanner(
          'Files are stored in Firebase Storage; document details are stored in the patientDocuments collection.',
          AppColors.info,
          Icons.lock_outline_rounded),
      const SizedBox(height: 14),
      async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _inlineError('Unable to load documents: $e'),
        data: (docs) {
          if (docs.isEmpty) {
            return _emptyCard(Icons.folder_open_rounded, 'No documents yet',
                'Use Upload to add a lab report, prescription, referral, or other file.');
          }
          return Column(
              children: docs.map((doc) {
            final d = doc.data();
            final title =
                (d['title'] ?? d['fileName'] ?? 'Document').toString();
            final category = (d['category'] ?? 'Other').toString();
            return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                    child: Row(children: [
                  Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: AppColors.info.withOpacity(.12),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.description_rounded,
                          color: AppColors.info)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(title,
                            style: AppTextStyles.body
                                .copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(
                            '$category • ${_dateLabel(_asDate(d['createdAt']))}',
                            style: AppTextStyles.caption)
                      ])),
                  IconButton(
                      tooltip: 'Open document',
                      onPressed: () => _openDocument(d),
                      icon: const Icon(Icons.open_in_new_rounded)),
                  IconButton(
                      tooltip: 'Download document',
                      onPressed: () => _downloadDocument(d),
                      icon: const Icon(Icons.download_rounded)),
                ])));
          }).toList());
        },
      ),
    ]);
  }

  Future<void> _uploadDocument(Map<String, dynamic> patient) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'],
      );
      if (file == null) return;
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.length > 15 * 1024 * 1024) {
        if (mounted) {
          _toast('Please choose a file smaller than 15 MB.', AppColors.error);
        }
        return;
      }
      final titleController =
          TextEditingController(text: file.name.split('.').first);
      final category = await showDialog<String>(
          context: context,
          builder: (dialogContext) {
            String selected = 'Lab report';
            return StatefulBuilder(
                builder: (context, setDialogState) => AlertDialog(
                      title: const Text('Upload document'),
                      content:
                          Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                            controller: titleController,
                            decoration: const InputDecoration(
                                labelText: 'Document title')),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                            value: selected,
                            decoration: const InputDecoration(
                                labelText: 'Category'),
                            items: const [
                              'Lab report',
                              'Prescription',
                              'Referral',
                              'Invoice',
                              'Discharge summary',
                              'Other'
                            ]
                                .map((v) =>
                                    DropdownMenuItem(value: v, child: Text(v)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => selected = v);
                              }
                            }),
                      ]),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Cancel')),
                        ElevatedButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, selected),
                            child: const Text('Upload'))
                      ],
                    ));
          });
      if (category == null) {
        titleController.dispose();
        return;
      }
      final title = titleController.text.trim().isEmpty
          ? file.name
          : titleController.text.trim();
      titleController.dispose();
      final patientDocId = patient['patientDocId'] as String;
      final docRef =
          FirebaseFirestore.instance.collection('patientDocuments').doc();
      final safeName = file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storagePath =
          'patients/$patientDocId/documents/${docRef.id}/$safeName';
      final metadata = <String, String>{
        'patientDocId': patientDocId,
        'patientId': '${patient['patientId'] ?? ''}',
        'category': category,
        'title': title,
        'uploadedByUid': FirebaseAuth.instance.currentUser?.uid ?? '',
        'originalFileName': file.name
      };
      final contentType = _contentType(file.extension);
      await FirebaseStorage.instance.ref(storagePath).putData(
          bytes,
          SettableMetadata(
              contentType: contentType, customMetadata: metadata));
      await docRef.set({
        'patientDocId': patientDocId,
        'patientId': patient['patientId'],
        'clinicId': patient['clinicId'],
        'title': title,
        'category': category,
        'storagePath': storagePath,
        'fileName': file.name,
        'contentType': contentType,
        'sizeBytes': bytes.length,
        'uploadedByUid': FirebaseAuth.instance.currentUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      ref.invalidate(patientDocumentsProvider);
      if (mounted) _toast('Document uploaded successfully.', AppColors.success);
    } catch (e) {
      if (mounted) _toast('Upload failed: $e', AppColors.error);
    }
  }

  String _contentType(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  Future<String?> _documentUrl(Map<String, dynamic> data) async {
    final path = data['storagePath']?.toString();
    if (path == null || path.isEmpty) return data['downloadUrl']?.toString();
    return FirebaseStorage.instance.ref(path).getDownloadURL();
  }

  Future<void> _openDocument(Map<String, dynamic> data) async {
    try {
      final url = await _documentUrl(data);
      if (url == null ||
          !await launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication)) {
        if (mounted) _toast('Could not open this document.', AppColors.error);
      }
    } catch (e) {
      if (mounted) _toast('Could not open document: $e', AppColors.error);
    }
  }

  Future<void> _downloadDocument(Map<String, dynamic> data) async {
    await _openDocument(data);
  }

  // -----------------------------------------------------------------
  // Billing
  // -----------------------------------------------------------------
  Widget _billing() {
    final async = ref.watch(patientInvoicesProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Billing & invoices', style: AppTextStyles.h1),
      const SizedBox(height: 6),
      Text('Review invoices and payment status from your clinic.',
          style: AppTextStyles.bodyMuted),
      const SizedBox(height: 18),
      async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _inlineError('Unable to load invoices: $e'),
        data: (docs) {
          if (docs.isEmpty) {
            return _emptyCard(Icons.receipt_long_rounded, 'No invoices found',
                'Invoices linked to your patient record will appear here.');
          }
          final due = docs
              .where((d) => ![
                    'paid',
                    'completed',
                    'settled'
                  ].contains('${d.data()['status'] ?? ''}'.toLowerCase()))
              .fold<num>(
                  0,
                  (sum, d) =>
                      sum +
                      ((d.data()['balanceDue'] ?? d.data()['amountDue'] ?? 0)
                              is num
                          ? (d.data()['balanceDue'] ??
                              d.data()['amountDue'] ??
                              0) as num
                          : num.tryParse(
                                  '${d.data()['balanceDue'] ?? d.data()['amountDue'] ?? 0}') ??
                              0));
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlassCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Outstanding balance',
                          style: AppTextStyles.bodyMuted),
                      const SizedBox(height: 7),
                      Text(_money(due), style: AppTextStyles.h1)
                    ])),
                const SizedBox(height: 14),
                ...docs.map((doc) {
                  final d = doc.data();
                  final status = (d['status'] ?? 'pending').toString();
                  final paid = ['paid', 'completed', 'settled']
                      .contains(status.toLowerCase());
                  return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassCard(
                          child: Row(children: [
                        Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                color: (paid
                                        ? AppColors.success
                                        : AppColors.warning)
                                    .withOpacity(.12),
                                borderRadius: BorderRadius.circular(12)),
                            child: Icon(Icons.receipt_long_rounded,
                                color: paid
                                    ? AppColors.success
                                    : AppColors.warning)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  (d['invoiceNumber'] ??
                                          d['invoiceId'] ??
                                          doc.id)
                                      .toString(),
                                  style: AppTextStyles.body.copyWith(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(_dateLabel(_asDate(d['createdAt'])),
                                  style: AppTextStyles.caption),
                              Text(
                                  _money(d['totalAmount'] ??
                                      d['amount'] ??
                                      d['amountDue']),
                                  style: AppTextStyles.body)
                            ])),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                                color: (paid
                                        ? AppColors.success
                                        : AppColors.warning)
                                    .withOpacity(.12),
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(status,
                                style: AppTextStyles.caption.copyWith(
                                    color: paid
                                        ? AppColors.success
                                        : AppColors.warning))),
                      ])));
                }),
              ]);
        },
      ),
    ]);
  }

  // -----------------------------------------------------------------
  // Profile
  // -----------------------------------------------------------------
  Widget _profile(Map<String, dynamic> patient) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('My profile', style: AppTextStyles.h1),
        const SizedBox(height: 6),
        Text('Keep your contact details up to date.',
            style: AppTextStyles.bodyMuted),
        const SizedBox(height: 18),
        GlassCard(
            child: Column(children: [
          CircleAvatar(
              radius: 34,
              backgroundColor: AppColors.patientAccent.withOpacity(.13),
              child: const Icon(Icons.person_rounded,
                  color: AppColors.patientAccent, size: 36)),
          const SizedBox(height: 10),
          Text('${patient['fullName'] ?? 'Patient'}',
              style: AppTextStyles.h3),
          Text('Patient ID: ${patient['patientId'] ?? '—'}',
              style: AppTextStyles.bodyMuted),
          const SizedBox(height: 16),
          _profileRow(Icons.email_outlined, 'Email', patient['email']),
          _profileRow(Icons.phone_outlined, 'Phone', patient['phone']),
          _profileRow(Icons.location_on_outlined, 'Address',
              patient['address']),
          _profileRow(Icons.location_city_outlined, 'City', patient['city']),
          _profileRow(Icons.calendar_month_outlined, 'Date of birth',
              _formatDob(patient['dob'])),
          _profileRow(
              Icons.person_outline_rounded, 'Gender', patient['gender']),
          const SizedBox(height: 14),
          if (patient['isLabCustomer'] != true)
            SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                    onPressed: () => _editProfile(patient),
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit contact details'))),
        ])),
        const SizedBox(height: 14),
        _infoBanner(
            'Your patient ID and authentication identity are managed by the clinic and cannot be changed here.',
            AppColors.info,
            Icons.shield_outlined),
      ]);

  Widget _profileRow(IconData icon, String label, dynamic value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 19, color: AppColors.textMuted),
          const SizedBox(width: 11),
          SizedBox(
              width: 105,
              child: Text(label, style: AppTextStyles.bodyMuted)),
          Expanded(
              child: Text(
                  value == null || '$value'.trim().isEmpty
                      ? 'Not recorded'
                      : '$value',
                  style: AppTextStyles.body))
        ]),
      );

  Future<void> _editProfile(Map<String, dynamic> patient) async {
    final name = TextEditingController(text: '${patient['fullName'] ?? ''}');
    final phone = TextEditingController(text: '${patient['phone'] ?? ''}');
    final address = TextEditingController(text: '${patient['address'] ?? ''}');
    final city = TextEditingController(text: '${patient['city'] ?? ''}');
    final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Edit contact details'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Full name')),
                TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone')),
                TextField(
                    controller: address,
                    decoration: const InputDecoration(labelText: 'Address')),
                TextField(
                    controller: city,
                    decoration: const InputDecoration(labelText: 'City')),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Save'))
              ],
            ));
    if (result == true) {
      try {
        await FirebaseFirestore.instance
            .collection('patients')
            .doc(patient['patientDocId'])
            .update({
          'fullName': name.text.trim(),
          'phone': phone.text.trim(),
          'address': address.text.trim(),
          'city': city.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        ref.invalidate(currentPatientProvider);
        if (mounted) _toast('Profile updated.', AppColors.success);
      } catch (e) {
        if (mounted) _toast('Could not update profile: $e', AppColors.error);
      }
    }
    name.dispose();
    phone.dispose();
    address.dispose();
    city.dispose();
  }

  Widget _recentActivity(AsyncValue<List<AppointmentModel>> async) {
    final items = async.valueOrNull;
    if (items == null) {
      if (async.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _emptyCard(Icons.history_rounded, 'No recent activity',
          'Your recent visits will appear here.');
    }
    final recent = [...items]..sort((a, b) => b.slot.compareTo(a.slot));
    if (recent.isEmpty) {
      return _emptyCard(Icons.history_rounded, 'No recent activity',
          'Your recent visits will appear here.');
    }
    return GlassCard(
      child: Column(
        children: recent.take(4).map((a) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.event_note_rounded,
                    color: AppColors.patientAccent),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${a.statusLabel} appointment with ${a.doctorName}',
                          style: AppTextStyles.body),
                      const SizedBox(height: 3),
                      Text(_dateLabel(a.slot), style: AppTextStyles.caption),
                    ],
                  ),
                ),
                _statusChip(a),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _healthFact(String title, String value, IconData icon, Color color) =>
      GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: color.withOpacity(.12),
                  borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: color)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: AppTextStyles.caption),
                const SizedBox(height: 3),
                Text(value, style: AppTextStyles.body)
              ]))
        ]),
      );

  Widget _statusChip(AppointmentModel appt) {
    final color = switch (appt.status) {
      AppointmentStatus.confirmed ||
      AppointmentStatus.completed =>
        AppColors.success,
      AppointmentStatus.awaitingConfirmation => AppColors.warning,
      AppointmentStatus.checkedIn => AppColors.info,
      AppointmentStatus.inConsult => AppColors.accent,
      AppointmentStatus.onHold => AppColors.textMuted,
      AppointmentStatus.cancelled ||
      AppointmentStatus.declined ||
      AppointmentStatus.noShow =>
        AppColors.error,
      AppointmentStatus.booked =>
        appt.confirmationRequested ? AppColors.warning : AppColors.textMuted,
    };
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: color.withOpacity(.13),
            borderRadius: BorderRadius.circular(8)),
        child: Text(appt.statusLabel,
            style: AppTextStyles.caption.copyWith(color: color)));
  }

  Widget _infoBanner(String text, Color color, IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: color.withOpacity(.09),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(.25))),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: color, fontSize: 12, height: 1.35)))
        ]),
      );

  Widget _emptyCard(IconData icon, String title, String message) => GlassCard(
        child: SizedBox(
            width: double.infinity,
            child: Column(children: [
              Icon(icon, size: 34, color: AppColors.textMuted),
              const SizedBox(height: 10),
              Text(title, style: AppTextStyles.h3),
              const SizedBox(height: 5),
              Text(message,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMuted)
            ])),
      );

  Widget _inlineError(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.error.withOpacity(.08),
            borderRadius: BorderRadius.circular(12)),
        child: Text(message, style: const TextStyle(color: AppColors.error)),
      );

  void _toast(String message, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }
}

// -----------------------------------------------------------------
// Lab report detail bottom sheet
// -----------------------------------------------------------------
class _LabReportDetailSheet extends StatelessWidget {
  final LabOrderModel order;
  const _LabReportDetailSheet({required this.order});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Lab order', style: AppTextStyles.h3),
            const SizedBox(height: 4),
            Text(order.labName, style: AppTextStyles.bodyMuted),
            const SizedBox(height: 14),
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _labStatusColor(order.status).withOpacity(.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_labStatusLabel(order.status),
                    style: AppTextStyles.caption
                        .copyWith(color: _labStatusColor(order.status))),
              ),
            ]),
            const SizedBox(height: 14),
            Text('Tests', style: AppTextStyles.caption),
            const SizedBox(height: 6),
            ...order.tests.map((t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    const Icon(Icons.science_outlined,
                        color: AppColors.info, size: 16),
                    const SizedBox(width: 10),
                    Expanded(child: Text(t.label, style: AppTextStyles.body)),
                  ]),
                )),
            if (order.instructions != null &&
                order.instructions!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Instructions', style: AppTextStyles.caption),
              const SizedBox(height: 4),
              Text(order.instructions!, style: AppTextStyles.bodyMuted),
            ],
            const SizedBox(height: 16),
            Text('Timeline', style: AppTextStyles.caption),
            const SizedBox(height: 6),
            _timelineRow('Ordered', order.orderedAt),
            _timelineRow('Accepted', order.acceptedAt),
            _timelineRow('Sample collected', order.sampleCollectedAt),
            _timelineRow('Processing started', order.processingStartedAt),
            _timelineRow('Report ready', order.reportReadyAt),
            _timelineRow('Delivered', order.deliveredAt),
            if (order.cancelledAt != null)
              _timelineRow('Cancelled', order.cancelledAt),
            if (order.noShowAt != null)
              _timelineRow('No-show', order.noShowAt),
            if (order.reportUrl != null &&
                order.reportUrl!.isNotEmpty) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final url = Uri.tryParse(order.reportUrl!);
                    if (url == null) return;
                    await launchUrl(url,
                        mode: LaunchMode.externalApplication);
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Download report'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
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
      child: Row(children: [
        Icon(
          at == null
              ? Icons.radio_button_unchecked
              : Icons.radio_button_checked,
          size: 14,
          color: at == null ? AppColors.textMuted : AppColors.success,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: AppTextStyles.body)),
        Text(
          at == null ? '—' : DateFormat('dd MMM • hh:mm a').format(at),
          style: AppTextStyles.caption,
        ),
      ]),
    );
  }
}