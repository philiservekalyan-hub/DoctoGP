import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/models/appointment_model.dart';
import '../../core/providers/service_providers.dart';

/// Shows the reschedule dialog for [appointment].
///
/// Returns `true` if the appointment was successfully rescheduled,
/// `false` if the user cancelled or the update failed.
Future<bool> showRescheduleDialog(
  BuildContext context,
  WidgetRef ref,
  AppointmentModel appointment,
) async {
  DateTime newDay = appointment.slot;
  String newPeriod = appointment.slotPeriod ?? 'morning';

  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (context, setD) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Reschedule', style: AppTextStyles.h3),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Day', style: AppTextStyles.caption),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                    child: Text(
                        DateFormat('EEE, dd MMM yyyy').format(newDay),
                        style: AppTextStyles.body)),
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: newDay,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now()
                          .add(const Duration(days: 180)),
                    );
                    if (d == null) return;
                    setD(() => newDay = d);
                  },
                  child: const Text('Change'),
                ),
              ]),
              const SizedBox(height: 16),
              Text('Slot', style: AppTextStyles.caption),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['morning', 'afternoon', 'evening']
                    .map((p) => ChoiceChip(
                          label: Text(p[0].toUpperCase() +
                              p.substring(1)),
                          selected: newPeriod == p,
                          selectedColor: AppColors.primary,
                          onSelected: (_) =>
                              setD(() => newPeriod = p),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),
              Text(
                'Patient will be asked to re-confirm the new slot.',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Reschedule')),
        ],
      ),
    ),
  );

  if (ok != true) return false;

  final (newSlotStart, _) =
      AppointmentModel.slotWindow(newDay, newPeriod);

  try {
    await ref.read(appointmentServiceProvider).rescheduleAppointment(
          docId: appointment.docId,
          newSlot: newSlotStart,
          newSlotPeriod: newPeriod,
          resetConfirmation: true,
        );
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not reschedule: $e'),
        backgroundColor: AppColors.error,
      ));
    }
    return false;
  }
}