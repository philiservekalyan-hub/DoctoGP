import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/models/appointment_model.dart';
import '../../../../core/models/appointment_request_model.dart';
import '../../../../core/providers/service_providers.dart';
import '../../../../core/services/dashboard_service.dart'
    hide patientSearchProvider, patientAppointmentsProvider;
import '../../../../core/services/reception_stats_service.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../shared/widgets/clinic_app_bar.dart';
import '../../shared/find_appointment_screen.dart';
import '../../shared/reschedule_appointment_dialog.dart';
import 'patient_lookup_screen.dart';
import 'pending_requests_screen.dart';
import 'unpaid_today_screen.dart';

   

class ReceptionistDashboard extends ConsumerStatefulWidget {
  const ReceptionistDashboard({super.key});

  @override
  ConsumerState<ReceptionistDashboard> createState() =>
      _ReceptionistDashboardState();
}

class _ReceptionistDashboardState extends ConsumerState<ReceptionistDashboard> {
  final _searchCtrl = TextEditingController();
  DateTime _queueDay = DateTime.now();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    final todayAsync = ref.watch(todayAllAppointmentsProvider);
    final invoiceAsync = ref.watch(todayInvoiceStatsProvider);
    final routedAsync = ref.watch(routedToDoctorProvider);
    final requestsAsync = ref.watch(pendingRequestsProvider);
    final dayQueueAsync = ref.watch(appointmentsForDayProvider(_queueDay));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ClinicAppBar(
        title: 'Reception',
        extraActions: [
          IconButton(
            tooltip: 'Find appointment',
            icon: const Icon(Icons.search_rounded,
                color: AppColors.textSecondary, size: 20),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => FindAppointmentScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (user) => RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(todayAllAppointmentsProvider);
              ref.invalidate(todayInvoiceStatsProvider);
              ref.invalidate(routedToDoctorProvider);
              ref.invalidate(pendingRequestsProvider);
              ref.invalidate(appointmentsForDayProvider(_queueDay));
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hello, ${user?.name.split(" ").first ?? "there"}',
                      style: AppTextStyles.bodyMuted),
                  const SizedBox(height: 4),
                  Text(_greeting(), style: AppTextStyles.h1),
                  const SizedBox(height: 20),
                  _searchBar(context),
                  const SizedBox(height: 24),
                  _needsAttention(context, requestsAsync, todayAsync,
                      invoiceAsync),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Today at a glance'),
                  _glanceGrid(todayAsync, invoiceAsync),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Today by doctor'),
                  _byDoctor(todayAsync),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Today by slot'),
                  _bySlot(todayAsync),
                  const SizedBox(height: 24),
                  Row(children: [
                    const Expanded(child: SectionHeader(title: 'Queue')),
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () => setState(() => _queueDay = _queueDay
                          .subtract(const Duration(days: 1))),
                    ),
                    TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _queueDay,
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 365)),
                          lastDate: DateTime.now()
                              .add(const Duration(days: 365)),
                        );
                        if (d != null) setState(() => _queueDay = d);
                      },
                      child: Text(DateFormat('EEE, dd MMM').format(_queueDay)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () => setState(() => _queueDay = _queueDay
                          .add(const Duration(days: 1))),
                    ),
                  ]),
                  _queueList(dayQueueAsync),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Routed to Doctor'),
                  _routedList(routedAsync),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Search
  // -------------------------------------------------------------
  Widget _searchBar(BuildContext context) {
    return TextField(
      controller: _searchCtrl,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search patient by name, phone, or ID',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: IconButton(
          icon: const Icon(Icons.arrow_forward_rounded),
          onPressed: () {
            final q = _searchCtrl.text.trim();
            if (q.isNotEmpty) _openSearchResults(context, q);
          },
        ),
      ),
      onSubmitted: (q) {
        if (q.trim().isNotEmpty) _openSearchResults(context, q.trim());
      },
    );
  }

  void _openSearchResults(BuildContext context, String q) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PatientSearchResults(query: q)),
    );
  }

  // -------------------------------------------------------------
  // Needs attention
  // -------------------------------------------------------------
  Widget _needsAttention(
    BuildContext context,
    AsyncValue<List<AppointmentRequestModel>> requestsAsync,
    AsyncValue<List<AppointmentModel>> todayAsync,
    AsyncValue<InvoiceDayStats> invoiceAsync,
  ) {
    final items = <Widget>[];

    final pendingReqs = requestsAsync.asData?.value.length ?? 0;
    if (pendingReqs > 0) {
      items.add(_attentionTile(
        context,
        icon: Icons.inbox_rounded,
        color: AppColors.warning,
        title:
            '$pendingReqs new appointment request${pendingReqs == 1 ? '' : 's'}',
        subtitle: 'Assign doctors and slots',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PendingRequestsScreen()),
        ),
      ));
    }

    final today = todayAsync.asData?.value ?? const <AppointmentModel>[];
    final unconfirmed = today
        .where((a) =>
            a.status == AppointmentStatus.awaitingConfirmation ||
            (a.status == AppointmentStatus.booked &&
                a.confirmationRequested))
        .length;
    if (unconfirmed > 0) {
      items.add(_attentionTile(
        context,
        icon: Icons.hourglass_top_rounded,
        color: AppColors.warning,
        title:
            '$unconfirmed confirmation${unconfirmed == 1 ? '' : 's'} pending today',
        subtitle: 'Call or message patients to confirm',
        onTap: () {},
      ));
    }

    final inv = invoiceAsync.asData?.value;
    if (inv != null && inv.unpaidCount > 0) {
      items.add(_attentionTile(
        context,
        icon: Icons.receipt_long_outlined,
        color: AppColors.error,
        title:
            '${inv.unpaidCount} unpaid invoice${inv.unpaidCount == 1 ? '' : 's'} today',
        subtitle: '₹${inv.unpaidAmount.toStringAsFixed(0)} outstanding',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const UnpaidTodayScreen()),
        ),
      ));
    }

    if (items.isEmpty) {
      return GlassCard(
        child: Row(children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: AppColors.success, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Nothing needs your attention right now',
                style: AppTextStyles.body
                    .copyWith(color: AppColors.textSecondary)),
          ),
        ]),
      );
    }

    return Column(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        items[i],
      ]
    ]);
  }

  Widget _attentionTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      GlassCard(
        borderColor: color.withOpacity(0.4),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.body),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted),
          ]),
        ),
      );

  // -------------------------------------------------------------
  // Today at a glance
  // -------------------------------------------------------------
  Widget _glanceGrid(
      AsyncValue<List<AppointmentModel>> todayAsync,
      AsyncValue<InvoiceDayStats> invoiceAsync) {
    final today = todayAsync.asData?.value ?? const <AppointmentModel>[];
    final confirmed = today
        .where((a) =>
            a.status == AppointmentStatus.confirmed ||
            a.status == AppointmentStatus.checkedIn ||
            a.status == AppointmentStatus.inConsult ||
            a.status == AppointmentStatus.completed)
        .length;
    final unconfirmed = today
        .where((a) =>
            a.status == AppointmentStatus.awaitingConfirmation ||
            (a.status == AppointmentStatus.booked &&
                a.confirmationRequested))
        .length;
    final inClinic = today
        .where((a) =>
            a.status == AppointmentStatus.checkedIn ||
            a.status == AppointmentStatus.inConsult)
        .length;
    final unassigned = today.where((a) => a.doctorDocId.isEmpty).length;

    final inv = invoiceAsync.asData?.value;

    final tiles = [
      _GlanceTile(
          label: 'Confirmed',
          value: '$confirmed',
          icon: Icons.verified_rounded,
          color: AppColors.success),
      _GlanceTile(
          label: 'Pending confirm',
          value: '$unconfirmed',
          icon: Icons.hourglass_top_rounded,
          color: AppColors.warning),
      _GlanceTile(
          label: 'In clinic',
          value: '$inClinic',
          icon: Icons.how_to_reg_rounded,
          color: AppColors.info),
      _GlanceTile(
          label: 'Unassigned',
          value: '$unassigned',
          icon: Icons.person_off_outlined,
          color: unassigned > 0 ? AppColors.error : AppColors.textMuted),
      _GlanceTile(
          label: 'Unpaid inv.',
          value: inv == null ? '—' : '${inv.unpaidCount}',
          icon: Icons.receipt_long_outlined,
          color: AppColors.error),
      _GlanceTile(
          label: 'Collected',
          value: inv == null
              ? '—'
              : '₹${inv.collectedAmount.toStringAsFixed(0)}',
          icon: Icons.currency_rupee_rounded,
          color: AppColors.accent),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.05,
      children: tiles.map((t) => _glanceCard(t)).toList(),
    );
  }

  Widget _glanceCard(_GlanceTile t) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(t.value, style: AppTextStyles.h2),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(t.label,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted)),
            ),
          ],
        ),
      );

  // -------------------------------------------------------------
  // Today by doctor
  // -------------------------------------------------------------
  Widget _byDoctor(AsyncValue<List<AppointmentModel>> todayAsync) {
    final today = todayAsync.asData?.value ?? const <AppointmentModel>[];
    if (today.isEmpty) {
      return GlassCard(
          child:
              Text('No appointments today', style: AppTextStyles.caption));
    }

    final byDoctor = <String, List<AppointmentModel>>{};
    for (final a in today) {
      final key = a.doctorName.isEmpty ? '(Unassigned)' : a.doctorName;
      byDoctor.putIfAbsent(key, () => []).add(a);
    }
    final entries = byDoctor.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return GlassCard(
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              const Divider(height: 16, color: AppColors.cardBorder),
            _doctorRow(entries[i].key, entries[i].value),
          ],
        ],
      ),
    );
  }

  Widget _doctorRow(String name, List<AppointmentModel> appts) {
    final confirmed = appts
        .where((a) =>
            a.status == AppointmentStatus.confirmed ||
            a.status == AppointmentStatus.checkedIn ||
            a.status == AppointmentStatus.inConsult ||
            a.status == AppointmentStatus.completed)
        .length;
    final waiting = appts
        .where((a) =>
            a.status == AppointmentStatus.awaitingConfirmation ||
            a.status == AppointmentStatus.booked)
        .length;

    return Row(children: [
      const Icon(Icons.medical_services_rounded,
          color: AppColors.doctorAccent, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text('Dr. $name', style: AppTextStyles.body)),
      _chip('${appts.length}', AppColors.primary),
      const SizedBox(width: 6),
      _chip('$confirmed ✓', AppColors.success),
      const SizedBox(width: 6),
      _chip('$waiting ⌛', AppColors.warning),
    ]);
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.13),
          borderRadius: BorderRadius.circular(6),
        ),
        child:
            Text(text, style: AppTextStyles.caption.copyWith(color: color)),
      );

  // -------------------------------------------------------------
  // Today by slot
  // -------------------------------------------------------------
  Widget _bySlot(AsyncValue<List<AppointmentModel>> todayAsync) {
    final today = todayAsync.asData?.value ?? const <AppointmentModel>[];
    if (today.isEmpty) {
      return GlassCard(
          child:
              Text('No appointments today', style: AppTextStyles.caption));
    }

    const periods = ['morning', 'afternoon', 'evening'];
    return Column(children: [
      for (final p in periods) _slotRow(p, today),
    ]);
  }

  Widget _slotRow(String period, List<AppointmentModel> today) {
    final appts = today.where((a) => a.slotPeriod == period).toList();
    final label = switch (period) {
      'morning' => 'Morning · 9–12',
      'afternoon' => 'Afternoon · 13–16',
      _ => 'Evening · 17–20',
    };
    final color = switch (period) {
      'morning' => AppColors.info,
      'afternoon' => AppColors.warning,
      _ => AppColors.accent,
    };
    final doctors = <String>{...appts.map((a) => a.doctorName)}..remove('');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Row(children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.body),
                const SizedBox(height: 2),
                Text(
                  '${appts.length} appointment${appts.length == 1 ? '' : 's'}'
                  '${doctors.isEmpty ? '' : ' • ${doctors.length} doctor${doctors.length == 1 ? '' : 's'}'}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.13),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${appts.length}',
                style: AppTextStyles.caption.copyWith(color: color)),
          ),
        ]),
      ),
    );
  }

  // -------------------------------------------------------------
  // Queue list
  // -------------------------------------------------------------
  Widget _queueList(AsyncValue<List<AppointmentModel>> dayAsync) {
    return dayAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => GlassCard(
        child: Text('Failed to load queue: $e',
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            icon: Icons.queue_rounded,
            title: 'Nothing scheduled',
            subtitle: 'No appointments on this date.',
          );
        }
        return Column(
          children: list
              .map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SimpleQueueRow(appointment: a, onChanged: () {
                      ref.invalidate(
                          appointmentsForDayProvider(_queueDay));
                    }),
                  ))
              .toList(),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // Routed list
  // -------------------------------------------------------------
  Widget _routedList(AsyncValue<List<AppointmentModel>> routedAsync) {
    return routedAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => GlassCard(
        child: Text('Failed to load: $e',
            style: const TextStyle(color: AppColors.error)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return GlassCard(
            child: Row(children: [
              const Icon(Icons.check_circle_outline_rounded,
                  color: AppColors.success, size: 20),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      'No future appointments awaiting correction',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textSecondary))),
            ]),
          );
        }
        return Column(
          children: list
              .map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RoutedRow(appointment: a),
                  ))
              .toList(),
        );
      },
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

