import 'package:cloud_firestore/cloud_firestore.dart';

enum AppointmentRequestStatus {
  pending,
  approved,
  rejected,
  cancelled,
  rescheduled,
}

class AppointmentRequestModel {
  final String docId;
  final String patientDocId;
  final String patientId;
  final String patientName;
  final String? patientPhone;
  final String? clinicId;
  final String reason;
  final String? preferredTimeOfDay;
  final List<String> preferredDates;
  final String kind; // 'new' | 're_appointment'
  final AppointmentRequestStatus status;
  final DateTime? requestedAt;
  final DateTime? reviewedAt;
  final String? reviewedByUid;
  final String? assignedAppointmentId;

  // Snapshot of what the receptionist assigned (in case the appointment
  // doc is later archived or moved).
  final String? assignedDoctorDocId;
  final String? assignedDoctorName;
  final DateTime? assignedSlot;

  final String? rejectionReason;

  AppointmentRequestModel({
    required this.docId,
    required this.patientDocId,
    required this.patientId,
    required this.patientName,
    this.patientPhone,
    this.clinicId,
    required this.reason,
    this.preferredTimeOfDay,
    this.preferredDates = const [],
    this.kind = 'new',
    required this.status,
    this.requestedAt,
    this.reviewedAt,
    this.reviewedByUid,
    this.assignedAppointmentId,
    this.assignedDoctorDocId,
    this.assignedDoctorName,
    this.assignedSlot,
    this.rejectionReason,
  });

  static AppointmentRequestStatus _parseStatus(dynamic v) {
    switch ('${v ?? 'pending'}'.toLowerCase()) {
      case 'approved':
        return AppointmentRequestStatus.approved;
      case 'rejected':
        return AppointmentRequestStatus.rejected;
      case 'cancelled':
        return AppointmentRequestStatus.cancelled;
      case 'rescheduled':
        return AppointmentRequestStatus.rescheduled;
      default:
        return AppointmentRequestStatus.pending;
    }
  }

  static DateTime? _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory AppointmentRequestModel.fromMap(
      String id, Map<String, dynamic> m) {
    return AppointmentRequestModel(
      docId: id,
      patientDocId: (m['patientDocId'] ?? '').toString(),
      patientId: (m['patientId'] ?? '').toString(),
      patientName: (m['patientName'] ?? 'Patient').toString(),
      patientPhone: m['patientPhone']?.toString(),
      clinicId: m['clinicId']?.toString(),
      reason: (m['reason'] ?? '').toString(),
      preferredTimeOfDay: m['preferredTimeOfDay']?.toString(),
      preferredDates: (m['preferredDates'] is List)
          ? (m['preferredDates'] as List).map((e) => '$e').toList()
          : const [],
      kind: (m['kind'] ?? 'new').toString(),
      status: _parseStatus(m['status']),
      requestedAt: _asDate(m['requestedAt']),
      reviewedAt: _asDate(m['reviewedAt']),
      reviewedByUid: m['reviewedByUid']?.toString(),
      assignedAppointmentId: m['assignedAppointmentId']?.toString(),
      assignedDoctorDocId: m['assignedDoctorDocId']?.toString(),
      assignedDoctorName: m['assignedDoctorName']?.toString(),
      assignedSlot: _asDate(m['assignedSlot']),
      rejectionReason: m['rejectionReason']?.toString(),
    );
  }

  String get statusLabel {
    switch (status) {
      case AppointmentRequestStatus.pending:
        return 'Pending review';
      case AppointmentRequestStatus.approved:
        return 'Approved';
      case AppointmentRequestStatus.rejected:
        return 'Rejected';
      case AppointmentRequestStatus.cancelled:
        return 'Cancelled';
      case AppointmentRequestStatus.rescheduled:
        return 'Rescheduled';
    }
  }
}