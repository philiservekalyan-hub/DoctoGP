import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme/app_colors.dart';

class LogoutHelper {
  LogoutHelper._();

  static Future<void> confirmAndSignOut(
    BuildContext context,
    WidgetRef ref, {
    String? userName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Sign out?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          userName == null || userName.isEmpty
              ? 'You will be logged out of this device.'
              : 'Goodbye, $userName. You will be logged out of this device.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    await ref.read(authServiceProvider).signOut();

    if (!context.mounted) return;
    context.go('/login');
  }
}