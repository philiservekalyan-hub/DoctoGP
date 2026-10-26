import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/models/appointment_request_model.dart';
import '../../../core/services/appointment_request_service.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';
import '../../../core/services/dashboard_service.dart';

final requestServiceProvider =
    Provider<AppointmentRequestService>((ref) => AppointmentRequestService());

final pendingRequestsProvider =
    StreamProvider.autoDispose<List<AppointmentRequestModel>>((ref) {
  return ref.watch(requestServiceProvider).watchPendingRequests();
});

/// Streams all doctors (and owner-doctors) in the given clinic.
/// Owners only count as doctors if their user doc has `isDoctor: true`,
/// which covers solo-practitioner clinics without including purely
/// administrative owners.
final clinicDoctorsProvider =
    StreamProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, clinicId) {
  if (clinicId.isEmpty) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('users')
      .where('clinicId', isEqualTo: clinicId)
      .where('role', whereIn: ['doctor', 'owner'])
      .snapshots()
      .map((snap) {
    final docs = snap.docs
        .map((d) => <String, dynamic>{'uid': d.id, ...d.data()})
        .where((m) {
      final role = '${m['role'] ?? ''}';
      if (role == 'owner') {
        return m['isDoctor'] == true;
      }
      return role == 'doctor';
    })
        .toList();

    docs.sort((a, b) => '${a['name'] ?? ''}'
        .toLowerCase()
        .compareTo('${b['name'] ?? ''}'.toLowerCase()));
    return docs;
  });
});

class PendingRequestsScreen extends ConsumerWidget {
  const PendingRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pendingRequestsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(title: 'Appointment requests'),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (reqs) {
            if (reqs.isEmpty) {
              return const EmptyState(
                icon: Icons.inbox_rounded,
                title: 'No pending requests',
                subtitle:
                    'New appointment requests from patients will appear here.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: reqs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _requestCard(context, ref, reqs[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _requestCard(BuildContext context, WidgetRef ref,
          AppointmentRequestModel r) =>
      GlassCard(
        borderColor: AppColors.warning.withOpacity(0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(r.patientName, style: AppTextStyles.h3)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(.12),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('Pending',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.warning)),
              ),
            ]),
            const SizedBox(height: 6),
            Text('${r.patientId} • ${r.patientPhone ?? 'no phone'}',
                style: AppTextStyles.caption),
            const SizedBox(height: 10),
            Text(r.reason, style: AppTextStyles.body),
            if (r.preferredTimeOfDay != null) ...[
              const SizedBox(height: 6),
              Text('Preferred: ${r.preferredTimeOfDay}',
                  style: AppTextStyles.caption),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _rejectDialog(context, ref, r),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _assignDialog(context, ref, r),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Assign'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white),
                ),
              ),
            ]),
          ],
        ),
      );

  Future<void> _assignDialog(BuildContext context, WidgetRef ref,
      AppointmentRequestModel r) async {
    final clinicId = r.clinicId ?? '';
    if (clinicId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This request has no clinic. Cannot assign.'),
        backgroundColor: AppColors.error,
      ));
      return;
    }

    // Load the doctors list once — we need it to decide the initial
    // selection and to render the dropdown inside the dialog.
    final doctors = await ref.read(clinicDoctorsProvider(clinicId).future);

    if (doctors.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No doctors found in this clinic.'),
          backgroundColor: AppColors.error,
        ));
      }
      return;
    }

    // Auto-select the only doctor if there's exactly one.
    String? selectedUid =
        doctors.length == 1 ? doctors.first['uid'] as String : null;

    // Day = tomorrow by default; period = morning.
    DateTime slotDay = DateTime.now().add(const Duration(days: 1));
    String slotPeriod = 'morning';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Assign appointment', style: AppTextStyles.h3),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.patientName, style: AppTextStyles.body),
                const SizedBox(height: 2),
                Text(r.patientId, style: AppTextStyles.caption),
                const SizedBox(height: 16),

                Text('Assign to', style: AppTextStyles.caption),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedUid,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(hintText: 'Select doctor'),
                  items: doctors
                      .map((d) => DropdownMenuItem<String>(
                            value: d['uid'] as String,
                            child: Text(
                              _doctorLabel(d),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setDState(() => selectedUid = v),
                ),
                if (doctors.length == 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Only one doctor in this clinic — auto-selected.',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ),

                const SizedBox(height: 16),

                Text('Day', style: AppTextStyles.caption),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('EEE, dd MMM yyyy').format(slotDay),
                        style: AppTextStyles.body,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: slotDay,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 180)),
                        );
                        if (d == null) return;
                        setDState(() => slotDay = d);
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                Text('Slot', style: AppTextStyles.caption),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['morning', 'afternoon', 'evening'].map((p) {
                    final selected = slotPeriod == p;
                    return ChoiceChip(
                      label: Text(
                        p[0].toUpperCase() + p.substring(1),
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      selected: selected,
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.surface,
                      side: BorderSide(
                          color: selected
                              ? AppColors.primary
                              : AppColors.cardBorder),
                      onSelected: (_) =>
                          setDState(() => slotPeriod = p),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 8),
                Text(
                  _periodWindowLabel(slotPeriod),
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedUid == null
                  ? null
                  : () => Navigator.pop(dctx, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || selectedUid == null) return;

    final chosen = doctors.firstWhere(
      (d) => d['uid'] == selectedUid,
      orElse: () => const <String, dynamic>{},
    );
    final doctorName = '${chosen['name'] ?? 'Doctor'}';

    // Compute the actual slot timestamp = day + period start.
    final (slotStart, _) =
        AppointmentModel.slotWindow(slotDay, slotPeriod);

    try {
      await ref.read(requestServiceProvider).approveRequest(
            request: r,
            doctorDocId: selectedUid!,
            doctorName: doctorName,
            slot: slotStart,
            slotPeriod: slotPeriod,
          );
      // Refresh the routed-to-doctor section on the dashboard.
      ref.invalidate(upcomingAppointmentsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Assigned to $doctorName.'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not assign: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  /// "Name • Specialization" — falls back gracefully if specialization
  /// is missing or empty.
  String _doctorLabel(Map<String, dynamic> d) {
    final name = '${d['name'] ?? 'Unnamed'}';
    final spec = '${d['specialization'] ?? ''}'.trim();
    return spec.isEmpty ? name : '$name • $spec';
  }

  String _periodWindowLabel(String period) {
    switch (period) {
      case 'morning':
        return '9:00 AM – 12:00 PM';
      case 'afternoon':
        return '1:00 PM – 4:00 PM';
      case 'evening':
        return '5:00 PM – 8:00 PM';
      default:
        return '';
    }
  }

  Future<void> _rejectDialog(BuildContext context, WidgetRef ref,
      AppointmentRequestModel r) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Reject request', style: AppTextStyles.h3),
        content: TextField(
            controller: reasonCtrl,
            maxLines: 2,
            decoration:
                const InputDecoration(labelText: 'Reason (optional)')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Reject')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(requestServiceProvider).rejectRequest(r.docId,
          reason: reasonCtrl.text.trim().isEmpty
              ? null
              : reasonCtrl.text.trim());
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not reject: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }
}