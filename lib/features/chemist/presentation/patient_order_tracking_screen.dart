// lib/features/chemist/presentation/patient_order_tracking_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/chemist_model.dart';
import '../../../core/models/prescription_order_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/utils/contact_utils.dart';

// -----------------------------------------------------------------
// Providers — defined at the top level so they aren't rebuilt on
// every frame. Using FutureProvider (.get) instead of StreamProvider
// (.snapshots) prevents the infinite loading spinner on Android.
// -----------------------------------------------------------------
final _singleOrderProvider = FutureProvider.autoDispose
    .family<PrescriptionOrderModel?, String>((ref, orderId) async {
  if (orderId.isEmpty) return null;
  final doc = await FirebaseFirestore.instance
      .collection('prescriptionOrders')
      .doc(orderId)
      .get()
      .timeout(const Duration(seconds: 5));
  if (!doc.exists) return null;
  return PrescriptionOrderModel.fromMap(doc.id, doc.data()!);
});

final _singleChemistProvider = FutureProvider.autoDispose
    .family<ChemistModel?, String>((ref, chemistId) async {
  if (chemistId.isEmpty) return null;
  final doc = await FirebaseFirestore.instance
      .collection('chemists')
      .doc(chemistId)
      .get()
      .timeout(const Duration(seconds: 5));
  if (!doc.exists) return null;
  return ChemistModel.fromMap(doc.id, doc.data()!);
});

