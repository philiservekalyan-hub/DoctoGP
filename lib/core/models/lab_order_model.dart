// lib/core/models/lab_order_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// One test within a lab order. `code` is optional for custom tests.
class LabTestItem {
  final String? code;
  final String name;
  final String? notes;

  LabTestItem({this.code, required this.name, this.notes});

  Map<String, dynamic> toMap() => {
        if (code != null && code!.isNotEmpty) 'code': code,
        'name': name,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };

  factory LabTestItem.fromMap(Map<String, dynamic> m) => LabTestItem(
        code: m['code']?.toString(),
        name: (m['name'] ?? '').toString(),
        notes: m['notes']?.toString(),
      );

  String get label =>
      (code != null && code!.isNotEmpty) ? '$code — $name' : name;
}

enum LabOrderStatus {
  ordered,
  accepted,
  sampleCollected,
  processing,
  ready,
  delivered,
  cancelled,
  noShow,
  unknown,
}

// ── Patient-paid lab order lifecycle (Model A) ──
enum LabPaymentStatus { unpaid, paid, waived }

class LabOrderModel {
  final String docId;

  // Two-sided link — where the order came from and where it goes.
  //
  // `referringClinicId`, `doctorDocId`, and `doctorName` are null for
  // walk-in orders (patient came to the lab directly, no clinic or
  // doctor referred them).
  final String? referringClinicId;
  final String labClinicId;
  final String labName;
  final String? deptId;

  final String patientDocId;
  final String patientId;
  final String patientName;
  final String? patientPhone;

  final String? doctorDocId;
  final String? doctorName;
  final String? appointmentId;

  final List<LabTestItem> tests;
  final String? instructions;
  final String? referralNotes;

  final LabOrderStatus status;

  final DateTime? orderedAt;
  final DateTime? acceptedAt;
  final DateTime? sampleCollectedAt;
  final DateTime? processingStartedAt;
  final DateTime? reportReadyAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final DateTime? noShowAt;

  final String? cancelledByRole;
  final String? cancelReason;
  final String? noShowReason;

  final String? reportUrl;
  final String? reportFileName;
  final String? reportStoragePath;
  final DateTime? reportUploadedAt;

  // ── Report release control ──
  //
  // The lab technician uploads the report and sets status = `ready`,
  // but the report is NOT visible to the patient or the referring
  // doctor until the lab receptionist has verified payment and
  // explicitly released it (`released == true`).
  //
  // Before this field existed, `status == ready` implied the report
  // was final and visible. That coupling is now broken: `released`
  // is the gate on visibility, `status` is the pipeline stage.
  //
  // Existing lab orders deserialize with `released == false` —
  // receptionists should review and release them manually.
  final bool released;
  final DateTime? releasedAt;
  final String? releasedByUid;

  // ── Patient-facing billing (Model A) ──
  final double? billableAmount;
  final LabPaymentStatus paymentStatus;
  final DateTime? feesPaidAt;
  final String? feesCollectedByUid;

  LabOrderModel({
    required this.docId,
    this.referringClinicId,
    required this.labClinicId,
    required this.labName,
    this.deptId,
    required this.patientDocId,
    required this.patientId,
    required this.patientName,
    this.patientPhone,
    this.doctorDocId,
    this.doctorName,
    this.appointmentId,
    required this.tests,
    this.instructions,
    this.referralNotes,
    required this.status,
    this.orderedAt,
    this.acceptedAt,
    this.sampleCollectedAt,
    this.processingStartedAt,
    this.reportReadyAt,
    this.deliveredAt,
    this.cancelledAt,
    this.noShowAt,
    this.cancelledByRole,
    this.cancelReason,
    this.noShowReason,
    this.reportUrl,
    this.reportFileName,
    this.reportStoragePath,
    this.reportUploadedAt,
    this.released = false,
    this.releasedAt,
    this.releasedByUid,
    this.billableAmount,
    this.paymentStatus = LabPaymentStatus.unpaid,
    this.feesPaidAt,
    this.feesCollectedByUid,
  });

  bool get isWalkIn =>
      (referringClinicId == null || referringClinicId!.isEmpty) &&
      (doctorDocId == null || doctorDocId!.isEmpty);

  /// True if the report has been uploaded by the technician but not
  /// yet released by the receptionist.
  ///
  /// This is the state a receptionist uses to see "reports awaiting
  /// payment check" on their dashboard. It's the ONLY state in which
  /// the report is invisible to the patient and referring doctor.
  bool get awaitingRelease =>
      status == LabOrderStatus.ready && !released;

  /// True if the report is uploaded AND released — meaning the
  /// patient and referring doctor can see it.
  bool get reportVisible =>
      status == LabOrderStatus.ready &&
      released &&
      (reportUrl?.isNotEmpty ?? false);

