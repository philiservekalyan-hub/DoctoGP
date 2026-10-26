// lib/core/services/consultation_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/appointment_model.dart';
import '../models/consultation_model.dart';

class ConsultationService {
  final _col = FirebaseFirestore.instance.collection('consultations');

  /// Watch a single consult record, keyed by appointment doc id.
  Stream<ConsultationModel?> watchByAppointment(String appointmentId) {
    return _col.doc(appointmentId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return ConsultationModel.fromMap(snap.id, snap.data() ?? {});
    });
  }

  /// Create-or-update the draft for this appointment.
  Future<void> upsertDraft({
    required AppointmentModel appointment,
    required String doctorName,
    String? chiefComplaint,
    String? symptoms,
    String? diagnosis,
    String? diagnosisCode,   
    String? diagnosisText,   
    String? notes,
    String? rx,
    String? followUpPlan,
    List<Medication> medications = const [],
    String? disposition,     
    Map<String, String>? vitals,
    DateTime? endedAt,
  }) async {
    final ref = _col.doc(appointment.docId);
    final snap = await ref.get();

    final data = <String, dynamic>{
      'appointmentId': appointment.docId,
      'patientDocId': appointment.patientDocId,
      'patientId': appointment.patientId,
      'patientName': appointment.patientName,
      'doctorDocId': appointment.doctorDocId,
      'doctorName': doctorName,
      'clinicId': appointment.clinicId,
      'chiefComplaint': chiefComplaint ?? appointment.chiefComplaint,
      'symptoms': symptoms,
      'diagnosis': diagnosis,
      'diagnosisCode': diagnosisCode,   
      'diagnosisText': diagnosisText,   
      'medications': medications.map((m) => m.toMap()).toList(),
      'notes': notes,
      'rx': rx,
      'followUpPlan': followUpPlan,
      'disposition': disposition,       
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (vitals != null) data['vitals'] = vitals;
    if (endedAt != null) data['endedAt'] = Timestamp.fromDate(endedAt);

    if (!snap.exists) {
      data['createdAt'] = FieldValue.serverTimestamp();
      data['startedAt'] = FieldValue.serverTimestamp();
      data['labOrderIds'] = <String>[];
    }

    await ref.set(data, SetOptions(merge: true));
  }

  /// Adds an order id to the consult's labOrderIds (idempotent).
  Future<void> appendLabOrderId({
    required String appointmentId,
    required String orderId,
  }) async {
    final ref = _col.doc(appointmentId);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'appointmentId': appointmentId,
        'labOrderIds': [orderId],
        'startedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }
    await ref.update({
      'labOrderIds': FieldValue.arrayUnion([orderId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}