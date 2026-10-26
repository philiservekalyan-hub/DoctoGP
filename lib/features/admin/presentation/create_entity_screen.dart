// lib/features/admin/presentation/create_entity_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/labeled_field.dart';
import '../../../core/widgets/section_header.dart';

class CreateEntityScreen extends ConsumerStatefulWidget {
  const CreateEntityScreen({super.key});

  @override
  ConsumerState<CreateEntityScreen> createState() =>
      _CreateEntityScreenState();
}

class _CreateEntityScreenState
    extends ConsumerState<CreateEntityScreen> {
  String _type = 'clinic'; // "clinic" | "lab"

  final _nameCtrl = TextEditingController();
  final _ownerEmailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ownerEmailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final ownerEmail = _ownerEmailCtrl.text.trim().toLowerCase();
    final phone = _phoneCtrl.text.trim();
    final address = _addressCtrl.text.trim();

    if (name.isEmpty) {
      _snack('Name is required.', AppColors.error);
      return;
    }
    if (ownerEmail.isEmpty) {
      _snack('Owner email is required.', AppColors.error);
      return;
    }

    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      final docRef = db.collection('clinics').doc();

      // Generate a code — DGP-CLN-XXXXX or DGP-LAB-XXXXX
      final rand = (10000 + DateTime.now().millisecondsSinceEpoch % 90000)
          .toString()
          .substring(0, 5);
      final code = _type == 'lab' ? 'DGP-LAB-$rand' : 'DGP-CLN-$rand';

      await docRef.set({
        'type': _type,
        'name': name,
        'clinicCode': code,
        'ownerEmail': ownerEmail,
        'primaryPhone': phone,
        'email': ownerEmail,
        'displayName': name,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByAdminUid':
            FirebaseAuth.instance.currentUser?.uid,
      });

      _snack(
          '${_type == 'lab' ? 'Lab' : 'Clinic'} created: $code',
          AppColors.success);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Failed: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Create entity')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionHeader(title: 'Type'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _typeTile(
                value: 'clinic',
                icon: Icons.local_hospital_outlined,
                label: 'Clinic',
                subtitle: 'GP doctors, patients, appointments',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _typeTile(
                value: 'lab',
                icon: Icons.science_outlined,
                label: 'Lab',
                subtitle: 'Diagnostic tests and reports',
              ),
            ),
          ]),

          const SizedBox(height: 24),
          const SectionHeader(title: 'Details'),
          const SizedBox(height: 8),

          LabeledField(
            label: _type == 'lab' ? 'Lab name' : 'Clinic name',
            required: true,
            child: DarkTextField(
              controller: _nameCtrl,
              hint: _type == 'lab'
                  ? 'e.g. Bhaskar Path Lab'
                  : 'e.g. Sharma Family Clinic',
            ),
          ),
          LabeledField(
            label: 'Owner email',
            required: true,
            child: DarkTextField(
              controller: _ownerEmailCtrl,
              hint: 'owner@example.com',
              keyboardType: TextInputType.emailAddress,
            ),
          ),
          LabeledField(
            label: 'Phone',
            child: DarkTextField(
              controller: _phoneCtrl,
              hint: '+91 ...',
              keyboardType: TextInputType.phone,
            ),
          ),
          LabeledField(
            label: 'Address',
            child: DarkTextField(
              controller: _addressCtrl,
              hint: 'Street, city, pincode',
              maxLines: 2,
            ),
          ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving
                  ? 'Creating...'
                  : 'Create ${_type == 'lab' ? 'lab' : 'clinic'}'),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _typeTile({
    required String value,
    required IconData icon,
    required String label,
    required String subtitle,
  }) {
    final selected = _type == value;
    return GestureDetector(
      onTap: () => setState(() => _type = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(.12)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.cardBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                color: selected
                    ? AppColors.primary
                    : AppColors.textMuted,
                size: 22),
            const SizedBox(height: 8),
            Text(label,
                style: AppTextStyles.body.copyWith(
                  fontWeight: selected
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: selected
                      ? AppColors.primary
                      : AppColors.textPrimary,
                )),
            const SizedBox(height: 2),
            Text(subtitle, style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }
}