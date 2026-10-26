import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';
import 'add_staff_screen.dart';

final teamProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
  final me = await ref.watch(currentUserProvider.future);
  if (me?.clinicId == null) {
    yield [];
    return;
  }
  yield* FirebaseFirestore.instance
      .collection('users')
      .where('clinicId', isEqualTo: me!.clinicId)
      .snapshots()
      .map((s) => s.docs
          .where((d) => d.id != me.uid)
          .map((d) {
            final data = d.data();
            return {
              'type': 'user',
              'id': d.id,
              'name': data['name'] ?? '',
              'email': data['email'] ?? '',
              'role': data['role'] ?? '',
              'active': data['active'] ?? true,
            };
          })
          .toList());
});

final pendingInvitesProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
  final me = await ref.watch(currentUserProvider.future);
  if (me?.clinicId == null) {
    yield [];
    return;
  }
  yield* FirebaseFirestore.instance
      .collection('invites')
      .where('clinicId', isEqualTo: me!.clinicId)
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((s) => s.docs.map((d) {
            final data = d.data();
            return {
              'type': 'invite',
              'id': d.id,
              'name': data['name'] ?? '',
              'email': data['email'] ?? '',
              'role': data['role'] ?? '',
            };
          }).toList());
});

class TeamListScreen extends ConsumerWidget {
  const TeamListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamAsync = ref.watch(teamProvider);
    final invitesAsync = ref.watch(pendingInvitesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(title: 'Team'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddStaffScreen()),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add Staff'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('ACTIVE STAFF',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  )),
            ),
            teamAsync.when(
              loading: () => const Center(
                  child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                    color: AppColors.primary),
              )),
              error: (e, _) => Text('Error: $e',
                  style: const TextStyle(color: AppColors.error)),
              data: (team) {
                if (team.isEmpty) {
                  return const EmptyState(
                    icon: Icons.people_outline,
                    title: 'No team members yet',
                    subtitle:
                        'Tap "Add Staff" to invite your first receptionist or doctor.',
                  );
                }
                return Column(
                  children: team
                      .map((m) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: 10),
                            child: _MemberTile(member: m),
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 28),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('PENDING INVITES',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  )),
            ),
            invitesAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
              data: (invites) {
                if (invites.isEmpty) {
                  return const GlassCard(
                    child: Text(
                      'No pending invites. Everyone you added has signed up.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  );
                }
                return Column(
                  children: invites
                      .map((m) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: 10),
                            child: _InviteTile(invite: m),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final Map<String, dynamic> member;
  const _MemberTile({required this.member});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.secondary.withOpacity(0.2),
            child: Text(
              (member['name'] as String).isNotEmpty
                  ? (member['name'] as String)[0].toUpperCase()
                  : '?',
              style: const TextStyle(color: AppColors.secondary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member['name'] ?? '', style: AppTextStyles.h3),
                Text(member['email'] ?? '',
                    style: AppTextStyles.caption),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              (member['role'] as String).toUpperCase(),
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  final Map<String, dynamic> invite;
  const _InviteTile({required this.invite});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderColor: AppColors.warning.withOpacity(0.4),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded,
              color: AppColors.warning, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invite['name'] ?? '', style: AppTextStyles.body),
                Text(invite['email'] ?? '',
                    style: AppTextStyles.caption),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              (invite['role'] as String).toUpperCase(),
              style: const TextStyle(
                color: AppColors.warning,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}