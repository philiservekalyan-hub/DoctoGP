// lib/features/chemist/presentation/chemist_order_detail_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/prescription_order_model.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/glass_card.dart';

final _singleOrderByIdProvider = FutureProvider.autoDispose
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

class ChemistOrderDetailScreen extends ConsumerWidget {
  final String orderId;
  const ChemistOrderDetailScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(_singleOrderByIdProvider(orderId));

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
        title: Text('Order details', style: AppTextStyles.h3),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.primary),
            onPressed: () =>
                ref.invalidate(_singleOrderByIdProvider(orderId)),
          ),
        ],
      ),
      body: SafeArea(
        child: orderAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Failed: $e',
                  style: const TextStyle(color: AppColors.error)),
            ),
          ),
          data: (order) {
            if (order == null) {
              return const Center(child: Text('Order not found.'));
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                _header(order),
                const SizedBox(height: 14),
                _prescriptionCard(order),
                const SizedBox(height: 14),
                _patientCard(order),
                const SizedBox(height: 14),
                _contactPatientCard(context, order),
                const SizedBox(height: 14),
                _itemsCard(order),
                if (order.totalAmount != null) ...[
                  const SizedBox(height: 14),
                  _billCard(order),
                ],
                const SizedBox(height: 14),
                _actionsCard(context, ref, order),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── sections ────────────────────────────────────────────
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
            const SizedBox(height: 8),
            Text('Status: ${o.statusLabel}', style: AppTextStyles.body),
            if (o.chemistNote != null && o.chemistNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Chemist note: ${o.chemistNote}',
                  style: AppTextStyles.caption),
            ],
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
      borderColor: AppColors.doctorAccent.withOpacity(.4),
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

  Widget _patientCard(PrescriptionOrderModel o) => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.person_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 9),
              Text('Patient', style: AppTextStyles.h3),
            ]),
            const SizedBox(height: 10),
            _kv('Name', o.patientName),
            _kv('Phone', o.patientPhone),
            _kv('Patient ID', o.patientId),
            _kv('Delivery address', o.deliveryAddress),
            if ((o.deliveryNotes ?? '').isNotEmpty)
              _kv('Delivery notes', o.deliveryNotes!),
            if (o.doctorName.isNotEmpty)
              _kv('Prescribed by', 'Dr. ${o.doctorName}'),
          ],
        ),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
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

  Widget _contactPatientCard(
      BuildContext context, PrescriptionOrderModel o) {
    final hasPhone = o.patientPhone.trim().isNotEmpty;
    if (!hasPhone) return const SizedBox.shrink();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.support_agent_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 9),
            Text('Contact patient', style: AppTextStyles.h3),
          ]),
          const SizedBox(height: 10),
          Text(o.patientName,
              style: AppTextStyles.body
                  .copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(o.patientPhone, style: AppTextStyles.bodyMuted),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  // (Contact logic unchanged)
                },
                icon: const Icon(Icons.phone_rounded, size: 16),
                label: const Text('Call patient'),
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
                  // (Contact logic unchanged)
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
      ),
    );
  }

  Widget _itemsCard(PrescriptionOrderModel o) => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.medication_rounded,
                  size: 18, color: AppColors.patientAccent),
              const SizedBox(width: 9),
              Text('Items', style: AppTextStyles.h3),
            ]),
            const SizedBox(height: 10),
            ...o.items.map((i) {
              final unavailable = i.status == OrderItemStatus.unavailable;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            i.name,
                            style: AppTextStyles.body.copyWith(
                              color: unavailable ? AppColors.textMuted : null,
                              decoration: unavailable ? TextDecoration.lineThrough : null,
                            ),
                          ),
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
                    if (i.lineTotal != null && !unavailable) ...[
                      const SizedBox(width: 10),
                      Text('₹${i.lineTotal!.toStringAsFixed(0)}',
                          style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      );

  Widget _billCard(PrescriptionOrderModel o) => GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.receipt_long_rounded,
                  size: 18, color: AppColors.success),
              const SizedBox(width: 9),
              Text('Bill', style: AppTextStyles.h3),
            ]),
            const SizedBox(height: 10),
            if (o.deliveryFee != null)
              _kv('Delivery fee', '₹${o.deliveryFee!.toStringAsFixed(0)}'),
            if (o.discountPercent != null && o.discountPercent! > 0)
              _kv('Discount', '${o.discountPercent!.toStringAsFixed(0)}%'),
            _kv('Total', '₹${o.totalAmount!.toStringAsFixed(0)}'),
            if (o.paymentMethod != null)
              _kv('Payment method', o.paymentMethod!),
            if (o.receiptNumber != null && o.receiptNumber!.isNotEmpty)
              _kv('Receipt no.', o.receiptNumber!),
            if (o.paymentReference != null &&
                o.paymentReference!.isNotEmpty)
              _kv('UPI reference', o.paymentReference!),
            if (o.paidAt != null)
              _kv('Paid at',
                  DateFormat('dd MMM yyyy • hh:mm a').format(o.paidAt!)),
          ],
        ),
      );

  Widget _actionsCard(
          BuildContext context, WidgetRef ref, PrescriptionOrderModel o) =>
      GlassCard(
        child: Column(
          children: [
            // ── placed → accept / reject ──
            if (o.status == PrescriptionOrderStatus.placed) ...[
              ElevatedButton.icon(
                onPressed: () => _accept(context, ref, o),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Accept order'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _reject(context, ref, o),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Reject order'),
              ),
            ],

            // ── accepted → bill patient / cancel ──
            if (o.status == PrescriptionOrderStatus.accepted) ...[
              ElevatedButton.icon(
                onPressed: () => _billDialog(context, ref, o),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.patientAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('Set price & bill patient'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _cancel(context, ref, o),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel order'),
              ),
            ],

            // ── paidPendingVerification → verify / reject payment ──
            if (o.status == PrescriptionOrderStatus.paidPendingVerification) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.info.withOpacity(.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.hourglass_top_rounded,
                          size: 18, color: AppColors.info),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Payment awaiting verification',
                          style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.info),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    _kvSmall('Receipt no.', o.receiptNumber ?? '—'),
                    _kvSmall('UPI reference', o.paymentReference ?? '—'),
                    if (o.paidAt != null)
                      _kvSmall('Submitted at',
                          DateFormat('dd MMM yyyy • hh:mm a').format(o.paidAt!)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () => _verifyPayment(context, ref, o),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.verified_rounded),
                label: const Text('Verify & mark paid'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _rejectPayment(context, ref, o),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Reject payment'),
              ),
            ],

            // ── paid → preparing ──
            if (o.status == PrescriptionOrderStatus.paid)
              ElevatedButton.icon(
                onPressed: () => _transition(
                    context, ref, o, (s) => s.markPreparing(o.docId),
                    'Marked as preparing'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.info,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Mark as preparing'),
              ),

            // ── preparing → out for delivery ──
            if (o.status == PrescriptionOrderStatus.preparing)
              ElevatedButton.icon(
                onPressed: () => _transition(
                    context, ref, o, (s) => s.markOutForDelivery(o.docId),
                    'Marked out for delivery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.info,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Mark out for delivery'),
              ),

            // ── outForDelivery → delivered ──
            if (o.status == PrescriptionOrderStatus.outForDelivery)
              ElevatedButton.icon(
                onPressed: () => _transition(
                    context, ref, o, (s) => s.markDelivered(o.docId),
                    'Marked delivered'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('Mark delivered'),
              ),
          ],
        ),
      );

  Widget _kvSmall(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text(k, style: AppTextStyles.caption)),
            Expanded(
              child: Text(v,
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  // ── actions ─────────────────────────────────────────────
  Future<void> _accept(
      BuildContext context, WidgetRef ref, PrescriptionOrderModel o) async {
    try {
      await ref.read(chemistServiceProvider).acceptOrder(o.docId);
      ref.invalidate(_singleOrderByIdProvider(orderId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order accepted'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, PrescriptionOrderModel o) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Cancel order', style: AppTextStyles.h3),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'e.g. Out of stock, Store closed',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Keep')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (ok != true) {
      Future.delayed(const Duration(milliseconds: 500), reasonCtrl.dispose);
      return;
    }

    try {
      await ref.read(chemistServiceProvider).rejectOrder(
            o.docId,
            reason: reasonCtrl.text.trim().isEmpty
                ? 'Order cancelled by chemist'
                : reasonCtrl.text.trim(),
          );
      ref.invalidate(_singleOrderByIdProvider(orderId));
      if (context.mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
    Future.delayed(const Duration(milliseconds: 500), reasonCtrl.dispose);
  }

  Future<void> _reject(
      BuildContext context, WidgetRef ref, PrescriptionOrderModel o) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Reject order', style: AppTextStyles.h3),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'e.g. Out of stock',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true) {
      Future.delayed(const Duration(milliseconds: 500), reasonCtrl.dispose);
      return;
    }
    try {
      await ref.read(chemistServiceProvider).rejectOrder(
            o.docId,
            reason: reasonCtrl.text.trim().isEmpty
                ? 'Order rejected'
                : reasonCtrl.text.trim(),
          );
      ref.invalidate(_singleOrderByIdProvider(orderId));
      if (context.mounted) Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
    Future.delayed(const Duration(milliseconds: 500), reasonCtrl.dispose);
  }

  // ── Bill Dialog ─────────────────────────────────────────
  Future<void> _billDialog(
      BuildContext context, WidgetRef ref, PrescriptionOrderModel o) async {
    
    // 1. Fetch the chemist's profile to get their default delivery fee and discount
    double defaultDeliveryFee = 0;
    double defaultDiscount = 0;
    try {
      final container = ProviderScope.containerOf(context);
      final user = await container.read(currentUserProvider.future);
      if (user != null) {
        final chemistSnap = await FirebaseFirestore.instance
            .collection('chemists')
            .doc(o.chemistDocId) // Use the order's chemist ID
            .get();
        if (chemistSnap.exists) {
          final chemistData = chemistSnap.data()!;
          defaultDeliveryFee = (chemistData['deliveryFee'] as num?)?.toDouble() ?? 0;
          defaultDiscount = (chemistData['discountPercent'] as num?)?.toDouble() ?? 0;
        }
      }
    } catch (e) {
      debugPrint('[BillDialog] Failed to load chemist defaults: $e');
    }

    if (!context.mounted) return;

    // 2. Create controllers, prefilled with the defaults
    final controllers = <int, TextEditingController>{};
    final isUnavailable = <int, bool>{};
    for (var i = 0; i < o.items.length; i++) {
      controllers[i] = TextEditingController(
          text: o.items[i].unitPrice?.toStringAsFixed(0) ?? '');
      isUnavailable[i] = false;
    }
    
    // PREFILL THESE
    final deliveryCtrl = TextEditingController(text: defaultDeliveryFee.toStringAsFixed(0));
    final discountCtrl = TextEditingController(text: defaultDiscount.toStringAsFixed(0));
    final noteCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDialogState) {
          // Calculate live totals based on current inputs
          double subtotal = 0;
          for (var i = 0; i < o.items.length; i++) {
            if (isUnavailable[i] == true) continue;
            final unit = double.tryParse(controllers[i]!.text.trim()) ?? 0;
            subtotal += unit * o.items[i].quantity;
          }
          final delivery = double.tryParse(deliveryCtrl.text.trim()) ?? 0;
          final discountPct = double.tryParse(discountCtrl.text.trim()) ?? 0;
          
          final discountAmt = subtotal * (discountPct / 100);
          final total = (subtotal - discountAmt) + delivery;

          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text('Bill order', style: AppTextStyles.h3),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...List.generate(o.items.length, (i) {
                      final item = o.items[i];
                      final unavailable = isUnavailable[i] == true;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${item.name} ×${item.quantity}',
                                    style: AppTextStyles.body.copyWith(
                                      color: unavailable ? AppColors.textMuted : null,
                                      decoration: unavailable ? TextDecoration.lineThrough : null,
                                    )),
                                if (unavailable)
                                  Text('Out of stock',
                                      style: AppTextStyles.caption.copyWith(color: AppColors.error)),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 90,
                            child: TextField(
                              controller: controllers[i],
                              enabled: !unavailable,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                prefixText: '₹ ',
                                hintText: 'Unit',
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              unavailable ? Icons.add_circle_outline : Icons.remove_circle_outline,
                              color: unavailable ? AppColors.success : AppColors.error,
                            ),
                            tooltip: unavailable ? 'Mark Available' : 'Mark Out of Stock',
                            onPressed: () {
                              setDialogState(() => isUnavailable[i] = !unavailable);
                            },
                          ),
                        ]),
                      );
                    }),
                    const Divider(),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: deliveryCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Delivery fee',
                            prefixText: '₹ ',
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: discountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Discount %',
                            suffixText: '%',
                          ),
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Note to patient (optional)'),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total to pay', style: AppTextStyles.body),
                          Text('₹${total.toStringAsFixed(0)}', 
                            style: AppTextStyles.h3.copyWith(color: AppColors.primary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(dctx, true),
                  child: const Text('Save bill')),
            ],
          );
        },
      ),
    );

    if (ok != true) {
      Future.delayed(const Duration(milliseconds: 500), () {
        for (final c in controllers.values) {
          c.dispose();
        }
        deliveryCtrl.dispose();
        discountCtrl.dispose();
        noteCtrl.dispose();
      });
      return;
    }

    final priced = List.generate(o.items.length, (i) {
      final item = o.items[i];
      final unavailable = isUnavailable[i] == true;
      
      if (unavailable) {
        return item.copyWith(
          status: OrderItemStatus.unavailable,
          unitPrice: 0,
          lineTotal: 0,
        );
      }

      final unit = double.tryParse(controllers[i]!.text.trim()) ?? 0;
      return item.copyWith(
        unitPrice: unit,
        lineTotal: unit * item.quantity,
        status: OrderItemStatus.available,
      );
    });
    
    final delivery = double.tryParse(deliveryCtrl.text.trim()) ?? 0;
    final discountPct = double.tryParse(discountCtrl.text.trim()) ?? 0;

    try {
      await ref.read(chemistServiceProvider).billOrder(
            orderId: o.docId,
            pricedItems: priced,
            deliveryFee: delivery,
            discountPercent: discountPct,
            chemistNote: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
          );
      ref.invalidate(_singleOrderByIdProvider(orderId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bill sent to patient'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
    
    Future.delayed(const Duration(milliseconds: 500), () {
      for (final c in controllers.values) {
        c.dispose();
      }
      deliveryCtrl.dispose();
      discountCtrl.dispose();
      noteCtrl.dispose();
    });
  }

  Future<void> _verifyPayment(
      BuildContext context, WidgetRef ref, PrescriptionOrderModel o) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Verify payment', style: AppTextStyles.h3),
        content: Text(
          'Confirm that ₹${o.totalAmount?.toStringAsFixed(0) ?? '—'} '
          'has been received against UTR ${o.paymentReference ?? '—'}.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(chemistServiceProvider).verifyPayment(
            o.docId,
            chemistUid: user.uid,
          );
      ref.invalidate(_singleOrderByIdProvider(orderId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment verified. You can prepare the order.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _rejectPayment(
      BuildContext context, WidgetRef ref, PrescriptionOrderModel o) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Reject payment', style: AppTextStyles.h3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The patient will be asked to submit a new UTR. '
              'Use this only if the transaction cannot be found.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g. UTR not found in bank statement',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true) {
      Future.delayed(const Duration(milliseconds: 500), ctrl.dispose);
      return;
    }
    try {
      await ref.read(chemistServiceProvider).rejectPayment(
            o.docId,
            reason: ctrl.text.trim().isEmpty
                ? 'Payment could not be verified'
                : ctrl.text.trim(),
          );
      ref.invalidate(_singleOrderByIdProvider(orderId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment rejected. Patient will be notified.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
    Future.delayed(const Duration(milliseconds: 500), ctrl.dispose);
  }

  Future<void> _transition(
    BuildContext context,
    WidgetRef ref,
    PrescriptionOrderModel o,
    Future<void> Function(dynamic) action,
    String successLabel,
  ) async {
    try {
      await action(ref.read(chemistServiceProvider));
      ref.invalidate(_singleOrderByIdProvider(orderId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(successLabel),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }
}