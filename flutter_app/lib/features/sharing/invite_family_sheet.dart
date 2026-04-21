import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/stitch_text_field.dart';
import 'providers/sharing_providers.dart';
import 'sharing_repository.dart';

// Invite-by-email modal bottom sheet.
// Source: invite_family_modal/code.html
// Shows drag handle → title → body explanation → email input → Send + Cancel.
// On success: button morphs to checkmark 1s, sheet dismisses, caller shows toast.
class InviteFamilySheet extends ConsumerStatefulWidget {
  const InviteFamilySheet({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<InviteFamilySheet> createState() => _InviteFamilySheetState();
}

class _InviteFamilySheetState extends ConsumerState<InviteFamilySheet> {
  final _emailController = TextEditingController();
  bool _sending = false;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final repo = ref.read(sharingRepositoryProvider);
      await repo.invite(deviceId: widget.deviceId, email: email);
      // Invalidate device shares so caller list refreshes
      ref.invalidate(deviceSharesProvider(widget.deviceId));
      setState(() {
        _sending = false;
        _success = true;
      });
      // Morph to checkmark 1s, then dismiss
      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted) Navigator.of(context).pop(true); // true = invited
    } on SharingException catch (e) {
      setState(() {
        _sending = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _sending = false;
        _error = 'Something went wrong. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // rounded-t-[24px], surface-container color (#1A222D ≈ surfaceContainerLow)
      decoration: const BoxDecoration(
        color: Color(0xFF1A222D),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 48,
                height: 6,
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            // Title
            Text(
              'Invite family',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: AppFontWeight.semiBold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            // Body explanation
            Text(
              "They'll get an email invite. When they accept, they'll see the same realtime data and alerts you do.",
              style: GoogleFonts.inter(
                fontSize: AppTextSize.base,
                color: AppColors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            // Email input
            StitchTextField(
              controller: _emailController,
              placeholder: 'mom@example.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              errorText: _error,
            ),
            const SizedBox(height: 32),
            // Send button (morphs to checkmark on success)
            _SendButton(
              sending: _sending,
              success: _success,
              onPressed: _send,
            ),
            const SizedBox(height: 12),
            // Cancel button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.base,
                    fontWeight: AppFontWeight.medium,
                    color: const Color(0xFF8B96A5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Send button with success morph ────────────────────────────────────────────

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.sending,
    required this.success,
    required this.onPressed,
  });

  final bool sending;
  final bool success;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryContainer],
          ),
          borderRadius: BorderRadius.circular(AppRadius.full),
          boxShadow: const [
            BoxShadow(
              color: Color(0x265EE7DF),
              blurRadius: 20,
            ),
          ],
        ),
        child: MaterialButton(
          onPressed: (sending || success) ? null : onPressed,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          padding: EdgeInsets.zero,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: success
                ? const Icon(
                    Symbols.check,
                    key: ValueKey('check'),
                    color: AppColors.onPrimaryFixed,
                    size: 28,
                    fill: 1,
                  )
                : sending
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimaryFixed,
                        ),
                      )
                    : Text(
                        'Send invite',
                        key: const ValueKey('label'),
                        style: GoogleFonts.inter(
                          fontSize: AppTextSize.lg,
                          fontWeight: AppFontWeight.semiBold,
                          color: AppColors.onPrimaryFixed,
                        ),
                      ),
          ),
        ),
      ),
    );
  }
}
