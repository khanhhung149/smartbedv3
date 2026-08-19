import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import 'models/device_out.dart';
import '../../l10n/app_localizations.dart';

// Header section — device name with edit button + copyable device ID.

class DeviceDetailInfoCard extends StatelessWidget {
  const DeviceDetailInfoCard({
    super.key,
    required this.device,
    required this.onEditName,
  });

  final DeviceOut? device;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context) {
    final name = device?.displayName ?? '—';
    final id = device?.deviceId ?? '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.xl3,
                fontWeight: AppFontWeight.bold,
                color: AppColors.onSurface,
                letterSpacing: -0.5,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit,
                color: AppColors.onSurfaceVariant, size: 20),
            onPressed: onEditName,
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text(
            id,
            style: GoogleFonts.inter(
              fontSize: AppTextSize.sm,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: id));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context)!.deviceIdCopied),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: const Icon(Icons.content_copy,
                color: AppColors.onSurfaceVariant, size: 16),
          ),
        ]),
      ],
    );
  }
}

// ── Change WiFi card ──────────────────────────────────────────────────────────

class DeviceDetailChangeWifiCard extends StatelessWidget {
  const DeviceDetailChangeWifiCard({super.key, required this.onChangeWifi});
  final VoidCallback onChangeWifi;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: AppColors.surfaceContainer,
      borderRadius: AppRadius.defaultBr,
      child: InkWell(
        onTap: onChangeWifi,
        borderRadius: AppRadius.defaultBr,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.wifi, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  l10n.changeWifi,
                  style: GoogleFonts.inter(
                    fontWeight: AppFontWeight.medium,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Change WiFi instruction dialog ────────────────────────────────────────────

class DeviceChangeWifiDialog extends StatelessWidget {
  const DeviceChangeWifiDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainer,
      title: Text(
        l10n.changeWifi,
        style: GoogleFonts.inter(
          fontWeight: AppFontWeight.semiBold,
          color: AppColors.onSurface,
        ),
      ),
      content: Text(
        l10n.changeWifiDescription,
        style: GoogleFonts.inter(
          fontSize: AppTextSize.sm,
          color: AppColors.onSurfaceVariant,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            l10n.cancel,
            style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            l10n.changeWifiContinue,
            style: GoogleFonts.inter(
              color: AppColors.primaryContainer,
              fontWeight: AppFontWeight.semiBold,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────────────

// Backend returns last_seen as UTC ISO-8601; display in local tz DD/MM/YYYY HH:mm:ss.
String formatDeviceLastSeen(String? iso) {
  if (iso == null || iso.isEmpty) return 'Unknown';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return iso;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${dt.year} '
      '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}

class DeviceDetailStatusCard extends StatelessWidget {
  const DeviceDetailStatusCard({super.key, required this.device});
  final DeviceOut? device;

  @override
  Widget build(BuildContext context) {
    final online = device?.online ?? false;
    final lastSeen = device?.lastSeen;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: AppRadius.defaultBr,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: online ? AppColors.primary : AppColors.onSurfaceVariant,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              online ? AppLocalizations.of(context)!.online : AppLocalizations.of(context)!.offline,
              style: GoogleFonts.inter(
                fontWeight: AppFontWeight.medium,
                color: online ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            'Last seen: ${formatDeviceLastSeen(lastSeen)}',
            style: GoogleFonts.inter(
              fontSize: AppTextSize.sm,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'SLEEP TECH V2',
            style: GoogleFonts.inter(
              fontSize: AppTextSize.xs,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
              letterSpacing: 1.2,
              fontWeight: AppFontWeight.semiBold,
            ),
          ),
        ],
      ),
    );
  }
}
