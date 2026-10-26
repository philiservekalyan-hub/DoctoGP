import 'package:cloud_firestore/cloud_firestore.dart';

enum AppointmentStatus {
  booked,
  awaitingConfirmation,
  confirmed,
  onHold,
  declined,
  checkedIn,
  inConsult,
  completed,
  cancelled,
  noShow,
}

// ── NEW ── billing state for the reception flow
enum PaymentStatus { unpaid, paid, waived }

class AppointmentModel {
  final String docId;
  final String appointmentCode;
  final String clinicId;

  final String patientDocId;
  final String patientId;
  final String patientName;
  final String patientPhone;

  final String doctorDocId;
  final String doctorName;

  final DateTime slot;
  final String? slotPeriod;
  final String? slotKey;
  final int tokenNumber;
  final String tokenLabel;
  final int queuePosition;

  final AppointmentStatus status;
  final String? chiefComplaint;
  final String? type;

  final bool confirmationRequested;
  final DateTime? confirmedAt;
  final DateTime? declinedAt;
  final String? declineReason;

  final DateTime? checkedInAt;
  final DateTime? consultStartedAt;
  final DateTime? consultEndedAt;
  final DateTime createdAt;

  // ── NEW ── billing
  final double? consultationFees;
  final String? feesSetByDoctorId;
  final PaymentStatus paymentStatus;
  final DateTime? feesPaidAt;
  final String? feesCollectedByUid;

  AppointmentModel({
    required this.docId,
    required this.appointmentCode,
    required this.clinicId,
    required this.patientDocId,
    required this.patientId,
    required this.patientName,
    required this.patientPhone,
    required this.doctorDocId,
    required this.doctorName,
    required this.slot,
    this.slotPeriod,
    this.slotKey,
    required this.tokenNumber,
    required this.tokenLabel,
    this.queuePosition = 0,
    this.status = AppointmentStatus.booked,
    this.chiefComplaint,
    this.type = 'in_person',
    this.confirmationRequested = false,
    this.confirmedAt,
    this.declinedAt,
    this.declineReason,
    this.checkedInAt,
    this.consultStartedAt,
    this.consultEndedAt,
    required this.createdAt,
    this.consultationFees,
    this.feesSetByDoctorId,
    this.paymentStatus = PaymentStatus.unpaid,
    this.feesPaidAt,
    this.feesCollectedByUid,
  });

  Map<String, dynamic> toMap() => {
        'appointmentCode': appointmentCode,
        'clinicId': clinicId,
        'patientDocId': patientDocId,
        'patientId': patientId,
        'patientName': patientName,
        'patientPhone': patientPhone,
        'doctorDocId': doctorDocId,
        'doctorName': doctorName,
        'slot': Timestamp.fromDate(slot),
        'slotPeriod': slotPeriod,
        'slotKey': slotKey,
        'tokenNumber': tokenNumber,
        'tokenLabel': tokenLabel,
        'queuePosition': queuePosition,
        'status': status.name,
        'chiefComplaint': chiefComplaint,
        'type': type,
        'confirmationRequested': confirmationRequested,
        'confirmedAt':
            confirmedAt != null ? Timestamp.fromDate(confirmedAt!) : null,
        'declinedAt':
            declinedAt != null ? Timestamp.fromDate(declinedAt!) : null,
        'declineReason': declineReason,
        'checkedInAt': checkedInAt != null
            ? Timestamp.fromDate(checkedInAt!)
            : null,
        'consultStartedAt': consultStartedAt != null
            ? Timestamp.fromDate(consultStartedAt!)
            : null,
        'consultEndedAt': consultEndedAt != null
            ? Timestamp.fromDate(consultEndedAt!)
            : null,
        'createdAt': Timestamp.fromDate(createdAt),
        'consultationFees': consultationFees,
        'feesSetByDoctorId': feesSetByDoctorId,
        'paymentStatus': paymentStatus.name,
        'feesPaidAt':
            feesPaidAt != null ? Timestamp.fromDate(feesPaidAt!) : null,
        'feesCollectedByUid': feesCollectedByUid,
      };

