// lib/features/subscription/widgets/subscription_checkout_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/glass_card.dart';

class SubscriptionCheckoutScreen extends ConsumerStatefulWidget {
  final String entityType; // 'clinic' | 'lab' | 'chemist'
  final String entityId;
  final String planType;

  const SubscriptionCheckoutScreen({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.planType,
  });

  @override
  ConsumerState<SubscriptionCheckoutScreen> createState() =>
      _SubscriptionCheckoutScreenState();
}

class _SubscriptionCheckoutScreenState
    extends ConsumerState<SubscriptionCheckoutScreen> {
  bool _loading = true;
  bool _paying = false;
  Map<String, dynamic>? _doc;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('subscriptions')
          .where('entityType', isEqualTo: widget.entityType)
          .where('entityId', isEqualTo: widget.entityId)
          .where('planType', isEqualTo: widget.planType)
          .limit(1)
          .get();
      if (mounted) {
        setState(() {
          _doc = snap.docs.isEmpty ? null : snap.docs.first.data();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _productLabel => switch (widget.entityType) {
        'clinic' => 'Clinic',
        'lab' => 'Lab',
        'chemist' => 'Chemist',
        _ => 'Subscription',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Renew ${_productLabel.toLowerCase()} subscription',
            style: AppTextStyles.h3),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child:
                    CircularProgressIndicator(color: AppColors.primary))
            : _doc == null
                ? _emptyState()
                : _body(),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 48, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(
                'Your subscription hasn\'t been set up yet.\n'
                'Please contact your administrator to activate a plan.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMuted,
              ),
            ],
          ),
        ),
      );

  Widget _body() {
    final doc = _doc!;
    final planName =
        (doc['planName'] ?? doc['name'] ?? '$_productLabel plan').toString();
    final amount = (doc['planAmount'] as num?)?.toDouble() ??
        (doc['amount'] as num?)?.toDouble() ??
        (doc['price'] as num?)?.toDouble() ??
        0.0;
    final currency = (doc['currency'] ?? 'INR').toString();
    final cycle = (doc['billingCycle'] ?? 'monthly').toString();
    final periodEndRaw = doc['currentPeriodEnd'];
    final expiry =
        periodEndRaw is Timestamp ? periodEndRaw.toDate() : null;
    final status = (doc['status'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$_productLabel plan', style: AppTextStyles.caption),
              const SizedBox(height: 4),
              Text(planName, style: AppTextStyles.h3),
              const SizedBox(height: 16),
              _row('Amount',
                  '$currency ${amount.toStringAsFixed(0)} / $cycle'),
              if (expiry != null)
                _row('Current expiry',
                    DateFormat('d MMM yyyy').format(expiry)),
              _row('Status', _statusLabel(status)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Amount is set by your DoctoGP administrator. Contact them if '
          'this looks incorrect.',
          style: AppTextStyles.caption,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed:
                _paying || amount <= 0 ? null : () => _startPayment(amount, currency),
            icon: _paying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.lock_outline_rounded, size: 18),
            label: Text(_paying
                ? 'Processing…'
                : 'Pay $currency ${amount.toStringAsFixed(0)}'),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text('Secure payment · No hidden charges',
              style: AppTextStyles.caption),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.caption),
            Text(value,
                style: AppTextStyles.body
                    .copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  String _statusLabel(String s) => switch (s) {
        'active' => 'Active',
        'past_due' => 'Past due',
        'pending_payment' => 'Pending payment',
        'cancelled' => 'Cancelled',
        'expired' => 'Expired',
        '' => 'Not set',
        _ => s,
      };

  Future<void> _startPayment(double amount, String currency) async {
    setState(() => _paying = true);

    // TODO: wire real payment gateway here.
    //  1. Call Cloud Function `startSubscriptionRenewal({ entityType,
    //     entityId, planType })` — server validates the caller is the
    //     owner of `entityId` and creates a Razorpay/Stripe order using
    //     the admin-set `planAmount` from Firestore.
    //  2. Launch the gateway sheet with the returned order id.
    //  3. On webhook success, the CF updates
    //     `subscriptions/{doc}.{ status: 'active', currentPeriodEnd: +cycle }`.
    //  4. On success, pop the screen here. Never mark paid client-side.
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => _paying = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content:
          Text('Payment integration pending — connect Razorpay/Stripe'),
      backgroundColor: AppColors.warning,
      duration: Duration(seconds: 4),
    ));
  }
}