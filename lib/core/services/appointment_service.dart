import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/appointment_model.dart';

class AppointmentService {
  final _db = FirebaseFirestore.instance;

  // -----------------------------------------------------------------
  // Token generation — resets per doctor per day per slot period
  // -----------------------------------------------------------------
  Future<({int number, String label})> _nextToken({
    required String doctorDocId,
    required String doctorInitial,
    required DateTime slot,
    required String slotPeriod,
  }) async {
    final dayKey =
        '${slot.year}${slot.month.toString().padLeft(2, '0')}${slot.day.toString().padLeft(2, '0')}';

    // Key includes slotPeriod so morning / afternoon / evening counters
    // reset independently.
    final counterRef = _db
        .collection('counters')
        .doc('token_${doctorDocId}_${dayKey}_$slotPeriod');

    return _db.runTransaction((tx) async {
      final snap = await tx.get(counterRef);
      int current = 0;
      if (snap.exists) {
        current = (snap.data()?['count'] ?? 0) as int;
      }
      final next = current + 1;
      tx.set(
        counterRef,
        {
          'count': next,
          'day': dayKey,
          'slotPeriod': slotPeriod,
          'doctorDocId': doctorDocId,
        },
        SetOptions(merge: true),
      );
      return (
        number: next,
        label:
            '${doctorInitial.toUpperCase()}-${next.toString().padLeft(3, '0')}',
      );
    });
  }

