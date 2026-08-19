import 'package:flutter/material.dart';
import '../../core/app_colors.dart';

// Full-screen translucent overlay with centered spinner.
// Wrap around screen content during async operations.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
  });

  final bool isLoading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          const ColoredBox(
            color: Color(0x80101419), // background at 50% opacity
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.primaryContainer,
                strokeWidth: 2.5,
              ),
            ),
          ),
      ],
    );
  }
}
