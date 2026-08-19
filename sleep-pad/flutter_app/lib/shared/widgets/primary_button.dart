import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';

// Primary CTA button matching Stitch design:
// bg-gradient-to-br from-primary to-primary-container, rounded-full,
// text-on-primary-fixed font-semibold, py-4, shadow glow effect.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryContainer],
          ),
          borderRadius: BorderRadius.circular(AppRadius.full),
          boxShadow: const [
            BoxShadow(
              color: Color(0x265EE7DF), // rgba(94,231,223,0.15)
              blurRadius: 40,
              spreadRadius: 0,
            ),
          ],
        ),
        child: MaterialButton(
          onPressed: isLoading ? null : onPressed,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          padding: EdgeInsets.zero,
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onPrimaryFixed,
                  ),
                )
              : Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.base,
                    fontWeight: AppFontWeight.semiBold,
                    color: AppColors.onPrimaryFixed,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }
}
