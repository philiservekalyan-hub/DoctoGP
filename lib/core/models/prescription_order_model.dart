// lib/core/models/prescription_order_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum PrescriptionOrderStatus {
  placed,
  accepted,
  billed,
  paidPendingVerification,
  paid,
  preparing,
  outForDelivery,
  delivered,
  cancelled,
  rejected,
  unknown,
}

enum OrderItemStatus { pending, available, unavailable }

class PrescriptionOrderItem {
  final String name;
  final String dose;
  final String frequency;
  final String duration;
  final int quantity;
  final OrderItemStatus status;
  final double? unitPrice;
  final double? lineTotal;
  final String? chemistNote;

  PrescriptionOrderItem({
    required this.name,
    this.dose = '',
    this.frequency = '',
    this.duration = '',
    required this.quantity,
    this.status = OrderItemStatus.pending,
    this.unitPrice,
    this.lineTotal,
    this.chemistNote,
  });

  factory PrescriptionOrderItem.fromMap(Map<String, dynamic> m) {
    return PrescriptionOrderItem(
      name: (m['name'] ?? '').toString(),
      dose: (m['dose'] ?? '').toString(),
      frequency: (m['frequency'] ?? '').toString(),
      duration: (m['duration'] ?? '').toString(),
      quantity: (m['quantity'] is num) ? (m['quantity'] as num).toInt() : 1,
      status: _parseStatus(m['status']),
      unitPrice:
          (m['unitPrice'] is num) ? (m['unitPrice'] as num).toDouble() : null,
      lineTotal:
          (m['lineTotal'] is num) ? (m['lineTotal'] as num).toDouble() : null,
      chemistNote: m['chemistNote']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'dose': dose,
        'frequency': frequency,
        'duration': duration,
        'quantity': quantity,
        'status': status.name,
        'unitPrice': unitPrice,
        'lineTotal': lineTotal,
        'chemistNote': chemistNote,
      };

  PrescriptionOrderItem copyWith({
    int? quantity,
    OrderItemStatus? status,
    double? unitPrice,
    double? lineTotal,
    String? chemistNote,
  }) =>
      PrescriptionOrderItem(
        name: name,
        dose: dose,
        frequency: frequency,
        duration: duration,
        quantity: quantity ?? this.quantity,
        status: status ?? this.status,
        unitPrice: unitPrice ?? this.unitPrice,
        lineTotal: lineTotal ?? this.lineTotal,
        chemistNote: chemistNote ?? this.chemistNote,
      );

  static OrderItemStatus _parseStatus(dynamic v) {
    switch ('${v ?? ''}'.toLowerCase()) {
      case 'available':
        return OrderItemStatus.available;
      case 'unavailable':
        return OrderItemStatus.unavailable;
      default:
        return OrderItemStatus.pending;
    }
  }
}

class PrescriptionOrderModel {
  final String docId;
  final String orderNumber;

  // ── patient ──
  final String patientDocId;
  final String patientId;
  final String patientName;
  final String patientPhone;
  final int? patientAgeYears;
  final String? patientGender;
  final String deliveryAddress;
  final String? deliveryNotes;

  // ── prescription snapshot ──
  final String consultationDocId;
  final String appointmentDocId;
  final String doctorDocId;
  final String doctorName;
  final String? doctorRegistrationNumber;
  final String? doctorQualification;
  final String clinicId;
  final String? clinicName;
  final String? diagnosis;
  final String? rxFreeText;
  final DateTime? prescriptionDate;

  // ── chemist ──
  final String chemistDocId;
  final String chemistName;

  final List<PrescriptionOrderItem> items;
  final PrescriptionOrderStatus status;

  // ── payment ──
  final double? totalAmount;
  final double? discountPercent;
  final double? deliveryFee;
  final String? paymentMethod;
  final String? paymentReference;
  final String? receiptNumber;
  final DateTime? paidAt;
  final DateTime? paymentVerifiedAt;
  final String? paymentVerifiedByUid;
  final String? paymentRejectionReason;
  final String? chemistNote;

