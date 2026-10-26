import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment_model.dart';

/// Fixed capacity per slot period.
const int kSlotsPerPeriod = 12;

class DashboardService {
  final _db = FirebaseFirestore.instance;

  // ----------------------------------------------------------------
  // APPOINTMENTS
  // ----------------------------------------------------------------

  Stream<List<AppointmentModel>> appointmentsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    return _db
        .collection('appointments')
        .where('slot', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('slot', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((s) {
          final list = s.docs
              .map((d) => AppointmentModel.fromMap(d.id, d.data()))
              .toList();
          list.sort((a, b) => a.slot.compareTo(b.slot));
          return list;
        });
  }

  Stream<List<AppointmentModel>> todayAppointments() =>
      appointmentsForDay(DateTime.now());

  Stream<List<AppointmentModel>> upcomingAppointments() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 7));

    return _db
        .collection('appointments')
        .where('slot', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('slot', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((s) {
          final list = s.docs
              .map((d) => AppointmentModel.fromMap(d.id, d.data()))
              .where((a) =>
                  a.status != AppointmentStatus.cancelled &&
                  a.status != AppointmentStatus.declined &&
                  a.status != AppointmentStatus.noShow)
              .toList();
          list.sort((a, b) => a.slot.compareTo(b.slot));
          return list;
        });
  }

  Stream<List<AppointmentModel>> patientAppointments(String patientDocId) {
    return _db
        .collection('appointments')
        .where('patientDocId', isEqualTo: patientDocId)
        .snapshots()
        .map((s) {
          final list = s.docs
              .map((d) => AppointmentModel.fromMap(d.id, d.data()))
              .toList();
          list.sort((a, b) => b.slot.compareTo(a.slot));
          return list;
        });
  }

  // ----------------------------------------------------------------
  // COUNTS
  // ----------------------------------------------------------------

  Stream<int> pendingConfirmationsCount() {
    final now = DateTime.now();
    final window = now.add(const Duration(days: 30));

    return _db
        .collection('appointments')
        .where('status', isEqualTo: 'booked')
        .where('confirmationRequested', isEqualTo: true)
        .where('slot', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .where('slot', isLessThanOrEqualTo: Timestamp.fromDate(window))
        .snapshots()
        .map((s) => s.size);
  }

  Stream<int> labPickupsCount() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    return _db
        .collection('labOrders')
        .where('status', isEqualTo: 'ordered')
        .where('orderedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('orderedAt', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((s) => s.size);
  }

  // ----------------------------------------------------------------
  // INVOICES / COLLECTIONS
  // ----------------------------------------------------------------

  Stream<({int count, num amount})> unpaidInvoicesSummary() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 30));

    return _db
        .collection('invoices')
        .where('status', whereIn: ['draft', 'issued'])
        .where('issuedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .snapshots()
        .map((s) {
          num total = 0;
          for (final d in s.docs) {
            final m = d.data();
            final amount = (m['totalAmount'] as num?) ?? 0;
            final paid = (m['amountPaid'] as num?) ?? 0;
            total += (amount - paid);
          }
          return (count: s.size, amount: total);
        });
  }

  Stream<num> todayCollections() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    return _db
        .collection('invoices')
        .where('paidAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('paidAt', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((s) {
          num total = 0;
          for (final d in s.docs) {
            total += ((d.data()['amountPaid'] as num?) ?? 0);
          }
          return total;
        });
  }

  // ----------------------------------------------------------------
  // PATIENTS
  // ----------------------------------------------------------------

  Stream<Map<String, dynamic>?> streamPatient(String uid) {
    return _db.collection('patients').doc(uid).snapshots().map((s) {
      if (!s.exists) return null;
      return <String, dynamic>{'uid': s.id, ...s.data()!};
    });
  }

  Stream<List<Map<String, dynamic>>> searchPatients(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const Stream.empty();

    return _db.collection('patients').snapshots().map((s) {
      final list = s.docs
          .map((d) => <String, dynamic>{'uid': d.id, ...d.data()})
          .where((m) {
            final name =
                '${m['fullName'] ?? m['name'] ?? ''}'.toLowerCase();
            final phone = '${m['phone'] ?? ''}'.toLowerCase();
            final pid = '${m['patientId'] ?? ''}'.toLowerCase();
            return name.contains(q) ||
                phone.contains(q) ||
                pid.contains(q);
          })
          .toList();
      list.sort((a, b) => '${a['fullName'] ?? ''}'
          .toLowerCase()
          .compareTo('${b['fullName'] ?? ''}'.toLowerCase()));
      return list.take(30).toList();
    });
  }
}

