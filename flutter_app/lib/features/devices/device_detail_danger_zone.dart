import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/primary_button.dart';

// Danger zone section — remove device button + confirm dialog.

class DeviceDetailDangerZone extends StatelessWidget {
  const DeviceDetailDangerZone({super.key, required this.onRemove});
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Color(0x26FFFFFF), thickness: 1),
        const SizedBox(height: 24),
        Text('Danger Zone',
            style: GoogleFonts.inter(
                fontSize: AppTextSize.lg,
                fontWeight: AppFontWeight.medium,
                color: AppColors.error)),
        const SizedBox(height: 4),
        Text('Careful, this cannot be undone.',
            style: GoogleFonts.inter(
                fontSize: AppTextSize.sm,
                color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_forever,
                color: AppColors.error, size: 20),
            label: Text('Remove device',
                style: GoogleFonts.inter(
                    fontSize: AppTextSize.base,
                    fontWeight: AppFontWeight.semiBold,
                    color: AppColors.error)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: AppColors.error.withValues(alpha: 0.3), width: 1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Rename bottom sheet ───────────────────────────────────────────────────────

class DeviceRenameSheet extends StatelessWidget {
  const DeviceRenameSheet({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A222D),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Rename device',
                style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: AppFontWeight.semiBold,
                    color: AppColors.onSurface)),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              style: GoogleFonts.inter(color: AppColors.onSurface),
              decoration: InputDecoration(
                hintText: 'Device name',
                hintStyle: GoogleFonts.inter(
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.6)),
                filled: true,
                fillColor: AppColors.surfaceContainer,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.4))),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Save',
              onPressed: () =>
                  Navigator.of(context).pop(controller.text),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Remove confirm dialog ─────────────────────────────────────────────────────

class DeviceRemoveConfirmDialog extends StatelessWidget {
  const DeviceRemoveConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainer,
      title: Text('Remove device?',
          style: GoogleFonts.inter(
              fontWeight: AppFontWeight.semiBold, color: AppColors.error)),
      content: Text(
        'This will unpair the device. Sleep data is not deleted. '
        'This cannot be undone.',
        style: GoogleFonts.inter(
            fontSize: AppTextSize.sm,
            color: AppColors.onSurfaceVariant),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel',
              style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Remove',
              style: GoogleFonts.inter(
                  color: AppColors.error,
                  fontWeight: AppFontWeight.semiBold)),
        ),
      ],
    );
  }
}
