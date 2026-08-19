import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../sharing/models/shared_device_out.dart';

// SHARED WITH ME section tile — view-only device shared by another user.

class SharedDeviceTile extends StatelessWidget {
  const SharedDeviceTile({super.key, required this.device});
  final SharedDeviceOut device;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: AppRadius.defaultBr,
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.home,
                color: AppColors.secondary, size: 24, fill: 1),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(device.deviceName,
                      style: GoogleFonts.inter(
                        fontSize: AppTextSize.lg,
                        fontWeight: AppFontWeight.semiBold,
                        color: AppColors.onSurface,
                      )),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color:
                              AppColors.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Text('view only',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: AppFontWeight.bold,
                          color: AppColors.onSurfaceVariant,
                          letterSpacing: 0.8,
                        )),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('Shared by ${device.ownerEmail}',
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.xs,
                      color: AppColors.onSurfaceVariant,
                    )),
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              color: AppColors.onSurfaceVariant, size: 24),
        ],
      ),
    );
  }
}
