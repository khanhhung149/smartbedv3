import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';

// Canonical 5-tab bottom nav bar.
// Source: sleep_pad_home_final_sync/code.html lines ~224-262.
// Attributes:
//   - Container: rounded-t-[32px], bg #0a0e13/70, backdrop-blur-3xl,
//     gradient from #0a0e13 to #101419/90, top border white/5
//   - Active: color #5EE7DF, pill bg #1a383a rounded-[16px] px-5 py-1
//   - Inactive: color #8B96A5 opacity 80
//   - Label: Inter 10sp font-medium uppercase tracking-widest
//   - Icon: Material Symbols Outlined 24sp, fill=1 when active
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const List<_NavItem> _items = [
    _NavItem(label: 'HOME', icon: Symbols.home),
    _NavItem(label: 'HISTORY', icon: Symbols.history),
    _NavItem(label: 'ALERTS', icon: Symbols.notifications),
    _NavItem(label: 'DEVICES', icon: Symbols.devices),
    _NavItem(label: 'SETTINGS', icon: Symbols.settings),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.topLg, // rounded-t-[32px]
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), // backdrop-blur-3xl
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.topLg,
            gradient: const LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                AppColors.navBackground,          // #0a0e13
                Color(0xE6101419),                // #101419/90
              ],
            ),
            border: const Border(
              top: BorderSide(
                color: Color(0x0DFFFFFF), // white/5
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_items.length, (i) {
                  return _NavButton(
                    item: _items[i],
                    isActive: currentIndex == i,
                    onTap: () => onTap(i),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? AppColors.navActive
        : AppColors.navInactive.withValues(alpha: 0.8);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Active icon gets pill background
          isActive
              ? Container(
                  decoration: BoxDecoration(
                    color: AppColors.navActivePill, // #1a383a
                    borderRadius: BorderRadius.circular(16), // rounded-[16px]
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20, // px-5
                    vertical: 4,    // py-1
                  ),
                  margin: const EdgeInsets.only(bottom: 4),
                  child: Icon(
                    item.icon,
                    size: 24,
                    color: color,
                    fill: 1, // FILL=1 when active
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ).copyWith(bottom: 4 + 0), // match active pill height
                  child: Icon(
                    item.icon,
                    size: 24,
                    color: color,
                    fill: 0,
                  ),
                ),
          Text(
            item.label,
            style: GoogleFonts.inter(
              fontSize: 10, // 10sp
              fontWeight: FontWeight.w500, // font-medium
              color: color,
              letterSpacing: 1.5, // tracking-widest ≈ 0.15em on 10sp
            ),
          ),
        ],
      ),
    );
  }
}
