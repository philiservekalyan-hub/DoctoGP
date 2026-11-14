// lib/core/models/chemist_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum DeliveryMatch { delivers, outside, pickupOnly, unknown }

class ChemistModel {
  final String docId;
  final String name;
  final String ownerName;
  final String phone;
  final String email;
  final String address;
  final String city;
  final String pincode;
  final String licenseNumber;

  /// Clinics this chemist has a partnership with (metadata only —
  /// NOT used to gate patient access; delivery is pincode-driven).
  final List<String> linkedClinicIds;

  /// Pincodes where this chemist delivers. Empty list + deliveryAvailable
  /// = false means pickup-only.
  final List<String> serviceablePincodes;

  final bool deliveryAvailable;
  final double deliveryRadiusKm;
  final double deliveryFee;
  final double? minOrderAmount;
  final double? discountPercent;

  final String upiId;
  final String? upiQrUrl;

  final bool isActive;
  final bool isVetted;

  // ── invite state (Option A variant c) ──
  /// UID of the linked Firebase Auth user, set when the admin sends
  /// an invite (or when "Link login" attaches an existing account).
  final String? linkedUserUid;

  /// 'sent' | 'activated' | null
  final String? inviteStatus;

  final DateTime? inviteSentAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  ChemistModel({
    required this.docId,
    required this.name,
    this.ownerName = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.city = '',
    this.pincode = '',
    this.licenseNumber = '',
    this.linkedClinicIds = const [],
    this.serviceablePincodes = const [],
    this.deliveryAvailable = false,
    this.deliveryRadiusKm = 0,
    this.deliveryFee = 0,
    this.minOrderAmount,
    this.discountPercent,
    this.upiId = '',
    this.upiQrUrl,
    this.isActive = true,
    this.isVetted = true,
    this.linkedUserUid,
    this.inviteStatus,
    this.inviteSentAt,
    this.createdAt,
    this.updatedAt,
  });

  factory ChemistModel.fromMap(String id, Map<String, dynamic> m) {
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    double asDouble(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
    double? asDoubleOrNull(dynamic v) =>
        v == null ? null : asDouble(v);
    List<String> asList(dynamic v) => v is List
        ? v.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
        : const [];

    return ChemistModel(
      docId: id,
      name: (m['name'] ?? '').toString(),
      ownerName: (m['ownerName'] ?? '').toString(),
      phone: (m['phone'] ?? '').toString(),
      email: (m['email'] ?? '').toString(),
      address: (m['address'] ?? '').toString(),
      city: (m['city'] ?? '').toString(),
      pincode: (m['pincode'] ?? '').toString(),
      licenseNumber: (m['licenseNumber'] ?? '').toString(),
      linkedClinicIds: asList(m['linkedClinicIds']),
      serviceablePincodes: asList(m['serviceablePincodes']),
      deliveryAvailable: m['deliveryAvailable'] == true,
      deliveryRadiusKm: asDouble(m['deliveryRadiusKm']),
      deliveryFee: asDouble(m['deliveryFee']),
      minOrderAmount: asDoubleOrNull(m['minOrderAmount']),
      discountPercent: asDoubleOrNull(m['discountPercent']),
      upiId: (m['upiId'] ?? '').toString(),
      upiQrUrl: m['upiQrUrl']?.toString(),
      isActive: m['isActive'] != false,
      isVetted: m['isVetted'] != false,
      linkedUserUid: m['linkedUserUid']?.toString(),
      inviteStatus: m['inviteStatus']?.toString(),
      inviteSentAt: ts(m['inviteSentAt']),
      createdAt: ts(m['createdAt']),
      updatedAt: ts(m['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'ownerName': ownerName,
        'phone': phone,
        'email': email,
        'address': address,
        'city': city,
        'pincode': pincode,
        'licenseNumber': licenseNumber,
        'linkedClinicIds': linkedClinicIds,
        'serviceablePincodes': serviceablePincodes,
        'deliveryAvailable': deliveryAvailable,
        'deliveryRadiusKm': deliveryRadiusKm,
        'deliveryFee': deliveryFee,
        'minOrderAmount': minOrderAmount,
        'discountPercent': discountPercent,
        'upiId': upiId,
        'upiQrUrl': upiQrUrl,
        'isActive': isActive,
        'isVetted': isVetted,
        'linkedUserUid': linkedUserUid,
        'inviteStatus': inviteStatus,
        'inviteSentAt': inviteSentAt != null
            ? Timestamp.fromDate(inviteSentAt!)
            : null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  String get fullAddress {
    final parts = <String>[address, city, pincode]
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return parts.join(', ');
  }

  /// Compact delivery status label for UI.
  /// `patientPincode` may be empty — then we only show the chemist's
  /// general delivery info.
  DeliveryMatch matchDelivery(String patientPincode) {
    final p = patientPincode.trim();
    if (p.isEmpty) {
      return deliveryAvailable
          ? DeliveryMatch.unknown
          : DeliveryMatch.pickupOnly;
    }
    if (serviceablePincodes.contains(p)) return DeliveryMatch.delivers;
    if (deliveryAvailable && pincode == p) return DeliveryMatch.delivers;
    if (!deliveryAvailable) return DeliveryMatch.pickupOnly;
    return DeliveryMatch.outside;
  }

  /// Returns a UPI deep-link the patient can launch to pre-fill the
  /// chemist's UPI ID and the amount due. Works with GPay, PhonePe,
  /// Paytm, BHIM, etc.
  ///
  /// Example:
  /// upi://pay?pa=pharmacy@okicici&pn=MedPlus&am=240.00&cu=INR&tn=RX-123456
  Uri? upiPaymentUri({
    required double amount,
    required String orderNumber,
  }) {
    if (upiId.trim().isEmpty) return null;
    return Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': upiId.trim(),
        'pn': name,
        'am': amount.toStringAsFixed(2),
        'cu': 'INR',
        'tn': 'Rx $orderNumber',
      },
    );
  }
}