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

enum DeviceLinkState { connecting, connected, disconnected }

// Compact status band: single row with icon + status label on the left and
// a pulsing connection dot on the right.
//   - connecting → blue, pulsing
//   - connected  → green, steady
//   - disconnected → red, steady
class StatusHero extends StatelessWidget {
  const StatusHero({
    super.key,
    this.statusCode,
    this.connection = DeviceLinkState.connecting,
  });

  final int? statusCode;
  final DeviceLinkState connection;

  @override
  Widget build(BuildContext context) {
    final cfg = statusCode != null
        ? (_statusMap[statusCode] ?? _defaultStatus)
        : _defaultStatus;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cfg.color.withValues(alpha: 0.20),
            ),
            child: Icon(cfg.icon, size: 24, color: cfg.color, fill: 1),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              cfg.label,
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: cfg.color,
                letterSpacing: -0.3,
              ),
            ),
          ),
          // Connection dot (pulsing when connecting)
          _ConnectionDot(connection: connection),
        ],
      ),
    );
  }
}

class _ConnectionDot extends StatefulWidget {
  const _ConnectionDot({required this.connection});
  final DeviceLinkState connection;

  @override
  State<_ConnectionDot> createState() => _ConnectionDotState();
}

class _ConnectionDotState extends State<_ConnectionDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _dotColor => switch (widget.connection) {
        DeviceLinkState.connected => const Color(0xFF34D399),    // green
        DeviceLinkState.connecting => const Color(0xFF60A5FA),   // blue
        DeviceLinkState.disconnected => const Color(0xFFF06262), // red
      };

  @override
  Widget build(BuildContext context) {
    final animates = widget.connection == DeviceLinkState.connecting;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final opacity = animates ? 0.4 + _ctrl.value * 0.6 : 1.0;
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _dotColor.withValues(alpha: opacity),
            boxShadow: [
              BoxShadow(
                color: _dotColor.withValues(alpha: animates ? opacity * 0.5 : 0.35),
                blurRadius: 8,
              ),
            ],
          ),
        );
      },
    );
  }
}
