import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/primary_button.dart';

// Segmented tab control and save button used by AlertsBody.

// ── Segmented control ─────────────────────────────────────────────────────────

class AlertsSegmentedControl extends StatelessWidget {
  const AlertsSegmentedControl({
    super.key,
    required this.selected,
    required this.labels,
    required this.onChanged,
  });

  final int selected;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: AppRadius.fullBr,
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isActive = i == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.surfaceContainerHigh
                      : Colors.transparent,
                  borderRadius: AppRadius.fullBr,
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.sm,
                    fontWeight: AppFontWeight.medium,
                    color: isActive
                        ? AppColors.primaryContainer
                        : const Color(0xFF8B96A5),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Save button ───────────────────────────────────────────────────────────────

class AlertsSaveButton extends StatelessWidget {
  const AlertsSaveButton({
    super.key,
    required this.isDirty,
    required this.onPressed,
  });

  final bool isDirty;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (isDirty) {
      return PrimaryButton(label: 'Save changes', onPressed: onPressed);
    }
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Opacity(
          opacity: 0.7,
          child: Center(
            child: Text(
              'Save changes',
              style: GoogleFonts.inter(
                fontSize: AppTextSize.base,
                fontWeight: AppFontWeight.semiBold,
                color: const Color(0xFF8B96A5),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
