// lib/features/doctor/presentation/doctor_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/models/consultation_model.dart';
import '../../../core/models/lab_order_model.dart';
import '../../../core/providers/service_providers.dart';
import '../domain/patient_history.dart';

/// The appointment the doctor is currently consulting on.
final selectedAppointmentProvider =
    StateProvider<AppointmentModel?>((ref) => null);

/// 0 = Home, 1 = Consult, 2 = Lab orders, 3 = History
final doctorTabProvider = StateProvider<int>((ref) => 0);

/// Live draft consult record for the selected appointment.
final consultationDraftProvider =
    StreamProvider.autoDispose.family<ConsultationModel?, String>(
        (ref, appointmentId) {
  return ref
      .read(consultationServiceProvider)
      .watchByAppointment(appointmentId);
});

/// Today's appointment queue for the signed-in doctor.
final doctorTodayAppointmentsProvider =
    StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref.read(appointmentServiceProvider).watchDoctorQueue(
        doctorDocId: user.uid,
        date: DateTime.now(),
      );
});

/// All lab orders the signed-in doctor has ever created.
final doctorLabOrdersProvider =
    StreamProvider.autoDispose<List<LabOrderModel>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return const Stream.empty();
  return ref
      .read(labServiceProvider)
      .watchDoctorOrders(doctorDocId: user.uid);
});

/// Full history (appointments + consultations + labs) for one patient.
final patientHistoryProvider =
    StreamProvider.autoDispose.family<PatientHistory, String>((ref, id) {
  return ref.read(patientHistoryServiceProvider).watchPatientHistory(id);
});