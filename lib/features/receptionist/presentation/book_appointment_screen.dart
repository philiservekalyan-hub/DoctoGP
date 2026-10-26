import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/models/patient_model.dart';
import '../../../core/services/appointment_service.dart';
import '../../../core/services/patient_service.dart';
import '../../../core/widgets/labeled_field.dart';
import '../../../core/providers/service_providers.dart';


// -----------------------------------------------------------------
// Live doctors for a clinic — from Firestore `users` collection
// -----------------------------------------------------------------
final clinicDoctorsProvider = StreamProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, clinicId) {
  return FirebaseFirestore.instance
      .collection('users')
      .where('clinicId', isEqualTo: clinicId)
      .where('role', isEqualTo: 'doctor')
      .where('active', isEqualTo: true)
      .snapshots()
      .map((s) => s.docs.map((d) {
            final data = d.data();
            return {
              'id': d.id,
              'name': data['name'] ?? 'Doctor',
              'specialization':
                  data['specialization'] ?? 'General Physician',
            };
          }).toList());
});

class BookAppointmentScreen extends ConsumerStatefulWidget {
  final PatientModel? preselectedPatient;
  const BookAppointmentScreen({super.key, this.preselectedPatient});

  @override
  ConsumerState<BookAppointmentScreen> createState() =>
      _BookAppointmentScreenState();
}

