// lib/core/models/pill_models.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum PillDoseStatus {
  pending,
  taken,
  missed,
  skipped;

  static PillDoseStatus fromString(String? s) {
    switch (s) {
      case 'taken':
        return PillDoseStatus.taken;
      case 'missed':
        return PillDoseStatus.missed;
      case 'skipped':
        return PillDoseStatus.skipped;
      default:
        return PillDoseStatus.pending;
    }
  }

  String get wire => name;

  String get label => switch (this) {
        PillDoseStatus.pending => 'Pending',
        PillDoseStatus.taken => 'Taken',
        PillDoseStatus.missed => 'Missed',
        PillDoseStatus.skipped => 'Skipped',
      };
}

class PillSchedule {
  final String scheduleId;
  final String patientDocId;
  final String patientAuthUid;
  final String? clinicId;
  final String medicationName;
  final String dose;
  final List<String> times;
  final DateTime startDate;
  final DateTime? endDate;
  final int graceMinutes;
  final bool active;
  final String? prescribedBy;
  final String? notes;
  final String? deviceId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PillSchedule({
    required this.scheduleId,
    required this.patientDocId,
    required this.patientAuthUid,
    this.clinicId,
    required this.medicationName,
    required this.dose,
    required this.times,
    required this.startDate,
    this.endDate,
    this.graceMinutes = 30,
    this.active = true,
    this.prescribedBy,
    this.notes,
    this.deviceId,
    this.createdAt,
    this.updatedAt,
  });

  factory PillSchedule.fromMap(String id, Map<String, dynamic> m) {
    DateTime? ts(dynamic v) =>
        v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
    return PillSchedule(
      scheduleId: id,
      patientDocId: (m['patientDocId'] ?? '').toString(),
      patientAuthUid: (m['patientAuthUid'] ?? '').toString(),
      clinicId: m['clinicId'] as String?,
      medicationName: (m['medicationName'] ?? '').toString(),
      dose: (m['dose'] ?? '').toString(),
      times: (m['times'] as List?)?.cast<String>() ?? const [],
      startDate: ts(m['startDate']) ?? DateTime.now(),
      endDate: ts(m['endDate']),
      graceMinutes: (m['graceMinutes'] ?? 30) as int,
      active: m['active'] != false,
      prescribedBy: m['prescribedBy'] as String?,
      notes: m['notes'] as String?,
      deviceId: m['deviceId'] as String?,
      createdAt: ts(m['createdAt']),
      updatedAt: ts(m['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'patientDocId': patientDocId,
        'patientAuthUid': patientAuthUid,
        'clinicId': clinicId,
        'medicationName': medicationName,
        'dose': dose,
        'times': times,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': endDate == null ? null : Timestamp.fromDate(endDate!),
        'graceMinutes': graceMinutes,
        'active': active,
        'prescribedBy': prescribedBy,
        'notes': notes,
        'deviceId': deviceId,
      };

  String get summary => '$medicationName $dose';
}

class PillDose {
  final String doseId;
  final String scheduleId;
  final String patientDocId;
  final String patientAuthUid;
  final DateTime scheduledAt;
  final DateTime graceUntil;
  final PillDoseStatus status;
  final String? confirmedBy;
  final DateTime? confirmedAt;
  final String? deviceEventId;
  final Map<String, dynamic>? escalation;
  final String? notes;
  final String? medicationName;
  final String? dose;

  const PillDose({
    required this.doseId,
    required this.scheduleId,
    required this.patientDocId,
    required this.patientAuthUid,
    required this.scheduledAt,
    required this.graceUntil,
    this.status = PillDoseStatus.pending,
    this.confirmedBy,
    this.confirmedAt,
    this.deviceEventId,
    this.escalation,
    this.notes,
    this.medicationName,
    this.dose,
  });

  factory PillDose.fromMap(String id, Map<String, dynamic> m) {
    DateTime ts(dynamic v) =>
        v is Timestamp ? v.toDate() : (v is DateTime ? v : DateTime(2000));
    return PillDose(
      doseId: id,
      scheduleId: (m['scheduleId'] ?? '').toString(),
      patientDocId: (m['patientDocId'] ?? '').toString(),
      patientAuthUid: (m['patientAuthUid'] ?? '').toString(),
      scheduledAt: ts(m['scheduledAt']),
      graceUntil: ts(m['graceUntil']),
      status: PillDoseStatus.fromString(m['status'] as String?),
      confirmedBy: m['confirmedBy'] as String?,
      confirmedAt: m['confirmedAt'] is Timestamp
          ? (m['confirmedAt'] as Timestamp).toDate()
          : null,
      deviceEventId: m['deviceEventId'] as String?,
      escalation: m['escalation'] is Map
          ? Map<String, dynamic>.from(m['escalation'] as Map)
          : null,
      notes: m['notes'] as String?,
      medicationName: m['medicationName'] as String?,
      dose: m['dose'] as String?,
    );
  }

  String get summary {
    final name = medicationName ?? 'Medication';
    final d = dose ?? '';
    return d.isEmpty ? name : '$name · $d';
  }
}