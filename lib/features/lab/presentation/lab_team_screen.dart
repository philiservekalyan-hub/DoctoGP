// lib/features/lab/presentation/lab_team_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/user_model.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/role_badge.dart';
import '../../staff/presentation/add_staff_screen.dart';

/// All team members for the current lab.
final labTeamProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final labClinicId = user?.clinicId;
  if (labClinicId == null || labClinicId.isEmpty) {
    return const Stream.empty();
  }
  return FirebaseFirestore.instance
      .collection('users')
      .where('clinicId', isEqualTo: labClinicId)
      .snapshots()
      .map((s) => s.docs
          .map((d) => <String, dynamic>{'uid': d.id, ...d.data()})
          .toList());
});

class LabTeamScreen extends ConsumerWidget {
  const LabTeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final teamAsync = ref.watch(labTeamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Team'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(labTeamProvider),
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.textSecondary, size: 20),
          ),
        ],
      ),
      floatingActionButton: userAsync.maybeWhen(
        data: (user) {
          final isOwner = user?.role == UserRole.owner ||
    user?.role == UserRole.admin ||
    user?.isLabOwner == true;
          if (!isOwner) return null;
          return FloatingActionButton.extended(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AddStaffScreen(),
              ),
            ),
            icon: const Icon(Icons.person_add_alt_rounded),
            label: const Text('Add member'),
          );
        },
        orElse: () => null,
      ),
      body: SafeArea(
        child: userAsync.when(
          loading: () => const Center(
              child:
                  CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(child: Text('$e')),
          data: (user) {
            final isOwner = user?.role == UserRole.owner ||
    user?.role == UserRole.admin ||
    user?.isLabOwner == true;
            return teamAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primary)),
              error: (e, _) => Center(child: Text('$e')),
              data: (members) {
                if (members.isEmpty) {
                  return const EmptyState(
                    icon: Icons.groups_outlined,
                    title: 'No team members yet',
                    subtitle:
                        'Add technicians and receptionists to help run the lab.',
                  );
                }
                final sorted = [...members]..sort((a, b) {
                    // Owner first, then active, then by name
                    final aOwner =
                        a['role'] == UserRole.owner.name ? 0 : 1;
                    final bOwner =
                        b['role'] == UserRole.owner.name ? 0 : 1;
                    if (aOwner != bOwner) return aOwner - bOwner;
                    final aActive = a['active'] == false ? 1 : 0;
                    final bActive = b['active'] == false ? 1 : 0;
                    if (aActive != bActive) return aActive - bActive;
                    return (a['name'] ?? '')
                        .toString()
                        .compareTo((b['name'] ?? '').toString());
                  });
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (_, i) => _MemberRow(
                    member: sorted[i],
                    canManage: isOwner,
                    currentUserUid: user?.uid,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _MemberRow extends ConsumerStatefulWidget {
  final Map<String, dynamic> member;
  final bool canManage;
  final String? currentUserUid;
  const _MemberRow({
    required this.member,
    required this.canManage,
    required this.currentUserUid,
  });

  @override
  ConsumerState<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends ConsumerState<_MemberRow> {
  bool _busy = false;

  Future<void> _toggleActive() async {
    final uid = widget.member['uid']?.toString() ?? '';
    if (uid.isEmpty) return;
    final currentlyActive = widget.member['active'] != false;
    final action = currentlyActive ? 'Deactivate' : 'Reactivate';

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('$action member', style: AppTextStyles.h3),
        content: Text(
          currentlyActive
              ? 'This member will no longer be able to sign in. Their '
                  'historical activity is preserved.'
              : 'This member will be able to sign in again.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: currentlyActive
                  ? AppColors.error
                  : AppColors.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'active': !currentlyActive});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$action successful.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.member;
    final name = (m['name'] ?? 'Unnamed').toString();
    final email = (m['email'] ?? '').toString();
    final roleStr = (m['role'] ?? 'unknown').toString();
    final active = m['active'] != false;
    final uid = m['uid']?.toString() ?? '';
    final isSelf = uid.isNotEmpty && uid == widget.currentUserUid;
    final isOwner = roleStr == UserRole.owner.name;

    final roleColor = switch (roleStr) {
      'owner' => AppColors.accent,
      'lab' => AppColors.info,
      'receptionist' => AppColors.labAccent,
      'admin' => AppColors.secondary,
      _ => AppColors.textMuted,
    };
    final roleLabel = switch (roleStr) {
      'owner' => 'Owner',
      'lab' => 'Technician',
      'receptionist' => 'Reception',
      'admin' => 'Admin',
      _ => 'Unknown',
    };

    return Opacity(
      opacity: active ? 1 : 0.55,
      child: GlassCard(
        borderColor: active
            ? roleColor.withOpacity(.35)
            : AppColors.cardBorder,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: roleColor.withOpacity(.15),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: roleColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('you',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  if (email.isNotEmpty)
                    Text(email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption),
                  const SizedBox(height: 4),
                  Row(children: [
                    RoleBadge(label: roleLabel, color: roleColor),
                    if (!active) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('Inactive',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
            if (widget.canManage && !isOwner && !isSelf)
              IconButton(
                tooltip: active ? 'Deactivate' : 'Reactivate',
                onPressed: _busy ? null : _toggleActive,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary),
                      )
                    : Icon(
                        active
                            ? Icons.pause_circle_outline_rounded
                            : Icons.play_circle_outline_rounded,
                        color: active
                            ? AppColors.warning
                            : AppColors.success,
                        size: 22,
                      ),
              ),
          ]),
        ),
      ),
    );
  }
}