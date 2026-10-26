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

  // -----------------------------------------------------------------
  // Main signup flow
  // -----------------------------------------------------------------
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
    // Step 2 — Role resolution (owner → invite → patient → reject)
    //
    // Any failure from here on rolls back the just-created Auth account
    // so the user can retry with the same email cleanly.
    // -----------------------------------------------------------------
    try {
      // -------------------------------------------------------------
      // 2a. Owner — clinic registered with this email as ownerEmail
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
          'phone': _phone.text.trim(),
          'role': 'owner',
          'clinicId': clinicId,
          'clinicCode': clinicData['clinicCode'],
          'clinicName': clinicData['name'],
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        context.go('/owner');
        return;
      }

      // -------------------------------------------------------------
      // 2b. Invite — a pending invite for this email (staff signup)
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

        // Fetch clinic code + name (for the users doc)
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
          'name': invite['name'] ?? _name.text.trim(),
          'email': normalizedEmail,
          'phone': _phone.text.trim(),
          'role': role,
          'clinicId': clinicId,
          'clinicCode': clinicCode,
          'clinicName': clinicName,
          'specialization': invite['specialization'],
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
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
      // 2c. Patient — a patient doc already exists for this email
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

        // Fetch clinic code + name
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
          'phone': patientData['phone'] ?? _phone.text.trim(),
          'role': 'patient',
          'clinicId': clinicId,
          'clinicCode': clinicCode,
          'clinicName': clinicName,
          'linkedPatientDocId': patientDoc.id,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Link the patient doc to this Auth UID so future reads
        // resolve to the right user. The rule allows this exact
        // field change during signup.
        await patientDoc.reference.update({
          'userId': uid,
          'appRegisteredAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        context.go('/patient');
        return;
      }

      // -------------------------------------------------------------
      // 2d. No match — clean up and reject
      // -------------------------------------------------------------
      await _rollbackAuth(cred);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'This email is not registered with any clinic. '
            'Ask your clinic to add you, or use the email '
            'they registered for you.';
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

  /// Deletes the just-created Auth account. Falls back to signOut if
  /// delete fails (e.g., requires-recent-login). Logs any failure so
  /// orphan accounts don't accumulate silently.
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
                  'For clinic owners, staff, and registered patients',
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