// lib/core/services/canonical_test_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lab_test_model.dart';

/// Result of a create/update attempt. The admin UI shows a snackbar
/// or a field-level error based on which case is returned.
enum CanonicalTestWriteResult {
  success,
  duplicateCode,
  invalidCodeFormat,
  invalidNameLength,
}

class CanonicalTestService {
  final _col = FirebaseFirestore.instance.collection('tests');

  // ── Reads ──

  /// Watch every canonical test. If [activeOnly] is true, filter to
  /// active tests — used by the doctor picker and lab catalogue
  /// selection.
  Stream<List<CanonicalTestModel>> watchAll({bool activeOnly = false}) {
    Query<Map<String, dynamic>> q = _col;
    if (activeOnly) {
      q = q.where('active', isEqualTo: true);
    }
    return q.snapshots().map((s) => s.docs
        .map((d) => CanonicalTestModel.fromDoc(d))
        .toList());
  }

  /// Watch a single test.
  Stream<CanonicalTestModel?> watchOne(String testId) {
    return _col.doc(testId).snapshots().map((d) {
      if (!d.exists) return null;
      return CanonicalTestModel.fromDoc(d);
    });
  }

  /// Detect duplicates by code (case-insensitive via denormalized
  /// `codeLower`). Returns the existing test if found.
  Future<CanonicalTestModel?> findByCode(String code) async {
    final snap = await _col
        .where('codeLower', isEqualTo: code.toLowerCase().trim())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return CanonicalTestModel.fromDoc(snap.docs.first);
  }

  // ── Writes ──

  /// Create a new canonical test. Returns a `WriteResult` so the UI
  /// can show a specific error.
  Future<({CanonicalTestWriteResult result, String? testId, String? existingName})>
      create({
    required String code,
    required String name,
    required LabTestCategory category,
    required LabSampleType sampleType,
    bool fastingRequired = false,
    String? description,
    String? turnaroundHint,
    String? loincCode,
  }) async {
    // 1. Normalize
    final trimmedCode = code.trim().toUpperCase();
    final trimmedName = name.trim();

    // 2. Validate code format
    final codeRegex = RegExp(r'^[A-Z0-9_]{2,12}$');
    if (!codeRegex.hasMatch(trimmedCode)) {
      return (
        result: CanonicalTestWriteResult.invalidCodeFormat,
        testId: null,
        existingName: null,
      );
    }

    // 3. Validate name length
    if (trimmedName.length < 3 || trimmedName.length > 80) {
      return (
        result: CanonicalTestWriteResult.invalidNameLength,
        testId: null,
        existingName: null,
      );
    }

    // 4. Duplicate check
    final existing = await findByCode(trimmedCode);
    if (existing != null) {
      return (
        result: CanonicalTestWriteResult.duplicateCode,
        testId: null,
        existingName: existing.name,
      );
    }

    // 5. Write
    final user = FirebaseAuth.instance.currentUser;
    final docRef = _col.doc();
    final model = CanonicalTestModel(
      testId: docRef.id,
      code: trimmedCode,
      name: trimmedName,
      category: category,
      sampleType: sampleType,
      fastingRequired: fastingRequired,
      description: description?.trim(),
      turnaroundHint: turnaroundHint?.trim(),
      loincCode: loincCode?.trim(),
      active: true,
      createdByUid: user?.uid,
      createdByEmail: user?.email,
    );
    await docRef.set(model.toMap());

    return (
      result: CanonicalTestWriteResult.success,
      testId: docRef.id,
      existingName: null,
    );
  }

  /// Update an existing canonical test. [code] is immutable.
  Future<void> update({
    required String testId,
    required String name,
    required LabTestCategory category,
    required LabSampleType sampleType,
    required bool fastingRequired,
    required bool active,
    String? description,
    String? turnaroundHint,
    String? loincCode,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    await _col.doc(testId).update({
      'name': name.trim(),
      'nameLower': name.trim().toLowerCase(),
      'category': category.name,
      'sampleType': sampleType.name,
      'fastingRequired': fastingRequired,
      'active': active,
      'description': description?.trim(),
      'turnaroundHint': turnaroundHint?.trim(),
      'loincCode': loincCode?.trim(),
      'updatedByUid': user?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Soft-delete. Never hard-delete a canonical test — labs and
  /// historical orders reference it.
  Future<void> deactivate(String testId) async {
    final user = FirebaseAuth.instance.currentUser;
    await _col.doc(testId).update({
      'active': false,
      'updatedByUid': user?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Re-activate (undo a previous deactivate).
  Future<void> reactivate(String testId) async {
    final user = FirebaseAuth.instance.currentUser;
    await _col.doc(testId).update({
      'active': true,
      'updatedByUid': user?.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

// ── Riverpod providers ──

final canonicalTestServiceProvider =
    Provider<CanonicalTestService>((ref) => CanonicalTestService());

/// Every canonical test, live — used by the admin list screen.
final allCanonicalTestsProvider =
    StreamProvider.autoDispose<List<CanonicalTestModel>>((ref) {
  return ref.watch(canonicalTestServiceProvider).watchAll();
});

/// Active canonical tests only — used by the doctor picker and lab
/// offering UI.
final activeCanonicalTestsProvider =
    StreamProvider.autoDispose<List<CanonicalTestModel>>((ref) {
  return ref.watch(canonicalTestServiceProvider).watchAll(activeOnly: true);
});