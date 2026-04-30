import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import 'models/device_out.dart';

// MY DEVICES section — section header + owned device tile.

// ── Section header ────────────────────────────────────────────────────────────

class DevicesSectionHeader extends StatelessWidget {
  const DevicesSectionHeader({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: AppTextSize.sm,
        fontWeight: AppFontWeight.semiBold,
        color: AppColors.secondary,
        letterSpacing: 1.5,
      ),
    );
  }
}

// ── My device tile ────────────────────────────────────────────────────────────

class MyDeviceTile extends StatelessWidget {
  const MyDeviceTile({super.key, required this.device, required this.onTap});

  final DeviceOut device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.defaultBr,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: AppRadius.defaultBr,
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 24,
                  offset: Offset(0, 4))
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bed,
                    color: AppColors.primaryContainer, size: 24, fill: 1),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.displayName,
                        style: GoogleFonts.inter(
                          fontSize: AppTextSize.lg,
                          fontWeight: AppFontWeight.semiBold,
                          color: AppColors.onSurface,
                        )),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(
                        'Paired ${_formatPairedDate(device.pairedAt)}',
                        style: GoogleFonts.inter(
                          fontSize: AppTextSize.xs,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                              color: AppColors.outlineVariant,
                              shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      if (device.online) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          device.lastSeen != null
                              ? 'Active ${_relativeTime(device.lastSeen!)}'
                              : 'Online',
                          style: GoogleFonts.inter(
                            fontSize: AppTextSize.xs,
                            color: AppColors.primary,
                          ),
                        ),
                      ] else
                        Text('Offline',
                            style: GoogleFonts.inter(
                              fontSize: AppTextSize.xs,
                              color: AppColors.onSurfaceVariant,
                            )),
                    ]),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.onSurfaceVariant, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPairedDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return iso;
    }
  }

  String _relativeTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 2) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
      return '${diff.inHours}h ago';
    } catch (_) {
      return '';
    }
  }
}
