// lib/core/services/lab_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/lab_order_model.dart';
import '../models/lab_test_model.dart';

class LabService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection('labOrders');

  CollectionReference<Map<String, dynamic>> get _clinics =>
      _db.collection('clinics');

  CollectionReference<Map<String, dynamic>> _testsFor(String labClinicId) =>
      _clinics.doc(labClinicId).collection('labTests');

  // =================================================================
  // LINK MANAGEMENT (admin only)
  // =================================================================
  Future<void> linkClinicAndLab({
    required String clinicId,
    required String clinicName,
    required String labClinicId,
    required String labName,
  }) async {
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();
    final adminUid = FirebaseAuth.instance.currentUser?.uid;

    final base = <String, dynamic>{
      'clinicId': clinicId,
      'clinicName': clinicName,
      'labClinicId': labClinicId,
      'labName': labName,
      'linkedAt': now,
      'linkedByAdminUid': adminUid,
      'active': true,
    };

    batch.set(
      _clinics.doc(clinicId).collection('linkedLabs').doc(labClinicId),
      base,
    );
    batch.set(
      _clinics
          .doc(labClinicId)
          .collection('linkedClinics')
          .doc(clinicId),
      base,
    );

    await batch.commit();
  }

  Future<void> unlinkClinicAndLab({
    required String clinicId,
    required String labClinicId,
  }) async {
    final batch = _db.batch();
    batch.delete(
      _clinics.doc(clinicId).collection('linkedLabs').doc(labClinicId),
    );
    batch.delete(
      _clinics
          .doc(labClinicId)
          .collection('linkedClinics')
          .doc(clinicId),
    );
    await batch.commit();
  }

  Stream<List<Map<String, dynamic>>> watchLinkedLabs(String clinicId) {
    return _clinics
        .doc(clinicId)
        .collection('linkedLabs')
        .where('active', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }

  Stream<List<Map<String, dynamic>>> watchLinkedClinics(
      String labClinicId) {
    return _clinics
        .doc(labClinicId)
        .collection('linkedClinics')
        .where('active', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.map((d) => d.data()).toList());
  }

  Stream<List<Map<String, dynamic>>> watchEntitiesByType(String type) {
    return _clinics
        .where('type', isEqualTo: type)
        .where('active', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .toList());
  }

  // =================================================================
  // CATALOGS
  // =================================================================
  Stream<List<({String labClinicId, String labName, List<dynamic> tests})>>
      watchLinkedCatalogs(String referringClinicId) {
    return watchLinkedLabs(referringClinicId).asyncMap((linked) async {
      final out =
          <({String labClinicId, String labName, List<dynamic> tests})>[];
      for (final lab in linked) {
        final labClinicId = lab['labClinicId'] as String;
        final labName = (lab['labName'] ?? 'Lab').toString();
        final catSnap = await _clinics
            .doc(labClinicId)
            .collection('catalog')
            .doc('main')
            .get();
        final tests = catSnap.exists
            ? (catSnap.data()?['tests'] as List? ?? [])
            : <dynamic>[];
        out.add((labClinicId: labClinicId, labName: labName, tests: tests));
      }
      return out;
    });
  }

  // =================================================================
  // LAB TEST CATALOG CRUD
  // =================================================================
  Stream<List<LabTestModel>> watchLabTests({
    required String labClinicId,
    bool includeInactive = false,
  }) {
    Query<Map<String, dynamic>> q = _testsFor(labClinicId);
    if (!includeInactive) {
      q = q.where('active', isEqualTo: true);
    }
    return q.orderBy('code').snapshots().map((s) => s.docs
        .map((d) => LabTestModel.fromMap(d.id, d.data()))
        .toList());
  }

  Future<String> createLabTest({
    required String labClinicId,
    required String code,
    required String name,
    required String category,
    required String sampleType,
    bool fastingRequired = false,
    int? turnaroundHours,
    String? deptId,
  }) async {
    final idx = LabTestModel.buildSearchIndex(
      code: code,
      name: name,
      category: category,
      sampleType: sampleType,
    );

    final ref = _testsFor(labClinicId).doc();
    await ref.set({
      'labClinicId': labClinicId,
      'code': code.trim(),
      'name': name.trim(),
      'category': category.trim(),
      'sampleType': sampleType.trim(),
      'fastingRequired': fastingRequired,
      'turnaroundHours': turnaroundHours,
      'deptId': deptId,
      'active': true,
      'searchKey': idx.key,
      'searchTokens': idx.tokens,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _rebuildDenormalizedCatalog(labClinicId);
    return ref.id;
  }

  Future<void> updateLabTest({
    required String labClinicId,
    required String testDocId,
    required String code,
    required String name,
    required String category,
    required String sampleType,
    required bool fastingRequired,
    int? turnaroundHours,
    String? deptId,
    required bool active,
  }) async {
    final idx = LabTestModel.buildSearchIndex(
      code: code,
      name: name,
      category: category,
      sampleType: sampleType,
    );

    await _testsFor(labClinicId).doc(testDocId).update({
      'code': code.trim(),
      'name': name.trim(),
      'category': category.trim(),
      'sampleType': sampleType.trim(),
      'fastingRequired': fastingRequired,
      'turnaroundHours': turnaroundHours,
      'deptId': deptId,
      'active': active,
      'searchKey': idx.key,
      'searchTokens': idx.tokens,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _rebuildDenormalizedCatalog(labClinicId);
  }

  Future<void> deactivateLabTest({
    required String labClinicId,
    required String testDocId,
  }) async {
    await _testsFor(labClinicId).doc(testDocId).update({
      'active': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _rebuildDenormalizedCatalog(labClinicId);
  }

  Future<void> _rebuildDenormalizedCatalog(String labClinicId) async {
    final snap = await _testsFor(labClinicId)
        .where('active', isEqualTo: true)
        .get();

    final tests = snap.docs.map((d) {
      final m = d.data();
      return {
        'code': (m['code'] ?? '').toString(),
        'name': (m['name'] ?? '').toString(),
        'category': (m['category'] ?? 'Other').toString(),
        'sampleType': (m['sampleType'] ?? 'Blood').toString(),
        'fastingRequired': m['fastingRequired'] == true,
        'turnaroundHours': m['turnaroundHours'],
        'searchKey': (m['searchKey'] ?? '').toString(),
        'searchTokens': m['searchTokens'] ?? const [],
      };
    }).toList();

    await _clinics
        .doc(labClinicId)
        .collection('catalog')
        .doc('main')
        .set({
      'tests': tests,
      'count': tests.length,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // =================================================================
  // LAB ORDERS
  // =================================================================

  Future<String> createOrder({
    String? referringClinicId,
    required String labClinicId,
    required String labName,
    required String patientDocId,
    required String patientId,
    required String patientName,
    String? patientPhone,
    String? doctorDocId,
    String? doctorName,
    required List<LabTestItem> tests,
    String? instructions,
    String? referralNotes,
    String? appointmentId,
    String? deptId,
    double? billableAmount,
  }) async {
    final ref = _orders.doc();
    await ref.set({
      'referringClinicId': referringClinicId,
      'labClinicId': labClinicId,
      'labName': labName,
      'deptId': deptId,
      'patientDocId': patientDocId,
      'patientId': patientId,
      'patientName': patientName,
      'patientPhone': patientPhone,
      'doctorDocId': doctorDocId,
      'doctorName': doctorName,
      'appointmentId': appointmentId,
      'tests': tests.map((t) => t.toMap()).toList(),
      'instructions': instructions,
      'referralNotes': referralNotes,
      'status': 'ordered',
      'orderedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': FirebaseAuth.instance.currentUser?.uid,
      'billableAmount': billableAmount,
      'paymentStatus': LabPaymentStatus.unpaid.name,
      // ── New orders are not released — a receptionist must
      //    release the report after payment is settled.
      'released': false,
    });
    return ref.id;
  }

  Stream<List<LabOrderModel>> watchDoctorOrders({
    required String doctorDocId,
  }) {
    return _orders
        .where('doctorDocId', isEqualTo: doctorDocId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => LabOrderModel.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<LabOrderModel>> watchPatientOrders(String patientDocId) {
    return _orders
        .where('patientDocId', isEqualTo: patientDocId)
        .orderBy('orderedAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => LabOrderModel.fromMap(d.id, d.data()))
            .toList());
  }

  Stream<List<LabOrderModel>> watchLabOrders({
    required String labClinicId,
    String? deptId,
    List<LabOrderStatus>? statuses,
  }) {
    Query<Map<String, dynamic>> q =
        _orders.where('labClinicId', isEqualTo: labClinicId);

    if (deptId != null && deptId.isNotEmpty) {
      q = q.where('deptId', isEqualTo: deptId);
    }

    if (statuses != null && statuses.isNotEmpty) {
      if (statuses.length == 1) {
        q = q.where('status', isEqualTo: statuses.first.name);
      } else {
        q = q.where('status',
            whereIn: statuses.map((s) => s.name).toList());
      }
    }

    return q.orderBy('orderedAt', descending: true).snapshots().map(
        (s) => s.docs
            .map((d) => LabOrderModel.fromMap(d.id, d.data()))
            .toList());
  }

  Future<void> updateStatus(String orderId, LabOrderStatus status) async {
    final data = <String, dynamic>{
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': FirebaseAuth.instance.currentUser?.uid,
    };
    switch (status) {
      case LabOrderStatus.accepted:
        data['acceptedAt'] = FieldValue.serverTimestamp();
        break;
      case LabOrderStatus.sampleCollected:
        data['sampleCollectedAt'] = FieldValue.serverTimestamp();
        break;
      case LabOrderStatus.processing:
        data['processingStartedAt'] = FieldValue.serverTimestamp();
        break;
      case LabOrderStatus.ready:
        data['reportReadyAt'] = FieldValue.serverTimestamp();
        break;
      case LabOrderStatus.delivered:
        data['deliveredAt'] = FieldValue.serverTimestamp();
        break;
      default:
        break;
    }
    await _orders.doc(orderId).update(data);
  }

  Future<void> cancelOrder(
    String orderId, {
    String? reason,
    String byRole = 'doctor',
  }) async {
    await _orders.doc(orderId).update({
      'status': LabOrderStatus.cancelled.name,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledByRole': byRole,
      'cancelReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  Future<void> markNoShow(String orderId, {String? reason}) async {
    await _orders.doc(orderId).update({
      'status': LabOrderStatus.noShow.name,
      'noShowAt': FieldValue.serverTimestamp(),
      'noShowReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  /// Upload a report.
  ///
  /// Sets `status = 'ready'` and explicitly `released = false`. The
  /// report is uploaded and the technician's work is done, but the
  /// report is **NOT yet visible** to the patient or referring
  /// doctor. It becomes visible only after a receptionist calls
  /// [releaseReport] once payment is settled.
  ///
  /// This is the enforcement point for the report-release gate. Do
  /// not let the technician's upload directly flip visibility.
  Future<void> attachReport({
    required String orderId,
    required String reportUrl,
    required String reportStoragePath,
    required String reportFileName,
  }) async {
    await _orders.doc(orderId).update({
      'reportUrl': reportUrl,
      'reportStoragePath': reportStoragePath,
      'reportFileName': reportFileName,
      'reportUploadedAt': FieldValue.serverTimestamp(),
      'reportUploadedByUid': FirebaseAuth.instance.currentUser?.uid,
      'status': 'ready',
      'reportReadyAt': FieldValue.serverTimestamp(),
      // ── Release gate ──
      // The report is uploaded but hidden. A receptionist must
      // explicitly release it after payment is settled or waived.
      'released': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  /// Release a report.
  ///
  /// Called by the **receptionist** after payment is settled (paid
  /// or waived). Until this runs, the report is invisible to the
  /// patient and the referring doctor.
  ///
  /// Guards:
  /// - Order must exist.
  /// - Order must be in `status == ready`.
  /// - A report must have been uploaded (`reportUrl` not null).
  /// - Payment must be settled (`paymentStatus != unpaid`) or the
  ///   caller must pass `overrideUnpaid: true` for edge cases
  ///   (e.g. senior management releasing a report on credit).
  Future<void> releaseReport({
    required String orderId,
    required String releasedByUid,
    bool overrideUnpaid = false,
  }) async {
    final ref = _orders.doc(orderId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw StateError('Lab order $orderId not found.');
    }
    final m = snap.data() ?? {};
    final status = (m['status'] ?? '').toString();
    final reportUrl = (m['reportUrl'] ?? '').toString();
    final paymentStatus = (m['paymentStatus'] ?? 'unpaid').toString();
    final alreadyReleased = m['released'] == true;

    if (alreadyReleased) {
      // Idempotent — safe to call twice.
      return;
    }
    if (status != 'ready') {
      throw StateError(
          'Cannot release: order is in status "$status", not "ready".');
    }
    if (reportUrl.isEmpty) {
      throw StateError(
          'Cannot release: no report has been uploaded yet.');
    }
    if (paymentStatus == 'unpaid' && !overrideUnpaid) {
      throw StateError(
          'Cannot release: payment not settled. Mark paid or waived first.');
    }

    await ref.update({
      'released': true,
      'releasedAt': FieldValue.serverTimestamp(),
      'releasedByUid': releasedByUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': releasedByUid,
    });
  }

  // =================================================================
  // MODEL A — PATIENT-FACING BILLING
  // =================================================================

  /// Receptionist sets (or corrects) the amount the patient must pay.
  Future<void> setBillableAmount({
    required String orderId,
    required double amount,
    required String setByUid,
  }) async {
    if (amount < 0) throw ArgumentError('Amount cannot be negative');
    await _orders.doc(orderId).update({
      'billableAmount': amount,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': setByUid,
    });
  }

  /// Patient has paid.
  Future<void> markLabFeesPaid({
    required String orderId,
    required String collectedByUid,
  }) async {
    await _orders.doc(orderId).update({
      'paymentStatus': LabPaymentStatus.paid.name,
      'feesPaidAt': FieldValue.serverTimestamp(),
      'feesCollectedByUid': collectedByUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': collectedByUid,
    });
  }

  /// Fees waived.
  Future<void> waiveLabFees({
    required String orderId,
    required String collectedByUid,
  }) async {
    await _orders.doc(orderId).update({
      'paymentStatus': LabPaymentStatus.waived.name,
      'feesPaidAt': FieldValue.serverTimestamp(),
      'feesCollectedByUid': collectedByUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': collectedByUid,
    });
  }
}