  // ── timeline ──
  final DateTime placedAt;
  final DateTime? acceptedAt;
  final DateTime? billedAt;
  final DateTime? preparingAt;
  final DateTime? outForDeliveryAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final DateTime? updatedAt;

  PrescriptionOrderModel({
    required this.docId,
    required this.orderNumber,
    required this.patientDocId,
    required this.patientId,
    required this.patientName,
    required this.patientPhone,
    this.patientAgeYears,
    this.patientGender,
    required this.deliveryAddress,
    this.deliveryNotes,
    required this.consultationDocId,
    required this.appointmentDocId,
    required this.doctorDocId,
    required this.doctorName,
    this.doctorRegistrationNumber,
    this.doctorQualification,
    required this.clinicId,
    this.clinicName,
    this.diagnosis,
    this.rxFreeText,
    this.prescriptionDate,
    required this.chemistDocId,
    required this.chemistName,
    required this.items,
    required this.status,
    this.totalAmount,
    this.deliveryFee,
    this.paymentMethod,
    this.paymentReference,
    this.receiptNumber,
    this.paidAt,
    this.paymentVerifiedAt,
    this.paymentVerifiedByUid,
    this.paymentRejectionReason,
    this.chemistNote,
    required this.placedAt,
    this.acceptedAt,
    this.billedAt,
    this.preparingAt,
    this.outForDeliveryAt,
    this.deliveredAt,
    this.cancelledAt,
    this.cancelReason,
    this.updatedAt,
    this.discountPercent,
  });

  factory PrescriptionOrderModel.fromMap(String id, Map<String, dynamic> m) {
    DateTime ts(dynamic v) =>
        v is Timestamp ? v.toDate() : DateTime.now();
    DateTime? tsOrNull(dynamic v) => v is Timestamp ? v.toDate() : null;
    final itemsRaw = m['items'];
    final items = <PrescriptionOrderItem>[];
    if (itemsRaw is List) {
      for (final e in itemsRaw) {
        if (e is Map) {
          items.add(
              PrescriptionOrderItem.fromMap(Map<String, dynamic>.from(e)));
        }
      }
    }

    return PrescriptionOrderModel(
      docId: id,
      orderNumber: (m['orderNumber'] ?? '').toString(),
      patientDocId: (m['patientDocId'] ?? '').toString(),
      patientId: (m['patientId'] ?? '').toString(),
      patientName: (m['patientName'] ?? '').toString(),
      patientPhone: (m['patientPhone'] ?? '').toString(),
      patientAgeYears: (m['patientAgeYears'] is num)
          ? (m['patientAgeYears'] as num).toInt()
          : null,
      patientGender: m['patientGender']?.toString(),
      deliveryAddress: (m['deliveryAddress'] ?? '').toString(),
      deliveryNotes: m['deliveryNotes']?.toString(),
      consultationDocId: (m['consultationDocId'] ?? '').toString(),
      appointmentDocId: (m['appointmentDocId'] ?? '').toString(),
      doctorDocId: (m['doctorDocId'] ?? '').toString(),
      doctorName: (m['doctorName'] ?? '').toString(),
      doctorRegistrationNumber:
          m['doctorRegistrationNumber']?.toString(),
      doctorQualification: m['doctorQualification']?.toString(),
      clinicId: (m['clinicId'] ?? '').toString(),
      clinicName: m['clinicName']?.toString(),
      diagnosis: m['diagnosis']?.toString(),
      rxFreeText: m['rxFreeText']?.toString(),
      prescriptionDate: tsOrNull(m['prescriptionDate']),
      chemistDocId: (m['chemistDocId'] ?? '').toString(),
      chemistName: (m['chemistName'] ?? '').toString(),
      items: items,
      status: _parseOrderStatus(m['status']),
      totalAmount: (m['totalAmount'] is num)
          ? (m['totalAmount'] as num).toDouble()
          : null,
      deliveryFee: (m['deliveryFee'] is num)
          ? (m['deliveryFee'] as num).toDouble()
          : null,
      discountPercent: (m['discountPercent'] is num)
          ? (m['discountPercent'] as num).toDouble()
          : null,
      paymentMethod: m['paymentMethod']?.toString(),
      paymentReference: m['paymentReference']?.toString(),
      receiptNumber: m['receiptNumber']?.toString(),
      paidAt: tsOrNull(m['paidAt']),
      paymentVerifiedAt: tsOrNull(m['paymentVerifiedAt']),
      paymentVerifiedByUid: m['paymentVerifiedByUid']?.toString(),
      paymentRejectionReason: m['paymentRejectionReason']?.toString(),
      chemistNote: m['chemistNote']?.toString(),
      placedAt: ts(m['placedAt']),
      acceptedAt: tsOrNull(m['acceptedAt']),
      billedAt: tsOrNull(m['billedAt']),
      preparingAt: tsOrNull(m['preparingAt']),
      outForDeliveryAt: tsOrNull(m['outForDeliveryAt']),
      deliveredAt: tsOrNull(m['deliveredAt']),
      cancelledAt: tsOrNull(m['cancelledAt']),
      cancelReason: m['cancelReason']?.toString(),
      updatedAt: tsOrNull(m['updatedAt']),
    );
  }

