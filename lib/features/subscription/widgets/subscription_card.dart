// lib/features/subscription/widgets/subscription_card.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/subscription_access.dart';
import '../../../core/providers/subscription_providers.dart';
import '../../../core/widgets/glass_card.dart';

// ───────────────────────────────────────────────────────────────────
// Raw doc provider (mirrors the private one in subscription_providers)
// so the card can display amount / expiry / auto-renew fields that
// `resolveState` doesn't expose.
// ───────────────────────────────────────────────────────────────────

class SubscriptionEntityKey {
  final String entityType;
  final String entityId;
  final String planType;
  const SubscriptionEntityKey(this.entityType, this.entityId, this.planType);

  @override
  bool operator ==(Object o) =>
      o is SubscriptionEntityKey &&
      o.entityType == entityType &&
      o.entityId == entityId &&
      o.planType == planType;

  @override
  int get hashCode => Object.hash(entityType, entityId, planType);
}

final rawSubscriptionProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>?, SubscriptionEntityKey>((ref, key) {
  return FirebaseFirestore.instance
      .collection('subscriptions')
      .where('entityType', isEqualTo: key.entityType)
      .where('entityId', isEqualTo: key.entityId)
      .where('planType', isEqualTo: key.planType)
      .limit(1)
      .snapshots()
      .map((snap) => snap.docs.isEmpty ? null : snap.docs.first.data());
});

// ───────────────────────────────────────────────────────────────────
// Card
// ───────────────────────────────────────────────────────────────────

class SubscriptionCard extends ConsumerWidget {
  /// 'clinic' | 'lab' | 'chemist'
  final String entityType;
  final String? entityIdOverride; 
  /// Override the display label. Defaults to capitalised `entityType`.
  final String? productLabel;

  const SubscriptionCard({
    super.key,
    required this.entityType,
    this.entityIdOverride,
    this.productLabel,
  });

  String get _label =>
      productLabel ??
      '${entityType[0].toUpperCase()}${entityType.substring(1)}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final entityId = entityIdOverride ?? user?.clinicId;
    
    if (entityId == null || entityId.isEmpty) {
      return const SizedBox.shrink();
    }
    final planType = '${entityType}_monthly';

    final rawAsync = ref.watch(rawSubscriptionProvider(
      SubscriptionEntityKey(entityType, entityId, planType),
    ));
    final access = ref.watch(subscriptionAccessProvider(
      (entityType: entityType, entityId: entityId, planType: planType),
    ));

