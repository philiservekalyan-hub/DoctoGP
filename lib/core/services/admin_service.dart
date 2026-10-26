import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/clinic_model.dart';

class AdminService {
  final _db = FirebaseFirestore.instance;

  /// Live stream of all clinics, newest first.
  Stream<List<ClinicModel>> watchAllClinics() {
    return _db
        .collection('clinics')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => ClinicModel.fromMap(d.id, d.data()))
            .toList());
  }

  /// Creates a new clinic document with an auto-generated ID.
  /// Returns the new clinicId (doc ID).
  Future<String> createClinic(Map<String, dynamic> data) async {
    final ref = _db.collection('clinics').doc();
    await ref.set({
      ...data,
      'clinicId': ref.id,
      'active': true,
      'subscriptionPlan': data['subscriptionPlan'] ?? 'starter',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Attaches a clinic to an existing user by their auth UID.
  Future<void> attachClinicToUser({
    required String userId,
    required String clinicId,
    required String role,
  }) async {
    await _db.collection('users').doc(userId).update({
      'clinicId': clinicId,
      'role': role,
      'active': true,
    });
  }

  /// Look up a user by email to find their UID.
  Future<String?> findUserIdByEmail(String email) async {
    final snap = await _db
        .collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  Future<void> toggleClinicActive(String clinicId, bool active) async {
    await _db.collection('clinics').doc(clinicId).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

final adminServiceProvider =
    Provider<AdminService>((ref) => AdminService());

final allClinicsProvider =
    StreamProvider.autoDispose<List<ClinicModel>>((ref) {
  return ref.read(adminServiceProvider).watchAllClinics();
});