import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static final TextStyle h1 = GoogleFonts.inter(
    fontSize: 28, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary, letterSpacing: -0.5,
  );
  static final TextStyle h2 = GoogleFonts.inter(
    fontSize: 22, fontWeight: FontWeight.w700,
    color: AppColors.textPrimary, letterSpacing: -0.3,
  );
  static final TextStyle h3 = GoogleFonts.inter(
    fontSize: 18, fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static final TextStyle body = GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );
  static final TextStyle bodyMuted = GoogleFonts.inter(
    fontSize: 14, fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );
  static final TextStyle caption = GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w500,
    color: AppColors.textMuted, letterSpacing: 0.2,
  );
  static final TextStyle button = GoogleFonts.inter(
    fontSize: 15, fontWeight: FontWeight.w600,
    color: AppColors.background, letterSpacing: 0.2,
  );
  static final TextStyle label = GoogleFonts.inter(
    fontSize: 12, fontWeight: FontWeight.w600,
    color: AppColors.textSecondary, letterSpacing: 0.6,
  );
}