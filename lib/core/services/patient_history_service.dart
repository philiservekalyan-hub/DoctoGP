import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';

import '../models/appointment_model.dart';
import '../models/consultation_model.dart';
import '../models/lab_order_model.dart';
import '../../features/doctor/domain/patient_history.dart';

import 'appointment_service.dart';
import 'consultation_service.dart';
import 'lab_service.dart';

class PatientHistoryService {
  final AppointmentService appointmentService;
  final ConsultationService consultationService;
  final LabService labService;
  final FirebaseFirestore firestore;

  PatientHistoryService({
    required this.appointmentService,
    required this.consultationService,
    required this.labService,
    required this.firestore,
  });

  String? _fallbackName;
  String? _fallbackCode;

  Stream<PatientHistory> watchPatientHistory(String patientDocId) {
    final apptsStream =
        appointmentService.watchPatientAppointments(patientDocId);

    // Include consults for ALL appointments, so in-progress drafts are
    // visible and resumable.
    final consultsStream = apptsStream.switchMap((appts) {
      final ids = appts.map((a) => a.docId).toList();
      if (ids.isEmpty) return Stream.value(const <ConsultationModel>[]);
      return _watchConsultationsByIds(ids);
    });

    final labsStream = labService.watchPatientOrders(patientDocId);

    return Rx.combineLatest3<
      List<AppointmentModel>,
      List<ConsultationModel>,
      List<LabOrderModel>,
      PatientHistory
    >(
      apptsStream,
      consultsStream,
      labsStream,
      (appts, consults, labs) => PatientHistory(
        patientDocId: patientDocId,
        patientName: appts.isNotEmpty
            ? appts.first.patientName
            : (_fallbackName ?? 'Patient'),
        patientCode: appts.isNotEmpty
            ? appts.first.patientId
            : (_fallbackCode ?? patientDocId),
        appointments: appts,
        consultations: consults,
        labOrders: labs,
      ),
    );
  }

  Future<void> prefillPatientIdentity(String patientDocId) async {
    final snap =
        await firestore.collection('patients').doc(patientDocId).get();
    if (!snap.exists) return;
    final m = snap.data() ?? {};
    _fallbackName = (m['fullName'] ?? m['name'])?.toString();
    _fallbackCode = (m['patientId'] ?? m['patientCode'])?.toString();
  }

  Stream<List<ConsultationModel>> _watchConsultationsByIds(List<String> ids) {
    final chunks = <List<String>>[];
    for (var i = 0; i < ids.length; i += 30) {
      final end = (i + 30) > ids.length ? ids.length : i + 30;
      chunks.add(ids.sublist(i, end));
    }

    final streams = chunks.map((chunk) {
      return firestore
          .collection('consultations')
          .where(FieldPath.documentId, whereIn: chunk)
          .snapshots()
          .map((s) => s.docs
              .map((d) => ConsultationModel.fromMap(d.id, d.data()))
              .toList());
    }).toList();

    if (streams.isEmpty) return Stream.value(const []);
    return Rx.combineLatestList(streams).map((lists) {
      final merged = lists.expand((l) => l).toList()
        ..sort((a, b) {
          final at = a.startedAt ??
              a.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.startedAt ??
              b.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        });
      return merged;
    });
  }
}