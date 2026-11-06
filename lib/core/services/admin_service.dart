// lib/core/services/admin_service.dart
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

  /// Attaches a clinic or lab to a user's account.
  ///
  /// Sets the user's clinic linkage, role, orgType, and the two
  /// capability flags (`isDoctor` and `isLabOwner`).
  ///
  /// [role] is the primary role for routing — `'owner'` when the
  /// admin is linking the owner, or `'lab'`/`'receptionist'` when
  /// the admin is linking a staff member later.
  ///
  /// [orgType] must be `'clinic'` or `'lab'`. It distinguishes clinic
  /// from lab and is used by the router's fast path.
  ///
  /// [isDoctor] / [isLabOwner] are inferred when not passed:
  ///   • An owner of a clinic becomes `isDoctor: true` by default
  ///     (most GPs own their practice).
  ///   • An owner of a lab becomes `isLabOwner: true`.
  ///   • Staff linking leaves both flags at their defaults (false).
  Future<void> attachClinicToUser({
    required String userId,
    required String clinicId,
    required String role,
    required String orgType,
    bool? isDoctor,
    bool? isLabOwner,
  }) async {
    final org = await _db.collection('clinics').doc(clinicId).get();
    final m = org.data() ?? {};

    final isLab = orgType == 'lab';
    final effectiveIsDoctor =
        isDoctor ?? (role == 'owner' && !isLab);
    final effectiveIsLabOwner =
        isLabOwner ?? (isLab && role == 'owner');

    await _db.collection('users').doc(userId).update({
      'clinicId': clinicId,
      'clinicCode': (m['clinicCode'] ?? '').toString(),
      'clinicName': (m['name'] ?? '').toString(),
      'role': role,
      'orgType': orgType,
      'isDoctor': effectiveIsDoctor,
      'isLabOwner': effectiveIsLabOwner,
      'active': true,
      'updatedAt': FieldValue.serverTimestamp(),
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