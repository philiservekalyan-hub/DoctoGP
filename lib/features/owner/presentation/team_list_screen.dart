import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';
import '../../staff/presentation/add_staff_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// PROVIDERS
// ═══════════════════════════════════════════════════════════════════

/// All staff in the clinic (active + inactive). Patients excluded.
/// `me.uid` excluded so the current user can't deactivate themselves.
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
          .where((d) {
            if (d.id == me.uid) return false;
            final role = (d.data()['role'] ?? '').toString();
            return role != 'patient';
          })
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

// ═══════════════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════════════

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
                final active =
                    team.where((m) => (m['active'] ?? true) == true).toList();
                final inactive =
                    team.where((m) => (m['active'] ?? true) != true).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (active.isEmpty)
                      const EmptyState(
                        icon: Icons.people_outline,
                        title: 'No active team members',
                        subtitle:
                            'Tap "Add Staff" to invite your first receptionist or doctor.',
                      )
                    else
                      ...active.map((m) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: 10),
                            child: _MemberTile(member: m),
                          )),
                    if (inactive.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text('INACTIVE STAFF',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            )),
                      ),
                      ...inactive.map((m) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: 10),
                            child: _MemberTile(member: m),
                          )),
                    ],
                  ],
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

// ═══════════════════════════════════════════════════════════════════
// MEMBER TILE (with deactivate / reactivate)
// ═══════════════════════════════════════════════════════════════════

class _MemberTile extends ConsumerWidget {
  final Map<String, dynamic> member;
  const _MemberTile({required this.member});

  bool get _isActive => (member['active'] ?? true) == true;

  Future<void> _setActive({
    required String uid,
    required bool active,
  }) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  Future<void> _confirmToggle(BuildContext context) async {
    final name = (member['name'] ?? 'this staff member').toString();
    final uid = (member['id'] ?? '').toString();
    if (uid.isEmpty) return;

    final willDeactivate = _isActive;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
            willDeactivate ? 'Deactivate staff?' : 'Reactivate staff?',
            style: AppTextStyles.h3),
        content: Text(
          willDeactivate
              ? '$name will be signed out and unable to log in until reactivated.'
              : '$name will be able to log in again.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  willDeactivate ? AppColors.error : AppColors.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(willDeactivate ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _setActive(uid: uid, active: !willDeactivate);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(willDeactivate
            ? '$name deactivated'
            : '$name reactivated'),
        backgroundColor: AppColors.success,
      ));
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
    final active = _isActive;
    final name = (member['name'] ?? '').toString();
    final role = (member['role'] ?? '').toString();

    return Opacity(
      opacity: active ? 1.0 : 0.55,
      child: GlassCard(
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: (active ? AppColors.secondary : AppColors.textMuted)
                  .withOpacity(0.2),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: active
                      ? AppColors.secondary
                      : AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(name, style: AppTextStyles.h3),
                    ),
                    if (!active) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.textMuted.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'INACTIVE',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ]),
                  Text((member['email'] ?? '').toString(),
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
                role.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: active ? 'Deactivate' : 'Reactivate',
              icon: Icon(
                active
                    ? Icons.person_off_rounded
                    : Icons.person_add_alt_1_rounded,
                color: active ? AppColors.error : AppColors.success,
                size: 20,
              ),
              onPressed: () => _confirmToggle(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// INVITE TILE (unchanged)
// ═══════════════════════════════════════════════════════════════════

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