// ----------------------------------------------------------------
// Small widgets
// ----------------------------------------------------------------
class _GlanceTile {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _GlanceTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

// ----------------------------------------------------------------
// Queue row  ── UPDATED: fees badge, Mark paid, reception-safe inConsult
// ----------------------------------------------------------------
class _SimpleQueueRow extends ConsumerWidget {
  final AppointmentModel appointment;
  final VoidCallback onChanged;
  const _SimpleQueueRow({
    required this.appointment,
    required this.onChanged,
  });

  Color get _statusColor {
    switch (appointment.status) {
      case AppointmentStatus.awaitingConfirmation:
        return AppColors.warning;
      case AppointmentStatus.confirmed:
        return AppColors.success;
      case AppointmentStatus.checkedIn:
        return AppColors.info;
      case AppointmentStatus.inConsult:
        return AppColors.accent;
      case AppointmentStatus.completed:
        return AppColors.success;
      case AppointmentStatus.onHold:
        return AppColors.textMuted;
      case AppointmentStatus.declined:
      case AppointmentStatus.cancelled:
      case AppointmentStatus.noShow:
        return AppColors.error;
      case AppointmentStatus.booked:
        return appointment.confirmationRequested
            ? AppColors.warning
            : AppColors.textMuted;
    }
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
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(tokenLabel,
                  style: AppTextStyles.caption
                      .copyWith(color: _statusColor)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appointment.patientName,
                      style: AppTextStyles.body),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('hh:mm a').format(appointment.slot)}'
                    ' • Dr. ${appointment.doctorName.isEmpty ? '—' : appointment.doctorName}',
                    style: AppTextStyles.caption,
                  ),
                  const SizedBox(height: 2),
                  Text(appointment.statusLabel,
                      style: AppTextStyles.caption
                          .copyWith(color: _statusColor)),
                ],
              ),
            ),
            _primaryAction(context, ref),
            const SizedBox(width: 4),
            _moreMenu(context, ref),
          ]),
          if (appointment.consultationFees != null)
            _feesRow(context, ref),
        ],
      ),
    );
  }

  Widget _feesRow(BuildContext context, WidgetRef ref) {
    final fees = appointment.consultationFees!;
    final isPaid = appointment.paymentStatus == PaymentStatus.paid;
    final isWaived = appointment.paymentStatus == PaymentStatus.waived;
    final color =
        (isPaid || isWaived) ? AppColors.success : AppColors.warning;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.currency_rupee_rounded,
                size: 12, color: AppColors.warning),
            const SizedBox(width: 2),
            Text(
              isWaived
                  ? '${fees.toStringAsFixed(0)} · Waived'
                  : '${fees.toStringAsFixed(0)} · ${appointment.paymentStatusLabel}',
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
        ),
        const Spacer(),
        if (!isPaid && !isWaived)
          TextButton(
            onPressed: () => _collectFees(context, ref),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.success,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
            ),
            child: const Text('Mark paid'),
          ),
      ]),
    );
  }

  Future<void> _collectFees(
      BuildContext context, WidgetRef ref) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref.read(appointmentServiceProvider).markFeesPaid(
            appointmentDocId: appointment.docId,
            collectedByUid: user.uid,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Fees collected · ₹${appointment.consultationFees!.toStringAsFixed(0)} · ${appointment.patientName}'),
          backgroundColor: AppColors.success,
        ));
        ref.invalidate(todayInvoiceStatsProvider);
        onChanged();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Widget _primaryAction(BuildContext context, WidgetRef ref) {
    switch (appointment.status) {
      case AppointmentStatus.booked:
      case AppointmentStatus.confirmed:
        return _textBtn(
          'Check In',
          AppColors.receptionAccent,
          () => _run(
            context,
            ref,
            'Checked in',
            () => ref
                .read(appointmentServiceProvider)
                .updateStatus(
                    appointment.docId, AppointmentStatus.checkedIn),
          ),
        );

      case AppointmentStatus.checkedIn:
        return _textBtn(
          'Send in',
          AppColors.accent,
          () => _run(
            context,
            ref,
            'Sent to doctor',
            () => ref
                .read(appointmentServiceProvider)
                .updateStatus(
                    appointment.docId, AppointmentStatus.inConsult),
          ),
        );

      case AppointmentStatus.inConsult:
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            ),
            SizedBox(width: 6),
            Text('With doctor',
                style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _textBtn(String label, Color color, VoidCallback onTap) =>
      TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 0),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      );

  Widget _moreMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded,
          color: AppColors.textMuted, size: 20),
      color: AppColors.surface,
      onSelected: (value) async {
        switch (value) {
          case 'request_confirmation':
            await _run(
              context,
              ref,
              'Confirmation requested',
              () => ref
                  .read(appointmentServiceProvider)
                  .requestConfirmation(appointment.docId),
            );
            break;
          case 'hold':
            await _run(
              context,
              ref,
              'Put on hold',
              () => ref
                  .read(appointmentServiceProvider)
                  .holdAppointment(appointment.docId),
            );
            break;
          case 'resume':
            await _run(
              context,
              ref,
              'Resumed',
              () => ref
                  .read(appointmentServiceProvider)
                  .resumeAppointment(appointment.docId),
            );
            break;
          case 'force_complete':
            await _forceComplete(context, ref);
            break;
          case 'reschedule':
            final changed =
                await showRescheduleDialog(context, ref, appointment);
            if (changed) {
              onChanged();
              ref.invalidate(todayAllAppointmentsProvider);
              ref.invalidate(routedToDoctorProvider);
            }
            break;
          case 'cancel':
            await _run(
              context,
              ref,
              'Cancelled',
              () => ref
                  .read(appointmentServiceProvider)
                  .cancelByStaff(appointment.docId),
            );
            break;
          case 'no_show':
            await _run(
              context,
              ref,
              'Marked no-show',
              () => ref
                  .read(appointmentServiceProvider)
                  .markNoShow(appointment.docId),
            );
            break;
        }
      },
      itemBuilder: (_) {
        final items = <PopupMenuEntry<String>>[];
        final s = appointment.status;

        if (s == AppointmentStatus.booked) {
          items.add(const PopupMenuItem(
            value: 'request_confirmation',
            child: _MenuRow(
                icon: Icons.notifications_active_rounded,
                label: 'Request confirmation',
                color: AppColors.warning),
          ));
        }

        if (s == AppointmentStatus.onHold) {
          items.add(const PopupMenuItem(
            value: 'resume',
            child: _MenuRow(
                icon: Icons.play_arrow_rounded,
                label: 'Resume',
                color: AppColors.success),
          ));
        } else if (s != AppointmentStatus.completed &&
            s != AppointmentStatus.cancelled &&
            s != AppointmentStatus.declined &&
            s != AppointmentStatus.noShow) {
          items.add(const PopupMenuItem(
            value: 'hold',
            child: _MenuRow(
                icon: Icons.pause_rounded,
                label: 'Put on hold',
                color: AppColors.textMuted),
          ));
        }

        if (s == AppointmentStatus.booked ||
            s == AppointmentStatus.awaitingConfirmation ||
            s == AppointmentStatus.confirmed ||
            s == AppointmentStatus.onHold) {
          items.add(const PopupMenuItem(
            value: 'reschedule',
            child: _MenuRow(
                icon: Icons.event_repeat_rounded,
                label: 'Reschedule',
                color: AppColors.info),
          ));
        }

        if (s == AppointmentStatus.inConsult) {
          items.add(const PopupMenuItem(
            value: 'force_complete',
            child: _MenuRow(
                icon: Icons.warning_amber_rounded,
                label: 'Force complete (doctor unavailable)',
                color: AppColors.warning),
          ));
        }

        if (s != AppointmentStatus.completed &&
            s != AppointmentStatus.cancelled &&
            s != AppointmentStatus.declined) {
          items.add(const PopupMenuItem(
            value: 'cancel',
            child: _MenuRow(
                icon: Icons.cancel_outlined,
                label: 'Cancel appointment',
                color: AppColors.error),
          ));
        }

        if (s == AppointmentStatus.confirmed ||
            s == AppointmentStatus.booked) {
          items.add(const PopupMenuItem(
            value: 'no_show',
            child: _MenuRow(
                icon: Icons.person_off_outlined,
                label: 'Mark no-show',
                color: AppColors.error),
          ));
        }

        return items;
      },
    );
  }

  Future<void> _forceComplete(
      BuildContext context, WidgetRef ref) async {
    final fees = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ReceptionFeesDialog(),
    );
    if (fees == null) return;
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref.read(appointmentServiceProvider).completeConsultation(
            appointmentDocId: appointment.docId,
            fees: fees,
            doctorUid: appointment.doctorDocId.isEmpty
                ? user.uid
                : appointment.doctorDocId,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${appointment.tokenLabel} — force-completed · ₹${fees.toStringAsFixed(0)}'),
          backgroundColor: AppColors.success,
        ));
        onChanged();
        ref.invalidate(todayAllAppointmentsProvider);
        ref.invalidate(todayInvoiceStatsProvider);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    String successLabel,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${appointment.tokenLabel} — $successLabel · ${appointment.patientName}'),
          backgroundColor: AppColors.success,
        ));
        onChanged();
        ref.invalidate(todayAllAppointmentsProvider);
        ref.invalidate(todayInvoiceStatsProvider);
        ref.invalidate(routedToDoctorProvider);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }
}

