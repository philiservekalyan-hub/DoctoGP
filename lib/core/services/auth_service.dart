import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // -----------------------------------------------------------------
  // Sign in — email based lookup
  // -----------------------------------------------------------------
  Future<UserModel?> signIn({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();

    await _auth.signInWithEmailAndPassword(
      email: normalized,
      password: password,
    );

// DEBUG: print claims after fresh sign-in
final token = await _auth.currentUser?.getIdTokenResult(true);
debugPrint('Claims: ${token?.claims}');

    final user = await _loadUserByEmail(normalized);

    // If no matching Firestore doc, sign back out so the app doesn't
    // hold a half-valid session.
    if (user == null) {
      await _auth.signOut();
      return null;
    }

    return user;
  }

  // -----------------------------------------------------------------
  // Sign up
  // -----------------------------------------------------------------
  Future<UserModel?> signUp({
    required String name,
    required String email,
    required String phone,
    required String password,
    required UserRole role,
    String? clinicId,
  }) async {
    final normalized = email.trim().toLowerCase();

    final cred = await _auth.createUserWithEmailAndPassword(
      email: normalized,
      password: password,
    );
    final uid = cred.user!.uid;

    await _db.collection('users').doc(uid).set({
      'name': name,
      'email': normalized,
      'phone': phone,
      'role': role.name,
      'clinicId': clinicId,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return _loadUserByEmail(normalized);
  }

  // -----------------------------------------------------------------
  // Single lookup path — by email
  // -----------------------------------------------------------------
  Future<UserModel?> _loadUserByEmail(String email) async {
    final normalized = email.trim().toLowerCase();

    final snap = await _db
        .collection('users')
        .where('email', isEqualTo: normalized)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return UserModel.fromMap(doc.id, doc.data());
  }

  // -----------------------------------------------------------------
  // Session restore — resolved via FirebaseAuth email
  // -----------------------------------------------------------------
  Future<UserModel?> currentUserModel() async {
    final authUser = _auth.currentUser;
    if (authUser == null) return null;
    if (authUser.email == null) return null;
    return _loadUserByEmail(authUser.email!);
  }

  Future<void> signOut() => _auth.signOut();
}