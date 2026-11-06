// lib/features/auth/presentation/signup_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/user_model.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      return digits.substring(1);
    }
    return digits;
  }

  String _maskPhone(String p) {
    if (p.length <= 4) return '****';
    return '...${p.substring(p.length - 4)}';
  }

  String _maskEmail(String e) {
    if (e.isEmpty) return '—';
    final at = e.indexOf('@');
    if (at <= 0) return e;
    if (at <= 2) return '***@${e.substring(at + 1)}';
    return '${e.substring(0, 2)}***@${e.substring(at + 1)}';
  }

  Future<void> _signUp() async {
    if (_name.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _phone.text.trim().isEmpty) {
      setState(() => _error = 'Please fill all fields');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (_password.text != _confirmPassword.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final normalizedEmail = _email.text.trim().toLowerCase();
    final normalizedPhone = _normalizePhone(_phone.text);
    final db = FirebaseFirestore.instance;

    // -----------------------------------------------------------------
    // Step 1 — Create the Firebase Auth account
    // -----------------------------------------------------------------
    UserCredential? cred;
    try {
      cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: _password.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _loading = false;
        _error = switch (e.code) {
          'email-already-in-use' =>
            'This email is already registered. Try signing in.',
          'weak-password' => 'Password must be at least 6 characters.',
          'invalid-email' => 'Please enter a valid email.',
          _ => e.message ?? 'Sign up failed',
        };
      });
      return;
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Sign up failed: $e';
      });
      return;
    }

    final uid = cred.user!.uid;

    // -----------------------------------------------------------------
    // Step 2 — Role resolution
    //   2a. Owner
    //   2b. Invite
    //   2c. Clinic patient (patients collection)
    //   2d. Lab customer (labCustomers collection) — with confirmation
    //   2e. No match → rollback + reject
    // -----------------------------------------------------------------
    try {
      // -------------------------------------------------------------
      // 2a. Owner
      // -------------------------------------------------------------
      final ownerSnap = await db
          .collection('clinics')
          .where('ownerEmail', isEqualTo: normalizedEmail)
          .limit(1)
          .get();

      if (ownerSnap.docs.isNotEmpty) {
        final clinicDoc = ownerSnap.docs.first;
        final clinicId = clinicDoc.id;
        final clinicData = clinicDoc.data();

        await clinicDoc.reference.update({
          'ownerUserId': uid,
          'ownerClaimedAt': FieldValue.serverTimestamp(),
        });

        await db.collection('users').doc(uid).set({
          'name': _name.text.trim(),
          'email': normalizedEmail,
          'phone': normalizedPhone,
          'role': 'owner',
          'clinicId': clinicId,
          'clinicCode': clinicData['clinicCode'],
          'clinicName': clinicData['name'],
          'orgType': clinicData['orgType'] ?? clinicData['type'],
          'isDoctor': clinicData['ownerIsDoctor'] == true,
          'isLabOwner': clinicData['ownerIsLabOwner'] == true,
          'canPractise': clinicData['ownerIsDoctor'] == true,
          'authUid': uid,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByUid': uid,
        });

        if (!mounted) return;
        context.go('/owner');
        return;
      }

      // -------------------------------------------------------------
      // 2b. Invite
      // -------------------------------------------------------------
      final inviteSnap = await db
          .collection('invites')
          .where('email', isEqualTo: normalizedEmail)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (inviteSnap.docs.isNotEmpty) {
        final inviteDoc = inviteSnap.docs.first;
        final invite = inviteDoc.data();
        final role = invite['role'] as String? ?? 'receptionist';
        final clinicId = invite['clinicId'] as String?;
        final inviteOrgType = invite['orgType'] as String?;

        String? clinicCode;
        String? clinicName;
        String? derivedOrgType;
        if (clinicId != null) {
          final clinicDoc =
              await db.collection('clinics').doc(clinicId).get();
          if (clinicDoc.exists) {
            final cData = clinicDoc.data() ?? {};
            clinicCode = cData['clinicCode'] as String?;
            clinicName = cData['name'] as String?;
            derivedOrgType =
                (cData['orgType'] ?? cData['type']) as String?;
          }
        }

        await db.collection('users').doc(uid).set({
          'name': invite['name'] ?? _name.text.trim(),
          'email': normalizedEmail,
          'phone': normalizedPhone.isNotEmpty
              ? normalizedPhone
              : (invite['phone'] ?? ''),
          'role': role,
          'clinicId': clinicId,
          'clinicCode': clinicCode,
          'clinicName': clinicName,
          'orgType': inviteOrgType ?? derivedOrgType ?? 'clinic',
          'isDoctor': role == 'doctor',
          'isLabOwner': false,
          'canPractise': role == 'doctor',
          'specialization': invite['specialization'],
          'authUid': uid,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByUid': uid,
        });

        await inviteDoc.reference.update({
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
          'acceptedByUserId': uid,
        });

        if (!mounted) return;
        _routeByRole(_roleFromString(role));
        return;
      }

      // -------------------------------------------------------------
      // 2c. Clinic patient
      // -------------------------------------------------------------
      final patientSnap = await db
          .collection('patients')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();

      if (patientSnap.docs.isNotEmpty) {
        final patientDoc = patientSnap.docs.first;
        final patientData = patientDoc.data();
        final clinicId = patientData['clinicId'] as String?;

        String? clinicCode;
        String? clinicName;
        if (clinicId != null) {
          final clinicDoc =
              await db.collection('clinics').doc(clinicId).get();
          if (clinicDoc.exists) {
            final cData = clinicDoc.data() ?? {};
            clinicCode = cData['clinicCode'] as String?;
            clinicName = cData['name'] as String?;
          }
        }

        await db.collection('users').doc(uid).set({
          'name': patientData['fullName'] ?? _name.text.trim(),
          'email': normalizedEmail,
          'phone': patientData['phone'] ?? normalizedPhone,
          'role': 'patient',
          'clinicId': clinicId,
          'clinicCode': clinicCode,
          'clinicName': clinicName,
          'linkedPatientDocId': patientDoc.id,
          'authUid': uid,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByUid': uid,
        });

        await patientDoc.reference.update({
          'userId': uid,
          'appRegisteredAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        context.go('/patient');
        return;
      }

      // -------------------------------------------------------------
      // 2d. Lab customer — either-match lookup, then confirmation.
      // -------------------------------------------------------------
      var labCustomerSnap = await db
          .collection('labCustomers')
          .where('phone', isEqualTo: normalizedPhone)
          .limit(5)
          .get();

      if (labCustomerSnap.docs.isEmpty && normalizedEmail.isNotEmpty) {
        labCustomerSnap = await db
            .collection('labCustomers')
            .where('email', isEqualTo: normalizedEmail)
            .limit(5)
            .get();
      }

      if (labCustomerSnap.docs.isNotEmpty) {
        final matched = labCustomerSnap.docs.first;
        final data = matched.data();
        final matchedName = (data['fullName'] ?? '').toString();
        final matchedPhone = (data['phone'] ?? '').toString();
        final matchedEmail = (data['email'] ?? '').toString();
        final labClinicId = (data['labClinicId'] ?? '').toString();

        String? labName;
        if (labClinicId.isNotEmpty) {
          final labDoc =
              await db.collection('clinics').doc(labClinicId).get();
          if (labDoc.exists) {
            labName = labDoc.data()?['name'] as String?;
          }
        }

        if (!mounted) return;
        final confirmed = await _confirmLabCustomerMatch(
          name: matchedName,
          phone: matchedPhone,
          email: matchedEmail,
          labName: labName ?? 'a lab',
        );

        if (confirmed != true) {
          await _rollbackAuth(cred);
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = "The record we found doesn't match you. Please contact "
                'your lab to correct your phone or email, then try again.';
          });
          return;
        }

        final displayPatientId = data['displayPatientId'] as String?;

        String? labCode;
        if (labClinicId.isNotEmpty) {
          final labDoc =
              await db.collection('clinics').doc(labClinicId).get();
          if (labDoc.exists) {
            labCode = labDoc.data()?['clinicCode'] as String?;
          }
        }

        await db.collection('users').doc(uid).set({
          'name': matchedName.isEmpty ? _name.text.trim() : matchedName,
          'email': normalizedEmail,
          'phone': matchedPhone.isEmpty ? normalizedPhone : matchedPhone,
          'role': 'patient',
          'clinicId': labClinicId.isEmpty ? null : labClinicId,
          'clinicCode': labCode,
          'clinicName': labName,
          'linkedLabCustomerDocId': matched.id,
          'linkedDisplayPatientId': displayPatientId,
          'authUid': uid,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByUid': uid,
        });

        final batch = db.batch();
        for (final doc in labCustomerSnap.docs) {
          batch.update(doc.reference, {
            'linkedUserUid': uid,
            'linkedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();

        if (!mounted) return;
        context.go('/patient');
        return;
      }

      // -------------------------------------------------------------
      // 2e. No match
      // -------------------------------------------------------------
      await _rollbackAuth(cred);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'This email or phone is not registered with any clinic '
            'or lab. Ask your clinic or lab to add you, or use the '
            'contact details they registered for you.';
      });
    } catch (e) {
      debugPrint('[SIGNUP] failed after auth creation: $e');
      await _rollbackAuth(cred);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Sign up failed: $e';
      });
    }
  }

  Future<bool?> _confirmLabCustomerMatch({
    required String name,
    required String phone,
    required String email,
    required String labName,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24, 24, 24,
            MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(.13),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_search_rounded,
                      color: AppColors.info, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('We found a record for you',
                      style: AppTextStyles.h3),
                ),
              ]),
              const SizedBox(height: 12),
              Text(
                'Please confirm this is your record before we link it to your '
                'account. This helps keep your medical data safe.',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _matchRow('Name', name.isEmpty ? '—' : name),
                    const SizedBox(height: 8),
                    _matchRow('Phone', _maskPhone(phone)),
                    const SizedBox(height: 8),
                    _matchRow('Email', _maskEmail(email)),
                    const SizedBox(height: 8),
                    _matchRow('Lab', labName),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'If any of the above is wrong, contact the lab to correct it '
                'before signing up.',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Yes, this is me'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('No, this is not my record'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _matchRow(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: AppTextStyles.bodyMuted),
          ),
          Expanded(
            child: Text(value,
                style: AppTextStyles.body
                    .copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      );

  Future<void> _rollbackAuth(UserCredential? cred) async {
    final user = cred?.user;
    if (user == null) return;

    try {
      await user.delete();
      debugPrint('[SIGNUP] rolled back auth user ${user.uid}');
    } catch (e) {
      debugPrint('[SIGNUP] delete() failed: $e — falling back to signOut');
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e2) {
        debugPrint('[SIGNUP] signOut() also failed: $e2');
      }
    }
  }

  UserRole _roleFromString(String r) {
    switch (r) {
      case 'owner':
        return UserRole.owner;
      case 'receptionist':
        return UserRole.receptionist;
      case 'doctor':
        return UserRole.doctor;
      case 'nurse':
        return UserRole.nurse;
      case 'lab':
        return UserRole.lab;
      case 'admin':
        return UserRole.admin;
      case 'patient':
        return UserRole.patient;
      default:
        return UserRole.unknown;
    }
  }

  void _routeByRole(UserRole role) {
    switch (role) {
      case UserRole.owner:
        context.go('/owner');
        break;
      case UserRole.receptionist:
        context.go('/reception');
        break;
      case UserRole.doctor:
        context.go('/doctor');
        break;
      case UserRole.nurse:
        context.go('/nurse');
        break;
      case UserRole.lab:
        context.go('/lab');
        break;
      case UserRole.patient:
        context.go('/patient');
        break;
      default:
        context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go('/login'),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Create an account', style: AppTextStyles.h1),
                const SizedBox(height: 8),
                Text(
                  'For clinic owners, staff, registered patients, and lab customers',
                  style: AppTextStyles.bodyMuted,
                ),
                const SizedBox(height: 32),

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
                  hint: 'you@clinic.com',
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
                const SizedBox(height: 20),
                CustomTextField(
                  controller: _password,
                  label: 'Password',
                  hint: 'Min 6 characters',
                  icon: Icons.lock_outline_rounded,
                  obscure: true,
                ),
                const SizedBox(height: 20),
                CustomTextField(
                  controller: _confirmPassword,
                  label: 'Confirm Password',
                  hint: 'Re-enter password',
                  icon: Icons.lock_outline_rounded,
                  obscure: true,
                ),

                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.error.withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_error!,
                            style: AppTextStyles.bodyMuted
                                .copyWith(color: AppColors.error)),
                      ),
                    ]),
                  ),
                ],

                const SizedBox(height: 28),
                CustomButton(
                  label: 'Create Account',
                  loading: _loading,
                  onPressed: _signUp,
                  icon: Icons.arrow_forward_rounded,
                ),

                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/login'),
                    child: Text(
                      'Already have an account? Sign in',
                      style: AppTextStyles.bodyMuted
                          .copyWith(color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}