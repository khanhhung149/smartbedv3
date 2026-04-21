import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';

// Color-coded status badge mapping ESP32 status codes 0x01–0x08.
// Source: phase-07 plan status badge section + sleep_pad_home_final_sync/code.html
// hero band showing "Sleeping" with primary color icon + text.

class StatusConfig {
  const StatusConfig({
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;
}

// Full status map per ESP32 firmware protocol.
const Map<int, StatusConfig> _statusMap = {
  0x01: StatusConfig(
    label: 'Out of Bed',
    color: Color(0xFFFFB4AB), // error color
    icon: Symbols.exit_to_app,
  ),
  0x02: StatusConfig(
    label: 'Movement',
    color: Color(0xFFFFB470), // orange-ish
    icon: Symbols.directions_walk,
  ),
  0x03: StatusConfig(
    label: 'Sitting Up',
    color: Color(0xFFFFB470),
    icon: Symbols.accessibility,
  ),
  0x04: StatusConfig(
    label: 'Sleeping',
    color: AppColors.primary, // #A4FFF8 teal
    icon: Symbols.bedtime,
  ),
  0x05: StatusConfig(
    label: 'Waking Up',
    color: Color(0xFFF2BF59), // tertiary-fixed-dim amber
    icon: Symbols.wb_sunny,
  ),
  0x06: StatusConfig(
    label: 'Heavy Object',
    color: Color(0xFFFFB4AB),
    icon: Symbols.warning,
  ),
  0x07: StatusConfig(
    label: 'Snoring',
    color: AppColors.secondary, // #D4BBFF lavender
    icon: Symbols.volume_up,
  ),
  0x08: StatusConfig(
    label: 'Weak Breathing',
    color: Color(0xFFFF7043), // deep-orange
    icon: Symbols.air,
  ),
};

// Default when no status code received yet.
const _defaultStatus = StatusConfig(
  label: 'No Signal',
  color: AppColors.onSurfaceVariant,
  icon: Symbols.sensors_off,
);

// Hero status section matching the design's status band:
//   - bg surface-container-low (#181C21), rounded-lg, p-6
//   - gradient overlay from-primary/10 to-transparent
//   - w-16 h-16 rounded-full icon container with glow shadow
//   - 30sp bold tracking-tight label in status color
//   - 14sp subtitle in on-surface-variant
class StatusHero extends StatelessWidget {
  const StatusHero({
    super.key,
    this.statusCode,
    this.subtitle = 'Device active & monitoring',
  });

  final int? statusCode;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cfg = statusCode != null
        ? (_statusMap[statusCode] ?? _defaultStatus)
        : _defaultStatus;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow, // #181C21
        borderRadius: BorderRadius.circular(16), // rounded-lg
      ),
      padding: const EdgeInsets.all(24), // p-6
      child: Stack(
        children: [
          // Gradient overlay: from-primary/10 to-transparent
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon circle with subtle glow
              Container(
                width: 64,  // w-16
                height: 64, // h-16
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cfg.color.withValues(alpha: 0.20),
                  boxShadow: [
                    BoxShadow(
                      color: cfg.color.withValues(alpha: 0.10),
                      blurRadius: 40,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Icon(
                  cfg.icon,
                  size: 32, // text-3xl ≈ 30sp
                  color: cfg.color,
                  fill: 1,
                ),
              ),
              const SizedBox(height: 12), // gap-3
              Text(
                cfg.label,
                style: GoogleFonts.inter(
                  fontSize: 30, // text-3xl
                  fontWeight: FontWeight.w700,
                  color: cfg.color,
                  letterSpacing: -0.5, // tracking-tight
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
