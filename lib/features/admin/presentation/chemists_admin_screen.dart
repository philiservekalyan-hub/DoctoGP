// lib/features/admin/presentation/chemists_admin_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/chemist_model.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../shared/widgets/clinic_app_bar.dart';
import 'chemist_form_screen.dart';

// Stream of all chemists, used by both this screen and AdminDashboard.
final allChemistsProvider =
    StreamProvider.autoDispose<List<ChemistModel>>((ref) {
  return FirebaseFirestore.instance
      .collection('chemists')
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs
          .map((d) => ChemistModel.fromMap(d.id, d.data()))
          .toList());
});

// Look up a clinic name by id — for the "Linked to" chips.
final _clinicNameProvider =
    FutureProvider.autoDispose.family<String, String>((ref, clinicId) async {
  if (clinicId.isEmpty) return '';
  final doc = await FirebaseFirestore.instance
      .collection('clinics')
      .doc(clinicId)
      .get();
  return (doc.data()?['name'] ?? clinicId).toString();
});

class ChemistsAdminScreen extends ConsumerWidget {
  const ChemistsAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chemistsAsync = ref.watch(allChemistsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(title: 'Chemists'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ChemistFormScreen(),
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.local_pharmacy_rounded),
        label: const Text('Add chemist'),
      ),
      body: SafeArea(
        child: chemistsAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child: Text('Unable to load chemists: $e',
                  style: const TextStyle(color: AppColors.error))),
          data: (chemists) {
            if (chemists.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_pharmacy_outlined,
                          size: 48, color: AppColors.textMuted),
                      const SizedBox(height: 12),
                      Text('No chemists added yet',
                          style: AppTextStyles.h3),
                      const SizedBox(height: 6),
                      Text(
                        'Add a chemist so patients can order prescriptions.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMuted,
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: chemists.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _ChemistRow(chemist: chemists[i]),
            );
          },
        ),
      ),
    );
  }
}

class _ChemistRow extends ConsumerWidget {
  final ChemistModel chemist;
  const _ChemistRow({required this.chemist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = chemist.isActive ? AppColors.success : AppColors.textMuted;

    return GlassCard(
      borderColor: color.withOpacity(.35),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChemistFormScreen(existing: chemist),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(.13),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_pharmacy_rounded,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(chemist.name,
                          style: AppTextStyles.body
                              .copyWith(fontWeight: FontWeight.w600)),
                      if (chemist.fullAddress.isNotEmpty)
                        Text(chemist.fullAddress,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.caption),
                      if (chemist.phone.isNotEmpty)
                        Text('Phone: ${chemist.phone}',
                            style: AppTextStyles.caption),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.13),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    chemist.isActive ? 'Active' : 'Inactive',
                    style: AppTextStyles.caption.copyWith(color: color),
                  ),
                ),
              ]),

              // Delivery badge row.
              const SizedBox(height: 10),
              Row(children: [
                Icon(
                  chemist.deliveryAvailable
                      ? Icons.delivery_dining_rounded
                      : Icons.store_rounded,
                  size: 15,
                  color: chemist.deliveryAvailable
                      ? AppColors.info
                      : AppColors.textMuted,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    chemist.deliveryAvailable
                        ? 'Delivery · ${chemist.deliveryRadiusKm.toStringAsFixed(0)} km'
                            ' · ₹${chemist.deliveryFee.toStringAsFixed(0)} fee'
                            '${(chemist.serviceablePincodes.isNotEmpty) ? ' · ${chemist.serviceablePincodes.length} pincodes' : ''}'
                        : 'Pickup only · ${chemist.pincode}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(
                      color: chemist.deliveryAvailable
                          ? AppColors.info
                          : AppColors.textMuted,
                    ),
                  ),
                ),
                if (chemist.discountPercent != null &&
                    chemist.discountPercent! > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(.13),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${chemist.discountPercent!.toStringAsFixed(0)}% off',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.success),
                    ),
                  ),
              ]),

              if (chemist.linkedClinicIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: chemist.linkedClinicIds.map((id) {
                    final clinicAsync = ref.watch(_clinicNameProvider(id));
                    final label = clinicAsync.maybeWhen(
                      data: (n) => n.isEmpty ? id : n,
                      orElse: () => '…',
                    );
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppColors.info.withOpacity(.25)),
                      ),
                      child: Text(
                        label,
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.info),
                      ),
                    );
                  }).toList(),
                ),
              ],

              if (chemist.upiId.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.currency_rupee_rounded,
                      size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text('UPI: ${chemist.upiId}',
                      style: AppTextStyles.caption),
                ]),
              ],

              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _openLinkUserDialog(context, ref, chemist),
                    icon: const Icon(Icons.person_add_alt_1_rounded,
                        size: 16),
                    label: const Text('Link login'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.info,
                      side: const BorderSide(color: AppColors.info),
                      minimumSize: const Size.fromHeight(38),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleActive(ref, chemist),
                    icon: Icon(
                      chemist.isActive
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                      size: 16,
                    ),
                    label:
                        Text(chemist.isActive ? 'Deactivate' : 'Activate'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: chemist.isActive
                          ? AppColors.warning
                          : AppColors.success,
                      side: BorderSide(
                          color: chemist.isActive
                              ? AppColors.warning
                              : AppColors.success),
                      minimumSize: const Size.fromHeight(38),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleActive(WidgetRef ref, ChemistModel c) async {
    await FirebaseFirestore.instance
        .collection('chemists')
        .doc(c.docId)
        .update({
      'isActive': !c.isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _openLinkUserDialog(
      BuildContext context, WidgetRef ref, ChemistModel c) async {
    final emailCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Link login to chemist', style: AppTextStyles.h3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the email of an existing user account. That user '
              'will land on the chemist dashboard when they sign in.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'User email',
                hintText: 'chemist@example.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Link'),
          ),
        ],
      ),
    );
    if (ok != true) {
      emailCtrl.dispose();
      return;
    }

    final email = emailCtrl.text.trim().toLowerCase();
    emailCtrl.dispose();
    if (email.isEmpty) return;

    final db = FirebaseFirestore.instance;
    try {
      final snap = await db
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        if (context.mounted) {
          _toast(context,
              'No user with that email. Create the login first.',
              AppColors.error);
        }
        return;
      }

      final userRef = snap.docs.first.reference;
      await userRef.update({
        'role': 'chemist',
        'linkedChemistDocId': c.docId,
        'orgType': 'pharmacy',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        _toast(
            context,
            'Linked ${snap.docs.first.data()['email']} to ${c.name}',
            AppColors.success);
      }
    } catch (e) {
      if (context.mounted) {
        _toast(context, 'Failed: $e', AppColors.error);
      }
    }
  }

  void _toast(BuildContext context, String m, Color c) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
  }
}