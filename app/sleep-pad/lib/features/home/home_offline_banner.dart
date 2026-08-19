import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';

// Offline/reconnecting banner shown at top of home when WS stream errors.
class HomeOfflineBanner extends StatelessWidget {
  const HomeOfflineBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.errorContainer.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 12,
          color: AppColors.onErrorContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
