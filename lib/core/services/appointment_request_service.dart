import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/appointment_model.dart';
import '../models/appointment_request_model.dart';
import 'appointment_service.dart';

class AppointmentRequestService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AppointmentService _appointments = AppointmentService();

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('appointmentRequests');

  Future<String> createRequest({
    required String patientDocId,
    required String patientId,
    required String patientName,
    required String patientPhone,
    required String clinicId,
    required String reason,
    String? preferredTimeOfDay,
    List<String> preferredDates = const [],
    String kind = 'new',
  }) async {
    final ref = _col.doc();
    await ref.set({
      'patientDocId': patientDocId,
      'patientId': patientId,
      'patientName': patientName,
      'patientPhone': patientPhone,
      'clinicId': clinicId,
      'reason': reason,
      'preferredTimeOfDay': preferredTimeOfDay,
      'preferredDates': preferredDates,
      'kind': kind,
      'status': 'pending',
      'requestedAt': FieldValue.serverTimestamp(),
      'reviewedAt': null,
      'reviewedByUid': null,
      'assignedAppointmentId': null,
      'assignedDoctorDocId': null,
      'assignedDoctorName': null,
      'assignedSlot': null,
      'rejectionReason': null,
    });
    return ref.id;
  }

  Future<void> cancelRequest(String requestId, {String? reason}) async {
    await _col.doc(requestId).update({
      'status': 'cancelled',
      'rejectionReason': reason,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedByUid': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  Stream<List<AppointmentRequestModel>> watchPatientRequests(
      String patientDocId) {
    return _col
        .where('patientDocId', isEqualTo: patientDocId)
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => AppointmentRequestModel.fromMap(d.id, d.data()))
            .toList());
  }

  Stream<List<AppointmentRequestModel>> watchPendingRequests(
      {String? clinicId}) {
    Query<Map<String, dynamic>> q =
        _col.where('status', isEqualTo: 'pending');
    if (clinicId != null && clinicId.isNotEmpty) {
      q = q.where('clinicId', isEqualTo: clinicId);
    }
    return q.orderBy('requestedAt', descending: false).snapshots().map((s) =>
        s.docs
            .map((d) => AppointmentRequestModel.fromMap(d.id, d.data()))
            .toList());
  }

  
  Future<AppointmentModel> approveRequest({
    required AppointmentRequestModel request,
    required String doctorDocId,
    required String doctorName,
    required DateTime slot,
    required String slotPeriod,   
    String type = 'in_person',
  }) async {
    final appt = await _appointments.bookAppointment(
      clinicId: request.clinicId ?? '',
      patientDocId: request.patientDocId,
      patientId: request.patientId,
      patientName: request.patientName,
      patientPhone: request.patientPhone ?? '',
      doctorDocId: doctorDocId,
      doctorName: doctorName,
      slot: slot,
      slotPeriod: slotPeriod,     
      chiefComplaint: request.reason,
      type: type,
    );

    await _col.doc(request.docId).update({
      'status': 'approved',
      'assignedAppointmentId': appt.docId,
      'assignedDoctorDocId': doctorDocId,
      'assignedDoctorName': doctorName,
      'assignedSlot': Timestamp.fromDate(slot),
      'assignedSlotPeriod': slotPeriod,   
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedByUid': FirebaseAuth.instance.currentUser?.uid,
    });

    return appt;
  }


  Future<void> rejectRequest(String requestId, {String? reason}) async {
    await _col.doc(requestId).update({
      'status': 'rejected',
      'rejectionReason': reason,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedByUid': FirebaseAuth.instance.currentUser?.uid,
    });
  }
}