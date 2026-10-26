// lib/features/doctor/presentation/doctor_dashboard.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';                    // currentUserProvider
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/models/lab_order_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../shared/widgets/role_badge.dart';
import 'doctor_providers.dart';
import 'lab_order_create_screen.dart';
import 'lab_order_history_screen.dart';
import 'patient_history_screen.dart';
import 'patient_search_screen.dart';

class DoctorDashboard extends ConsumerWidget {
  const DoctorDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(child: Text('$e')),
          data: (user) => RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(doctorTodayAppointmentsProvider);
              ref.invalidate(doctorLabOrdersProvider);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context, ref, user?.name ?? ''),
                  const SizedBox(height: 24),
                  _statsRow(ref),
                  const SizedBox(height: 12),
                  _labTile(context, ref),
                  const SizedBox(height: 12),
                  _patientHistoryTile(context),
                  const SizedBox(height: 28),
                  const SectionHeader(title: "Today's Patients"),
                  const SizedBox(height: 8),
                  _patientList(context, ref),
                  const SizedBox(height: 28),
                  Row(children: [
                    const Expanded(
                        child: SectionHeader(title: 'Pending reports')),
                    TextButton(
                      onPressed: () => _openHistory(context),
                      child: const Text('View all',
                          style: TextStyle(
                              color: AppColors.info,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _pendingReports(context, ref),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, WidgetRef ref, String name) {
    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome back,', style: AppTextStyles.bodyMuted),
            const SizedBox(height: 4),
            Text('Dr. $name', style: AppTextStyles.h1),
          ],
        ),
      ),
      IconButton(
        tooltip: 'New lab order',
        onPressed: () => _openCreateLab(context, ref),
        icon: const Icon(Icons.science_outlined, color: AppColors.info),
      ),
      IconButton(
        tooltip: 'Logout',
        onPressed: () => _confirmLogout(context),
        icon: const Icon(Icons.logout_rounded, color: AppColors.error),
      ),
      const RoleBadge(label: 'Doctor', color: AppColors.doctorAccent),
    ]);
  }

  Widget _statsRow(WidgetRef ref) {
    final apptAsync = ref.watch(doctorTodayAppointmentsProvider);
    final labAsync = ref.watch(doctorLabOrdersProvider);

    final inQueue = apptAsync.maybeWhen(
      data: (l) =>
          l.where((a) => a.status == AppointmentStatus.checkedIn).length,
      orElse: () => 0,
    );
    final completed = apptAsync.maybeWhen(
      data: (l) =>
          l.where((a) => a.status == AppointmentStatus.completed).length,
      orElse: () => 0,
    );
    final toReview = labAsync.maybeWhen(
      data: (l) => l.where((o) => o.status == LabOrderStatus.ready).length,
      orElse: () => 0,
    );
    final followUps = apptAsync.maybeWhen(
      data: (l) => l
          .where((a) =>
              a.type == 'follow_up' &&
              a.status != AppointmentStatus.completed &&
              a.status != AppointmentStatus.cancelled)
          .length,
      orElse: () => 0,
    );

    return Column(children: [
      Row(children: [
        Expanded(
            child: StatCard(
          label: 'In queue',
          value: inQueue.toString().padLeft(2, '0'),
          icon: Icons.people_alt_rounded,
          accent: AppColors.doctorAccent,
        )),
        const SizedBox(width: 12),
        Expanded(
            child: StatCard(
          label: 'Completed today',
          value: completed.toString().padLeft(2, '0'),
          icon: Icons.check_circle_outline_rounded,
          accent: AppColors.success,
        )),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: StatCard(
          label: 'Reports to review',
          value: toReview.toString().padLeft(2, '0'),
          icon: Icons.science_outlined,
          accent: AppColors.info,
        )),
        const SizedBox(width: 12),
        Expanded(
            child: StatCard(
          label: 'Follow-ups',
          value: followUps.toString().padLeft(2, '0'),
          icon: Icons.event_repeat_rounded,
          accent: AppColors.accent,
        )),
      ]),
    ]);
  }

  Widget _labTile(BuildContext context, WidgetRef ref) {
    final labAsync = ref.watch(doctorLabOrdersProvider);
    return labAsync.maybeWhen(
      data: (orders) {
        final pending = orders
            .where((o) =>
                o.status != LabOrderStatus.delivered &&
                o.status != LabOrderStatus.cancelled &&
                o.status != LabOrderStatus.noShow)
            .length;
        final ready =
            orders.where((o) => o.status == LabOrderStatus.ready).length;

        return GlassCard(
          borderColor: AppColors.info.withOpacity(.3),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openHistory(context),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.science_outlined,
                      color: AppColors.info, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lab order history', style: AppTextStyles.body),
                      const SizedBox(height: 2),
                      Text(
                        ready > 0
                            ? '$ready ready · $pending active'
                            : '$pending active order${pending == 1 ? '' : 's'}',
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted),
              ]),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _patientHistoryTile(BuildContext context) {
    return GlassCard(
      borderColor: AppColors.doctorAccent.withOpacity(.3),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PatientSearchScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.doctorAccent.withOpacity(.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.history_rounded,
                  color: AppColors.doctorAccent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Patient consult history', style: AppTextStyles.body),
                  const SizedBox(height: 2),
                  Text(
                    "Look up any patient's past visits, notes & tests",
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }

  Widget _patientList(BuildContext context, WidgetRef ref) {
    final apptAsync = ref.watch(doctorTodayAppointmentsProvider);

    return apptAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => GlassCard(
        child: Text('Failed: $e',
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (list) {
        final active = list
            .where((a) =>
                a.status != AppointmentStatus.cancelled &&
                a.status != AppointmentStatus.declined &&
                a.status != AppointmentStatus.noShow)
            .toList()
          ..sort(_sortToday);

        if (active.isEmpty) {
          return GlassCard(
            child: Column(children: [
              const Icon(Icons.event_busy_rounded,
                  size: 34, color: AppColors.textMuted),
              const SizedBox(height: 10),
              Text('No appointments today', style: AppTextStyles.h3),
              const SizedBox(height: 4),
              Text('Your schedule will appear here.',
                  style: AppTextStyles.bodyMuted),
            ]),
          );
        }

        return Column(
          children: active
              .map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PatientRow(appointment: a),
                  ))
              .toList(),
        );
      },
    );
  }

  int _sortToday(AppointmentModel a, AppointmentModel b) {
    int rank(AppointmentModel x) => switch (x.status) {
          AppointmentStatus.inConsult => 0,
          AppointmentStatus.checkedIn => 1,
          AppointmentStatus.confirmed => 2,
          AppointmentStatus.awaitingConfirmation => 3,
          AppointmentStatus.booked => 4,
          AppointmentStatus.onHold => 5,
          AppointmentStatus.completed => 6,
          _ => 7,
        };
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    if (a.status == AppointmentStatus.checkedIn &&
        b.status == AppointmentStatus.checkedIn) {
      final at = a.checkedInAt ?? a.slot;
      final bt = b.checkedInAt ?? b.slot;
      return at.compareTo(bt);
    }
    return a.slot.compareTo(b.slot);
  }

  Widget _pendingReports(BuildContext context, WidgetRef ref) {
    final labAsync = ref.watch(doctorLabOrdersProvider);

    return labAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => GlassCard(
        child: Text('Failed: $e',
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (orders) {
        final active = orders
            .where((o) =>
                o.status != LabOrderStatus.delivered &&
                o.status != LabOrderStatus.cancelled &&
                o.status != LabOrderStatus.noShow)
            .take(4)
            .toList();

        if (active.isEmpty) {
          return GlassCard(
            child: Column(children: [
              const Icon(Icons.science_outlined,
                  size: 34, color: AppColors.textMuted),
              const SizedBox(height: 10),
              Text('No pending reports', style: AppTextStyles.h3),
              const SizedBox(height: 4),
              Text('Lab orders you create will appear here.',
                  style: AppTextStyles.bodyMuted),
            ]),
          );
        }

        return Column(
          children: active
              .map((o) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PendingReportRow(order: o),
                  ))
              .toList(),
        );
      },
    );
  }

  void _openHistory(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => const LabOrderHistoryScreen()),
      );

  void _openCreateLab(BuildContext context, WidgetRef ref) {
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => const LabOrderCreateScreen()))
        .then((_) => ref.invalidate(doctorLabOrdersProvider));
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Logout', style: AppTextStyles.h3),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      context.go('/login');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not sign out: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }
}

class _PatientRow extends ConsumerWidget {
  final AppointmentModel appointment;
  const _PatientRow({required this.appointment});

  Color get _statusColor {
    switch (appointment.status) {
      case AppointmentStatus.inConsult:
        return AppColors.accent;
      case AppointmentStatus.checkedIn:
        return AppColors.info;
      case AppointmentStatus.confirmed:
      case AppointmentStatus.completed:
        return AppColors.success;
      case AppointmentStatus.booked:
      case AppointmentStatus.awaitingConfirmation:
      case AppointmentStatus.onHold:
        return AppColors.textMuted;
      default:
        return AppColors.error;
    }
  }

  Future<void> _handle(BuildContext context, WidgetRef ref) async {
    if (appointment.status == AppointmentStatus.checkedIn) {
      try {
        await ref
            .read(appointmentServiceProvider)
            .startConsult(appointment.docId);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not start consult: $e'),
            backgroundColor: AppColors.error,
          ));
        }
        return;
      }
    }
    ref.read(selectedAppointmentProvider.notifier).state = appointment;
    ref.read(doctorTabProvider.notifier).state = 1;
  }

  void _openHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PatientHistoryScreen(
          patientDocId: appointment.patientDocId,
          patientNameHint: appointment.patientName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenLabel = appointment.tokenNumber > 0
        ? appointment.tokenLabel
        : 'Pending';

    return GlassCard(
      borderColor: _statusColor.withOpacity(0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(tokenLabel,
                  style: AppTextStyles.caption.copyWith(
                    color: _statusColor,
                    fontWeight: FontWeight.w700,
                  )),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openHistory(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(appointment.patientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.h3),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.history_rounded,
                            size: 14, color: AppColors.textMuted),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        '${appointment.patientId} • '
                        '${DateFormat('hh:mm a').format(appointment.slot)}',
                        style: AppTextStyles.caption,
                      ),
                      if (appointment.chiefComplaint != null &&
                          appointment.chiefComplaint!.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(appointment.chiefComplaint!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _actionButton(context, ref),
          ]),
          if (appointment.consultationFees != null) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (appointment.paymentStatus == PaymentStatus.paid
                        ? AppColors.success
                        : AppColors.warning)
                    .withOpacity(.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Fees: ₹${appointment.consultationFees!.toStringAsFixed(0)} · '
                '${appointment.paymentStatusLabel}',
                style: AppTextStyles.caption.copyWith(
                  color: appointment.paymentStatus == PaymentStatus.paid
                      ? AppColors.success
                      : AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionButton(BuildContext context, WidgetRef ref) {
    switch (appointment.status) {
      case AppointmentStatus.inConsult:
        return ElevatedButton(
          onPressed: () => _handle(context, ref),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Open'),
        );
      case AppointmentStatus.checkedIn:
        return ElevatedButton(
          onPressed: () => _handle(context, ref),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.doctorAccent,
            foregroundColor: AppColors.background,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Call in'),
        );
      case AppointmentStatus.completed:
        return OutlinedButton(
          onPressed: () => _handle(context, ref),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.success,
            side: const BorderSide(color: AppColors.success),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('View'),
        );
      default:
        return Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _statusColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(appointment.statusLabel,
              style:
                  AppTextStyles.caption.copyWith(color: _statusColor)),
        );
    }
  }
}

class _PendingReportRow extends StatelessWidget {
  final LabOrderModel order;
  const _PendingReportRow({required this.order});

  Color get _statusColor {
    switch (order.status) {
      case LabOrderStatus.ready:
      case LabOrderStatus.delivered:
        return AppColors.success;
      case LabOrderStatus.processing:
        return AppColors.warning;
      case LabOrderStatus.accepted:
      case LabOrderStatus.sampleCollected:
        return AppColors.info;
      case LabOrderStatus.cancelled:
      case LabOrderStatus.noShow:
        return AppColors.error;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: _statusColor.withOpacity(0.4),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PatientHistoryScreen(
              patientDocId: order.patientDocId,
              patientNameHint: order.patientName,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                order.status == LabOrderStatus.ready
                    ? Icons.description_rounded
                    : Icons.science_outlined,
                color: _statusColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.testsSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body),
                  const SizedBox(height: 3),
                  Text(
                    '${order.patientName} • ${order.labName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(.13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(order.statusLabel,
                  style:
                      AppTextStyles.caption.copyWith(color: _statusColor)),
            ),
          ]),
        ),
      ),
    );
  }
}