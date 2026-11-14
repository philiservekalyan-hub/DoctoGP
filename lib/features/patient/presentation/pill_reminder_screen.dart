// lib/features/patient/presentation/pill_reminder_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/pill_models.dart';
import '../../../core/services/pill_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../shared/widgets/role_badge.dart';
import 'emergency_contact_screen.dart';
import 'patient_dashboard.dart';
import 'pill_schedule_form_screen.dart';

class PillReminderScreen extends ConsumerWidget {
  const PillReminderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dosesAsync = ref.watch(todayPillDosesProvider);
    final schedulesAsync = ref.watch(pillSchedulesProvider);
    final contactAsync = ref.watch(patientEmergencyContactProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Row(children: [
          const Icon(Icons.medication_rounded,
              color: AppColors.patientAccent, size: 22),
          const SizedBox(width: 10),
          Text('Pill Guard', style: AppTextStyles.h3),
        ]),
        actions: const [
          RoleBadge(label: 'Patient', color: AppColors.patientAccent),
          SizedBox(width: 12),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(todayPillDosesProvider);
          ref.invalidate(pillSchedulesProvider);
          ref.invalidate(patientEmergencyContactProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          children: [
            contactAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (contact) {
                if (contact != null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _infoBanner(
                    'Add an emergency contact to enable missed-dose alerts.',
                    AppColors.warning,
                    Icons.warning_amber_rounded,
                  ),
                );
              },
            ),

            Row(children: [
              const Expanded(child: SectionHeader(title: "Today's doses")),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PillScheduleFormScreen(),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add medication'),
              ),
            ]),
            const SizedBox(height: 8),
            dosesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => GlassCard(
                  child: Text('Failed: $e',
                      style: const TextStyle(color: AppColors.error))),
              data: (doses) {
                if (doses.isEmpty) {
                  return GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        const Icon(Icons.medication_outlined,
                            size: 32, color: AppColors.textMuted),
                        const SizedBox(height: 10),
                        Text('No doses scheduled today',
                            style: AppTextStyles.h3),
                        const SizedBox(height: 4),
                        Text(
                          'Add a medication and schedule to start tracking.',
                          style: AppTextStyles.bodyMuted,
                          textAlign: TextAlign.center,
                        ),
                      ]),
                    ),
                  );
                }
                return Column(
                  children: doses
                      .map((d) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _DoseCard(dose: d),
                          ))
                      .toList(),
                );
              },
            ),

            const SizedBox(height: 24),
            const SectionHeader(title: 'Medications'),
            const SizedBox(height: 8),
            schedulesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (schedules) {
                if (schedules.isEmpty) return const SizedBox.shrink();
                return Column(
                  children: schedules
                      .map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ScheduleRow(schedule: s),
                          ))
                      .toList(),
                );
              },
            ),

            const SizedBox(height: 24),
            const SectionHeader(title: 'Safety & device'),
            const SizedBox(height: 8),
            contactAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (contact) => _contactTile(context, contact),
            ),
            const SizedBox(height: 8),
            _pillGuardTile(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _contactTile(BuildContext context, Map<String, dynamic>? contact) {
    final hasContact = contact != null;
    return GlassCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EmergencyContactScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.contact_phone_rounded,
                  color: AppColors.info, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasContact
                        ? 'Emergency contact: ${contact['name']}'
                        : 'Add emergency contact',
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasContact
                        ? '${contact['relationship']} · ${contact['phone']}'
                        : 'Required for missed-dose alerts',
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

  Widget _pillGuardTile() {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.textMuted.withOpacity(.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.developer_board_rounded,
                color: AppColors.textMuted, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pill Guard device',
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Coming soon — pair a device to auto-confirm doses',
                    style: AppTextStyles.caption),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _infoBanner(String text, Color color, IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(.25)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: color, fontSize: 12, height: 1.35))),
        ]),
      );
}

class _DoseCard extends ConsumerWidget {
  final PillDose dose;
  const _DoseCard({required this.dose});

  Color get _statusColor => switch (dose.status) {
        PillDoseStatus.taken => AppColors.success,
        PillDoseStatus.missed => AppColors.error,
        PillDoseStatus.skipped => AppColors.textMuted,
        PillDoseStatus.pending => AppColors.warning,
      };

  IconData get _statusIcon => switch (dose.status) {
        PillDoseStatus.taken => Icons.check_circle_rounded,
        PillDoseStatus.missed => Icons.cancel_rounded,
        PillDoseStatus.skipped => Icons.remove_circle_rounded,
        PillDoseStatus.pending => Icons.schedule_rounded,
      };

  Future<void> _markTaken(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(pillServiceProvider).markTaken(dose.doseId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not mark taken: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _markSkipped(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(pillServiceProvider).markSkipped(dose.doseId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not mark skipped: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeStr = DateFormat('h:mm a').format(dose.scheduledAt);
    final canAct = dose.status == PillDoseStatus.pending ||
        dose.status == PillDoseStatus.missed;

    return GlassCard(
      borderColor: _statusColor.withOpacity(.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_statusIcon, color: _statusColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dose.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(timeStr, style: AppTextStyles.caption),
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
                child: Text(dose.status.label,
                    style:
                        AppTextStyles.caption.copyWith(color: _statusColor)),
              ),
            ]),
            if (canAct) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _markTaken(context, ref),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Taken'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(40),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _markSkipped(context, ref),
                    icon: const Icon(Icons.remove_rounded, size: 18),
                    label: const Text('Skip'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      side: const BorderSide(color: AppColors.textMuted),
                      minimumSize: const Size.fromHeight(40),
                    ),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  final PillSchedule schedule;
  const _ScheduleRow({required this.schedule});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.patientAccent.withOpacity(.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.medication_rounded,
                color: AppColors.patientAccent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${schedule.medicationName} · ${schedule.dose}',
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(schedule.times.join(' · '),
                    style: AppTextStyles.caption),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}