import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../core/models/user_model.dart';
import '../../core/services/clinic_service.dart';
import 'logout_helper.dart';
import 'role_chip.dart';

class ClinicAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? extraActions;
  final bool showBackButton;

  const ClinicAppBar({
    super.key,
    required this.title,
    this.extraActions,
    this.showBackButton = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

   @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final clinicAsync = ref.watch(currentClinicProvider);

    final clinicName = user?.role == UserRole.admin
    ? 'DoctoGP Admin'
    : clinicAsync.maybeWhen(
        data: (c) => c?.name ?? 'Clinic',
        orElse: () => 'Clinic',
      );

    final roleLabel = user?.roleLabel ?? '';
    final roleColor = _roleColor(user?.role);
    final roleIcon = _roleIcon(user?.role);

    // Decide whether the role chip can fit. On narrow screens we drop it
    // and rely on the dashboard body's role indication instead.
    final screenWidth = MediaQuery.of(context).size.width;
    final showRoleChip = roleLabel.isNotEmpty && screenWidth >= 400;

    return AppBar(
      backgroundColor: AppColors.background,
      elevation: 0,
      toolbarHeight: 64,
      automaticallyImplyLeading: showBackButton,
      titleSpacing: 8,
      title: Row(
        children: [
          // Brand mark
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.local_hospital_rounded,
              color: AppColors.background,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  clinicName,
                  style: AppTextStyles.h3.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  title,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textMuted,
                    letterSpacing: 0.4,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        ...?extraActions,
        if (showRoleChip)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: RoleChip(
              label: roleLabel,
              color: roleColor,
              icon: roleIcon,
            ),
          ),
        if (user?.role == UserRole.receptionist)
          IconButton(
            tooltip: 'Clinic settings',
            icon: const Icon(
              Icons.settings_outlined,
              color: AppColors.textSecondary,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            onPressed: () => context.push('/clinic-settings'),
          ),
        IconButton(
          tooltip: 'Sign out',
          icon: const Icon(
            Icons.logout_rounded,
            color: AppColors.error,
            size: 20,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 36,
          ),
          onPressed: () => LogoutHelper.confirmAndSignOut(
            context,
            ref,
            userName: user?.name,
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Color _roleColor(UserRole? role) {
  switch (role) {
    case UserRole.patient: return AppColors.patientAccent;
    case UserRole.owner: return AppColors.secondary;
    case UserRole.receptionist: return AppColors.receptionAccent;
    case UserRole.doctor: return AppColors.doctorAccent;
    case UserRole.nurse: return AppColors.nurseAccent;
    case UserRole.lab: return AppColors.labAccent;
    case UserRole.admin: return AppColors.secondary;
    default: return AppColors.textMuted;
  }
}

IconData _roleIcon(UserRole? role) {
  switch (role) {
    case UserRole.patient: return Icons.person_rounded;
    case UserRole.owner: return Icons.business_center_rounded;
    case UserRole.receptionist: return Icons.support_agent_rounded;
    case UserRole.doctor: return Icons.medical_services_rounded;
    case UserRole.nurse: return Icons.volunteer_activism_rounded;
    case UserRole.lab: return Icons.science_rounded;
    case UserRole.admin: return Icons.shield_rounded;
    default: return Icons.person_outline_rounded;
  }
}
}