// lib/features/doctor/domain/patient_history.dart
import '../../../core/models/appointment_model.dart';
import '../../../core/models/consultation_model.dart';
import '../../../core/models/lab_order_model.dart';

class PatientHistory {
  final String patientDocId;
  final String patientName;
  final String patientCode;
  final List<AppointmentModel> appointments;
  final List<ConsultationModel> consultations;
  final List<LabOrderModel> labOrders;

  const PatientHistory({
    required this.patientDocId,
    required this.patientName,
    required this.patientCode,
    required this.appointments,
    required this.consultations,
    required this.labOrders,
  });

  AppointmentModel? get lastVisit {
    final completed = appointments
        .where((a) => a.status == AppointmentStatus.completed)
        .toList()
      ..sort((a, b) => b.slot.compareTo(a.slot));
    return completed.isEmpty ? null : completed.first;
  }

  ConsultationModel? get lastConsultation {
    if (consultations.isEmpty) return null;
    final sorted = [...consultations]..sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
    return sorted.first;
  }

  /// All tests ever ordered for this patient, newest first.
  /// `orderedAt` is nullable, so guard the sort.
  List<LabOrderModel> get allTests => [...labOrders]..sort((a, b) {
        final at = a.orderedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.orderedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });

  List<LabOrderModel> get pendingTests => allTests
      .where((o) =>
          o.status != LabOrderStatus.delivered &&
          o.status != LabOrderStatus.cancelled &&
          o.status != LabOrderStatus.noShow)
      .toList();

  List<HistoryEntry> get timeline {
    final entries = <HistoryEntry>[];
    for (final c in consultations) {
      entries.add(HistoryEntry.consult(c));
    }
    for (final a in appointments) {
      final hasConsult =
          consultations.any((c) => c.appointmentId == a.docId);
      if (!hasConsult) entries.add(HistoryEntry.visit(a));
    }
    entries.sort((a, b) => b.when.compareTo(a.when));
    return entries;
  }
}

class HistoryEntry {
  final DateTime when;
  final ConsultationModel? consult;
  final AppointmentModel? visit;

  HistoryEntry._({required this.when, this.consult, this.visit});

  factory HistoryEntry.consult(ConsultationModel c) => HistoryEntry._(
        // Prefer startedAt, fall back to createdAt for display ordering.
        when: c.startedAt ??
            c.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0),
        consult: c,
      );

  factory HistoryEntry.visit(AppointmentModel a) =>
      HistoryEntry._(when: a.slot, visit: a);
}