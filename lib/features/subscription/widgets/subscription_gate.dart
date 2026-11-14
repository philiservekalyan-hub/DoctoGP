// lib/features/subscription/widgets/subscription_gate.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/subscription_access.dart';
import '../../../core/providers/subscription_providers.dart';
import '../../../core/widgets/glass_card.dart';

/// Wraps a widget that requires a specific feature. If the current
/// subscription state doesn't allow that feature, renders an upgrade
/// card instead.
class SubscriptionGate extends ConsumerWidget {
  final String entityType;
  final String entityId;
  final String planType;
  final SubscriptionFeature feature;
  final Widget child;
  final VoidCallback onUpgrade;

  const SubscriptionGate({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.planType,
    required this.feature,
    required this.child,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(subscriptionAccessProvider(
      (entityType: entityType, entityId: entityId, planType: planType),
    ));
    if (access.allows(feature)) return child;

    return GlassCard(
      borderColor: AppColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.lock_outline_rounded,
                color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_featureName(feature),
                  style: AppTextStyles.h3),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            _featureDescription(feature),
            style: AppTextStyles.bodyMuted,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onUpgrade,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Renew subscription'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _featureName(SubscriptionFeature f) => switch (f) {
        SubscriptionFeature.newPatientRegistration =>
          'New patient registration',
        SubscriptionFeature.staffInvitation => 'Staff invitations',
        SubscriptionFeature.analyticsDashboard => 'Analytics dashboard',
        SubscriptionFeature.bulkCsvExport => 'Bulk exports',
        SubscriptionFeature.sponsoredAds => 'Sponsored offers',
        SubscriptionFeature.bulkCommunication => 'Bulk messaging',
        SubscriptionFeature.advancedIntegration => 'Advanced integrations',
        _ => 'This feature',
      };

  String _featureDescription(SubscriptionFeature f) => switch (f) {
        SubscriptionFeature.newPatientRegistration =>
          'Registering new patients requires an active subscription. Your '
              'existing patients are fully accessible.',
        SubscriptionFeature.staffInvitation =>
          'Adding new team members requires an active subscription.',
        SubscriptionFeature.analyticsDashboard =>
          'Analytics and reports require an active subscription. Your '
              'clinical data is untouched.',
        SubscriptionFeature.bulkCsvExport =>
          'Bulk CSV exports require an active subscription. Per-patient '
              'record export remains available from the patient screen.',
        SubscriptionFeature.sponsoredAds =>
          'Sponsored offers require an active subscription.',
        SubscriptionFeature.bulkCommunication =>
          'Bulk SMS and WhatsApp require an active subscription.',
        SubscriptionFeature.advancedIntegration =>
          'Advanced integrations require an active subscription.',
        _ => 'This feature requires an active subscription.',
      };
}