  Future<String> _nextAppointmentCode() async {
    final year = DateTime.now().year;
    final ref = _db.collection('counters').doc('appointment_$year');
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      int current = 0;
      if (snap.exists) current = (snap.data()?['count'] ?? 0) as int;
      final next = current + 1;
      tx.set(ref, {'count': next, 'year': year}, SetOptions(merge: true));
      return 'APT-$year-${next.toString().padLeft(4, '0')}';
    });
  }

  // -----------------------------------------------------------------
  // Book
  // -----------------------------------------------------------------
  Future<AppointmentModel> bookAppointment({
    required String clinicId,
    required String patientDocId,
    required String patientId,
    required String patientName,
    required String patientPhone,
    required String doctorDocId,
    required String doctorName,
    required DateTime slot,
    required String slotPeriod, // "morning" | "afternoon" | "evening"
    String? chiefComplaint,
    String type = 'in_person',
  }) async {
    final code = await _nextAppointmentCode();
    final doctorInitial = doctorName.isNotEmpty
        ? doctorName.trim().split(' ').last[0]
        : 'D';
    final token = await _nextToken(
      doctorDocId: doctorDocId,
      doctorInitial: doctorInitial,
      slot: slot,
      slotPeriod: slotPeriod,
    );

    final slotKey = AppointmentModel.makeSlotKey(slot, slotPeriod);

    // Count only appointments inside the same slot.
    final ahead = await _db
        .collection('appointments')
        .where('slotKey', isEqualTo: slotKey)
        .where('status', whereIn: ['booked', 'confirmed', 'checkedIn'])
        .get();

    final docRef = _db.collection('appointments').doc();
    final appt = AppointmentModel(
      docId: docRef.id,
      appointmentCode: code,
      clinicId: clinicId,
      patientDocId: patientDocId,
      patientId: patientId,
      patientName: patientName,
      patientPhone: patientPhone,
      doctorDocId: doctorDocId,
      doctorName: doctorName,
      slot: slot,
      slotPeriod: slotPeriod,
      slotKey: slotKey,
      tokenNumber: token.number,
      tokenLabel: token.label,
      queuePosition: ahead.size + 1,
      status: AppointmentStatus.booked,
      chiefComplaint: chiefComplaint,
      type: type,
      createdAt: DateTime.now(),
    );

    await docRef.set(appt.toMap());
    return appt;
  }

  // -----------------------------------------------------------------
  // Status updates
  // -----------------------------------------------------------------
  Future<void> updateStatus(
      String docId, AppointmentStatus status) async {
    final data = <String, dynamic>{'status': status.name};

    switch (status) {
      case AppointmentStatus.checkedIn:
        data['checkedInAt'] = FieldValue.serverTimestamp();
        break;
      case AppointmentStatus.inConsult:
        data['consultStartedAt'] = FieldValue.serverTimestamp();
        break;
      case AppointmentStatus.completed:
        data['consultEndedAt'] = FieldValue.serverTimestamp();
        break;
      default:
        break;
    }

    await _db.collection('appointments').doc(docId).update(data);
  }

  /// Convenience wrapper for the receptionist's "Check In" button.
  Future<void> checkIn(String docId) =>
      updateStatus(docId, AppointmentStatus.checkedIn);

  Future<void> confirmAppointment(String docId) async {
    await _db.collection('appointments').doc(docId).update({
      'status': AppointmentStatus.confirmed.name,
      'confirmedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> declineAppointment(String docId, {String? reason}) async {
    await _db.collection('appointments').doc(docId).update({
      'status': AppointmentStatus.declined.name,
      'declinedAt': FieldValue.serverTimestamp(),
      'declineReason': reason,
    });
  }

  Future<void> cancelAppointment(String docId, {String? reason}) async {
    await _db.collection('appointments').doc(docId).update({
      'status': AppointmentStatus.cancelled.name,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': 'patient',
      'cancelReason': reason,
    });
  }

  Future<void> markConfirmationRequested(String docId) async {
    await _db
        .collection('appointments')
        .doc(docId)
        .update({'confirmationRequested': true});
  }

  // -----------------------------------------------------------------
  // Receptionist control actions
  // -----------------------------------------------------------------

  /// Receptionist requests confirmation — status becomes awaitingConfirmation.
  Future<void> requestConfirmation(String docId) async {
    await _db.collection('appointments').doc(docId).update({
      'status': AppointmentStatus.awaitingConfirmation.name,
      'confirmationRequested': true,
      'confirmationRequestedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Puts an appointment on hold.
  Future<void> holdAppointment(String docId, {String? reason}) async {
    await _db.collection('appointments').doc(docId).update({
      'status': AppointmentStatus.onHold.name,
      'holdReason': reason,
      'heldAt': FieldValue.serverTimestamp(),
    });
  }

Future<void> startConsult(String appointmentDocId) async {
  await FirebaseFirestore.instance
      .collection('appointments')
      .doc(appointmentDocId)
      .update({
    'status': AppointmentStatus.inConsult.name,
    'consultStartedAt': FieldValue.serverTimestamp(),
  });
}

  Future<void> completeConsultation({
  required String appointmentDocId,
  required double fees,
  required String doctorUid,
}) async {
  if (fees < 0) throw ArgumentError('Fees cannot be negative');
  await FirebaseFirestore.instance
      .collection('appointments')
      .doc(appointmentDocId)
      .update({
    'status': AppointmentStatus.completed.name,
    'consultEndedAt': FieldValue.serverTimestamp(),
    'consultationFees': fees,
    'feesSetByDoctorId': doctorUid,
    'paymentStatus': PaymentStatus.unpaid.name,
  });
}

Future<void> markFeesPaid({
  required String appointmentDocId,
  required String collectedByUid,
}) async {
  await FirebaseFirestore.instance
      .collection('appointments')
      .doc(appointmentDocId)
      .update({
    'paymentStatus': PaymentStatus.paid.name,
    'feesPaidAt': FieldValue.serverTimestamp(),
    'feesCollectedByUid': collectedByUid,
  });
}

  Future<void> waiveFees({
  required String appointmentDocId,
  required String collectedByUid,
}) async {
  await FirebaseFirestore.instance
      .collection('appointments')
      .doc(appointmentDocId)
      .update({
    'paymentStatus': PaymentStatus.waived.name,
    'feesPaidAt': FieldValue.serverTimestamp(),
    'feesCollectedByUid': collectedByUid,
  });
}

  /// Resumes a held appointment.
  Future<void> resumeAppointment(String docId) async {
    await _db.collection('appointments').doc(docId).update({
      'status': AppointmentStatus.booked.name,
      'resumedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reschedules — moves to a new slot.
  Future<void> rescheduleAppointment({
    required String docId,
    required DateTime newSlot,
    required String newSlotPeriod,
    String? reason,
    bool resetConfirmation = true,
  }) async {
    final docRef = _db.collection('appointments').doc(docId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw Exception('Appointment not found');
    }
    final current = AppointmentModel.fromMap(snap.id, snap.data()!);

    final newSlotKey =
        AppointmentModel.makeSlotKey(newSlot, newSlotPeriod);

    // Reissue token when the slot period or day changes.
    int? newTokenNumber;
    String? newTokenLabel;
    if (current.slotPeriod != newSlotPeriod ||
        !_isSameDay(current.slot, newSlot)) {
      final doctorInitial = current.doctorName.isNotEmpty
          ? current.doctorName.trim().split(' ').last[0]
          : 'D';
      final token = await _nextToken(
        doctorDocId: current.doctorDocId,
        doctorInitial: doctorInitial,
        slot: newSlot,
        slotPeriod: newSlotPeriod,
      );
      newTokenNumber = token.number;
      newTokenLabel = token.label;
    }

    final data = <String, dynamic>{
      'slot': Timestamp.fromDate(newSlot),
      'slotPeriod': newSlotPeriod,
      'slotKey': newSlotKey,
      'rescheduledAt': FieldValue.serverTimestamp(),
      'rescheduledReason': reason,
    };
    if (newTokenNumber != null) {
      data['tokenNumber'] = newTokenNumber;
      data['tokenLabel'] = newTokenLabel;
    }
    if (resetConfirmation) {
      data['status'] = AppointmentStatus.awaitingConfirmation.name;
      data['confirmationRequested'] = true;
      data['confirmationRequestedAt'] = FieldValue.serverTimestamp();
      data['confirmedAt'] = null;
    }

    await docRef.update(data);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;


  /// Staff-initiated cancellation (as opposed to patient-initiated).
  Future<void> cancelByStaff(String docId, {String? reason}) async {
    await _db.collection('appointments').doc(docId).update({
      'status': AppointmentStatus.cancelled.name,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': 'staff',
      'cancelReason': reason,
    });
  }

  /// Marks the appointment as a no-show.
  Future<void> markNoShow(String docId) async {
    await _db.collection('appointments').doc(docId).update({
      'status': AppointmentStatus.noShow.name,
      'noShowAt': FieldValue.serverTimestamp(),
    });
  }




  // -----------------------------------------------------------------
  // Streams
  // -----------------------------------------------------------------
  Stream<List<AppointmentModel>> watchDoctorQueue({
    required String doctorDocId,
    required DateTime date,
  }) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    return _db
        .collection('appointments')
        .where('doctorDocId', isEqualTo: doctorDocId)
        .where('slot', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('slot', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => AppointmentModel.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) {
        final order = {
          AppointmentStatus.inConsult: 0,
          AppointmentStatus.checkedIn: 1,
          AppointmentStatus.confirmed: 2,
          AppointmentStatus.booked: 3,
          AppointmentStatus.completed: 4,
          AppointmentStatus.cancelled: 5,
          AppointmentStatus.declined: 6,
          AppointmentStatus.noShow: 7,
        };
        final c =
            (order[a.status] ?? 9).compareTo(order[b.status] ?? 9);
        if (c != 0) return c;
        return a.tokenNumber.compareTo(b.tokenNumber);
      });
      return list;
    });
  }

  /// All live appointments inside one (doctor, day, period) slot.
  /// Cancelled, declined, and no-show are excluded.
  /// Sorted by check-in time for FCFS; unchecked-in fall back to token order.
  Stream<List<AppointmentModel>> watchSlotQueue({
    required String doctorDocId,
    required String slotKey,
  }) {
    return _db
        .collection('appointments')
        .where('doctorDocId', isEqualTo: doctorDocId)
        .where('slotKey', isEqualTo: slotKey)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => AppointmentModel.fromMap(d.id, d.data()))
          .where((a) =>
              a.status != AppointmentStatus.cancelled &&
              a.status != AppointmentStatus.declined &&
              a.status != AppointmentStatus.noShow)
          .toList();

      list.sort((a, b) {
        // In-consult always first
        if (a.status == AppointmentStatus.inConsult) return -1;
        if (b.status == AppointmentStatus.inConsult) return 1;

        // Then checked-in, by arrival time
        final at = a.checkedInAt;
        final bt = b.checkedInAt;
        if (at != null && bt != null) return at.compareTo(bt);
        if (at != null) return -1;
        if (bt != null) return 1;

        // Remaining fall back to token order (booking order)
        return a.tokenNumber.compareTo(b.tokenNumber);
      });
      return list;
    });
  }

  Stream<List<AppointmentModel>> watchPatientAppointments(
      String patientDocId) {
    return _db
        .collection('appointments')
        .where('patientDocId', isEqualTo: patientDocId)
        .orderBy('slot', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => AppointmentModel.fromMap(d.id, d.data()))
            .toList());
  }

  Stream<AppointmentModel?> watchCurrentlyInConsult(String doctorDocId) {
    return _db
        .collection('appointments')
        .where('doctorDocId', isEqualTo: doctorDocId)
        .where('status', isEqualTo: 'inConsult')
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isEmpty
            ? null
            : AppointmentModel.fromMap(
                s.docs.first.id, s.docs.first.data()));
  }

  Stream<AppointmentModel?> watchOne(String docId) {
    return _db
        .collection('appointments')
        .doc(docId)
        .snapshots()
        .map((d) =>
            d.exists ? AppointmentModel.fromMap(d.id, d.data()!) : null);
  }

 Stream<List<AppointmentModel>> searchUpcoming(String query) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 30));

    return _db
        .collection('appointments')
        .where('slot', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('slot', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) {
      final q = query.trim().toLowerCase();
      final list = snap.docs
          .map((d) => AppointmentModel.fromMap(d.id, d.data()))
          .where((a) {
        if (a.status == AppointmentStatus.cancelled ||
            a.status == AppointmentStatus.declined ||
            a.status == AppointmentStatus.noShow ||
            a.status == AppointmentStatus.completed) {
          return false;
        }
        if (q.isEmpty) return true;
        return a.patientName.toLowerCase().contains(q) ||
            a.patientPhone.toLowerCase().contains(q) ||
            a.patientId.toLowerCase().contains(q) ||
            a.tokenLabel.toLowerCase().contains(q) ||
            a.appointmentCode.toLowerCase().contains(q);
      }).toList();

      list.sort((a, b) => a.slot.compareTo(b.slot));
      return list;
    });
  }


  Stream<List<AppointmentModel>> watchClinicAppointments({
    required DateTime date,
  }) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    return _db
        .collection('appointments')
        .where('slot', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('slot', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => AppointmentModel.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) => a.slot.compareTo(b.slot));
      return list;
    });
  }
}