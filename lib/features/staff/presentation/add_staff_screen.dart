// lib/features/staff/presentation/add_staff_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/user_model.dart';
import '../../../core/widgets/glass_card.dart';

/// Owner-only: invite a new team member to the current clinic or lab.
///
/// Works for both org types. Derives `orgType` from the owner's own
/// `users` doc (`me.orgType` — `'clinic'` or `'lab'`) and offers the
/// appropriate role list for that org type.
///
/// Writes **only** an `invites` doc. It does **not** pre-create a
/// `users/{autoId}` doc — doing so breaks the Firestore-rules
/// invariant that every signed-in user has a doc at `users/{auth.uid}`
/// (all rules call `get(users/$(auth.uid))`). Instead, when the
/// invitee signs up, signup_screen.dart branch 2b consumes the invite
/// and creates `users/{auth.uid}` with the full field set.
///
/// Only the owner can call this. Receptionist and other roles are
/// rejected both by UI (no Add button on their dashboard) and by
/// the guard at the top of `_save()`.
class AddStaffScreen extends ConsumerStatefulWidget {
  const AddStaffScreen({super.key});

  @override
  ConsumerState<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends ConsumerState<AddStaffScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _specializationCtrl = TextEditingController();

  /// Populated in initState (or first build) from the owner's doc.
  /// `null` means "still loading".
  String? _orgType;
  String _role = '';

  bool _saving = false;
  String? _nameError;
  String? _emailError;
  String? _phoneError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final me = await ref.read(currentUserProvider.future);
      if (!mounted || me == null) return;
      final org = me.orgType;
      setState(() {
        _orgType = (org == 'lab' || org == 'clinic') ? org : null;
        _role = _defaultRoleFor(org);
      });
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _specializationCtrl.dispose();
    super.dispose();
  }

  String _defaultRoleFor(String? org) =>
      org == 'lab' ? 'lab' : 'receptionist';

  List<({String value, String label})> _rolesFor(String org) {
    if (org == 'lab') {
      return const [
        (value: 'lab', label: 'Lab Technician'),
        (value: 'receptionist', label: 'Lab Receptionist'),
        (value: 'doctor', label: 'Doctor'),
      ];
    }
    return const [
      (value: 'receptionist', label: 'Receptionist'),
      (value: 'doctor', label: 'Doctor'),
      (value: 'nurse', label: 'Nurse'),
    ];
  }

  Future<void> _save() async {
    setState(() {
      _nameError = null;
      _emailError = null;
      _phoneError = null;
      _formError = null;
    });

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final phone = _phoneCtrl.text.trim();
    final specialization = _specializationCtrl.text.trim();

    var hasError = false;
    if (name.length < 3) {
      setState(() => _nameError = 'Enter at least 3 characters.');
      hasError = true;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _emailError = 'Enter a valid email address.');
      hasError = true;
    }
    if (phone.isNotEmpty && phone.length < 6) {
      setState(() => _phoneError = 'Enter a valid phone or leave blank.');
      hasError = true;
    }
    if (hasError) return;

    setState(() => _saving = true);
    try {
      final me = await ref.read(currentUserProvider.future);

      // ── Owner-only guard ──
      if (me == null) {
        throw StateError('Not signed in.');
      }
      if (me.role != UserRole.owner) {
        throw StateError('Only the owner can add staff.');
      }
      if (me.clinicId == null || me.clinicId!.isEmpty) {
        throw StateError('No clinic or lab linked to your account.');
      }
      final orgType = me.orgType;
      if (orgType != 'lab' && orgType != 'clinic') {
        throw StateError(
            'Your account is missing orgType. Contact admin.');
      }

      // ── Duplicate checks ──
      final existingUser = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (existingUser.docs.isNotEmpty) {
        setState(() =>
            _emailError = 'A user with this email already exists.');
        return;
      }

      final existingInvite = await FirebaseFirestore.instance
          .collection('invites')
          .where('email', isEqualTo: email)
          .where('clinicId', isEqualTo: me.clinicId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      if (existingInvite.docs.isNotEmpty) {
        setState(() => _emailError = 'This email is already invited.');
        return;
      }

      // ── Write only the invite. Signup creates users/{auth.uid}. ──
      final db = FirebaseFirestore.instance;
      final now = FieldValue.serverTimestamp();
      final inviteRef = db.collection('invites').doc();

      await inviteRef.set({
        'name': name,
        'email': email,
        'phone': phone,
        'role': _role,
        if (_role == 'doctor' && specialization.isNotEmpty)
          'specialization': specialization,
        'orgType': orgType,
        'clinicId': me.clinicId,
        'invitedByUserId': me.uid,
        'invitedByName': me.name,
        'status': 'pending',
        'createdAt': now,
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Invite sent. Ask $email to sign up in the app.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _formError = 'Failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_orgType == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final roles = _rolesFor(_orgType!);
    final orgLabel = _orgType == 'lab' ? 'lab' : 'clinic';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Add team member')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GlassCard(
              borderColor: AppColors.info.withOpacity(.35),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppColors.info, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'An invite is created for the new member. When they '
                    'sign up in the app with this email, they are added '
                    'to your $orgLabel team automatically.',
                    style: AppTextStyles.caption,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            _label('Full name'),
            _input(
              controller: _nameCtrl,
              hint: 'e.g. Ravi Kumar',
              errorText: _nameError,
            ),

            _label('Email'),
            _input(
              controller: _emailCtrl,
              hint: 'e.g. ravi@mylab.com',
              errorText: _emailError,
              keyboardType: TextInputType.emailAddress,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
            ),

            _label('Phone (optional)'),
            _input(
              controller: _phoneCtrl,
              hint: 'e.g. 9876543210',
              errorText: _phoneError,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
              ],
            ),

            _label('Role'),
            GlassCard(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _role,
                  isExpanded: true,
                  dropdownColor: AppColors.surfaceElevated,
                  style: AppTextStyles.body,
                  items: [
                    for (final r in roles)
                      DropdownMenuItem(value: r.value, child: Text(r.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _role = v);
                  },
                ),
              ),
            ),

            if (_role == 'doctor') ...[
              _label('Specialization (optional)'),
              _input(
                controller: _specializationCtrl,
                hint: 'e.g. General Physician',
              ),
            ],

            if (_formError != null) ...[
              const SizedBox(height: 16),
              Text(_formError!,
                  style: AppTextStyles.bodyMuted
                      .copyWith(color: AppColors.error)),
            ],

            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send invite'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(s, style: AppTextStyles.caption),
      );

  Widget _input({
    required TextEditingController controller,
    required String hint,
    String? errorText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return GlassCard(
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: AppTextStyles.body,
        decoration: InputDecoration(
          hintText: hint,
          errorText: errorText,
          border: InputBorder.none,
          isCollapsed: true,
        ),
      ),
    );
  }
}