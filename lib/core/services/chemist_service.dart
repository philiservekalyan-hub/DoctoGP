import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/chemist_model.dart';
import '../models/prescription_order_model.dart';

class ChemistService {
  final _chemists = FirebaseFirestore.instance.collection('chemists');
  final _orders = FirebaseFirestore.instance.collection('prescriptionOrders');

  // ── chemists ──────────────────────────────────────────────
  Stream<List<ChemistModel>> watchChemistsForClinic(String clinicId) {
    return _chemists
        .where('linkedClinicIds', arrayContains: clinicId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => ChemistModel.fromMap(d.id, d.data()))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name)));
  }

  Stream<ChemistModel?> watchChemist(String chemistDocId) {
    return _chemists.doc(chemistDocId).snapshots().map((s) =>
        s.exists ? ChemistModel.fromMap(s.id, s.data() ?? {}) : null);
  }

  // ── orders (patient) ─────────────────────────────────────
  Stream<List<PrescriptionOrderModel>> watchPatientOrders(
      String patientDocId) {
    return _orders
        .where('patientDocId', isEqualTo: patientDocId)
        .orderBy('placedAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => PrescriptionOrderModel.fromMap(d.id, d.data()))
            .toList());
  }

  Stream<PrescriptionOrderModel?> watchOrder(String orderId) {
    return _orders.doc(orderId).snapshots().map((s) =>
        s.exists ? PrescriptionOrderModel.fromMap(s.id, s.data() ?? {}) : null);
  }

  // ── orders (chemist) ─────────────────────────────────────
 Stream<List<PrescriptionOrderModel>> watchChemistOrders(
  String chemistDocId,
) {
  final cleanId = chemistDocId.trim();

  debugPrint('[CHEMIST] Starting orders stream: $cleanId');

  if (cleanId.isEmpty) {
    return Stream.error(
      StateError('Chemist document ID is empty'),
    );
  }

  return _orders
      .where('chemistDocId', isEqualTo: cleanId)
      .orderBy('placedAt', descending: true)
      .snapshots()
      .map((snapshot) {
        debugPrint(
          '[CHEMIST] Received ${snapshot.docs.length} orders',
        );

        try {
          return snapshot.docs.map((doc) {
            return PrescriptionOrderModel.fromMap(
              doc.id,
              doc.data(),
            );
          }).toList();
        } catch (e, stack) {
          debugPrint('[CHEMIST ERROR] Order parsing failed: $e');
          debugPrintStack(stackTrace: stack);
          rethrow;
        }
      });
}

  // ── patient action: place order ──────────────────────────
  Future<String> placeOrder({
    required String patientDocId,
    required String patientId,
    required String patientName,
    required String patientPhone,
    int? patientAgeYears,
    String? patientGender,
    required String deliveryAddress,
    String? deliveryNotes,
    required String consultationDocId,
    required String appointmentDocId,
    required String doctorDocId,
    required String doctorName,
    String? doctorRegistrationNumber,
    String? doctorQualification,
    required String clinicId,
    String? clinicName,
    String? diagnosis,
    String? rxFreeText,
    DateTime? prescriptionDate,
    required ChemistModel chemist,
    required List<PrescriptionOrderItem> items,
  }) async {
    final ref = _orders.doc();
    final orderNumber =
        'RX-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    await ref.set({
      'orderNumber': orderNumber,
      'patientDocId': patientDocId,
      'patientId': patientId,
      'patientName': patientName,
      'patientPhone': patientPhone,
      'patientAgeYears': patientAgeYears,
      'patientGender': patientGender,
      'deliveryAddress': deliveryAddress,
      'deliveryNotes': deliveryNotes,
      'consultationDocId': consultationDocId,
      'appointmentDocId': appointmentDocId,
      'doctorDocId': doctorDocId,
      'doctorName': doctorName,
      'doctorRegistrationNumber': doctorRegistrationNumber,
      'doctorQualification': doctorQualification,
      'clinicId': clinicId,
      'clinicName': clinicName,
      'diagnosis': diagnosis,
      'rxFreeText': rxFreeText,
      'prescriptionDate':
          prescriptionDate != null ? Timestamp.fromDate(prescriptionDate) : null,
      'chemistDocId': chemist.docId,
      'chemistName': chemist.name,
      'items': items.map((e) => e.toMap()).toList(),
      'status': PrescriptionOrderStatus.placed.name,
      'placedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await addChemistToPatient(
      patientDocId: patientDocId,
      chemistDocId: chemist.docId,
    );
    return ref.id;
  }

  // ── patient side: personal list + pincode search ─────────
  Stream<List<ChemistModel>> watchPatientChemists(String patientDocId) {
    final patientRef =
        FirebaseFirestore.instance.collection('patients').doc(patientDocId);
    return patientRef.snapshots().asyncExpand((snap) {
      final ids = (snap.data()?['linkedChemistIds'] is List)
          ? (snap.data()!['linkedChemistIds'] as List)
              .map((e) => '$e')
              .where((e) => e.isNotEmpty)
              .toList()
          : const <String>[];
      if (ids.isEmpty) return const Stream.empty();
      return _chemists
          .where(FieldPath.documentId, whereIn: ids.take(10).toList())
          .snapshots()
          .map(_sorted);
    });
  }

  Future<void> addChemistToPatient({
    required String patientDocId,
    required String chemistDocId,
  }) async {
    await FirebaseFirestore.instance
        .collection('patients')
        .doc(patientDocId)
        .update({
      'linkedChemistIds': FieldValue.arrayUnion([chemistDocId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

   Future<List<ChemistModel>> fetchChemistsForPincode(String pincode) async {
    final p = pincode.trim();
    if (p.isEmpty) return [];

    try {
      // We use .get() instead of .snapshots() so it returns once and stops.
      // No missing-index silent hangs.
      final snap = await _chemists
          .where('isActive', isEqualTo: true)
          .where('serviceablePincodes', arrayContains: p)
          .get()
          .timeout(const Duration(seconds: 5));

      final list = snap.docs
          .map((d) => ChemistModel.fromMap(d.id, d.data()))
          .toList();
      
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    } catch (e) {
      print('[ChemistService] fetchChemistsForPincode ERROR: $e');
      rethrow; // This will push the error to the UI!
    }
  }

  Stream<List<ChemistModel>> watchChemistsForCity(String city) {
    final c = city.trim();
    if (c.isEmpty) return const Stream.empty();
    return _chemists
        .where('isActive', isEqualTo: true)
        .where('city', isEqualTo: c)
        .snapshots()
        .map(_sorted);
  }

  Future<List<ChemistModel>> searchChemists({
    String pincode = '',
    String city = '',
    String query = '',
  }) async {
    final results = <String, ChemistModel>{};
    final p = pincode.trim();
    final c = city.trim();
    final q = query.trim().toLowerCase();

    Future<void> addFrom(Query<Map<String, dynamic>> qry) async {
      final snap = await qry.get();
      for (final doc in snap.docs) {
        final m = ChemistModel.fromMap(doc.id, doc.data());
        if (!m.isActive) continue;
        results[m.docId] = m;
      }
    }

    if (p.isNotEmpty) {
      await addFrom(_chemists
          .where('isActive', isEqualTo: true)
          .where('serviceablePincodes', arrayContains: p));
      await addFrom(_chemists
          .where('isActive', isEqualTo: true)
          .where('pincode', isEqualTo: p)
          .where('deliveryAvailable', isEqualTo: true));
    }
    if (c.isNotEmpty) {
      await addFrom(_chemists
          .where('isActive', isEqualTo: true)
          .where('city', isEqualTo: c));
    }
    if (q.isNotEmpty && p.isEmpty && c.isEmpty) {
      final snap = await _chemists
          .where('isActive', isEqualTo: true)
          .limit(200)
          .get();
      for (final doc in snap.docs) {
        final m = ChemistModel.fromMap(doc.id, doc.data());
        if (m.name.toLowerCase().contains(q)) results[m.docId] = m;
      }
    }

    final list = results.values.toList()
      ..sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<ChemistModel> _sorted(QuerySnapshot<Map<String, dynamic>> s) {
    final list = s.docs
        .map((d) => ChemistModel.fromMap(d.id, d.data()))
        .toList();
    list.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  // ── patient action: cancel ───────────────────────────────
  Future<void> cancelOrder(String orderId, {required String reason}) async {
    await _orders.doc(orderId).update({
      'status': PrescriptionOrderStatus.cancelled.name,
      'cancelReason': reason,
      'cancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── patient action: pay ──────────────────────────────────
  /// Patient submits the UPI transaction reference (UTR) after paying.
  /// Generates a receipt number and moves the order to
  /// `paidPendingVerification`. The chemist must call `verifyPayment`
  /// before dispatch.
  Future<String> submitUpiReference({
    required String orderId,
    required String utr,
  }) async {
    final receiptNumber = _makeReceiptNumber();
    await _orders.doc(orderId).update({
      'status': PrescriptionOrderStatus.paidPendingVerification.name,
      'paymentMethod': 'upi',
      'paymentReference': utr.trim(),
      'receiptNumber': receiptNumber,
      'paidAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return receiptNumber;
  }

  /// Chemist verifies that the UPI payment landed in their account.
  Future<void> verifyPayment(String orderId,
      {required String chemistUid}) async {
    await _orders.doc(orderId).update({
      'status': PrescriptionOrderStatus.paid.name,
      'paymentVerifiedAt': FieldValue.serverTimestamp(),
      'paymentVerifiedByUid': chemistUid,
      'paymentRejectionReason': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Chemist rejects the payment — patient must pay again.
  Future<void> rejectPayment(String orderId,
      {required String reason}) async {
    await _orders.doc(orderId).update({
      'status': PrescriptionOrderStatus.billed.name,
      'paymentReference': FieldValue.delete(),
      'receiptNumber': FieldValue.delete(),
      'paidAt': FieldValue.delete(),
      'paymentRejectionReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String _makeReceiptNumber() {
    final now = DateTime.now();
    final y = now.year.toString();
    final serial =
        now.millisecondsSinceEpoch.toString().substring(6); // last 7 digits
    return 'INV-$y-$serial';
  }

  // ── chemist actions ──────────────────────────────────────
  Future<void> acceptOrder(String orderId) async {
    await _orders.doc(orderId).update({
      'status': PrescriptionOrderStatus.accepted.name,
      'acceptedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejectOrder(String orderId, {required String reason}) async {
    await _orders.doc(orderId).update({
      'status': PrescriptionOrderStatus.rejected.name,
      'cancelReason': reason,
      'cancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

   Future<void> billOrder({
    required String orderId,
    required List<PrescriptionOrderItem> pricedItems,
    required double deliveryFee,
    double? discountPercent, // <-- Added
    String? chemistNote,
  }) async {
    // Only sum the items that the chemist marked as available
    final subtotal = pricedItems
        .where((i) => i.status == OrderItemStatus.available)
        .fold<double>(0, (s, i) => s + (i.lineTotal ?? 0));
        
    final discountAmount = subtotal * ((discountPercent ?? 0) / 100);
    final total = (subtotal - discountAmount) + deliveryFee;

    await _orders.doc(orderId).update({
      'items': pricedItems.map((e) => e.toMap()).toList(),
      'deliveryFee': deliveryFee,
      'discountPercent': discountPercent, // <-- Added
      'totalAmount': total,
      'chemistNote': chemistNote,
      'status': PrescriptionOrderStatus.billed.name,
      'billedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markPreparing(String orderId) async {
    await _orders.doc(orderId).update({
      'status': PrescriptionOrderStatus.preparing.name,
      'preparingAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markOutForDelivery(String orderId) async {
    await _orders.doc(orderId).update({
      'status': PrescriptionOrderStatus.outForDelivery.name,
      'outForDeliveryAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markDelivered(String orderId) async {
    await _orders.doc(orderId).update({
      'status': PrescriptionOrderStatus.delivered.name,
      'deliveredAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}