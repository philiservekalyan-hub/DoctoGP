import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/clinic_model.dart';
import '../../app/router.dart';

class ClinicService {
  final _db = FirebaseFirestore.instance;

  Stream<ClinicModel?> watchClinic(String clinicId) {
    return _db
        .collection('clinics')
        .doc(clinicId)
        .snapshots()
        .map((d) => d.exists
            ? ClinicModel.fromMap(d.id, d.data()!)
            : null);
  }

  Future<void> updateClinic(
      String clinicId, Map<String, dynamic> data) async {
    await _db.collection('clinics').doc(clinicId).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> uploadLogo({
    required String clinicId,
    required String localPath,
  }) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('clinics/$clinicId/logo.jpg');
    await ref.putFile(File(localPath));
    return await ref.getDownloadURL();
  }
}

final clinicServiceProvider =
    Provider<ClinicService>((ref) => ClinicService());

/// Resolves the clinic for the currently signed-in user.
/// Falls back to 'default' if the user's clinicId is null.
final currentClinicProvider =
    StreamProvider.autoDispose<ClinicModel?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final clinicId = user?.clinicId ?? 'default';
  return ref.read(clinicServiceProvider).watchClinic(clinicId);
});