  static LabOrderStatus _parseStatus(dynamic v) {
    switch ('${v ?? ''}'.toLowerCase()) {
      case 'ordered':
        return LabOrderStatus.ordered;
      case 'accepted':
        return LabOrderStatus.accepted;
      case 'samplecollected':
        return LabOrderStatus.sampleCollected;
      case 'processing':
        return LabOrderStatus.processing;
      case 'ready':
        return LabOrderStatus.ready;
      case 'delivered':
        return LabOrderStatus.delivered;
      case 'cancelled':
        return LabOrderStatus.cancelled;
      case 'noshow':
        return LabOrderStatus.noShow;
      default:
        return LabOrderStatus.unknown;
    }
  }

  static LabPaymentStatus _parsePayment(dynamic v) {
    switch ('${v ?? ''}'.toLowerCase()) {
      case 'paid':
        return LabPaymentStatus.paid;
      case 'waived':
        return LabPaymentStatus.waived;
      default:
        return LabPaymentStatus.unpaid;
    }
  }

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory LabOrderModel.fromMap(String id, Map<String, dynamic> m) {
    final rawTests = m['tests'];
    final tests = <LabTestItem>[];
    if (rawTests is List) {
      for (final t in rawTests) {
        if (t is Map) {
          tests.add(LabTestItem.fromMap(Map<String, dynamic>.from(t)));
        } else if (t is String) {
          tests.add(LabTestItem(name: t));
        }
      }
    }

    return LabOrderModel(
      docId: id,
      referringClinicId: m['referringClinicId']?.toString(),
      labClinicId: (m['labClinicId'] ?? '').toString(),
      labName: (m['labName'] ?? '').toString(),
      deptId: m['deptId']?.toString(),
      patientDocId: (m['patientDocId'] ?? '').toString(),
      patientId: (m['patientId'] ?? '').toString(),
      patientName: (m['patientName'] ?? '').toString(),
      patientPhone: m['patientPhone']?.toString(),
      doctorDocId: m['doctorDocId']?.toString(),
      doctorName: m['doctorName']?.toString(),
      appointmentId: m['appointmentId']?.toString(),
      tests: tests,
      instructions: m['instructions']?.toString(),
      referralNotes: m['referralNotes']?.toString(),
      status: _parseStatus(m['status']),
      orderedAt: _date(m['orderedAt']),
      acceptedAt: _date(m['acceptedAt']),
      sampleCollectedAt: _date(m['sampleCollectedAt']),
      processingStartedAt: _date(m['processingStartedAt']),
      reportReadyAt: _date(m['reportReadyAt']),
      deliveredAt: _date(m['deliveredAt']),
      cancelledAt: _date(m['cancelledAt']),
      noShowAt: _date(m['noShowAt']),
      cancelledByRole: m['cancelledByRole']?.toString(),
      cancelReason: m['cancelReason']?.toString(),
      noShowReason: m['noShowReason']?.toString(),
      reportUrl: m['reportUrl']?.toString(),
      reportFileName: m['reportFileName']?.toString(),
      reportStoragePath: m['reportStoragePath']?.toString(),
      reportUploadedAt: _date(m['reportUploadedAt']),
      released: m['released'] == true,
      releasedAt: _date(m['releasedAt']),
      releasedByUid: m['releasedByUid']?.toString(),
      billableAmount: (m['billableAmount'] as num?)?.toDouble(),
      paymentStatus: _parsePayment(m['paymentStatus']),
      feesPaidAt: _date(m['feesPaidAt']),
      feesCollectedByUid: m['feesCollectedByUid']?.toString(),
    );
  }

  String get statusLabel {
    switch (status) {
      case LabOrderStatus.ordered:
        return 'Ordered';
      case LabOrderStatus.accepted:
        return 'Accepted';
      case LabOrderStatus.sampleCollected:
        return 'Sample collected';
      case LabOrderStatus.processing:
        return 'Processing';
      case LabOrderStatus.ready:
        return released ? 'Ready' : 'Ready (awaiting release)';
      case LabOrderStatus.delivered:
        return 'Delivered';
      case LabOrderStatus.cancelled:
        return 'Cancelled';
      case LabOrderStatus.noShow:
        return 'No-show';
      case LabOrderStatus.unknown:
        return 'Unknown';
    }
  }

  String get paymentStatusLabel {
    switch (paymentStatus) {
      case LabPaymentStatus.paid:
        return 'Paid';
      case LabPaymentStatus.waived:
        return 'Waived';
      case LabPaymentStatus.unpaid:
        return 'Unpaid';
    }
  }

  String get testsSummary => tests.isEmpty
      ? 'Lab test'
      : tests.map((t) => t.code ?? t.name).join(', ');
}