class _BookAppointmentScreenState
    extends ConsumerState<BookAppointmentScreen> {
  final _complaint = TextEditingController();

  PatientModel? _patient;
  String? _doctorDocId;
  String _doctorName = '';
  DateTime? _slot;
  String _type = 'in_person';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _patient = widget.preselectedPatient;
  }

  @override
  void dispose() {
    _complaint.dispose();
    super.dispose();
  }

  Future<void> _pickSlot() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: AppColors.background,
            surface: AppColors.surfaceElevated,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null) return;
    if (!mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: AppColors.background,
            surface: AppColors.surfaceElevated,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null) return;

    setState(() {
      _slot = DateTime(date.year, date.month, date.day,
          time.hour, time.minute);
    });
  }

  Future<void> _pickPatient() async {
    final result = await Navigator.of(context).push<PatientModel>(
      MaterialPageRoute(builder: (_) => const _PatientPickerScreen()),
    );
    if (result != null && mounted) {
      setState(() => _patient = result);
    }
  }

  Future<void> _save() async {
    if (_patient == null || _doctorDocId == null || _slot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select patient, doctor and slot'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final currentUser = await ref.read(currentUserProvider.future);
      if (currentUser == null || currentUser.clinicId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No clinic linked to your account'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      // Derive the slot period from the picked hour.
      final slotPeriod = AppointmentModel.periodFromHour(_slot!.hour);

      final appt = await ref
          .read(appointmentServiceProvider)
          .bookAppointment(
            clinicId: currentUser.clinicId!,
            patientDocId: _patient!.docId,
            patientId: _patient!.patientId,
            patientName: _patient!.fullName,
            patientPhone: _patient!.phone,
            doctorDocId: _doctorDocId!,
            doctorName: _doctorName,
            slot: _slot!,
            slotPeriod: slotPeriod,
            chiefComplaint: _complaint.text.trim().isEmpty
                ? null
                : _complaint.text.trim(),
            type: _type,
          );

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Appointment Confirmed',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('Patient',
                  '${appt.patientName} (${appt.patientId})'),
              _row('Doctor', appt.doctorName),
              _row('Slot',
                  DateFormat('EEE, dd MMM • hh:mm a').format(appt.slot)),
              _row('Period',
                  _periodLabel(appt.slotPeriod ?? slotPeriod)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TOKEN',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          letterSpacing: 1.2,
                        )),
                    const SizedBox(height: 4),
                    Text(
                      appt.tokenLabel,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Ref: ${appt.appointmentCode}',
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK',
                  style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _periodLabel(String period) {
    switch (period) {
      case 'morning':
        return 'Morning (9:00 – 12:00)';
      case 'afternoon':
        return 'Afternoon (13:00 – 16:00)';
      case 'evening':
        return 'Evening (17:00 – 20:00)';
      default:
        return period;
    }
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 70,
              child: Text(k,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Book Appointment')),
      body: userAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error))),
        data: (user) {
          final clinicId = user?.clinicId ?? '';
          final doctorsAsync = ref.watch(clinicDoctorsProvider(clinicId));

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              LabeledField(
                label: 'Patient',
                required: true,
                child: GestureDetector(
                  onTap: _pickPatient,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_search_outlined,
                            color: AppColors.textMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _patient == null
                              ? const Text('Tap to select patient',
                                  style: TextStyle(
                                      color: AppColors.textMuted))
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(_patient!.fullName,
                                        style: AppTextStyles.body),
                                    Text(
                                        '${_patient!.patientId} • ${_patient!.phone}',
                                        style: AppTextStyles.caption),
                                  ],
                                ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textMuted),
                      ],
                    ),
                  ),
                ),
              ),

              // Doctor dropdown — live from Firestore
              LabeledField(
                label: 'Doctor',
                required: true,
                child: doctorsAsync.when(
                  loading: () => Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary),
                        ),
                        SizedBox(width: 12),
                        Text('Loading doctors...',
                            style: TextStyle(
                                color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  error: (e, _) => Text('Error: $e',
                      style:
                          const TextStyle(color: AppColors.error)),
                  data: (doctors) {
                    if (doctors.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.cardBorder),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: AppColors.warning, size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'No doctors added yet. Ask the owner to invite doctors.',
                                style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _doctorDocId,
                          isExpanded: true,
                          hint: const Text('Select doctor',
                              style:
                                  TextStyle(color: AppColors.textMuted)),
                          dropdownColor: AppColors.surfaceElevated,
                          style: const TextStyle(
                              color: AppColors.textPrimary),
                          items: doctors
                              .map((d) => DropdownMenuItem<String>(
                                    value: d['id'] as String,
                                    child: Text(
                                      '${d['name']} • ${d['specialization']}',
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            final d = doctors.firstWhere(
                                (x) => x['id'] == v);
                            setState(() {
                              _doctorDocId = d['id'] as String;
                              _doctorName = d['name'] as String;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),

              LabeledField(
                label: 'Date & Time',
                required: true,
                child: GestureDetector(
                  onTap: _pickSlot,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule_rounded,
                            color: AppColors.textMuted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                _slot == null
                                    ? 'Pick a slot'
                                    : DateFormat(
                                            'EEE, dd MMM • hh:mm a')
                                        .format(_slot!),
                                style: TextStyle(
                                  color: _slot == null
                                      ? AppColors.textMuted
                                      : AppColors.textPrimary,
                                ),
                              ),
                              if (_slot != null)
                                Text(
                                  _periodLabel(AppointmentModel
                                      .periodFromHour(_slot!.hour)),
                                  style: AppTextStyles.caption,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              LabeledField(
                label: 'Type',
                child: Row(
                  children: [
                    _typeChip('in_person', 'In Person',
                        Icons.meeting_room_outlined),
                    const SizedBox(width: 10),
                    _typeChip('teleconsult', 'Teleconsult',
                        Icons.videocam_outlined),
                  ],
                ),
              ),
              LabeledField(
                label: 'Chief Complaint',
                child: DarkTextField(
                  controller: _complaint,
                  hint: 'e.g. Fever for 3 days',
                  maxLines: 3,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child:
                      Text(_saving ? 'Booking...' : 'Confirm Booking'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _typeChip(String value, String label, IconData icon) {
    final selected = _type == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withOpacity(0.15)
                : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  selected ? AppColors.primary : AppColors.cardBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textMuted),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontWeight: selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------
// Patient picker — filtered by clinic
// -----------------------------------------------------------------
final _patientListProvider =
    StreamProvider.autoDispose<List<PatientModel>>((ref) async* {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null || user.clinicId == null) {
    yield [];
    return;
  }
  yield* ref
      .read(patientServiceProvider)
      .watchPatients(clinicId: user.clinicId!);
});

class _PatientPickerScreen extends ConsumerStatefulWidget {
  const _PatientPickerScreen();

  @override
  ConsumerState<_PatientPickerScreen> createState() =>
      _PatientPickerScreenState();
}

class _PatientPickerScreenState
    extends ConsumerState<_PatientPickerScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patientsAsync = ref.watch(_patientListProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Select Patient')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _search,
              onChanged: (v) => setState(() => _q = v.trim()),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Search by name or PT-...',
                prefixIcon:
                    Icon(Icons.search, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: patientsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primary),
                ),
                error: (e, _) => Center(
                    child: Text('$e',
                        style: const TextStyle(
                            color: AppColors.error))),
                data: (list) {
                  final filtered = _q.isEmpty
                      ? list
                      : list.where((p) {
                          final s = _q.toLowerCase();
                          return p.fullName
                                  .toLowerCase()
                                  .contains(s) ||
                              p.patientId
                                  .toLowerCase()
                                  .contains(s) ||
                              p.phone.contains(_q);
                        }).toList();

                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text('No patients found',
                          style:
                              TextStyle(color: AppColors.textMuted)),
                    );
                  }

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      return ListTile(
                        tileColor: AppColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(
                              color: AppColors.cardBorder),
                        ),
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withOpacity(0.15),
                          child: Text(
                            p.fullName.isNotEmpty
                                ? p.fullName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: AppColors.primary),
                          ),
                        ),
                        title: Text(p.fullName,
                            style: AppTextStyles.body),
                        subtitle: Text(
                            '${p.patientId} • ${p.phone}',
                            style: AppTextStyles.caption),
                        onTap: () =>
                            Navigator.of(context).pop(p),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}