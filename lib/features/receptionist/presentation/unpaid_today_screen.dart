// lib/features/receptionist/presentation/unpaid_today_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/appointment_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/reception_stats_service.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';

/// All appointments with a doctor-set fee that are still unpaid —
/// regardless of when they were completed. This matches the
/// "Unpaid inv." count shown on the receptionist dashboard tile, so
/// tapping the tile always shows every outstanding fee until each
/// one is marked paid (or waived).
///
/// Single-field query on `paymentStatus`. No composite index needed.
final unpaidTodayProvider =
    StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  return FirebaseFirestore.instance
      .collection('appointments')
      .where('paymentStatus', isEqualTo: PaymentStatus.unpaid.name)
      .snapshots()
      .map((snap) {
    // Filter client-side for "doctor actually set a fee" so we
    // don't count unpaid appointments that have no fee attached.
    final list = snap.docs
        .map((d) => AppointmentModel.fromMap(d.id, d.data()))
        .where((a) =>
            a.consultationFees != null &&
            a.consultationFees! > 0 &&
            a.paymentStatus == PaymentStatus.unpaid)
        .toList()
      ..sort((a, b) {
        final at = a.consultEndedAt ?? a.slot;
        final bt = b.consultEndedAt ?? b.slot;
        return bt.compareTo(at); // newest first
      });
    return list;
  });
});

class UnpaidTodayScreen extends ConsumerWidget {
  const UnpaidTodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unpaidAsync = ref.watch(unpaidTodayProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ClinicAppBar(
        title: 'Unpaid',
        showBackButton: true,
        extraActions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.textSecondary, size: 20),
            onPressed: () {
              ref.invalidate(todayAllAppointmentsProvider);
              ref.invalidate(todayInvoiceStatsProvider);
              ref.invalidate(unpaidTodayProvider);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: unpaidAsync.when(
          loading: () => const Center(
              child:
                  CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child: Text('Failed: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'All caught up',
                subtitle: 'No unpaid consultation fees.',
              );
            }
            final total = list.fold<double>(
                0, (s, a) => s + (a.consultationFees ?? 0));
            return Column(
              children: [
                _summaryBar(list.length, total),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (_, i) => _UnpaidRow(
                      appointment: list[i],
                      onChanged: () {
                        ref.invalidate(todayAllAppointmentsProvider);
                        ref.invalidate(todayInvoiceStatsProvider);
                        ref.invalidate(unpaidTodayProvider);
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summaryBar(int count, double total) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        const Icon(Icons.receipt_long_outlined,
            color: AppColors.error, size: 18),
        const SizedBox(width: 10),
        Text(
          '$count unpaid · ₹${total.toStringAsFixed(0)} outstanding',
          style: AppTextStyles.body
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

class _UnpaidRow extends ConsumerWidget {
  final AppointmentModel appointment;
  final VoidCallback onChanged;
  const _UnpaidRow({
    required this.appointment,
    required this.onChanged,
  });

  Future<void> _markPaid(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref.read(appointmentServiceProvider).markFeesPaid(
            appointmentDocId: appointment.docId,
            collectedByUid: user.uid,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Fees collected · ₹${appointment.consultationFees!.toStringAsFixed(0)} · ${appointment.patientName}'),
        backgroundColor: AppColors.success,
      ));
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _waive(BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Waive fees?', style: AppTextStyles.h3),
        content: Text(
          'Waive ₹${appointment.consultationFees!.toStringAsFixed(0)} for '
          '${appointment.patientName}? This cannot be undone.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Waive'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(appointmentServiceProvider).waiveFees(
            appointmentDocId: appointment.docId,
            collectedByUid: user.uid,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fees waived · ${appointment.patientName}'),
        backgroundColor: AppColors.success,
      ));
      onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fee = appointment.consultationFees ?? 0;
    final completedAt = appointment.consultEndedAt;
    final dateLabel = completedAt == null
        ? 'Completed'
        : 'Completed ${DateFormat('dd MMM yyyy · hh:mm a').format(completedAt)}';

    return GlassCard(
      borderColor: AppColors.error.withOpacity(.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.currency_rupee_rounded,
                  color: AppColors.error, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appointment.patientName,
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${appointment.patientId} · Dr. ${appointment.doctorName}',
                    style: AppTextStyles.caption,
                  ),
                  const SizedBox(height: 2),
                  Text(dateLabel, style: AppTextStyles.caption),
                ],
              ),
            ),
            Text(
              '₹${fee.toStringAsFixed(0)}',
              style: AppTextStyles.h3
                  .copyWith(color: AppColors.error),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _markPaid(context, ref),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Mark paid'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _waive(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.warning,
                side: BorderSide(
                    color: AppColors.warning.withOpacity(.6)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Waive'),
            ),
          ]),
        ],
      ),
    );
  }
}