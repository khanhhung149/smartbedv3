import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';

// Retry bottom sheet shown when WiFi or MQTT connection fails.
// BLE session is still alive — user edits credentials and retries without rescan.

class BlePairingRetrySheet extends StatefulWidget {
  const BlePairingRetrySheet({
    super.key,
    required this.title,
    required this.reason,
    required this.initialSsid,
    required this.onRetry,
    required this.onCancel,
  });

  final String title;
  final String reason;
  final String initialSsid;
  final void Function(String ssid, String password) onRetry;
  final VoidCallback onCancel;

  @override
  State<BlePairingRetrySheet> createState() => _BlePairingRetrySheetState();
}

class _BlePairingRetrySheetState extends State<BlePairingRetrySheet> {
  late final TextEditingController _ssid =
      TextEditingController(text: widget.initialSsid);
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.xl,
                fontWeight: AppFontWeight.semiBold,
                color: AppColors.onSurface,
              )),
          const SizedBox(height: 8),
          Text(widget.reason,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.sm,
                color: AppColors.onSurfaceVariant,
                height: 1.4,
              )),
          const SizedBox(height: 20),
          TextField(
            controller: _ssid,
            style: GoogleFonts.inter(color: AppColors.onSurface),
            decoration: _decoration('WiFi name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            style: GoogleFonts.inter(color: AppColors.onSurface),
            decoration: _decoration('WiFi password').copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                    color: AppColors.onSurfaceVariant,
                    size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onCancel,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                      color: AppColors.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Text('Cancel',
                    style: GoogleFonts.inter(color: AppColors.onSurface)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: () {
                  final s = _ssid.text.trim();
                  final p = _password.text;
                  if (s.isEmpty || p.isEmpty) return;
                  widget.onRetry(s, p);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: AppColors.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Retry',
                    style: GoogleFonts.inter(
                        fontWeight: AppFontWeight.semiBold)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(
          color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        filled: true,
        fillColor: AppColors.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}
