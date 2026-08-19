import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/primary_button.dart';

// Shared utility widgets used across devices list sections:
// loading spinner, error text, empty hint with optional CTA.

class DevicesLoadingRow extends StatelessWidget {
  const DevicesLoadingRow({super.key});
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(
              color: AppColors.primaryContainer, strokeWidth: 2),
        ),
      );
}

class DevicesErrorRow extends StatelessWidget {
  const DevicesErrorRow({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(message,
            style: GoogleFonts.inter(
                color: AppColors.error, fontSize: AppTextSize.sm)),
      );
}

class DevicesEmptyHint extends StatelessWidget {
  const DevicesEmptyHint(
      {super.key, required this.message, this.onAction, this.actionLabel});
  final String message;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(message,
                style: GoogleFonts.inter(
                    color: AppColors.onSurfaceVariant,
                    fontSize: AppTextSize.sm)),
          ),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: actionLabel!, onPressed: onAction),
            ),
          ],
        ],
      );
}
