import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment_model.dart';

class ReceptionStatsService {
  final _db = FirebaseFirestore.instance;

  // ---------------------------------------------------------------
  // Today's appointments, grouped many ways
  // ---------------------------------------------------------------
  Stream<List<AppointmentModel>> todayAll() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return _db
        .collection('appointments')
        .where('slot', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('slot', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((s) => s.docs
            .map((d) => AppointmentModel.fromMap(d.id, d.data()))
            .toList());
  }

  // ---------------------------------------------------------------
  // Invoice + consultation-fee stats
  // ---------------------------------------------------------------
  //
  // Four sources feed this stat:
  //
  //   1. `invoices` issued TODAY whose `amountPaid` > 0
  //      → contribute to "Collected".
  //   2. `appointments` with `consultEndedAt` TODAY and
  //      `paymentStatus == paid` → contribute to "Collected".
  //   3. `invoices` with status in {draft, issued} — ALL TIME
  //      → contribute to "Unpaid".
  //   4. `appointments` with `paymentStatus == unpaid` — ALL TIME
  //      → contribute to "Unpaid".
  //
  // The key behavioural change from earlier versions: unpaid
  // amounts are NOT date-filtered, so a fee or invoice that
  // becomes owed yesterday and is not paid today stays visible
  // until the receptionist marks it paid (or waives it). Only
  // "Collected" resets at midnight — because collections are
  // today's cash, but debts persist.
  //
  // All four queries are single-field. No composite index needed.
  Stream<InvoiceDayStats> todayInvoices() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    // 1. Paid invoices today (Collected).
    final paidInvoicesStream = _db
        .collection('invoices')
        .where('issuedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('issuedAt', isLessThan: Timestamp.fromDate(end))
        .snapshots();

    // 2. Paid consultation fees today (Collected).
    final paidFeesStream = _db
        .collection('appointments')
        .where('consultEndedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('consultEndedAt', isLessThan: Timestamp.fromDate(end))
        .snapshots();

    // 3. Unpaid invoices — all time (Unpaid).
    final unpaidInvoicesStream = _db
        .collection('invoices')
        .where('status', whereIn: ['draft', 'issued'])
        .snapshots();

    // 4. Unpaid consultation fees — all time (Unpaid).
    final unpaidFeesStream = _db
        .collection('appointments')
        .where('paymentStatus', isEqualTo: PaymentStatus.unpaid.name)
        .snapshots();

    return _combineStats(
      paidInvoicesStream,
      paidFeesStream,
      unpaidInvoicesStream,
      unpaidFeesStream,
    );
  }

  // ---------------------------------------------------------------
  // Search — patient by name / phone / ID, then their history
  // ---------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> searchPatients(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return const Stream.empty();

    // Firestore can't do case-insensitive contains, so fetch a page and
    // filter client-side. For a clinic-sized patient list this is fine.
    return _db
        .collection('patients')
        .limit(300)
        .snapshots()
        .map((s) => s.docs
            .map((d) => <String, dynamic>{'docId': d.id, ...d.data()})
            .where((p) {
              final name = '${p['fullName'] ?? ''}'.toLowerCase();
              final phone = '${p['phone'] ?? ''}'.toLowerCase();
              final pid = '${p['patientId'] ?? ''}'.toLowerCase();
              return name.contains(query) ||
                  phone.contains(query) ||
                  pid.contains(query);
            })
            .toList());
  }

  Stream<List<AppointmentModel>> patientAppointments(String patientDocId) {
    return _db
        .collection('appointments')
        .where('patientDocId', isEqualTo: patientDocId)
        .orderBy('slot', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => AppointmentModel.fromMap(d.id, d.data()))
            .toList());
  }
}