// ----------------------------------------------------------------
// Force-complete fees dialog (used only from _SimpleQueueRow)
// ----------------------------------------------------------------
class _ReceptionFeesDialog extends StatefulWidget {
  const _ReceptionFeesDialog();
  @override
  State<_ReceptionFeesDialog> createState() =>
      _ReceptionFeesDialogState();
}

class _ReceptionFeesDialogState extends State<_ReceptionFeesDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_ctrl.text.trim());
    if (v == null || v <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Force complete', style: AppTextStyles.h3),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          'Use only if the doctor is unavailable. Enter the fee to charge the patient.',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            prefixText: '₹ ',
            hintText: 'e.g. 500',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
          ),
          child: const Text('Complete & charge'),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------
// Routed row (unchanged)
// ----------------------------------------------------------------
class _RoutedRow extends ConsumerWidget {
  final AppointmentModel appointment;
  const _RoutedRow({required this.appointment});

  Color get _statusColor {
    switch (appointment.status) {
      case AppointmentStatus.awaitingConfirmation:
        return AppColors.warning;
      case AppointmentStatus.confirmed:
        return AppColors.success;
      case AppointmentStatus.booked:
        return AppColors.info;
      case AppointmentStatus.onHold:
        return AppColors.textMuted;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slotLabel =
        DateFormat('EEE, dd MMM · hh:mm a').format(appointment.slot);

    return GlassCard(
      borderColor: _statusColor.withOpacity(0.4),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.local_hospital_outlined,
              color: AppColors.info, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(appointment.patientName, style: AppTextStyles.body),
              const SizedBox(height: 2),
              Text(
                appointment.doctorName.isNotEmpty
                    ? 'Dr. ${appointment.doctorName}'
                    : 'Doctor unassigned',
                style: AppTextStyles.caption.copyWith(
                  color: appointment.doctorName.isNotEmpty
                      ? AppColors.textSecondary
                      : AppColors.error,
                ),
              ),
              const SizedBox(height: 2),
              Text(slotLabel, style: AppTextStyles.caption),
              const SizedBox(height: 3),
              Text(appointment.statusLabel,
                  style:
                      AppTextStyles.caption.copyWith(color: _statusColor)),
            ],
          ),
        ),
        TextButton(
          onPressed: () async {
            final changed =
                await showRescheduleDialog(context, ref, appointment);
            if (changed) {
              ref.invalidate(todayAllAppointmentsProvider);
              ref.invalidate(todayInvoiceStatsProvider);
              ref.invalidate(routedToDoctorProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      '${appointment.tokenLabel} — rescheduled · ${appointment.patientName}'),
                  backgroundColor: AppColors.success,
                ));
              }
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: AppColors.info,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600),
          ),
          child: const Text('Edit slot'),
        ),
      ]),
    );
  }
}

