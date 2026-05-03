import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';

// Scaffold shown when no device is paired — empty state with "Add Device" CTA.
class HomeNoDeviceView extends StatelessWidget {
  const HomeNoDeviceView({super.key, required this.onAddDevice});
  final VoidCallback onAddDevice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Symbols.sensors_off,
                size: 48, color: AppColors.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No device paired',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a Sleep Tech device to get started.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onAddDevice,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: AppColors.onPrimaryContainer,
              ),
              child: Text('Add Device', style: GoogleFonts.inter()),
            ),
          ],
        ),
      ),
    );
  }
}
