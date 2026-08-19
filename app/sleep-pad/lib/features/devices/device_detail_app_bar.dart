import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/alert_bell_button.dart';

// Translucent blur app bar for device detail screen — back button + bell.

PreferredSizeWidget buildDeviceDetailAppBar(BuildContext context) {
  final topInset = MediaQuery.of(context).padding.top;
  final totalHeight = 64 + topInset;
  return PreferredSize(
    preferredSize: Size.fromHeight(totalHeight),
    child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: totalHeight,
          color: const Color(0xB3101419),
          padding: EdgeInsets.only(top: topInset, left: 4, right: 4),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: AppColors.primaryContainer, size: 24),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/devices');
                    }
                  },
                ),
                Expanded(
                  child: Text(
                    'Device Details',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.xl,
                      fontWeight: AppFontWeight.bold,
                      color: AppColors.onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const AlertBellButton(color: AppColors.primaryContainer),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
