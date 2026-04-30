import 'package:flutter/material.dart';
import '../../core/app_colors.dart';

// Sweeping circular progress ring with a bluetooth icon in the center.
// Uses a CustomPainter to draw the animated arc — matches the SVG ring spec
// from device_pairing_progress: r=46, half-circle sweep always visible.

class BlePairingRing extends StatelessWidget {
  const BlePairingRing({super.key, required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: controller,
            builder: (_, __) => CustomPaint(
              size: const Size(200, 200),
              painter: _RingPainter(progress: controller.value),
            ),
          ),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.15),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.bluetooth_searching,
              color: AppColors.primaryContainer,
              size: 40,
            ),
          ),
        ],
      ),
    );
  }
}

// Draws background track + animated sweep arc.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.surfaceContainer
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Sweep arc — half-circle always visible, rotating continuously.
    const startAngle = -1.5707963; // -90 degrees
    const sweepAngle = 3.141592; // 180 degrees
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + progress * 6.283185,
      sweepAngle,
      false,
      Paint()
        ..shader = const LinearGradient(
          colors: [AppColors.primaryContainer, AppColors.primary],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
