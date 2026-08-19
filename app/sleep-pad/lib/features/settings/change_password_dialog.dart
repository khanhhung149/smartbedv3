import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../features/auth/auth_repository_impl.dart';
import '../../features/auth/providers/auth_repository_provider.dart';
import '../../l10n/app_localizations.dart';

class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final current = _currentCtrl.text.trim();
    final newPwd = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    if (newPwd.length < 8) {
      setState(() => _error = l10n.passwordTooShort);
      return;
    }
    if (newPwd != confirm) {
      setState(() => _error = l10n.passwordsDoNotMatch);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.changePassword(current, newPwd);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainer,
      title: Text(
        l10n.changePassword,
        style: GoogleFonts.inter(
          fontWeight: AppFontWeight.semiBold,
          color: AppColors.onSurface,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PasswordField(
            controller: _currentCtrl,
            label: l10n.currentPassword,
          ),
          const SizedBox(height: 12),
          _PasswordField(
            controller: _newCtrl,
            label: l10n.newPassword,
          ),
          const SizedBox(height: 12),
          _PasswordField(
            controller: _confirmCtrl,
            label: l10n.confirmPassword,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.sm,
                color: AppColors.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(
            l10n.cancel,
            style: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
          ),
        ),
        TextButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryContainer,
                  ),
                )
              : Text(
                  l10n.save,
                  style: GoogleFonts.inter(
                    color: AppColors.primaryContainer,
                    fontWeight: AppFontWeight.semiBold,
                  ),
                ),
        ),
      ],
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: _obscure,
        style: GoogleFonts.inter(color: AppColors.onSurface),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle:
              GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontSize: AppTextSize.sm),
          filled: true,
          fillColor: AppColors.surfaceContainerHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          suffixIcon: IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_off : Icons.visibility,
              color: AppColors.onSurfaceVariant,
              size: 20,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      );
}
