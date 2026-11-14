// lib/features/subscription/widgets/subscription_banner.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_text_styles.dart';
import '../../../core/providers/subscription_providers.dart';

class SubscriptionBanner extends ConsumerWidget {
  final String entityType;
  final String entityId;
  final String planType;
  final VoidCallback onRenew;

  const SubscriptionBanner({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.planType,
    required this.onRenew,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(subscriptionAccessProvider(
      (entityType: entityType, entityId: entityId, planType: planType),
    ));
    final banner = access.banner;
    if (banner == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: banner.color.withOpacity(.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: banner.color.withOpacity(.35)),
      ),
      child: Row(children: [
        Icon(banner.icon, color: banner.color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            banner.text,
            style: AppTextStyles.caption.copyWith(
              color: banner.color,
              height: 1.4,
            ),
          ),
        ),
        if (banner.showRenewCta)
          TextButton(
            onPressed: onRenew,
            child: Text('Renew', style: TextStyle(color: banner.color)),
          ),
      ]),
    );
  }
}