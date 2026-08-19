/// Single source of truth for layout width thresholds.
///
/// Kept in one file so `MediaQuery` lookups do not spread across widgets —
/// the tablet work in a later phase would otherwise have to hunt them down.
class Breakpoints {
  const Breakpoints._();

  /// Below this the layout is a single column; at or above it, a two-column grid.
  static const double expanded = 600;

  static bool isCompact(double width) => width < expanded;
}
