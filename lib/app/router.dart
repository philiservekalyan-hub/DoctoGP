// lib/app/router.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models/user_model.dart';
import '../core/services/auth_service.dart';
import '../features/admin/presentation/admin_shell.dart';
import '../features/admin/presentation/create_clinic_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/signup_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/doctor/presentation/doctor_shell.dart';
import '../features/chemist/presentation/chemist_dashboard.dart';
import '../features/lab/presentation/lab_dashboard.dart';
import '../features/lab/presentation/lab_receptionist_dashboard.dart';
import '../features/lab/presentation/lab_shell.dart';
import '../features/nurse/presentation/nurse_shell.dart';
import '../features/owner/presentation/doctor_owner_dashboard.dart';
import '../features/patient/presentation/patient_shell.dart';
import '../features/receptionist/presentation/clinic_settings_screen.dart';
import '../features/receptionist/presentation/receptionist_shell.dart';
import '../features/lab/presentation/lab_owner_dashboard.dart'; 
import '../features/subscription/widgets/subscription_checkout_screen.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final currentUserProvider = FutureProvider<UserModel?>((ref) async {
  final User? authState;
  try {
    authState = await ref
        .watch(authStateProvider.future)
        .timeout(const Duration(seconds: 5));
  } on TimeoutException catch (e) {
    debugPrint('[currentUserProvider] authState timed out: $e');
    return null;
  } catch (e) {
    debugPrint('[currentUserProvider] authState failed: $e');
    return null;
  }

  if (authState == null) return null;

  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: authState.email?.trim().toLowerCase())
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 6));

    if (doc.docs.isEmpty) return null;
    final d = doc.docs.first;
    return UserModel.fromMap(d.id, d.data());
  } on TimeoutException catch (e) {
    debugPrint('[currentUserProvider] users lookup timed out: $e');
    return null;
  } catch (e) {
    debugPrint('[currentUserProvider] users lookup failed: $e');
    return null;
  }
});

Future<String> _landingForUser(UserModel user) async {
  switch (user.role) {
    case UserRole.patient:
      return '/patient';
    case UserRole.owner:
      if (user.orgType == 'lab') return '/lab';
      if (user.orgType == 'clinic') return '/doctor/owner';
      if (user.clinicId == null || user.clinicId!.isEmpty) {
        return '/doctor/owner';
      }
      try {
        final org = await FirebaseFirestore.instance
            .collection('clinics')
            .doc(user.clinicId)
            .get();
        final type = org.data()?['type'];
        if (type == 'lab') return '/lab';
      } catch (_) {}
      return '/doctor/owner';
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
      } catch (_) {}
      return '/reception';
    case UserRole.chemist:
      return '/chemist';
    default:
      return '/login';
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  // ─────────────────────────────────────────────────────────────────
  // ROOT-CAUSE FIX
  //
  // GoRouter only re-runs `redirect` on navigation or when its
  // `refreshListenable` notifies. Without one, calling
  // `FirebaseAuth.instance.signOut()` clears auth but the router
  // stays on the current (lab) screen. LabOwnerDashboard then
  // re-renders with user == null → "No lab linked to your account",
  // and the user has to click Logout again.
  //
  // Bridge authStateChanges() into a ValueNotifier and hand it to
  // GoRouter. Sign-out (and sign-in) now instantly re-run redirect,
  // which sees currentUser == null synchronously and navigates to
  // /login — before the dashboard can render the empty state.
  // ─────────────────────────────────────────────────────────────────
  final authListenable =
      ValueNotifier<User?>(FirebaseAuth.instance.currentUser);
  final sub = FirebaseAuth.instance.authStateChanges().listen(
    (u) => authListenable.value = u,
  );
  ref.onDispose(() {
    sub.cancel();
    authListenable.dispose();
  });

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authListenable,
    redirect: (context, state) async {
      final location = state.matchedLocation;
      final isPublic = location == '/' ||
          location == '/login' ||
          location == '/signup';

      // Synchronous short-circuit: the instant signOut() completes,
      // this returns '/login' without awaiting any Firestore read.
      if (FirebaseAuth.instance.currentUser == null) {
        return isPublic ? null : '/login';
      }

      final user = await ref.read(currentUserProvider.future);

      if (user == null) {
        return isPublic ? null : '/login';
      }

      if (user.active == false) {
        FirebaseAuth.instance.signOut().catchError((_) {});
        return '/login';
      }

      if (isPublic) {
        return await _landingForUser(user);
      }

      if (user.role == UserRole.receptionist) {
        final landing = await _landingForUser(user);
        if (landing == '/lab-reception' &&
            location.startsWith('/reception')) {
          return '/lab-reception';
        }
        if (landing == '/reception' &&
            location.startsWith('/lab-reception')) {
          return '/reception';
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/patient', builder: (_, __) => const PatientShell()),
      GoRoute(path: '/reception', builder: (_, __) => const ReceptionistShell()),
      GoRoute(
          path: '/lab-reception',
          builder: (_, __) => const LabReceptionistDashboard()),
      GoRoute(path: '/doctor', builder: (_, __) => const DoctorShell()),
      GoRoute(
          path: '/doctor/owner',
          builder: (_, __) => const DoctorOwnerDashboard()),
      GoRoute(
  path: '/subscription/checkout',
  builder: (context, state) {
    final q = state.uri.queryParameters;
    return SubscriptionCheckoutScreen(
      entityType: q['entityType'] ?? '',
      entityId: q['entityId'] ?? '',
      planType: q['planType'] ?? '',
    );
  },
),

      GoRoute(path: '/chemist', builder: (_, __) => const ChemistDashboard()),
      GoRoute(path: '/nurse', builder: (_, __) => const NurseShell()),
      GoRoute(path: '/lab', builder: (_, __) => const LabShell()),
      GoRoute(path: '/lab/tech', builder: (_, __) => const LabDashboard()),
      GoRoute(path: '/lab-owner', builder: (_, __) => const LabOwnerDashboard()), 
      GoRoute(path: '/owner', builder: (_, __) => const DoctorOwnerDashboard()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminShell()),
      GoRoute(
          path: '/admin/create-clinic',
          builder: (_, __) => const CreateClinicScreen()),
      GoRoute(
          path: '/clinic-settings',
          builder: (_, __) => const ClinicSettingsScreen()),
    ],
  );
});