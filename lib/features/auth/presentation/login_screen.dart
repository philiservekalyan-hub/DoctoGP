// lib/features/auth/presentation/login_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/user_model.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      debugPrint('[Login] Attempting sign-in for "${_email.text}"');

      final user = await ref.read(authServiceProvider).signIn(
            email: _email.text,
            password: _password.text,
          );

      if (!mounted) return;

      if (user == null) {
        setState(() => _error =
            'No account found for this email. Please sign up first.');
        return;
      }

      debugPrint('[Login] Role = ${user.role} (${user.roleLabel}), '
          'orgType = ${user.orgType}');

      final path = await _landingFor(user);
      if (!mounted) return;
      context.go(path);
    } on Exception catch (e) {
      debugPrint('[Login] Exception: $e');
      setState(() => _error = 'Login failed: $e');
    } catch (e) {
      debugPrint('[Login] Generic error: $e');
      setState(() => _error = 'An unexpected error occurred');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Same decision logic as `SplashScreen._landingFor` — must stay
  /// in sync.
  Future<String> _landingFor(UserModel user) async {
    switch (user.role) {
      case UserRole.patient:
        return '/patient';
      case UserRole.owner:
        return '/owner';
      case UserRole.doctor:
        return '/doctor';
      case UserRole.nurse:
        return '/nurse';
      case UserRole.lab:
        return '/lab';
      case UserRole.admin:
        return '/admin';
      case UserRole.receptionist:
        if (user.orgType == 'lab') return '/lab-reception';
        if (user.orgType == 'clinic') return '/reception';

        if (user.clinicId == null || user.clinicId!.isEmpty) {
          return '/reception';
        }
        try {
          final org = await FirebaseFirestore.instance
              .collection('clinics')
              .doc(user.clinicId)
              .get();
          final type = org.data()?['type'];
          if (type == 'lab') return '/lab-reception';
        } catch (e) {
          debugPrint('[Login] orgType lookup failed: $e');
        }
        return '/reception';

      default:
        throw StateError('Unknown role: ${user.role}');
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
                const SizedBox(height: 30),
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.medical_services_rounded,
                      color: AppColors.background, size: 30),
                ),
                const SizedBox(height: 28),
                Text('Welcome back', style: AppTextStyles.h1),
                const SizedBox(height: 8),
                Text('Sign in to your clinic account',
                    style: AppTextStyles.bodyMuted),
                const SizedBox(height: 40),

                CustomTextField(
                  controller: _email,
                  label: 'Email',
                  hint: 'doctor@clinic.com',
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),
                CustomTextField(
                  controller: _password,
                  label: 'Password',
                  hint: '••••••••',
                  icon: Icons.lock_outline_rounded,
                  obscure: true,
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
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

                const SizedBox(height: 32),
                CustomButton(
                  label: 'Sign In',
                  loading: _loading,
                  onPressed: _signIn,
                  icon: Icons.arrow_forward_rounded,
                ),

                const SizedBox(height: 30),

                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account?",
                        style: AppTextStyles.bodyMuted,
                      ),
                      TextButton(
                        onPressed: () => context.go('/signup'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6),
                          minimumSize: const Size(0, 0),
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Create one',
                          style: AppTextStyles.bodyMuted.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'One account. All roles.',
                    style: AppTextStyles.caption,
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