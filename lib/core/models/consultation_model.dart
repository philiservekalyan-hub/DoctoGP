// lib/core/models/consultation_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Medication {
  final String name;
  final String dose;
  final String frequency;
  final String duration;

  const Medication({
    required this.name,
    this.dose = '',
    this.frequency = '',
    this.duration = '',
  });

  factory Medication.fromMap(Map<String, dynamic> m) => Medication(
        name: (m['name'] ?? '').toString(),
        dose: (m['dose'] ?? '').toString(),
        frequency: (m['frequency'] ?? '').toString(),
        duration: (m['duration'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'dose': dose,
        'frequency': frequency,
        'duration': duration,
      };
}

class ConsultationModel {
  final String docId;
  final String appointmentId;
  final String patientDocId;
  final String patientId;
  final String patientName;
  final String doctorDocId;
  final String doctorName;
  final String clinicId;

  final String? chiefComplaint;
  final String? rx;
  final String? notes;

  final String? symptoms;
  final String? diagnosis;

  // ── NEW (Phase 1) ──
  final String? diagnosisCode;
  final String? diagnosisText;

  final List<Medication> medications;
  final Map<String, String> vitals;
  final List<String> labOrderIds;
  final String? followUpPlan;

  // ── NEW (Phase 1) ──
  final String? disposition;   // Disposition.name — parsed at UI layer

  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ConsultationModel({
    required this.docId,
    required this.appointmentId,
    required this.patientDocId,
    required this.patientId,
    required this.patientName,
    required this.doctorDocId,
    required this.doctorName,
    required this.clinicId,
    this.chiefComplaint,
    this.rx,
    this.notes,
    this.symptoms,
    this.diagnosis,
    this.diagnosisCode,
    this.diagnosisText,
    this.medications = const [],
    this.vitals = const {},
    this.labOrderIds = const [],
    this.followUpPlan,
    this.disposition,
    this.startedAt,
    this.endedAt,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'appointmentId': appointmentId,
        'patientDocId': patientDocId,
        'patientId': patientId,
        'patientName': patientName,
        'doctorDocId': doctorDocId,
        'doctorName': doctorName,
        'clinicId': clinicId,
        'chiefComplaint': chiefComplaint,
        'symptoms': symptoms,
        'diagnosis': diagnosis,
        'diagnosisCode': diagnosisCode,
        'diagnosisText': diagnosisText,
        'medications': medications.map((m) => m.toMap()).toList(),
        'rx': rx,
        'notes': notes,
        'vitals': vitals,
        'labOrderIds': labOrderIds,
        'followUpPlan': followUpPlan,
        'disposition': disposition,
        'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
        'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toUpdateMap() {
    final m = toMap();
    m.remove('createdAt');
    return m;
  }

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory ConsultationModel.fromMap(String id, Map<String, dynamic> m) {
    final vitalsRaw = m['vitals'];
    final vitals = <String, String>{};
    if (vitalsRaw is Map) {
      vitalsRaw.forEach((k, v) => vitals['$k'] = '$v');
    }

    final medsRaw = m['medications'];
    final meds = <Medication>[];
    if (medsRaw is List) {
      for (final e in medsRaw) {
        if (e is Map) {
          meds.add(Medication.fromMap(Map<String, dynamic>.from(e)));
        }
      }
    }

    return ConsultationModel(
      docId: id,
      appointmentId: (m['appointmentId'] ?? id).toString(),
      patientDocId: (m['patientDocId'] ?? '').toString(),
      patientId: (m['patientId'] ?? '').toString(),
      patientName: (m['patientName'] ?? '').toString(),
      doctorDocId: (m['doctorDocId'] ?? '').toString(),
      doctorName: (m['doctorName'] ?? '').toString(),
      clinicId: (m['clinicId'] ?? '').toString(),
      chiefComplaint: m['chiefComplaint']?.toString(),
      rx: m['rx']?.toString(),
      notes: m['notes']?.toString(),
      symptoms: m['symptoms']?.toString(),
      diagnosis: m['diagnosis']?.toString(),
      diagnosisCode: m['diagnosisCode']?.toString(),
      diagnosisText: m['diagnosisText']?.toString(),
      medications: meds,
      vitals: vitals,
      labOrderIds: (m['labOrderIds'] is List)
          ? (m['labOrderIds'] as List).map((e) => '$e').toList()
          : const [],
      followUpPlan: m['followUpPlan']?.toString(),
      disposition: m['disposition']?.toString(),
      startedAt: _date(m['startedAt']),
      endedAt: _date(m['endedAt']),
      createdAt: _date(m['createdAt']),
      updatedAt: _date(m['updatedAt']),
    );
  }
}