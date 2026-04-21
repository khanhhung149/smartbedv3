import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';

// Text input matching Stitch register/login design:
// bg-surface-container, rounded-[20px], h-[52px], px-5,
// placeholder text-on-surface-variant/60, focus:ring-1 focus:ring-primary/40
class StitchTextField extends StatefulWidget {
  const StitchTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.showToggle = false,
    this.errorText,
    this.onChanged,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String placeholder;
  final TextInputType keyboardType;
  final bool obscureText;
  // Whether to show the eye-toggle icon (password fields)
  final bool showToggle;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<StitchTextField> createState() => _StitchTextFieldState();
}

class _StitchTextFieldState extends State<StitchTextField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 52,
          child: TextField(
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            obscureText: _obscured,
            onChanged: widget.onChanged,
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            style: GoogleFonts.inter(
              fontSize: AppTextSize.base,
              color: AppColors.onSurface,
            ),
            decoration: InputDecoration(
              hintText: widget.placeholder,
              hintStyle: GoogleFonts.inter(
                fontSize: AppTextSize.base,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              filled: true,
              fillColor: AppColors.surfaceContainer,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20, // px-5
                vertical: 14,   // py-[14px]
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadius.input, // rounded-[20px]
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.input,
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.input,
                borderSide: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.4), // focus:ring-primary/40
                  width: 1,
                ),
              ),
              suffixIcon: widget.showToggle
                  ? IconButton(
                      icon: Icon(
                        _obscured ? Icons.visibility : Icons.visibility_off,
                        size: 20,
                        color: AppColors.outline,
                      ),
                      onPressed: () => setState(() => _obscured = !_obscured),
                    )
                  : null,
            ),
          ),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              widget.errorText!,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.xs,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