class PatientOrderTrackingScreen extends ConsumerWidget {
  final String orderId;
  const PatientOrderTrackingScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(_singleOrderProvider(orderId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Order tracking', style: AppTextStyles.h3),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.primary),
            onPressed: () => ref.invalidate(_singleOrderProvider(orderId)),
          ),
        ],
      ),
      body: SafeArea(
        child: orderAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Failed to load order: $e',
                  style: const TextStyle(color: AppColors.error)),
            ),
          ),
          data: (order) {
            if (order == null) {
              return const Center(child: Text('Order not found.'));
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _header(order),
                const SizedBox(height: 14),
                _prescriptionCard(order),
                const SizedBox(height: 14),
                _chemistContactCard(context, ref, order),
                const SizedBox(height: 14),
                _statusCard(context, ref, order),
                const SizedBox(height: 14),
                _itemsCard(order),
                if (order.totalAmount != null) ...[
                  const SizedBox(height: 14),
                  _billCard(order),
                ],
                if (order.hasReceipt) ...[
                  const SizedBox(height: 14),
                  _receiptCard(order),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(PrescriptionOrderModel o) => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order #${o.orderNumber}', style: AppTextStyles.h2),
            const SizedBox(height: 4),
            Text(
              'Placed ${DateFormat('dd MMM yyyy • hh:mm a').format(o.placedAt)}',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 4),
            Text('From: ${o.chemistName}', style: AppTextStyles.body),
          ],
        ),
      );

  Widget _prescriptionCard(PrescriptionOrderModel o) {
    final hasAny = (o.doctorLine.trim().isNotEmpty) ||
        (o.clinicName ?? '').isNotEmpty ||
        (o.diagnosis ?? '').isNotEmpty ||
        o.prescriptionDate != null;

    if (!hasAny) return const SizedBox.shrink();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.medical_information_rounded,
                size: 18, color: AppColors.doctorAccent),
            const SizedBox(width: 9),
            Text('Prescription', style: AppTextStyles.h3),
          ]),
          const SizedBox(height: 10),
          if (o.doctorLine.trim().isNotEmpty) ...[
            Text('Prescribed by', style: AppTextStyles.caption),
            const SizedBox(height: 2),
            Text(o.doctorLine, style: AppTextStyles.body),
            const SizedBox(height: 8),
          ],
          if ((o.clinicName ?? '').isNotEmpty) ...[
            Text('Clinic', style: AppTextStyles.caption),
            const SizedBox(height: 2),
            Text(o.clinicName!, style: AppTextStyles.body),
            const SizedBox(height: 8),
          ],
          if (o.prescriptionDate != null) ...[
            Text('Date', style: AppTextStyles.caption),
            const SizedBox(height: 2),
            Text(
              DateFormat('dd MMM yyyy').format(o.prescriptionDate!),
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 8),
          ],
          if ((o.diagnosis ?? '').trim().isNotEmpty) ...[
            Text('Diagnosis / indication', style: AppTextStyles.caption),
            const SizedBox(height: 2),
            Text(o.diagnosis!, style: AppTextStyles.body),
            const SizedBox(height: 8),
          ],
          if ((o.rxFreeText ?? '').trim().isNotEmpty) ...[
            Text('Doctor\'s notes', style: AppTextStyles.caption),
            const SizedBox(height: 2),
            Text(o.rxFreeText!, style: AppTextStyles.body),
          ],
        ],
      ),
    );
  }

  Widget _chemistContactCard(
      BuildContext context, WidgetRef ref, PrescriptionOrderModel o) {
    final chemistAsync = ref.watch(_singleChemistProvider(o.chemistDocId));

    return chemistAsync.when(
      loading: () => GlassCard(
        child: Row(children: [
          const Icon(Icons.local_pharmacy_rounded,
              size: 18, color: AppColors.textMuted),
          const SizedBox(width: 9),
          Text('Contact chemist', style: AppTextStyles.h3),
        ]),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (chemist) {
        if (chemist == null) return const SizedBox.shrink();
        final hasPhone = chemist.phone.trim().isNotEmpty;
        return GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.local_pharmacy_rounded,
                    size: 18, color: AppColors.success),
                const SizedBox(width: 9),
                Text('Contact chemist', style: AppTextStyles.h3),
              ]),
              const SizedBox(height: 10),
              Text(chemist.name,
                  style: AppTextStyles.body
                      .copyWith(fontWeight: FontWeight.w600)),
              if (hasPhone) ...[
                const SizedBox(height: 2),
                Text(chemist.phone, style: AppTextStyles.bodyMuted),
              ],
              if (chemist.fullAddress.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(chemist.fullAddress, style: AppTextStyles.caption),
              ],
              if (hasPhone) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await callNumber(chemist.phone);
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not open dialer.'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.phone_rounded, size: 16),
                      label: const Text('Call chemist'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.info,
                        side: const BorderSide(color: AppColors.info),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await whatsappNumber(
                          chemist.phone,
                          message:
                              'Hi, this is about order #${o.orderNumber} on STAT.',
                        );
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not open WhatsApp.'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.chat_rounded, size: 16),
                      label: const Text('WhatsApp'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.success,
                        side: const BorderSide(color: AppColors.success),
                      ),
                    ),
                  ),
                ]),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statusCard(
      BuildContext context, WidgetRef ref, PrescriptionOrderModel o) {
    final color = switch (o.status) {
      PrescriptionOrderStatus.placed => AppColors.warning,
      PrescriptionOrderStatus.accepted => AppColors.info,
      PrescriptionOrderStatus.billed => AppColors.patientAccent,
      PrescriptionOrderStatus.paidPendingVerification => AppColors.info,
      PrescriptionOrderStatus.paid => AppColors.success,
      PrescriptionOrderStatus.preparing => AppColors.info,
      PrescriptionOrderStatus.outForDelivery => AppColors.info,
      PrescriptionOrderStatus.delivered => AppColors.success,
      PrescriptionOrderStatus.cancelled ||
      PrescriptionOrderStatus.rejected =>
        AppColors.error,
      PrescriptionOrderStatus.unknown => AppColors.textMuted,
    };

    final steps = <(String, bool)>[
      ('Order placed', true),
      (
        'Accepted by chemist',
        o.acceptedAt != null ||
            o.status.index >= PrescriptionOrderStatus.billed.index
      ),
      (
        'Bill generated',
        o.status == PrescriptionOrderStatus.billed ||
            o.status == PrescriptionOrderStatus.paidPendingVerification ||
            o.status == PrescriptionOrderStatus.paid ||
            o.status == PrescriptionOrderStatus.preparing ||
            o.status == PrescriptionOrderStatus.outForDelivery ||
            o.status == PrescriptionOrderStatus.delivered
      ),
      ('Payment verified', o.paymentVerifiedAt != null),
      ('Preparing', o.preparingAt != null),
      ('Out for delivery', o.outForDeliveryAt != null),
      ('Delivered', o.deliveredAt != null),
    ];

    return GlassCard(
      borderColor: color.withOpacity(.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withOpacity(.13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(o.statusLabel,
                  style: AppTextStyles.caption.copyWith(
                      color: color, fontWeight: FontWeight.w600)),
            ),
            const Spacer(),
            if (o.canPatientPay)
              ElevatedButton.icon(
                onPressed: () => _openPayDialog(context, ref, o),
                icon: const Icon(Icons.payments_rounded, size: 18),
                label:
                    Text('Pay ₹${o.totalAmount?.toStringAsFixed(0) ?? ''}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                ),
              ),
          ]),
          const SizedBox(height: 12),
          ...steps.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(
                    s.$2
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 16,
                    color:
                        s.$2 ? AppColors.success : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(s.$1,
                      style: AppTextStyles.body.copyWith(
                          color: s.$2
                              ? AppColors.textPrimary
                              : AppColors.textMuted)),
                ]),
              )),
        ],
      ),
    );
  }

  Widget _itemsCard(PrescriptionOrderModel o) => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Medicines', style: AppTextStyles.h3),
            const SizedBox(height: 10),
            ...o.items.map((i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.name, style: AppTextStyles.body),
                          Text(
                            [i.dose, i.frequency, i.duration]
                                .where((s) => s.trim().isNotEmpty)
                                .join(' • '),
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                    Text('×${i.quantity}', style: AppTextStyles.body),
                    if (i.lineTotal != null) ...[
                      const SizedBox(width: 10),
                      Text('₹${i.lineTotal!.toStringAsFixed(0)}',
                          style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w600)),
                    ],
                  ]),
                )),
          ],
        ),
      );

  Widget _billCard(PrescriptionOrderModel o) => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bill', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            if (o.deliveryFee != null)
              _kv('Delivery fee',
                  '₹${o.deliveryFee!.toStringAsFixed(0)}'),
            _kv('Total', '₹${o.totalAmount!.toStringAsFixed(0)}'),
          ],
        ),
      );

  Widget _receiptCard(PrescriptionOrderModel o) => GlassCard(
        borderColor: AppColors.success.withOpacity(.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.receipt_long_rounded,
                  size: 18, color: AppColors.success),
              const SizedBox(width: 9),
              Text('Receipt', style: AppTextStyles.h3),
            ]),
            const SizedBox(height: 10),
            _kv('Receipt no.', o.receiptNumber!),
            if (o.paidAt != null)
              _kv('Paid on',
                  DateFormat('dd MMM yyyy • hh:mm a').format(o.paidAt!)),
            if (o.paymentReference != null)
              _kv('UPI reference', o.paymentReference!),
            const SizedBox(height: 8),
            if (o.paymentVerifiedAt != null)
              Row(children: [
                const Icon(Icons.verified_rounded,
                    size: 16, color: AppColors.success),
                const SizedBox(width: 6),
                Text('Verified by chemist',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.success)),
              ])
            else
              Row(children: [
                const Icon(Icons.hourglass_top_rounded,
                    size: 16, color: AppColors.warning),
                const SizedBox(width: 6),
                Text('Awaiting chemist verification',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.warning)),
              ]),
          ],
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 130,
                child: Text(k, style: AppTextStyles.bodyMuted)),
            Expanded(child: Text(v, style: AppTextStyles.body)),
          ],
        ),
      );

  Future<void> _openPayDialog(
      BuildContext context, WidgetRef ref, PrescriptionOrderModel order) async {
    if (!context.mounted) return;
    final utrCtrl = TextEditingController();

    try {
      final chemist = await ref
          .read(_singleChemistProvider(order.chemistDocId).future);

      if (!context.mounted) return;
      if (chemist == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chemist details not found.'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }

      final upiUri = chemist.upiPaymentUri(
        amount: order.totalAmount ?? 0,
        orderNumber: order.orderNumber,
      );

      final submitted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
              'Pay ₹${order.totalAmount?.toStringAsFixed(0) ?? ''}',
              style: AppTextStyles.h3),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tap "Open UPI app" to pay ${chemist.name} directly. '
                  'After paying, paste the transaction reference (UTR) '
                  'below to generate your receipt.',
                  style: AppTextStyles.bodyMuted,
                ),
                const SizedBox(height: 12),
                if (chemist.upiId.isNotEmpty) ...[
                  Text('UPI ID', style: AppTextStyles.caption),
                  const SizedBox(height: 2),
                  SelectableText(chemist.upiId,
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: upiUri == null
                        ? null
                        : () async {
                            try {
                              final ok = await launchUrl(upiUri,
                                  mode: LaunchMode.externalApplication);
                              if (!ok && dctx.mounted) {
                                ScaffoldMessenger.of(dctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Could not open a UPI app. '
                                        'Pay manually via the UPI ID above.'),
                                    backgroundColor: AppColors.warning,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (dctx.mounted) {
                                ScaffoldMessenger.of(dctx).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('Could not open UPI app: $e'),
                                    backgroundColor: AppColors.error,
                                  ),
                                );
                              }
                            }
                          },
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open UPI app'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.info,
                      side: const BorderSide(color: AppColors.info),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: utrCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'UTR / transaction reference',
                    hintText: 'e.g. 1234567890ABCDEF',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (utrCtrl.text.trim().length < 6) return;
                Navigator.pop(dctx, true);
              },
              child: const Text('Generate receipt'),
            ),
          ],
        ),
      );

      if (!context.mounted) {
        utrCtrl.dispose();
        return;
      }
      if (submitted != true) {
        // Dialog dismissed. Defer disposal so the closing animation finishes first.
        Future.delayed(const Duration(milliseconds: 500), utrCtrl.dispose);
        return;
      }

      final utr = utrCtrl.text.trim();
      
      // Defer disposal. The dialog is still animating out and TextField
      // hasn't fully unmounted yet.
      Future.delayed(const Duration(milliseconds: 500), utrCtrl.dispose);

      final receiptNumber = await ref
          .read(chemistServiceProvider)
          .submitUpiReference(orderId: order.docId, utr: utr);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Receipt $receiptNumber generated. '
              'Chemist will verify shortly.'),
          backgroundColor: AppColors.success,
        ),
      );

      // Force a UI refresh to show the new status
      ref.invalidate(_singleOrderProvider(orderId));

    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
    }
  }