final dashboardServiceProvider =
    Provider<DashboardService>((ref) => DashboardService());

// ----------------------------------------------------------------
// Appointment providers
// ----------------------------------------------------------------

final appointmentsForDayProvider = StreamProvider.autoDispose
    .family<List<AppointmentModel>, DateTime>((ref, day) {
  return ref.read(dashboardServiceProvider).appointmentsForDay(day);
});

final todayAppointmentsProvider =
    StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  return ref.watch(appointmentsForDayProvider(DateTime.now()).stream);
});

final upcomingAppointmentsProvider =
    StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  return ref.read(dashboardServiceProvider).upcomingAppointments();
});

final patientAppointmentsProvider = StreamProvider.autoDispose
    .family<List<AppointmentModel>, String>((ref, patientDocId) {
  if (patientDocId.isEmpty) return const Stream.empty();
  return ref
      .read(dashboardServiceProvider)
      .patientAppointments(patientDocId);
});

// ----------------------------------------------------------------
// Count providers
// ----------------------------------------------------------------

final pendingConfirmationsProvider =
    StreamProvider.autoDispose<int>((ref) {
  return ref.read(dashboardServiceProvider).pendingConfirmationsCount();
});

final labPickupsProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.read(dashboardServiceProvider).labPickupsCount();
});

final unpaidInvoicesProvider =
    StreamProvider.autoDispose<({int count, num amount})>((ref) {
  return ref.read(dashboardServiceProvider).unpaidInvoicesSummary();
});

final todayCollectionsProvider = StreamProvider.autoDispose<num>((ref) {
  return ref.read(dashboardServiceProvider).todayCollections();
});

// ----------------------------------------------------------------
// Patient providers
// ----------------------------------------------------------------

final patientDocProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, uid) {
  if (uid.isEmpty) return const Stream.empty();
  return ref.read(dashboardServiceProvider).streamPatient(uid);
});

final patientSearchProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, query) {
  return ref.read(dashboardServiceProvider).searchPatients(query);
});

// ----------------------------------------------------------------
// Routed to doctor
// ----------------------------------------------------------------

final routedToDoctorProvider =
    StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  final db = FirebaseFirestore.instance;
  return db
      .collection('appointmentRequests')
      .where('status', isEqualTo: 'approved')
      .where('assignedAppointmentId', isNull: false)
      .snapshots()
      .asyncMap((reqSnap) async {
    final ids = reqSnap.docs
        .map((d) => d.data()['assignedAppointmentId'])
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) return <AppointmentModel>[];

    final out = <AppointmentModel>[];
    for (var i = 0; i < ids.length; i += 30) {
      final end = (i + 30).clamp(0, ids.length);
      final chunk = ids.sublist(i, end);
      final snap = await db
          .collection('appointments')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      out.addAll(snap.docs
          .map((d) => AppointmentModel.fromMap(d.id, d.data()))
          .where((a) =>
              a.status == AppointmentStatus.booked ||
              a.status == AppointmentStatus.awaitingConfirmation ||
              a.status == AppointmentStatus.confirmed ||
              a.status == AppointmentStatus.onHold));
    }

    out.sort((a, b) => b.slot.compareTo(a.slot));
    return out;
  });
});

// ----------------------------------------------------------------
// Derived providers — today summary, by-doctor, slot-load, past-due
// ----------------------------------------------------------------

class TodaySummary {
  final int total;
  final int confirmed;
  final int pendingConfirmation;
  final int checkedIn;
  final int completed;
  final int inConsult;
  final int cancelled;
  final int noShow;

  const TodaySummary({
    this.total = 0,
    this.confirmed = 0,
    this.pendingConfirmation = 0,
    this.checkedIn = 0,
    this.completed = 0,
    this.inConsult = 0,
    this.cancelled = 0,
    this.noShow = 0,
  });

  int get active => total - cancelled - noShow;
}

