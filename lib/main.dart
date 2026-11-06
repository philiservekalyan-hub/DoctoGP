import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ── Warm-up ──
  // Force the native FirebaseAuth module to initialize before the
  // first Flutter frame. Without this, `authStateChanges()` does its
  // native handshake lazily on first use — which is during the splash's
  // `_boot()`, blocking the main isolate for ~2–3s on cold start.
  //
  // Doing it here moves the cost to the (visually blank) native launch
  // screen phase instead of the (visibly janky) first Flutter frame.
  FirebaseAuth.instance.currentUser;
  FirebaseAuth.instance.authStateChanges().listen(
    (_) {},
    onError: (_) {},
  );

  runApp(const ProviderScope(child: GpClinicApp()));
}