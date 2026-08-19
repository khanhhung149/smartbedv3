import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';

// Snackbar factory functions for device detail actions.

SnackBar deviceDetailSnackBar(String message) => SnackBar(
      content: Text(message,
          style: GoogleFonts.inter(color: AppColors.onPrimaryFixed)),
      backgroundColor: AppColors.primaryContainer,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.defaultRadius)),
    );

SnackBar deviceDetailErrorSnackBar(String message) => SnackBar(
      content: Text(message,
          style: GoogleFonts.inter(color: AppColors.onErrorContainer)),
      backgroundColor: AppColors.errorContainer,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.defaultRadius)),
    );