final todaySummaryProvider = Provider<AsyncValue<TodaySummary>>((ref) {
  final async = ref.watch(todayAppointmentsProvider);
  return async.whenData((list) {
    var confirmed = 0, pending = 0, checkedIn = 0, completed = 0;
    var inConsult = 0, cancelled = 0, noShow = 0;
    for (final a in list) {
      switch (a.status) {
        case AppointmentStatus.confirmed:
          confirmed++;
          break;
        case AppointmentStatus.awaitingConfirmation:
        case AppointmentStatus.booked:
          pending++;
          break;
        case AppointmentStatus.checkedIn:
          checkedIn++;
          break;
        case AppointmentStatus.inConsult:
          inConsult++;
          break;
        case AppointmentStatus.completed:
          completed++;
          break;
        case AppointmentStatus.cancelled:
          cancelled++;
          break;
        case AppointmentStatus.noShow:
          noShow++;
          break;
        case AppointmentStatus.onHold:
        case AppointmentStatus.declined:
          break;
      }
    }
    return TodaySummary(
      total: list.length,
      confirmed: confirmed,
      pendingConfirmation: pending,
      checkedIn: checkedIn,
      completed: completed,
      inConsult: inConsult,
      cancelled: cancelled,
      noShow: noShow,
    );
  });
});

class DoctorDayStat {
  final String doctorDocId;
  final String doctorName;
  final int total;
  final int done;
  final int inQueue;
  final int onHold;

  const DoctorDayStat({
    required this.doctorDocId,
    required this.doctorName,
    required this.total,
    required this.done,
    required this.inQueue,
    required this.onHold,
  });
}

final todayByDoctorProvider =
    Provider<AsyncValue<List<DoctorDayStat>>>((ref) {
  final async = ref.watch(todayAppointmentsProvider);
  return async.whenData((list) {
    final names = <String, String>{};
    final counts = <String, ({int total, int done, int q, int hold})>{};

    for (final a in list) {
      names[a.doctorDocId] = a.doctorName;
      final c = counts[a.doctorDocId] ??
          (total: 0, done: 0, q: 0, hold: 0);
      counts[a.doctorDocId] = (
        total: c.total + 1,
        done: c.done +
            (a.status == AppointmentStatus.completed ||
                    a.status == AppointmentStatus.inConsult
                ? 1
                : 0),
        q: c.q +
            (a.status == AppointmentStatus.checkedIn ||
                    a.status == AppointmentStatus.confirmed ||
                    a.status == AppointmentStatus.booked
                ? 1
                : 0),
        hold: c.hold + (a.status == AppointmentStatus.onHold ? 1 : 0),
      );
    }

    return counts.entries.map((e) {
      final c = e.value;
      return DoctorDayStat(
        doctorDocId: e.key,
        doctorName: names[e.key] ?? 'Doctor',
        total: c.total,
        done: c.done,
        inQueue: c.q,
        onHold: c.hold,
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  });
});

class SlotLoad {
  final String period;
  final int booked;
  final int capacity;
  const SlotLoad(this.period, this.booked, this.capacity);
  double get ratio => capacity == 0 ? 0 : (booked / capacity).clamp(0, 1);
}

final todaySlotLoadProvider =
    Provider<AsyncValue<List<SlotLoad>>>((ref) {
  final async = ref.watch(todayAppointmentsProvider);
  return async.whenData((list) {
    final counts = <String, int>{
      'morning': 0,
      'afternoon': 0,
      'evening': 0
    };
    for (final a in list) {
      if (a.status == AppointmentStatus.cancelled ||
          a.status == AppointmentStatus.declined) {
        continue;
      }
      final p = a.slotPeriod ?? 'morning';
      counts[p] = (counts[p] ?? 0) + 1;
    }
    return counts.entries
        .map((e) => SlotLoad(e.key, e.value, kSlotsPerPeriod))
        .toList();
  });
});

final pastDueAppointmentsProvider =
    Provider<AsyncValue<List<AppointmentModel>>>((ref) {
  final async = ref.watch(todayAppointmentsProvider);
  return async.whenData((list) {
    final now = DateTime.now();
    return list
        .where((a) =>
            a.slot.isBefore(now) &&
            (a.status == AppointmentStatus.booked ||
                a.status == AppointmentStatus.confirmed))
        .toList();
  });
});