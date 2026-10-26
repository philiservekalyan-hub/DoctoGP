import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Backgrounds
  static const Color background = Color(0xFF070B14);
  static const Color surface = Color(0xFF0F1624);
  static const Color surfaceElevated = Color(0xFF162033);
  static const Color cardBorder = Color(0xFF1F2A44);

  // Brand / Accent
  static const Color primary = Color(0xFF00D4B8);     // Teal
  static const Color primaryDark = Color(0xFF00A88F);
  static const Color secondary = Color(0xFF6C8BFF);   // Indigo
  static const Color accent = Color(0xFFFFB020);      // Amber

  // Status
  static const Color success = Color(0xFF2ED47A);
  static const Color warning = Color(0xFFFFA940);
  static const Color error = Color(0xFFFF5C5C);
  static const Color info = Color(0xFF4FC3F7);

  // Role accents
  static const Color patientAccent = Color(0xFF00D4B8);
  static const Color receptionAccent = Color(0xFF6C8BFF);
  static const Color doctorAccent = Color(0xFFFF6B9D);
  static const Color labAccent = Color(0xFFFFB020);
  static const Color nurseAccent = Color(0xFF8B5CF6); 

  // Text
  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFF9BA5B7);
  static const Color textMuted = Color(0xFF5C6984);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00D4B8), Color(0xFF00A88F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF162033), Color(0xFF0F1624)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bgGradient = LinearGradient(
    colors: [Color(0xFF070B14), Color(0xFF0B1220)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}