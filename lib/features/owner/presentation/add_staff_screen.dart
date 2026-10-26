import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/user_model.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../shared/widgets/clinic_app_bar.dart';

class AddStaffScreen extends ConsumerStatefulWidget {
  const AddStaffScreen({super.key});
  @override
  ConsumerState<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends ConsumerState<AddStaffScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _specialization = TextEditingController();

  UserRole _role = UserRole.receptionist;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _specialization.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      setState(() => _error = 'Name and email are required');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final me = await ref.read(currentUserProvider.future);
      if (me?.clinicId == null) {
        setState(() => _error = 'No clinic linked to your account');
        return;
      }

      final normalizedEmail = _email.text.trim().toLowerCase();

      // Check for a duplicate pending invite
      final existing = await FirebaseFirestore.instance
          .collection('invites')
          .where('email', isEqualTo: normalizedEmail)
          .where('clinicId', isEqualTo: me!.clinicId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        setState(() => _error = 'This email is already invited.');
        return;
      }

      await FirebaseFirestore.instance.collection('invites').add({
        'name': _name.text.trim(),
        'email': normalizedEmail,
        'phone': _phone.text.trim(),
        'role': _role.name,
        if (_role == UserRole.doctor)
          'specialization': _specialization.text.trim(),
        'clinicId': me.clinicId,
        'invitedByUserId': me.uid,
        'invitedByName': me.name,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Added. Ask $normalizedEmail to sign up in the app.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ClinicAppBar(
        title: 'Add Staff',
        showBackButton: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          CustomTextField(
            controller: _name,
            label: 'Full Name',
            hint: 'e.g. Anita Rao',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 20),
          CustomTextField(
            controller: _email,
            label: 'Email',
            hint: 'anita@clinic.in',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 20),
          CustomTextField(
            controller: _phone,
            label: 'Phone',
            hint: '+91 98xxxxxxxx',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 24),
          const Text('ROLE',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              )),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(UserRole.receptionist, 'Receptionist'),
              _chip(UserRole.doctor, 'Doctor'),
              _chip(UserRole.nurse, 'Nurse'),
              _chip(UserRole.lab, 'Lab Tech'),
            ],
          ),
          if (_role == UserRole.doctor) ...[
            const SizedBox(height: 20),
            CustomTextField(
              controller: _specialization,
              label: 'Specialization',
              hint: 'e.g. General Physician',
              icon: Icons.medical_services_outlined,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!,
                style: AppTextStyles.bodyMuted
                    .copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: 24),
          CustomButton(
            label: 'Add',
            loading: _saving,
            onPressed: _add,
            icon: Icons.check_rounded,
          ),
        ],
      ),
    );
  }

  Widget _chip(UserRole role, String label) {
    final selected = _role == role;
    return GestureDetector(
      onTap: () => setState(() => _role = role),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected
                  ? AppColors.primary
                  : AppColors.textSecondary,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            )),
      ),
    );
  }
}