  factory AppointmentModel.fromMap(String docId, Map<String, dynamic> map) {
    DateTime ts(dynamic v) =>
        v is Timestamp ? v.toDate() : DateTime.now();

    return AppointmentModel(
      docId: docId,
      appointmentCode: map['appointmentCode'] ?? '',
      clinicId: map['clinicId'] ?? '',
      patientDocId: map['patientDocId'] ?? '',
      patientId: map['patientId'] ?? '',
      patientName: map['patientName'] ?? '',
      patientPhone: map['patientPhone'] ?? '',
      doctorDocId: map['doctorDocId'] ?? '',
      doctorName: map['doctorName'] ?? '',
      slot: ts(map['slot']),
      slotPeriod: map['slotPeriod'] as String?,
      slotKey: map['slotKey'] as String?,
      tokenNumber: map['tokenNumber'] ?? 0,
      tokenLabel: map['tokenLabel'] ?? '',
      queuePosition: map['queuePosition'] ?? 0,
      status: _parseStatus(map['status']),
      chiefComplaint: map['chiefComplaint'],
      type: map['type'] ?? 'in_person',
      confirmationRequested: map['confirmationRequested'] ?? false,
      confirmedAt:
          map['confirmedAt'] != null ? ts(map['confirmedAt']) : null,
      declinedAt:
          map['declinedAt'] != null ? ts(map['declinedAt']) : null,
      declineReason: map['declineReason'],
      checkedInAt:
          map['checkedInAt'] != null ? ts(map['checkedInAt']) : null,
      consultStartedAt: map['consultStartedAt'] != null
          ? ts(map['consultStartedAt'])
          : null,
      consultEndedAt: map['consultEndedAt'] != null
          ? ts(map['consultEndedAt'])
          : null,
      createdAt: ts(map['createdAt']),
      consultationFees: (map['consultationFees'] as num?)?.toDouble(),
      feesSetByDoctorId: map['feesSetByDoctorId'] as String?,
      paymentStatus: _parsePayment(map['paymentStatus']),
      feesPaidAt:
          map['feesPaidAt'] != null ? ts(map['feesPaidAt']) : null,
      feesCollectedByUid: map['feesCollectedByUid'] as String?,
    );
  }

  static AppointmentStatus _parseStatus(String? s) {
    switch (s) {
      case 'awaitingConfirmation':
        return AppointmentStatus.awaitingConfirmation;
      case 'confirmed':
        return AppointmentStatus.confirmed;
      case 'onHold':
        return AppointmentStatus.onHold;
      case 'declined':
        return AppointmentStatus.declined;
      case 'checkedIn':
        return AppointmentStatus.checkedIn;
      case 'inConsult':
        return AppointmentStatus.inConsult;
      case 'completed':
        return AppointmentStatus.completed;
      case 'cancelled':
        return AppointmentStatus.cancelled;
      case 'noShow':
        return AppointmentStatus.noShow;
      case 'booked':
      default:
        return AppointmentStatus.booked;
    }
  }

  static PaymentStatus _parsePayment(dynamic v) {
    switch ('${v ?? ''}'.toLowerCase()) {
      case 'paid':
        return PaymentStatus.paid;
      case 'waived':
        return PaymentStatus.waived;
      default:
        return PaymentStatus.unpaid;
    }
  }

  String get statusLabel {
    switch (status) {
      case AppointmentStatus.booked:
        return 'Booked';
      case AppointmentStatus.awaitingConfirmation:
        return 'Awaiting Confirmation';
      case AppointmentStatus.confirmed:
        return 'Confirmed';
      case AppointmentStatus.onHold:
        return 'On Hold';
      case AppointmentStatus.declined:
        return 'Declined';
      case AppointmentStatus.checkedIn:
        return 'Checked In';
      case AppointmentStatus.inConsult:
        return 'In Consult';
      case AppointmentStatus.completed:
        return 'Completed';
      case AppointmentStatus.cancelled:
        return 'Cancelled';
      case AppointmentStatus.noShow:
        return 'No Show';
    }
  }

