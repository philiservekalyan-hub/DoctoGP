// lib/features/auth/presentation/splash_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
    debugPrint('[Splash] boot start');

    // Minimum display time so the logo is visible even when auth
    // resolves instantly. Set to 2000ms for a noticeable splash.
    final minimumHold = Future.delayed(const Duration(milliseconds: 2000));

    UserModel? user;
    try {
      user = await ref
          .read(currentUserProvider.future)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[Splash] boot error: $e');
      user = null;
    }

    await minimumHold;

    debugPrint('[Splash] user=$user');
    if (!mounted) return;

    if (user == null) {
      _navigate('/login');
      return;
    }
    if (user.active == false) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        debugPrint('[Splash] signOut after deactivation failed: $e');
      }
      if (mounted) _navigate('/login');
      return;
    }

    final path = await _landingFor(user);
    if (!mounted) return;
    _navigate(path);
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

  Future<String> _landingFor(UserModel user) async {
    switch (user.role) {
      case UserRole.patient:
        return '/patient';
      case UserRole.owner:
        if (user.orgType == 'lab') return '/lab';
        if (user.orgType == 'clinic') return '/owner';
        if (user.clinicId == null || user.clinicId!.isEmpty) return '/owner';
        try {
          final org = await FirebaseFirestore.instance
              .collection('clinics')
              .doc(user.clinicId)
              .get();
          if (org.data()?['type'] == 'lab') return '/lab';
        } catch (_) {}
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
          if (org.data()?['type'] == 'lab') return '/lab-reception';
        } catch (_) {}
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
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              Image.asset(
                'assets/images/logo.png',
                height: 320,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.medical_services_rounded,
                  color: AppColors.primary,
                  size: 160,
                ),
              ),
              const SizedBox(height: 32),
              Text('STAT', style: AppTextStyles.h1),
              const SizedBox(height: 8),
              Text('Connected Care Platform',
                  style: AppTextStyles.bodyMuted),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(48, 0, 48, 48),
                child: Column(
                  children: [
                    SizedBox(
                      height: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: const LinearProgressIndicator(
                          minHeight: 4,
                          backgroundColor: AppColors.cardBorder,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Preparing your workspace…',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}