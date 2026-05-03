import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../shared/widgets/alert_bell_button.dart';

// Translucent blur app bar for the home screen.
// Shows app title, device chip (tap to switch device), and alert bell.

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({
    super.key,
    required this.deviceName,
    required this.onDeviceTap,
  });

  final String deviceName;
  final VoidCallback onDeviceTap;

  @override
  // Height hint used by Scaffold; actual height is computed dynamically in build.
  Size get preferredSize => const Size.fromHeight(72 + 44);

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final totalHeight = 72 + topInset;
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
              height: 72,
              child: Row(
                children: [
                  const SizedBox(width: 48),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Sleep Tech',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFE6EDF3),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        GestureDetector(
                          onTap: onDeviceTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A2E2F),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFF234241),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  deviceName,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.primaryContainer,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(
                                  Symbols.arrow_drop_down,
                                  size: 14,
                                  color: AppColors.primaryContainer,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
}