  String get paymentStatusLabel {
    switch (paymentStatus) {
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.waived:
        return 'Waived';
      case PaymentStatus.unpaid:
        return 'Unpaid';
    }
  }

  bool get withinConfirmationWindow {
    final now = DateTime.now();
    final diff = slot.difference(now);
    return diff.inHours <= 48 && diff.inHours >= -1;
  }

  static String makeSlotKey(DateTime slot, String period) {
    final y = slot.year;
    final m = slot.month.toString().padLeft(2, '0');
    final d = slot.day.toString().padLeft(2, '0');
    return '${y}-${m}-${d}_$period';
  }

  static (DateTime start, DateTime end) slotWindow(
      DateTime day, String period) {
    final base = DateTime(day.year, day.month, day.day);
    switch (period) {
      case 'morning':
        return (
          base.add(const Duration(hours: 9)),
          base.add(const Duration(hours: 12)),
        );
      case 'afternoon':
        return (
          base.add(const Duration(hours: 13)),
          base.add(const Duration(hours: 16)),
        );
      case 'evening':
        return (
          base.add(const Duration(hours: 17)),
          base.add(const Duration(hours: 20)),
        );
      default:
        return (base, base.add(const Duration(days: 1)));
    }
  }

  static String periodFromHour(int hour) {
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  String get slotPeriodLabel {
    switch (slotPeriod) {
      case 'morning':
        return 'Morning (9:00 – 12:00)';
      case 'afternoon':
        return 'Afternoon (13:00 – 16:00)';
      case 'evening':
        return 'Evening (17:00 – 20:00)';
      default:
        return 'Scheduled';
    }
  }

  AppointmentModel copyWith({
    int? queuePosition,
    AppointmentStatus? status,
    bool? confirmationRequested,
    DateTime? confirmedAt,
    DateTime? declinedAt,
    String? declineReason,
    DateTime? checkedInAt,
    DateTime? consultStartedAt,
    DateTime? consultEndedAt,
    String? slotPeriod,
    String? slotKey,
    double? consultationFees,
    String? feesSetByDoctorId,
    PaymentStatus? paymentStatus,
    DateTime? feesPaidAt,
    String? feesCollectedByUid,
  }) {
    return AppointmentModel(
      docId: docId,
      appointmentCode: appointmentCode,
      clinicId: clinicId,
      patientDocId: patientDocId,
      patientId: patientId,
      patientName: patientName,
      patientPhone: patientPhone,
      doctorDocId: doctorDocId,
      doctorName: doctorName,
      slot: slot,
      slotPeriod: slotPeriod ?? this.slotPeriod,
      slotKey: slotKey ?? this.slotKey,
      tokenNumber: tokenNumber,
      tokenLabel: tokenLabel,
      queuePosition: queuePosition ?? this.queuePosition,
      status: status ?? this.status,
      chiefComplaint: chiefComplaint,
      type: type,
      confirmationRequested:
          confirmationRequested ?? this.confirmationRequested,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      declinedAt: declinedAt ?? this.declinedAt,
      declineReason: declineReason ?? this.declineReason,
      checkedInAt: checkedInAt ?? this.checkedInAt,
      consultStartedAt: consultStartedAt ?? this.consultStartedAt,
      consultEndedAt: consultEndedAt ?? this.consultEndedAt,
      createdAt: createdAt,
      consultationFees: consultationFees ?? this.consultationFees,
      feesSetByDoctorId: feesSetByDoctorId ?? this.feesSetByDoctorId,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      feesPaidAt: feesPaidAt ?? this.feesPaidAt,
      feesCollectedByUid: feesCollectedByUid ?? this.feesCollectedByUid,
    );
  }
}