// ----------------------------------------------------------------
// Patient search results (unchanged)
// ----------------------------------------------------------------
class _PatientSearchResults extends ConsumerWidget {
  final String query;
  const _PatientSearchResults({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(patientSearchProvider(query));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ClinicAppBar(
        title: 'Results · $query',
        showBackButton: true,
      ),
      body: SafeArea(
        child: resultsAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (list) {
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_off_rounded,
                          size: 48, color: AppColors.textMuted),
                      const SizedBox(height: 12),
                      Text('No patients matched "$query"',
                          style: AppTextStyles.bodyMuted,
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _resultCard(context, list[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _resultCard(BuildContext context, Map<String, dynamic> p) {
    final name = '${p['fullName'] ?? p['name'] ?? 'Unknown'}';
    final pid = '${p['patientId'] ?? ''}';
    final phone = '${p['phone'] ?? ''}';
    final uid = p['docId'] as String;

    return GlassCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PatientLookupScreen(
              patientDocId: uid,
              patientName: name,
            ),
          ),
        ),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: AppColors.primary.withOpacity(0.15),
            child: Text(_initials(name),
                style: AppTextStyles.body
                    .copyWith(color: AppColors.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.body),
                const SizedBox(height: 2),
                Text(
                  [pid, phone].where((s) => s.isNotEmpty).join(' · '),
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted),
        ]),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }
}

// ----------------------------------------------------------------
// Menu row helper (unchanged)
// ----------------------------------------------------------------
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _MenuRow(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Text(label,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 13)),
    ]);
  }
}