// ---------------------------------------------------------------
// Merge four snapshot streams and derive the stats.
// Emits only when ALL four have delivered at least once, so the
// badge never flickers to a partial value.
// ---------------------------------------------------------------
Stream<InvoiceDayStats> _combineStats(
  Stream<QuerySnapshot<Map<String, dynamic>>> paidInvoices,
  Stream<QuerySnapshot<Map<String, dynamic>>> paidFees,
  Stream<QuerySnapshot<Map<String, dynamic>>> unpaidInvoices,
  Stream<QuerySnapshot<Map<String, dynamic>>> unpaidFees,
) {
  final paidInvCtl =
      StreamController<QuerySnapshot<Map<String, dynamic>>>();
  final paidFeeCtl =
      StreamController<QuerySnapshot<Map<String, dynamic>>>();
  final unpaidInvCtl =
      StreamController<QuerySnapshot<Map<String, dynamic>>>();
  final unpaidFeeCtl =
      StreamController<QuerySnapshot<Map<String, dynamic>>>();

  QuerySnapshot<Map<String, dynamic>>? paidInvSnap;
  QuerySnapshot<Map<String, dynamic>>? paidFeeSnap;
  QuerySnapshot<Map<String, dynamic>>? unpaidInvSnap;
  QuerySnapshot<Map<String, dynamic>>? unpaidFeeSnap;

  late StreamController<InvoiceDayStats> out;
  bool paidInvSeen = false;
  bool paidFeeSeen = false;
  bool unpaidInvSeen = false;
  bool unpaidFeeSeen = false;

  void emit() {
    if (!paidInvSeen || !paidFeeSeen || !unpaidInvSeen || !unpaidFeeSeen) {
      return;
    }
    if (paidInvSnap == null ||
        paidFeeSnap == null ||
        unpaidInvSnap == null ||
        unpaidFeeSnap == null) {
      return;
    }
    out.add(_stats(
      paidInvoices: paidInvSnap!,
      paidFees: paidFeeSnap!,
      unpaidInvoices: unpaidInvSnap!,
      unpaidFees: unpaidFeeSnap!,
    ));
  }

  out = StreamController<InvoiceDayStats>(
    onListen: () {
      paidInvCtl.stream.listen((s) {
        paidInvSnap = s;
        paidInvSeen = true;
        emit();
      }, onError: out.addError);

      paidFeeCtl.stream.listen((s) {
        paidFeeSnap = s;
        paidFeeSeen = true;
        emit();
      }, onError: out.addError);

      unpaidInvCtl.stream.listen((s) {
        unpaidInvSnap = s;
        unpaidInvSeen = true;
        emit();
      }, onError: out.addError);

      unpaidFeeCtl.stream.listen((s) {
        unpaidFeeSnap = s;
        unpaidFeeSeen = true;
        emit();
      }, onError: out.addError);

      paidInvoices.listen(paidInvCtl.add, onError: paidInvCtl.addError);
      paidFees.listen(paidFeeCtl.add, onError: paidFeeCtl.addError);
      unpaidInvoices.listen(unpaidInvCtl.add, onError: unpaidInvCtl.addError);
      unpaidFees.listen(unpaidFeeCtl.add, onError: unpaidFeeCtl.addError);
    },
    onCancel: () async {
      await paidInvCtl.close();
      await paidFeeCtl.close();
      await unpaidInvCtl.close();
      await unpaidFeeCtl.close();
    },
  );

  return out.stream;
}

InvoiceDayStats _stats({
  required QuerySnapshot<Map<String, dynamic>> paidInvoices,
  required QuerySnapshot<Map<String, dynamic>> paidFees,
  required QuerySnapshot<Map<String, dynamic>> unpaidInvoices,
  required QuerySnapshot<Map<String, dynamic>> unpaidFees,
}) {
  int unpaidCount = 0;
  double unpaidAmount = 0;
  double collected = 0;

  // ── Collected: paid invoices today ──
  for (final d in paidInvoices.docs) {
    final m = d.data();
    final paid = (m['amountPaid'] as num?)?.toDouble() ?? 0;
    if (paid > 0) collected += paid;
  }

  // ── Collected: appointment fees paid today ──
  for (final d in paidFees.docs) {
    final m = d.data();
    final fees = (m['consultationFees'] as num?)?.toDouble() ?? 0;
    if (fees <= 0) continue;
    final status = '${m['paymentStatus'] ?? 'unpaid'}'.toLowerCase();
    if (status == 'paid') collected += fees;
  }

  // ── Unpaid: all invoices with outstanding balance ──
  for (final d in unpaidInvoices.docs) {
    final m = d.data();
    final status = '${m['status'] ?? ''}';
    if (status != 'draft' && status != 'issued') continue;
    final total = (m['total'] as num?)?.toDouble() ?? 0;
    final paid = (m['amountPaid'] as num?)?.toDouble() ?? 0;
    final outstanding = (total - paid).clamp(0, double.infinity);
    if (outstanding > 0) {
      unpaidCount++;
      unpaidAmount += outstanding;
    }
  }

  // ── Unpaid: all appointment fees with paymentStatus == unpaid ──
  for (final d in unpaidFees.docs) {
    final m = d.data();
    final fees = (m['consultationFees'] as num?)?.toDouble() ?? 0;
    if (fees <= 0) continue;
    final status = '${m['paymentStatus'] ?? 'unpaid'}'.toLowerCase();
    if (status == 'unpaid') {
      unpaidCount++;
      unpaidAmount += fees;
    }
    // 'waived' → neither bucket.
  }

  return InvoiceDayStats(
    unpaidCount: unpaidCount,
    unpaidAmount: unpaidAmount,
    collectedAmount: collected,
  );
}

class InvoiceDayStats {
  final int unpaidCount;
  final double unpaidAmount;
  final double collectedAmount;
  const InvoiceDayStats({
    required this.unpaidCount,
    required this.unpaidAmount,
    required this.collectedAmount,
  });
}

final receptionStatsServiceProvider =
    Provider<ReceptionStatsService>((ref) => ReceptionStatsService());

final todayAllAppointmentsProvider =
    StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  return ref.watch(receptionStatsServiceProvider).todayAll();
});

final todayInvoiceStatsProvider =
    StreamProvider.autoDispose<InvoiceDayStats>((ref) {
  return ref.watch(receptionStatsServiceProvider).todayInvoices();
});

final patientSearchProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, q) {
  return ref.watch(receptionStatsServiceProvider).searchPatients(q);
});

final patientAppointmentsProvider = StreamProvider.autoDispose
    .family<List<AppointmentModel>, String>((ref, patientDocId) {
  return ref
      .watch(receptionStatsServiceProvider)
      .patientAppointments(patientDocId);
});