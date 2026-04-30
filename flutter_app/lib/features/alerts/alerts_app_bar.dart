import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/alert_bell_button.dart';

// Translucent blur app bar shared by AlertsScreen (no-device) and AlertsBody.

PreferredSizeWidget buildAlertsAppBar(BuildContext context) {
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
          padding: EdgeInsets.only(top: topInset, left: 8, right: 8),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: Text(
                    'Alerts',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.lg,
                      fontWeight: AppFontWeight.bold,
                      color: const Color(0xFFE6EDF3),
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const AlertBellButton(color: Color(0xFF8B96A5)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
