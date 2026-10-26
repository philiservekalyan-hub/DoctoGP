// lib/app/router.dart
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
import '../features/lab/presentation/lab_receptionist_dashboard.dart';
import '../features/lab/presentation/lab_shell.dart';
import '../features/nurse/presentation/nurse_shell.dart';
import '../features/owner/presentation/owner_shell.dart';
import '../features/patient/presentation/patient_shell.dart';
import '../features/receptionist/presentation/clinic_settings_screen.dart';
import '../features/receptionist/presentation/receptionist_shell.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

final currentUserProvider = FutureProvider<UserModel?>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  if (authState == null) return null;

  final doc = await FirebaseFirestore.instance
      .collection('users')
      .where('email', isEqualTo: authState.email?.trim().toLowerCase())
      .limit(1)
      .get();

  if (doc.docs.isEmpty) return null;
  final d = doc.docs.first;
  return UserModel.fromMap(d.id, d.data());
});

Future<String> _landingForUser(UserModel user) async {
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
      } catch (_) {}
      return '/reception';
    default:
      return '/login';
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final location = state.matchedLocation;
      final isPublic = location == '/' ||
          location == '/login' ||
          location == '/signup';

      // ── Fast path ──
      // Check Firebase's synchronous auth state first. This is the
      // source of truth and is cleared the instant signOut() resolves.
      // currentUserProvider is cached and can lag by one frame after
      // logout — consulting it first caused a redirect loop back to
      // the dashboard. This guard fixes that.
      if (FirebaseAuth.instance.currentUser == null) {
        return isPublic ? null : '/login';
      }

      // From here on, Firebase says we're signed in. Load the profile.
      final user = await ref.read(currentUserProvider.future);

      // Firebase is signed in but no user doc exists — treat as logged out.
      if (user == null) {
        return isPublic ? null : '/login';
      }

      // Signed in, sitting on a public page — send to the landing dashboard.
      if (isPublic) {
        return await _landingForUser(user);
      }

      // Receptionist cross-guard: a lab receptionist should not land on
      // /reception and vice versa.
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
      GoRoute(
        path: '/',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (_, __) => const SignupScreen(),
      ),
      GoRoute(
        path: '/patient',
        builder: (_, __) => const PatientShell(),
      ),
      GoRoute(
        path: '/reception',
        builder: (_, __) => const ReceptionistShell(),
      ),
      GoRoute(
        path: '/lab-reception',
        builder: (_, __) => const LabReceptionistDashboard(),
      ),
      GoRoute(
        path: '/doctor',
        builder: (_, __) => const DoctorShell(),
      ),
      GoRoute(
        path: '/nurse',
        builder: (_, __) => const NurseShell(),
      ),
      GoRoute(
        path: '/lab',
        builder: (_, __) => const LabShell(),
      ),
      GoRoute(
        path: '/owner',
        builder: (_, __) => const OwnerShell(),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminShell(),
      ),
      GoRoute(
        path: '/admin/create-clinic',
        builder: (_, __) => const CreateClinicScreen(),
      ),
      GoRoute(
        path: '/clinic-settings',
        builder: (_, __) => const ClinicSettingsScreen(),
      ),
    ],
  );
});