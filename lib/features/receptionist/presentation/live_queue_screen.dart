import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/providers/service_providers.dart'
    show appointmentServiceProvider;
import '../../../core/services/dashboard_service.dart';
import '../../../core/providers/service_providers.dart';

final todayClinicAppointmentsProvider =
    StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  return ref.read(appointmentServiceProvider).watchClinicAppointments(
        date: DateTime.now(),
      );
});

class LiveQueueScreen extends ConsumerStatefulWidget {
  const LiveQueueScreen({super.key});

  @override
  ConsumerState<LiveQueueScreen> createState() => _LiveQueueScreenState();
}

class _LiveQueueScreenState extends ConsumerState<LiveQueueScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final apptAsync = ref.watch(todayClinicAppointmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Live Queue'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.receptionAccent,
          labelColor: AppColors.receptionAccent,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Confirmed'),
            Tab(text: 'Pending'),
          ],
        ),
      ),
      body: apptAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.error)),
          ),
        ),
        data: (all) {
          final confirmed = all
              .where((a) =>
                  a.status == AppointmentStatus.confirmed ||
                  a.status == AppointmentStatus.checkedIn ||
                  a.status == AppointmentStatus.inConsult ||
                  a.status == AppointmentStatus.completed)
              .toList();
          final pending = all
              .where((a) => a.status == AppointmentStatus.booked)
              .toList();

          return TabBarView(
            controller: _tabs,
            children: [
              _listView(all, emptyHint: 'No appointments today'),
              _listView(confirmed,
                  emptyHint: 'No confirmed visits yet'),
              _listView(pending,
                  emptyHint: 'No pending confirmations'),
            ],
          );
        },
      ),
    );
  }

  Widget _listView(List<AppointmentModel> list,
      {required String emptyHint}) {
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.queue_rounded,
        title: 'Nothing here',
        subtitle: emptyHint,
      );
    }

    final confirmedCount = list
        .where((a) =>
            a.status == AppointmentStatus.confirmed ||
            a.status == AppointmentStatus.checkedIn ||
            a.status == AppointmentStatus.inConsult)
        .length;
    final pendingCount =
        list.where((a) => a.status == AppointmentStatus.booked).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'Confirmed',
                  value: confirmedCount.toString().padLeft(2, '0'),
                  icon: Icons.check_circle_outline_rounded,
                  accent: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'Pending',
                  value: pendingCount.toString().padLeft(2, '0'),
                  icon: Icons.hourglass_top_rounded,
                  accent: AppColors.warning,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _appointmentTile(list[i]),
          ),
        ),
      ],
    );
  }

  Widget _appointmentTile(AppointmentModel appt) {
    final color = _colorFor(appt.status);
    return GlassCard(
      borderColor: appt.status == AppointmentStatus.booked &&
              appt.confirmationRequested
          ? AppColors.warning
          : AppColors.cardBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(appt.tokenLabel,
                    style:
                        AppTextStyles.caption.copyWith(color: color)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(appt.patientName, style: AppTextStyles.h3),
                    Text(
                      '${appt.patientId} • ${DateFormat('hh:mm a').format(appt.slot)}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              _statusChip(appt),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.person_outline,
                  size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child:
                    Text(appt.doctorName, style: AppTextStyles.caption),
              ),
              if (appt.status == AppointmentStatus.confirmed)
                TextButton(
                  onPressed: () => ref
                      .read(appointmentServiceProvider)
                      .updateStatus(appt.docId,
                          AppointmentStatus.checkedIn),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Check In',
                      style: TextStyle(
                        color: AppColors.receptionAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      )),
                )
              else if (appt.status == AppointmentStatus.checkedIn)
                TextButton(
                  onPressed: () => ref
                      .read(appointmentServiceProvider)
                      .updateStatus(appt.docId,
                          AppointmentStatus.inConsult),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Start Consult',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      )),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(AppointmentModel appt) {
    final color = _colorFor(appt.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(appt.statusLabel,
          style: AppTextStyles.caption.copyWith(color: color)),
    );
  }

  Color _colorFor(AppointmentStatus s) {
    switch (s) {
      case AppointmentStatus.confirmed:
        return AppColors.success;
      case AppointmentStatus.checkedIn:
        return AppColors.info;
      case AppointmentStatus.inConsult:
        return AppColors.accent;
      case AppointmentStatus.completed:
        return AppColors.success;
      case AppointmentStatus.declined:
      case AppointmentStatus.cancelled:
        return AppColors.error;
      case AppointmentStatus.booked:
        return AppColors.warning;
      default:
        return AppColors.textMuted;
    }
  }
}