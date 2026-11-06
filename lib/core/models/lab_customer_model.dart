// lib/core/models/lab_customer_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// The two ways a patient can enter the lab's customer directory.
enum LabCustomerSource { clinicLinked, direct }

/// A lab-owned customer record. Never duplicates the referring clinic's
/// patient; deterministic doc IDs guarantee that.
///
///   • source = clinicLinked → docId = 'cl_${sourceClinicId}_${sourcePatientDocId}'
///   • source = direct       → docId = random; displayPatientId = 'LAB-YYYY-NNNN'
class LabCustomerModel {
  final String docId;
  final String labClinicId;
  final LabCustomerSource source;

  /// Human-readable ID shown to the patient:
  ///   clinicLinked → the referring clinic's patientId (e.g. PT-2026-0042)
  ///   direct       → lab-generated 'LAB-YYYY-NNNN'
  final String displayPatientId;

  // Copied identity — lab's own copy for promotions/analytics
  final String fullName;
  final String phone;
  final String? email;
  final String gender;
  final DateTime? dob;
  final String? bloodGroup;

  // Source linkage (clinicLinked only)
  final String? sourceClinicId;
  final String? sourceClinicName;
  final String? sourcePatientDocId;
  final String? sourcePatientId;

  // Free-text referrer (direct only)
  final String? referredByName;
  final String? referredByClinicName;

  // Stats
  final int orderCount;
  final DateTime? lastOrderAt;

  final bool active;
  final DateTime? createdAt;
  final String? createdByUid;
  final DateTime? updatedAt;
  final String? updatedByUid;

  LabCustomerModel({
    required this.docId,
    required this.labClinicId,
    required this.source,
    required this.displayPatientId,
    required this.fullName,
    required this.phone,
    this.email,
    required this.gender,
    this.dob,
    this.bloodGroup,
    this.sourceClinicId,
    this.sourceClinicName,
    this.sourcePatientDocId,
    this.sourcePatientId,
    this.referredByName,
    this.referredByClinicName,
    this.orderCount = 0,
    this.lastOrderAt,
    this.active = true,
    this.createdAt,
    this.createdByUid,
    this.updatedAt,
    this.updatedByUid,
  });

  bool get isClinicLinked => source == LabCustomerSource.clinicLinked;
  bool get isDirect => source == LabCustomerSource.direct;

  static String deterministicId({
    required String sourceClinicId,
    required String sourcePatientDocId,
  }) =>
      'cl_${sourceClinicId}_$sourcePatientDocId';

  Map<String, dynamic> toMap() => {
        'labClinicId': labClinicId,
        'source': source == LabCustomerSource.clinicLinked
    ? 'clinic_linked'
    : 'direct',
        'displayPatientId': displayPatientId,
        'fullName': fullName,
        'phone': phone,
        'email': email,
        'gender': gender,
        'dob': dob?.toIso8601String(),
        'bloodGroup': bloodGroup,
        'sourceClinicId': sourceClinicId,
        'sourceClinicName': sourceClinicName,
        'sourcePatientDocId': sourcePatientDocId,
        'sourcePatientId': sourcePatientId,
        'referredByName': referredByName,
        'referredByClinicName': referredByClinicName,
        'orderCount': orderCount,
        'lastOrderAt': lastOrderAt != null
            ? Timestamp.fromDate(lastOrderAt!)
            : null,
        'active': active,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        'createdByUid': createdByUid,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUid': updatedByUid,
      };

  factory LabCustomerModel.fromMap(String docId, Map<String, dynamic> m) {
    DateTime? parse(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final srcRaw = (m['source'] ?? 'direct').toString();
final src = (srcRaw == 'clinic_linked' || srcRaw == 'clinicLinked')
    ? LabCustomerSource.clinicLinked
    : LabCustomerSource.direct;

    return LabCustomerModel(
      docId: docId,
      labClinicId: (m['labClinicId'] ?? '').toString(),
      source: src,
      displayPatientId: (m['displayPatientId'] ?? '').toString(),
      fullName: (m['fullName'] ?? '').toString(),
      phone: (m['phone'] ?? '').toString(),
      email: m['email']?.toString(),
      gender: (m['gender'] ?? 'male').toString(),
      dob: parse(m['dob']),
      bloodGroup: m['bloodGroup']?.toString(),
      sourceClinicId: m['sourceClinicId']?.toString(),
      sourceClinicName: m['sourceClinicName']?.toString(),
      sourcePatientDocId: m['sourcePatientDocId']?.toString(),
      sourcePatientId: m['sourcePatientId']?.toString(),
      referredByName: m['referredByName']?.toString(),
      referredByClinicName: m['referredByClinicName']?.toString(),
      orderCount: (m['orderCount'] as num?)?.toInt() ?? 0,
      lastOrderAt: parse(m['lastOrderAt']),
      active: m['active'] != false,
      createdAt: parse(m['createdAt']),
      createdByUid: m['createdByUid']?.toString(),
      updatedAt: parse(m['updatedAt']),
      updatedByUid: m['updatedByUid']?.toString(),
    );
  }
}