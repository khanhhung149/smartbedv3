import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../features/home/home_screen.dart';
import '../../features/history/history_screen.dart';
import '../../features/alerts/alerts_screen.dart';
import '../../features/devices/devices_screen.dart';
import '../../features/settings/settings_screen.dart';
import 'app_bottom_nav.dart';

// Canonical shell that owns the shared bottom nav and animates only the
// content area when switching tabs. All 5 tab widgets stay mounted so
// state (charts, WS subscription, scroll offsets, etc.) is preserved.
//
// Slide direction follows tab order — moving to a higher index slides
// the new content in from the right; lower index slides in from the left.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.initialIndex});

  final int initialIndex;

  static const List<Widget> _pages = [
    HomeScreen(),
    HistoryScreen(),
    AlertsScreen(),
    DevicesScreen(),
    SettingsScreen(),
  ];

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  late int _index = widget.initialIndex;
  late int _prevIndex = widget.initialIndex;
  late final AnimationController _ctrl;
  late final CurvedAnimation _curve;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1.0,
    );
    _curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _curve.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap(int i) {
    if (i == _index) return;
    setState(() {
      _prevIndex = _index;
      _index = i;
    });
    _ctrl.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: AnimatedBuilder(
        animation: _curve,
        builder: (context, _) {
          final t = _curve.value;                 // 0 → 1
          final forward = _index > _prevIndex;    // tab order direction
          final showPrev = _prevIndex != _index && t < 1.0;
          // Incoming: begin at ±1, end at 0.  Outgoing: begin at 0, end at ∓1.
          final incomingDx = forward ? (1.0 - t) : -(1.0 - t);
          final outgoingDx = forward ? -t : t;

          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (showPrev)
                  Positioned.fill(
                    child: FractionalTranslation(
                      translation: Offset(outgoingDx, 0),
                      child: MainShell._pages[_prevIndex],
                    ),
                  ),
                Positioned.fill(
                  child: FractionalTranslation(
                    translation: Offset(incomingDx, 0),
                    child: MainShell._pages[_index],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _index,
        onTap: _onTap,
      ),
    );
  }
}
