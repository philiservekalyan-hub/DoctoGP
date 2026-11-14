// lib/core/providers/subscription_providers.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/subscription_access.dart';

class _EntityPlanKey {
  final String entityType;
  final String entityId;
  final String planType;
  const _EntityPlanKey(this.entityType, this.entityId, this.planType);

  @override
  bool operator ==(Object o) =>
      o is _EntityPlanKey &&
      o.entityType == entityType &&
      o.entityId == entityId &&
      o.planType == planType;

  @override
  int get hashCode => Object.hash(entityType, entityId, planType);
}

final _entitySubscriptionProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>?, _EntityPlanKey>((ref, key) {
  return FirebaseFirestore.instance
      .collection('subscriptions')
      .where('entityType', isEqualTo: key.entityType)
      .where('entityId', isEqualTo: key.entityId)
      .where('planType', isEqualTo: key.planType)
      .limit(1)
      .snapshots()
      .map((snap) => snap.docs.isEmpty ? null : snap.docs.first.data());
});

/// Resolves the current state from raw subscription data + clock.
/// This is the single place that decides whether a subscription is
/// active, in grace, restricted, or cancelled.
SubscriptionState resolveState(Map<String, dynamic>? sub) {
  if (sub == null) return SubscriptionState.none;

  final rawStatus = (sub['status'] ?? '').toString();
  final periodEnd = (sub['currentPeriodEnd'] as Timestamp?)?.toDate();
  final now = DateTime.now();

  if (rawStatus == 'pending_payment') return SubscriptionState.pendingPayment;
  if (rawStatus == 'cancelled') {
    // Cancelled but still in paid period → full access.
    if (periodEnd != null && periodEnd.isAfter(now)) {
      return SubscriptionState.cancelled;
    }
    return SubscriptionState.restricted;
  }
  if (rawStatus == 'expired') return SubscriptionState.restricted;

  if (rawStatus == 'active' || rawStatus == 'past_due') {
    if (periodEnd == null) return SubscriptionState.restricted;
    final daysPast = now.difference(periodEnd).inDays;
    if (daysPast < 0) return SubscriptionState.active;
    if (daysPast <= 7) return SubscriptionState.grace;
    return SubscriptionState.restricted;
  }

  return SubscriptionState.none;
}

final subscriptionAccessProvider = Provider.autoDispose.family<
    SubscriptionAccess,
    ({String entityType, String entityId, String planType})>((ref, key) {
  final sub = ref.watch(_entitySubscriptionProvider(
    _EntityPlanKey(key.entityType, key.entityId, key.planType),
  )).valueOrNull;
  return SubscriptionAccess.fromState(resolveState(sub));
});