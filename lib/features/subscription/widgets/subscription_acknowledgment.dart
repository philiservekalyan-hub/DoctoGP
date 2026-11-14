// lib/features/subscription/widgets/subscription_acknowledgment.dart
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';

Future<void> showSubscriptionAcknowledgment(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false, // must acknowledge
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(children: [
          const Icon(Icons.lock_outline_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Subscription inactive', style: AppTextStyles.h3),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your clinic subscription is inactive. You can still:',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 8),
            Text(
              '• Open any existing patient record\n'
              '• Write consultations and prescriptions\n'
              '• View appointments, lab orders and invoices\n'
              '• Access the patient mobile app',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'You cannot register new patients, invite staff, view '
              'analytics, or export bulk data until you renew.',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 12),
            Text(
              'Your clinical data is safe. You can export it at any time.',
              style: AppTextStyles.caption.copyWith(color: AppColors.info),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continue in restricted mode'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Caller navigates to checkout.
            },
            child: const Text('Renew now'),
          ),
        ],
      ),
    ),
  );
}