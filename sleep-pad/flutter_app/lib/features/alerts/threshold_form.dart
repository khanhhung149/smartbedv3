import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import 'models/threshold_out.dart';

// Threshold editing form: dual-thumb range sliders for HR + RR,
// single slider for sleep disturbances.
// Source: alerts_settings/code.html — cards section.
// Calls onChanged whenever any value changes so parent can track dirty state.
class ThresholdForm extends StatefulWidget {
  const ThresholdForm({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final ThresholdOut initial;
  final ValueChanged<ThresholdOut> onChanged;

  @override
  State<ThresholdForm> createState() => _ThresholdFormState();
}

class _ThresholdFormState extends State<ThresholdForm> {
  // Sliders operate on doubles; we round to int when sending int-typed
  // fields back via ThresholdOut (hr_high/hr_low/resp_disorder_count are
  // SMALLINT in Postgres — see backend/postgres/init.sql).
  late double _hrLow;
  late double _hrHigh;
  late double _rrLow;
  late double _rrHigh;
  late double _disturbance;

  @override
  void initState() {
    super.initState();
    _hrLow = widget.initial.hrLow.toDouble().clamp(30, 250);
    _hrHigh = widget.initial.hrHigh.toDouble().clamp(30, 250);
    _rrLow = widget.initial.rrLow.clamp(0, 60);
    _rrHigh = widget.initial.rrHigh.clamp(0, 60);
    _disturbance = widget.initial.respDisorderCount.toDouble().clamp(0, 60);
  }

  void _notify() {
    widget.onChanged(ThresholdOut(
      deviceId: widget.initial.deviceId,
      hrHigh: _hrHigh.round(),
      hrLow: _hrLow.round(),
      rrHigh: _rrHigh,
      rrLow: _rrLow,
      respDisorderCount: _disturbance.round(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MetricCard(
          icon: Symbols.favorite,
          iconColor: AppColors.primaryContainer,
          title: 'Heart Rate',
          lowLabel: 'Low ${_hrLow.round()}',
          highLabel: 'High ${_hrHigh.round()}',
          rangeMin: 30,
          rangeMax: 250,
          rangeMinLabel: '30 bpm',
          rangeMaxLabel: '250 bpm',
          low: _hrLow,
          high: _hrHigh,
          accentColor: AppColors.primaryContainer,
          onLowChanged: (v) {
            if (v < _hrHigh) {
              setState(() => _hrLow = v);
              _notify();
            }
          },
          onHighChanged: (v) {
            if (v > _hrLow) {
              setState(() => _hrHigh = v);
              _notify();
            }
          },
        ),
        const SizedBox(height: 16),
        _MetricCard(
          icon: Symbols.air,
          iconColor: AppColors.rrAccent,
          title: 'Respiration Rate',
          lowLabel: 'Low ${_rrLow.round()}',
          highLabel: 'High ${_rrHigh.round()}',
          rangeMin: 0,
          rangeMax: 60,
          rangeMinLabel: '0 rpm',
          rangeMaxLabel: '60 rpm',
          low: _rrLow,
          high: _rrHigh,
          accentColor: AppColors.rrAccent,
          onLowChanged: (v) {
            if (v < _rrHigh) {
              setState(() => _rrLow = v);
              _notify();
            }
          },
          onHighChanged: (v) {
            if (v > _rrLow) {
              setState(() => _rrHigh = v);
              _notify();
            }
          },
        ),
        const SizedBox(height: 16),
        _DisturbanceCard(
          value: _disturbance,
          onChanged: (v) {
            setState(() => _disturbance = v);
            _notify();
          },
        ),
      ],
    );
  }
}

// ── Dual-thumb range slider card ─────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.lowLabel,
    required this.highLabel,
    required this.rangeMin,
    required this.rangeMax,
    required this.rangeMinLabel,
    required this.rangeMaxLabel,
    required this.low,
    required this.high,
    required this.accentColor,
    required this.onLowChanged,
    required this.onHighChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String lowLabel;
  final String highLabel;
  final double rangeMin;
  final double rangeMax;
  final String rangeMinLabel;
  final String rangeMaxLabel;
  final double low;
  final double high;
  final Color accentColor;
  final ValueChanged<double> onLowChanged;
  final ValueChanged<double> onHighChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppRadius.defaultBr,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + title row
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22, fill: 1),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.lg,
                fontWeight: AppFontWeight.semiBold,
                color: AppColors.onSurface,
                letterSpacing: -0.3,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          // Low / High labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(lowLabel,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.sm,
                    fontWeight: AppFontWeight.medium,
                    color: accentColor,
                  )),
              Text(highLabel,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.sm,
                    fontWeight: AppFontWeight.medium,
                    color: accentColor,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          // Low slider
          _StyledSlider(
            value: low,
            min: rangeMin,
            max: rangeMax,
            accentColor: accentColor,
            onChanged: onLowChanged,
            label: lowLabel,
          ),
          const SizedBox(height: 4),
          // High slider
          _StyledSlider(
            value: high,
            min: rangeMin,
            max: rangeMax,
            accentColor: accentColor,
            onChanged: onHighChanged,
            label: highLabel,
          ),
          const SizedBox(height: 8),
          // Range labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(rangeMinLabel,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.xs,
                    color: AppColors.onSurfaceVariant,
                  )),
              Text(rangeMaxLabel,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.xs,
                    color: AppColors.onSurfaceVariant,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Single slider card — sleep disturbances ───────────────────────────────────

class _DisturbanceCard extends StatelessWidget {
  const _DisturbanceCard({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppRadius.defaultBr,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Symbols.warning,
                  color: AppColors.primaryContainer, size: 22, fill: 1),
            ),
            const SizedBox(width: 12),
            Text(
              'Sleep Disturbances',
              style: GoogleFonts.inter(
                fontSize: AppTextSize.lg,
                fontWeight: AppFontWeight.semiBold,
                color: AppColors.onSurface,
                letterSpacing: -0.3,
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Text(
            'Alert above ${value.round()}/min',
            style: GoogleFonts.inter(
              fontSize: AppTextSize.sm,
              fontWeight: AppFontWeight.medium,
              color: AppColors.primaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          _StyledSlider(
            value: value,
            min: 0,
            max: 60,
            accentColor: AppColors.primaryContainer,
            onChanged: onChanged,
            label: '${value.round()}/min',
          ),
        ],
      ),
    );
  }
}

// ── Shared styled slider ──────────────────────────────────────────────────────

class _StyledSlider extends StatelessWidget {
  const _StyledSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.accentColor,
    required this.onChanged,
    required this.label,
  });

  final double value;
  final double min;
  final double max;
  final Color accentColor;
  final ValueChanged<double> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    // Override slider theme to match Stitch design:
    // track height 4px, thumb 24px circle, active track = accentColor
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: accentColor,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
        thumbColor: accentColor,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
        overlayColor: accentColor.withValues(alpha: 0.12),
        valueIndicatorColor: accentColor,
        valueIndicatorTextStyle: GoogleFonts.inter(
          color: AppColors.onPrimaryFixed,
          fontSize: AppTextSize.xs,
          fontWeight: AppFontWeight.medium,
        ),
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        label: label,
        onChanged: onChanged,
      ),
    );
  }
}
