import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import 'ble_pairing_retry_sheet.dart';

// Free functions for BLE pairing error/retry dialogs so the pairing screen
// stays under the 200-line limit.

// Fatal path: BLE session lost, must restart from device scan.
void showBlePairingFatalError(
  BuildContext context,
  String reason, {
  required VoidCallback onBack,
}) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surfaceContainerHigh,
      title: Text(
        'Provisioning failed',
        style: GoogleFonts.inter(
          color: AppColors.onSurface,
          fontWeight: AppFontWeight.semiBold,
        ),
      ),
      content: Text(
        reason,
        style: GoogleFonts.inter(
          color: AppColors.onSurfaceVariant,
          fontSize: AppTextSize.sm,
        ),
      ),
      actions: [
        TextButton(
          onPressed: onBack,
          child: Text(
            'Back to devices',
            style: GoogleFonts.inter(color: AppColors.primary),
          ),
        ),
      ],
    ),
  );
}

// Retry path: BLE still alive, user edits WiFi credentials and retries.
void showBlePairingRetrySheet(
  BuildContext context, {
  required String title,
  required String reason,
  required String lastSsid,
  required void Function(String ssid, String password) onRetry,
  required Future<void> Function() onCancel,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: AppColors.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => BlePairingRetrySheet(
      title: title,
      reason: reason,
      initialSsid: lastSsid,
      onRetry: (ssid, password) {
        Navigator.of(context).pop();
        onRetry(ssid, password);
      },
      onCancel: () async {
        Navigator.of(context).pop();
        await onCancel();
      },
    ),
  );
}
