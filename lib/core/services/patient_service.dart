import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/patient_model.dart';

class PatientService {
  final _db = FirebaseFirestore.instance;

  /// Generates a human-readable patient ID using an atomic transaction.
  /// Format: PT-YYYY-NNNN (resets every year).
  Future<String> _nextPatientId() async {
    final year = DateTime.now().year;
    final counterRef = _db.collection('counters').doc('patient_$year');

    return await _db.runTransaction<String>((tx) async {
      final snap = await tx.get(counterRef);
      int current = 0;
      if (snap.exists) {
        current = (snap.data()?['count'] ?? 0) as int;
      }
      final next = current + 1;
      tx.set(
        counterRef,
        {'count': next, 'year': year},
        SetOptions(merge: true),
      );
      return 'PT-$year-${next.toString().padLeft(4, '0')}';
    });
  }

  /// Add patient — generates a new patientId first, then writes.
  Future<PatientModel> addPatient(PatientModel patient) async {
    final patientId = await _nextPatientId();
    final docRef = _db.collection('patients').doc();

    final withId = PatientModel(
      docId: docRef.id,
      patientId: patientId,
      fullName: patient.fullName,
      phone: patient.phone,
      email: patient.email,
      gender: patient.gender,
      dob: patient.dob,
      bloodGroup: patient.bloodGroup,
      maritalStatus: patient.maritalStatus,
      occupation: patient.occupation,
      address: patient.address,
      city: patient.city,
      pincode: patient.pincode,
      emergencyContactName: patient.emergencyContactName,
      emergencyContactPhone: patient.emergencyContactPhone,
      referredBy: patient.referredBy,
      allergies: patient.allergies,
      chronicConditions: patient.chronicConditions,
      currentMedicationNotes: patient.currentMedicationNotes,
      currentMedications: patient.currentMedications,
      pastMedicalHistory: patient.pastMedicalHistory,
      pastSurgeries: patient.pastSurgeries,
      pastTreatments: patient.pastTreatments,
      smoking: patient.smoking,
      alcohol: patient.alcohol,
      diet: patient.diet,
      activityLevel: patient.activityLevel,
      doctorNotes: patient.doctorNotes,
      clinicId: patient.clinicId,
      primaryDoctorId: patient.primaryDoctorId,
      primaryDoctorName: patient.primaryDoctorName,
      createdByUserId: patient.createdByUserId,
      active: patient.active,
    );

    await docRef.set(withId.toMap());
    return withId;
  }

  Future<void> updatePatient(PatientModel patient) async {
    await _db
        .collection('patients')
        .doc(patient.docId)
        .update(patient.toMap());
  }

  Future<PatientModel?> getPatientByDocId(String docId) async {
    final doc = await _db.collection('patients').doc(docId).get();
    if (!doc.exists) return null;
    return PatientModel.fromMap(doc.id, doc.data()!);
  }

  Future<PatientModel?> getPatientByPatientId(String patientId) async {
    final snap = await _db
        .collection('patients')
        .where('patientId', isEqualTo: patientId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return PatientModel.fromMap(snap.docs.first.id, snap.docs.first.data());
  }

  /// Search within a clinic — by name prefix or by patientId.
  Future<List<PatientModel>> search(
    String query, {
    required String clinicId,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    // Exact match on patientId (e.g. PT-2026-0001)
    if (q.toUpperCase().startsWith('PT-')) {
      final snap = await _db
          .collection('patients')
          .where('clinicId', isEqualTo: clinicId)
          .where('patientId', isEqualTo: q.toUpperCase())
          .limit(10)
          .get();
      return snap.docs
          .map((d) => PatientModel.fromMap(d.id, d.data()))
          .toList();
    }

    // Prefix search on full name
    final snap = await _db
        .collection('patients')
        .where('clinicId', isEqualTo: clinicId)
        .orderBy('fullName')
        .startAt([q])
        .endAt(['$q\uf8ff'])
        .limit(20)
        .get();
    return snap.docs
        .map((d) => PatientModel.fromMap(d.id, d.data()))
        .toList();
  }

  /// Live list of patients for a specific clinic.
  Stream<List<PatientModel>> watchPatients({
    required String clinicId,
    int limit = 100,
  }) {
    return _db
        .collection('patients')
        .where('clinicId', isEqualTo: clinicId)
        .where('active', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map((d) => PatientModel.fromMap(d.id, d.data()))
            .toList());
  }

Stream<List<Map<String, dynamic>>> searchInClinic({
  required String clinicId,
  required String query,
}) {
  final q = query.trim();
  if (q.isEmpty) return const Stream.empty();
  return FirebaseFirestore.instance
      .collection('patients')
      .where('clinicId', isEqualTo: clinicId)
      .where('fullName', isGreaterThanOrEqualTo: q)
      .where('fullName', isLessThan: '$q\uf8ff')
      .limit(20)
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'docId': d.id, ...d.data()})
          .toList());
}
}

