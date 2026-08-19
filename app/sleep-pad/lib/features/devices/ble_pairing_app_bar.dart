import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';

// App bar for BLE provisioning pairing screen — back button + step indicator.

class BlePairingAppBar extends StatelessWidget {
  const BlePairingAppBar({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: AppColors.surfaceContainerLowest.withValues(alpha: 0.7),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: const Opacity(
              opacity: 0.6,
              child: Icon(Icons.arrow_back,
                  color: AppColors.secondary, size: 24),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Setup Sleep Tech',
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.sm,
                    fontWeight: AppFontWeight.semiBold,
                    color: const Color(0xFFE6EDF3),
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  'STEP 2 OF 3',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppColors.secondary.withValues(alpha: 0.6),
                    fontWeight: AppFontWeight.medium,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }
}
