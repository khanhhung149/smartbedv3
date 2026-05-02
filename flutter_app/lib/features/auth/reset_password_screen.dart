import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/stitch_text_field.dart';
import 'auth_repository_impl.dart' show AuthException;
import 'providers/auth_repository_provider.dart';
import 'widgets/otp_input_field.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});
  final String email;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _otpKey = GlobalKey<OtpInputFieldState>();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final otp = _otpKey.currentState?.value ?? '';
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (otp.length < 6) {
      setState(() => _errorMsg = 'Enter the 6-digit code.');
      return;
    }
    if (pass.length < 8) {
      setState(() => _errorMsg = 'Password must be at least 8 characters.');
      return;
    }
    if (pass != confirm) {
      setState(() => _errorMsg = 'Passwords do not match.');
      return;
    }

    setState(() {
      _errorMsg = null;
      _loading = true;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .resetPassword(widget.email, otp, pass);
      if (!mounted) return;
      context.go('/login');
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = e.message);
      _otpKey.currentState?.clear();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 384),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 32),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Symbols.monitoring,
                          size: 24,
                          color: AppColors.primary,
                          fill: 1,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Sleep Pad',
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: AppFontWeight.bold,
                            color: AppColors.primary,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 64),

                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Text(
                      'Reset password',
                      style: GoogleFonts.inter(
                        fontSize: AppTextSize.xl3,
                        fontWeight: AppFontWeight.medium,
                        color: AppColors.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Text(
                      'Enter the code sent to ${widget.email}',
                      style: GoogleFonts.inter(
                        fontSize: AppTextSize.sm,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  OtpInputField(key: _otpKey),
                  const SizedBox(height: 24),

                  StitchTextField(
                    controller: _passCtrl,
                    placeholder: 'New password',
                    obscureText: true,
                    showToggle: true,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 20),

                  StitchTextField(
                    controller: _confirmCtrl,
                    placeholder: 'Confirm password',
                    obscureText: true,
                    showToggle: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                  ),

                  if (_errorMsg != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMsg!,
                      style: GoogleFonts.inter(
                        fontSize: AppTextSize.sm,
                        color: AppColors.error,
                      ),
                    ),
                  ],

                  const SizedBox(height: 36),

                  PrimaryButton(
                    label: 'Reset password',
                    onPressed: _submit,
                    isLoading: _loading,
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
