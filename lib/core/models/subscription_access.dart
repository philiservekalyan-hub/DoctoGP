// lib/core/models/subscription_access.dart
import 'package:flutter/material.dart';

enum SubscriptionState {
  none, // no subscription record at all — treated as trial/full
  pendingPayment,
  active,
  grace, // 0-7 days past period end
  restricted, // 7+ days past period end
  cancelled, // voluntary cancel, pays through period
}

enum SubscriptionFeature {
  readClinical,
  writeClinical,
  emergencyAccess,
  existingPatientWorkflow,
  newPatientRegistration,
  staffInvitation,
  analyticsDashboard,
  bulkCsvExport,
  sponsoredAds,
  bulkCommunication,
  advancedIntegration,
  fullDataExport,
}

class SubscriptionAccess {
  final SubscriptionState state;

  const SubscriptionAccess._(this.state);

  factory SubscriptionAccess.fromState(SubscriptionState state) =>
      SubscriptionAccess._(state);

  // ─── Feature predicates ────────────────────────────────────────────

  bool allows(SubscriptionFeature f) => switch (f) {
        // ── Always allowed, every state ──
        SubscriptionFeature.readClinical => true,
        SubscriptionFeature.writeClinical => true,
        SubscriptionFeature.emergencyAccess => true,
        SubscriptionFeature.existingPatientWorkflow => true,
        SubscriptionFeature.fullDataExport => true,

        // ── Blocked only in restricted ──
        SubscriptionFeature.newPatientRegistration =>
          state != SubscriptionState.restricted,
        SubscriptionFeature.staffInvitation =>
          state != SubscriptionState.restricted,
        SubscriptionFeature.analyticsDashboard =>
          state != SubscriptionState.restricted,
        SubscriptionFeature.bulkCsvExport =>
          state != SubscriptionState.restricted,
        SubscriptionFeature.sponsoredAds =>
          state != SubscriptionState.restricted,
        SubscriptionFeature.bulkCommunication =>
          state != SubscriptionState.restricted,
        SubscriptionFeature.advancedIntegration =>
          state != SubscriptionState.restricted,
      };

  // ─── Banner ────────────────────────────────────────────────────────

  /// Returns null if no banner is needed.
  ({String text, Color color, IconData icon, bool showRenewCta})
      ? get banner => switch (state) {
            SubscriptionState.active => null,
            SubscriptionState.pendingPayment => (
                text:
                    'Your payment is being confirmed. Features will unlock '
                    'as soon as it completes.',
                color: Colors.orange,
                icon: Icons.hourglass_top_rounded,
                showRenewCta: false,
              ),
            SubscriptionState.grace => (
                text:
                    'Your subscription ended. You have clinical access for '
                    '7 days. Renew to avoid losing growth features.',
                color: Colors.orange,
                icon: Icons.schedule_rounded,
                showRenewCta: true,
              ),
            SubscriptionState.restricted => (
                text:
                    'Your subscription is inactive. Clinical work is '
                    'unaffected, but you cannot onboard new patients or '
                    'access analytics until you renew.',
                color: Colors.red,
                icon: Icons.lock_outline_rounded,
                showRenewCta: true,
              ),
            SubscriptionState.cancelled => (
                text:
                    'You cancelled your subscription. It stays active '
                    'until the end of the current period.',
                color: Colors.blueGrey,
                icon: Icons.info_outline_rounded,
                showRenewCta: false,
              ),
            SubscriptionState.none => null,
          };

  /// Whether the app should show a blocking acknowledgement modal on
  /// login. Only for `restricted` — the clinic must actively
  /// acknowledge that they're in a degraded mode, so no later claim
  /// of "we didn't know."
  bool get requiresLoginAcknowledgment =>
      state == SubscriptionState.restricted;
}