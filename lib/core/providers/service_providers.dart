import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/appointment_request_service.dart';
import '../services/appointment_service.dart';
import '../services/consultation_service.dart';
import '../services/lab_service.dart';
import '../services/patient_history_service.dart';
import '../services/patient_service.dart';

final appointmentServiceProvider =
    Provider<AppointmentService>((ref) => AppointmentService());

final appointmentRequestServiceProvider =
    Provider<AppointmentRequestService>((ref) => AppointmentRequestService());

final patientServiceProvider =
    Provider<PatientService>((ref) => PatientService());

final labServiceProvider =
    Provider<LabService>((ref) => LabService());

final consultationServiceProvider =
    Provider<ConsultationService>((ref) => ConsultationService());


final patientHistoryServiceProvider = Provider<PatientHistoryService>((ref) {
  return PatientHistoryService(
    appointmentService: ref.read(appointmentServiceProvider),
    consultationService: ref.read(consultationServiceProvider),
    labService: ref.read(labServiceProvider),
    firestore: FirebaseFirestore.instance,
  );
});