  static PrescriptionOrderStatus _parseOrderStatus(dynamic v) {
    switch ('${v ?? ''}'.toLowerCase()) {
      case 'placed':
        return PrescriptionOrderStatus.placed;
      case 'accepted':
        return PrescriptionOrderStatus.accepted;
      case 'billed':
        return PrescriptionOrderStatus.billed;
      case 'paidpendingverification':
        return PrescriptionOrderStatus.paidPendingVerification;
      case 'paid':
        return PrescriptionOrderStatus.paid;
      case 'preparing':
        return PrescriptionOrderStatus.preparing;
      case 'outfordelivery':
        return PrescriptionOrderStatus.outForDelivery;
      case 'delivered':
        return PrescriptionOrderStatus.delivered;
      case 'cancelled':
        return PrescriptionOrderStatus.cancelled;
      case 'rejected':
        return PrescriptionOrderStatus.rejected;
      default:
        return PrescriptionOrderStatus.unknown;
    }
  }

  String get statusLabel {
    switch (status) {
      case PrescriptionOrderStatus.placed:
        return 'Placed';
      case PrescriptionOrderStatus.accepted:
        return 'Accepted';
      case PrescriptionOrderStatus.billed:
        return 'Bill ready';
      case PrescriptionOrderStatus.paidPendingVerification:
        return 'Payment verification';
      case PrescriptionOrderStatus.paid:
        return 'Paid';
      case PrescriptionOrderStatus.preparing:
        return 'Preparing';
      case PrescriptionOrderStatus.outForDelivery:
        return 'Out for delivery';
      case PrescriptionOrderStatus.delivered:
        return 'Delivered';
      case PrescriptionOrderStatus.cancelled:
        return 'Cancelled';
      case PrescriptionOrderStatus.rejected:
        return 'Rejected';
      case PrescriptionOrderStatus.unknown:
        return 'Unknown';
    }
  }

  bool get canPatientCancel =>
      status == PrescriptionOrderStatus.placed ||
      status == PrescriptionOrderStatus.accepted;

  bool get canPatientPay => status == PrescriptionOrderStatus.billed;

  bool get canChemistVerify =>
      status == PrescriptionOrderStatus.paidPendingVerification;

  bool get hasReceipt => receiptNumber != null && receiptNumber!.isNotEmpty;

  /// Doctor line as it should appear on a printed prescription:
  /// "Dr. Name, Qualification, Reg. No. XXXXX"
  String get doctorLine {
    final parts = <String>[];
    if (doctorName.isNotEmpty) parts.add('Dr. $doctorName');
    if ((doctorQualification ?? '').trim().isNotEmpty)
      parts.add(doctorQualification!.trim());
    if ((doctorRegistrationNumber ?? '').trim().isNotEmpty)
      parts.add('Reg. No. ${doctorRegistrationNumber!.trim()}');
    return parts.join(', ');
  }
}