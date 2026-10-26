// lib/features/auth/presentation/splash_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/user_model.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    debugPrint('[Splash] Boot starting...');

    try {
      final user = await ref
          .read(authServiceProvider)
          .currentUserModel()
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              debugPrint('[Splash] Firestore timeout');
              return null;
            },
          );

      debugPrint('[Splash] user = $user');

      if (!mounted) return;

      if (user == null) {
        _navigate('/login');
      } else {
        final path = await _landingFor(user);
        _navigate(path);
      }
    } catch (e, st) {
      debugPrint('[Splash] Error: $e\n$st');
      if (mounted) _navigate('/login');
    }
  }

  void _navigate(String path) {
    if (_navigated || !mounted) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      debugPrint('[Splash] → $path');
      context.go(path);
    });
  }

  /// Landing route for a signed-in user. Receptionists consult
  /// `orgType` (fast path) or the clinics/{clinicId}.type field
  /// (slow path) to distinguish lab reception from clinic
  /// reception.
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
        // Fast path — orgType denormalized onto the user doc.
        if (user.orgType == 'lab') return '/lab-reception';
        if (user.orgType == 'clinic') return '/reception';

        // Slow path — read once from the clinics doc.
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
          debugPrint('[Splash] orgType lookup failed: $e');
        }
        return '/reception';

      default:
        return '/login';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 40,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.medical_services_rounded,
                    color: AppColors.background, size: 44),
              ),
              const SizedBox(height: 24),
              Text('DoctoGP', style: AppTextStyles.h1),
              const SizedBox(height: 8),
              Text('Connected Care Platform',
                  style: AppTextStyles.bodyMuted),
              const SizedBox(height: 40),
              const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}