    return rawAsync.when(
      loading: () => const GlassCard(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            ),
          ),
        ),
      ),
      error: (_, __) => GlassCard(
  child: Row(children: [
    const Icon(Icons.error_outline_rounded,
        color: AppColors.error, size: 20),
    const SizedBox(width: 10),
    Expanded(
      child: Text('Could not load subscription',
          style: AppTextStyles.body),
    ),
  ]),
),
      data: (raw) => _build(
          context, ref, raw, access, entityId, planType),
    );
  }

  Widget _build(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? raw,
    SubscriptionAccess access,
    String entityId,
    String planType,
  ) {
    final state = access.state;
    final autoRenew = raw?['autoRenew'] == true;
    final meta = _metaFor(state, autoRenew);

    // Field-name fallbacks because admin tooling may use either name.
    final planName =
        (raw?['planName'] ?? raw?['name'] ?? '${_label} plan').toString();
    final amount = (raw?['planAmount'] as num?)?.toDouble() ??
        (raw?['amount'] as num?)?.toDouble() ??
        (raw?['price'] as num?)?.toDouble();
    final currency = (raw?['currency'] ?? 'INR').toString();
    final cycle = (raw?['billingCycle'] ?? 'monthly').toString();
    final periodEndRaw = raw?['currentPeriodEnd'];
    final expiry =
        periodEndRaw is Timestamp ? periodEndRaw.toDate() : null;

    return GlassCard(
      borderColor: meta.borderColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: meta.color.withOpacity(.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(meta.icon, color: meta.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$_label subscription',
                      style: AppTextStyles.caption),
                  const SizedBox(height: 2),
                  Text(meta.title,
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (meta.badge != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: meta.color.withOpacity(.13),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(meta.badge!,
                    style: AppTextStyles.caption.copyWith(
                        color: meta.color,
                        fontWeight: FontWeight.w600)),
              ),
          ]),

          if (raw != null) ...[
            const SizedBox(height: 12),
            _kv('Plan', planName),
            if (amount != null && amount > 0) ...[
              const SizedBox(height: 4),
              _kv('Amount',
                  '$currency ${amount.toStringAsFixed(0)} / $cycle'),
            ],
            if (expiry != null) ...[
              const SizedBox(height: 4),
              _kv(
                state == SubscriptionState.active
                    ? 'Renews on'
                    : 'Expired on',
                DateFormat('d MMM yyyy').format(expiry),
              ),
            ],
          ] else ...[
            const SizedBox(height: 8),
            Text(meta.subtitle, style: AppTextStyles.caption),
          ],

          if (meta.showAction) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: meta.actionColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _onAction(
                    context, state, autoRenew, entityId, planType),
                icon: Icon(meta.actionIcon, size: 18),
                label: Text(meta.actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: AppTextStyles.caption
                    .copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      );

  void _onAction(
    BuildContext context,
    SubscriptionState state,
    bool autoRenew,
    String entityId,
    String planType,
  ) {
    switch (state) {
      case SubscriptionState.active:
        _manageSheet(context, autoRenew, entityId, planType);
        break;
      case SubscriptionState.grace:
      case SubscriptionState.restricted:
      case SubscriptionState.cancelled:
      case SubscriptionState.pendingPayment:
        _openCheckout(context, entityId, planType);
        break;
      case SubscriptionState.none:
        _contactAdminDialog(context);
        break;
    }
  }

  void _openCheckout(
      BuildContext context, String entityId, String planType) {
    context.push(
      '/subscription/checkout'
      '?entityType=$entityType&entityId=$entityId&planType=$planType',
    );
  }

  void _manageSheet(BuildContext context, bool autoRenew, String entityId,
      String planType) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (bctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Renewal settings', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              Text(
                'Auto-renew keeps your plan active automatically. When off, '
                'you must renew manually before expiry.',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(bctx);
                      _openCheckout(context, entityId, planType);
                    },
                    child: const Text('Renew now'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: autoRenew
                          ? AppColors.error
                          : AppColors.success,
                      side: BorderSide(
                          color: autoRenew
                              ? AppColors.error
                              : AppColors.success),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(bctx);
                      _toggleAutoRenew(entityId, planType, !autoRenew);
                    },
                    child: Text(autoRenew
                        ? 'Turn off auto-renew'
                        : 'Turn on auto-renew'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _contactAdminDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Subscription not configured',
            style: AppTextStyles.h3),
        content: Text(
          'Your subscription plan hasn\'t been set up yet. Please contact '
          'your DoctoGP administrator to activate a plan.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _toggleAutoRenew(
      String entityId, String planType, bool value) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('subscriptions')
          .where('entityType', isEqualTo: entityType)
          .where('entityId', isEqualTo: entityId)
          .where('planType', isEqualTo: planType)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return;
      await snap.docs.first.reference.update({
        'autoRenew': value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {/* surfaced via provider stream */}
  }
}

// ───────────────────────────────────────────────────────────────────
// Meta
// ───────────────────────────────────────────────────────────────────

class _Meta {
  final String title;
  final String subtitle;
  final String? badge;
  final IconData icon;
  final Color color;
  final Color borderColor;
  final String actionLabel;
  final IconData actionIcon;
  final Color actionColor;
  final bool showAction;

  _Meta({
    required this.title,
    required this.subtitle,
    this.badge,
    required this.icon,
    required this.color,
    required this.borderColor,
    required this.actionLabel,
    required this.actionIcon,
    required this.actionColor,
    this.showAction = true,
  });
}

_Meta _metaFor(SubscriptionState s, bool autoRenew) {
  switch (s) {
    case SubscriptionState.active:
      return _Meta(
        title: autoRenew ? 'Active · Auto-renews' : 'Active · Auto-renew off',
        subtitle: '',
        badge: 'Active',
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.success,
        borderColor: AppColors.success.withOpacity(.25),
        actionLabel: 'Manage renewal',
        actionIcon: Icons.tune_rounded,
        actionColor: AppColors.primary,
      );
    case SubscriptionState.grace:
      return _Meta(
        title: 'Grace period',
        subtitle: '',
        badge: 'Grace',
        icon: Icons.schedule_rounded,
        color: AppColors.warning,
        borderColor: AppColors.warning.withOpacity(.35),
        actionLabel: 'Renew now',
        actionIcon: Icons.payment_rounded,
        actionColor: AppColors.warning,
      );
    case SubscriptionState.restricted:
      return _Meta(
        title: 'Subscription inactive',
        subtitle: '',
        badge: 'Inactive',
        icon: Icons.lock_outline_rounded,
        color: AppColors.error,
        borderColor: AppColors.error.withOpacity(.35),
        actionLabel: 'Reactivate',
        actionIcon: Icons.refresh_rounded,
        actionColor: AppColors.error,
      );
    case SubscriptionState.pendingPayment:
      return _Meta(
        title: 'Payment pending',
        subtitle: '',
        badge: 'Pending',
        icon: Icons.pending_outlined,
        color: AppColors.info,
        borderColor: AppColors.info.withOpacity(.35),
        actionLabel: 'Complete payment',
        actionIcon: Icons.open_in_new_rounded,
        actionColor: AppColors.info,
      );
    case SubscriptionState.cancelled:
      return _Meta(
        title: 'Cancelled',
        subtitle: '',
        badge: 'Cancelled',
        icon: Icons.block_rounded,
        color: AppColors.textMuted,
        borderColor: AppColors.cardBorder,
        actionLabel: 'Reactivate',
        actionIcon: Icons.refresh_rounded,
        actionColor: AppColors.primary,
      );
    case SubscriptionState.none:
      return _Meta(
        title: 'No subscription',
        subtitle: 'Your subscription hasn\'t been set up yet. '
            'Contact your administrator to activate a plan.',
        icon: Icons.workspace_premium_outlined,
        color: AppColors.textMuted,
        borderColor: AppColors.cardBorder,
        actionLabel: 'Contact admin',
        actionIcon: Icons.info_outline_rounded,
        actionColor: AppColors.textMuted,
      );
  }
}