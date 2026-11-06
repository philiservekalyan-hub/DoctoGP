// lib/core/services/lab_customer_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/lab_customer_model.dart';
import '../models/patient_model.dart';
import 'package:flutter/foundation.dart';

class LabCustomerService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _customers =>
      _db.collection('labCustomers');

  CollectionReference<Map<String, dynamic>> get _clinics =>
      _db.collection('clinics');

  CollectionReference<Map<String, dynamic>> get _patients =>
      _db.collection('patients');

  // =================================================================
  // SCENARIO 1 & 2: clinic-linked patient → deterministic labCustomers doc
  // =================================================================

  /// Idempotent. If the same patient from the same clinic is seen again
  /// (whether via doctor referral or walk-in), the doc is updated, not
  /// duplicated.
  Future<LabCustomerModel> upsertClinicLinked({
    required String labClinicId,
    required String sourceClinicId,
    required String sourceClinicName,
    required String sourcePatientDocId,
    required String sourcePatientId,
    required String fullName,
    required String phone,
    required String gender,
    String? email,
    DateTime? dob,
    String? bloodGroup,
  }) async {
    final docId = LabCustomerModel.deterministicId(
      sourceClinicId: sourceClinicId,
      sourcePatientDocId: sourcePatientDocId,
    );
    final ref = _customers.doc(docId);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final snap = await ref.get();

    if (!snap.exists) {
      final model = LabCustomerModel(
        docId: docId,
        labClinicId: labClinicId,
        source: LabCustomerSource.clinicLinked,
        displayPatientId: sourcePatientId,
        fullName: fullName,
        phone: phone,
        email: email,
        gender: gender,
        dob: dob,
        bloodGroup: bloodGroup,
        sourceClinicId: sourceClinicId,
        sourceClinicName: sourceClinicName,
        sourcePatientDocId: sourcePatientDocId,
        sourcePatientId: sourcePatientId,
        createdByUid: uid,
        updatedByUid: uid,
      );
      await ref.set(model.toMap());
      return model;
    }

    // Refresh contact + identity fields from the source clinic.
    await ref.update({
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'gender': gender,
      'dob': dob?.toIso8601String(),
      'bloodGroup': bloodGroup,
      'sourceClinicName': sourceClinicName,
      'sourcePatientId': sourcePatientId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': uid,
    });
    final refreshed = await ref.get();
    return LabCustomerModel.fromMap(docId, refreshed.data()!);
  }

  // =================================================================
  // SCENARIO 3: direct walk-in → new labCustomers doc + LAB-YYYY-NNNN
  // =================================================================

  Future<LabCustomerModel> createDirect({
    required String labClinicId,
    required String fullName,
    required String phone,
    required String gender,
    String? email,
    DateTime? dob,
    String? bloodGroup,
    String? referredByName,
    String? referredByClinicName,
  }) async {
    final displayId = await _nextLabPatientId(labClinicId);
    final ref = _customers.doc();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final model = LabCustomerModel(
      docId: ref.id,
      labClinicId: labClinicId,
      source: LabCustomerSource.direct,
      displayPatientId: displayId,
      fullName: fullName,
      phone: phone,
      email: email,
      gender: gender,
      dob: dob,
      bloodGroup: bloodGroup,
      referredByName: referredByName,
      referredByClinicName: referredByClinicName,
      createdByUid: uid,
      updatedByUid: uid,
    );
    final payload = model.toMap();
debugPrint('===== LAB CUSTOMER CREATE PAYLOAD =====');
payload.forEach((k, v) => debugPrint('$k: $v (${v.runtimeType})'));
debugPrint('=======================================');
await ref.set(payload);
    return model;
  }

  // =================================================================
  // Per-lab human-readable ID: LAB-YYYY-NNNN
  // =================================================================
  Future<String> _nextLabPatientId(String labClinicId) async {
    final year = DateTime.now().year;
    final counterRef =
        _db.collection('counters').doc('lab_patient_${year}_$labClinicId');
    return await _db.runTransaction<String>((tx) async {
      final snap = await tx.get(counterRef);
      final current = (snap.data()?['count'] as num?)?.toInt() ?? 0;
      final next = current + 1;
      tx.set(
        counterRef,
        {'count': next, 'year': year, 'labClinicId': labClinicId},
        SetOptions(merge: true),
      );
      return 'LAB-$year-${next.toString().padLeft(4, '0')}';
    });
  }

  // =================================================================
  // SCENARIO 2 LOOKUP: phone/email across linked clinics
  // =================================================================
  //
  // Loops per-clinic so the (clinicId, phone) rule is satisfiable for
  // the whole query under the tightened `patients` rule.
  //
  // Note: intentionally does NOT filter on `active`, so a patient
  // marked inactive at the clinic is still findable when they walk in.

  Future<List<PatientModel>> findLinkedPatients({
    required String labClinicId,
    required String query,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    // Discover the linked clinics for this lab.
    final linkedSnap = await _clinics
        .doc(labClinicId)
        .collection('linkedClinics')
        .where('active', isEqualTo: true)
        .get();

    final results = <String, PatientModel>{};

    for (final linkDoc in linkedSnap.docs) {
      final clinicId = (linkDoc.data()['clinicId'] ?? '').toString();
      if (clinicId.isEmpty) continue;

      // Phone lookup
      final byPhone = await _patients
          .where('clinicId', isEqualTo: clinicId)
          .where('phone', isEqualTo: q)
          .limit(5)
          .get();

      for (final d in byPhone.docs) {
        results[d.id] = PatientModel.fromMap(d.id, d.data());
      }

      // Email lookup (only if the query looks like an email)
      if (q.contains('@')) {
        final byEmail = await _patients
            .where('clinicId', isEqualTo: clinicId)
            .where('email', isEqualTo: q)
            .limit(5)
            .get();
        for (final d in byEmail.docs) {
          results[d.id] = PatientModel.fromMap(d.id, d.data());
        }
      }
    }

    return results.values.toList();
  }

  // =================================================================
  // DEDUPLICATION: find existing labCustomers in *this* lab by phone
  // =================================================================
  //
  // Used when the receptionist is about to create/upsert a customer and
  // wants to warn "this phone already exists as LAB-0003 (Rahul)".
  // Caller decides whether to link or keep separate.

  Future<List<LabCustomerModel>> findLabCustomersByPhone({
    required String labClinicId,
    required String phone,
  }) async {
    final snap = await _customers
        .where('labClinicId', isEqualTo: labClinicId)
        .where('phone', isEqualTo: phone)
        .limit(10)
        .get();
    return snap.docs
        .map((d) => LabCustomerModel.fromMap(d.id, d.data()))
        .toList();
  }

  // =================================================================
  // READS for UI
  // =================================================================

  Stream<List<LabCustomerModel>> watchLabCustomers(String labClinicId) {
    return _customers
        .where('labClinicId', isEqualTo: labClinicId)
        .snapshots()
        .map((s) => s.docs
            .map((d) => LabCustomerModel.fromMap(d.id, d.data()))
            .toList());
  }

  Future<LabCustomerModel?> getById(String docId) async {
    final snap = await _customers.doc(docId).get();
    if (!snap.exists) return null;
    return LabCustomerModel.fromMap(docId, snap.data()!);
  }

  // =================================================================
  // ORDER STATS — bump when an order is placed
  // =================================================================
  Future<void> recordOrderPlaced(String customerDocId) async {
    await _customers.doc(customerDocId).update({
      'orderCount': FieldValue.increment(1),
      'lastOrderAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': FirebaseAuth.instance.currentUser?.uid,
    });
  }
}