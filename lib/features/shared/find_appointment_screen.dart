import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/models/appointment_model.dart';
import '../../core/providers/service_providers.dart';
import '../../core/services/dashboard_service.dart';
import '../../core/widgets/glass_card.dart';
import '../../shared/widgets/clinic_app_bar.dart';
import 'reschedule_appointment_dialog.dart';

/// Free-text search screen — lets the receptionist pull up ANY upcoming
/// appointment (regardless of day) and edit the slot.
class FindAppointmentScreen extends ConsumerStatefulWidget {
  const FindAppointmentScreen({super.key});

  @override
  ConsumerState<FindAppointmentScreen> createState() =>
      _FindAppointmentScreenState();
}

class _FindAppointmentScreenState
    extends ConsumerState<FindAppointmentScreen> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync =
        ref.watch(_searchProvider(_query));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar:
          const ClinicAppBar(title: 'Find appointment', showBackButton: true),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Name, phone, token, or code',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: resultsAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary)),
                error: (e, _) => Center(
                    child: Text('Error: $e',
                        style:
                            const TextStyle(color: AppColors.error))),
                data: (list) {
                  if (list.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _query.isEmpty
                              ? 'Type to search upcoming appointments'
                              : 'No matches',
                          style: AppTextStyles.caption,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: list.length,
                    itemBuilder: (_, i) =>
                        _resultCard(context, ref, list[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(
          BuildContext context, WidgetRef ref, AppointmentModel a) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.patientName, style: AppTextStyles.body),
                    const SizedBox(height: 2),
                    Text(
                      '${a.tokenLabel} • ${DateFormat('EEE, dd MMM · hh:mm a').format(a.slot)}',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Dr. ${a.doctorName.isEmpty ? 'Unassigned' : a.doctorName} • ${a.statusLabel}',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () async {
                  final changed = await showRescheduleDialog(
                    context,
                    ref,
                    a,
                  );
                  if (changed) {
                    ref.invalidate(todayAppointmentsProvider);
                    ref.invalidate(upcomingAppointmentsProvider);
                    ref.invalidate(pendingConfirmationsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(
                        content: Text(
                            '${a.tokenLabel} — rescheduled · ${a.patientName}'),
                        backgroundColor: AppColors.success,
                      ));
                    }
                  }
                },
                child: const Text('Edit slot'),
              ),
            ],
          ),
        ),
      );
}

final _searchProvider =
    StreamProvider.autoDispose.family<List<AppointmentModel>, String>(
        (ref, query) {
  return ref.read(appointmentServiceProvider).searchUpcoming(query);
});