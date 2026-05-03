import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/stitch_text_field.dart';
import 'auth_repository_impl.dart' show AuthException;
import 'providers/auth_repository_provider.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String v) =>
      RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim());

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final l10n = AppLocalizations.of(context)!;
    if (!_isValidEmail(email)) {
      setState(() => _errorMsg = l10n.enterValidEmail);
      return;
    }
    setState(() {
      _errorMsg = null;
      _loading = true;
    });
    try {
      await ref.read(authRepositoryProvider).forgotPassword(email);
      if (!mounted) return;
      context.go('/reset-password', extra: email);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
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

                        Builder(builder: (ctx) {
                          final l10n = AppLocalizations.of(ctx)!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 2),
                                child: Text(
                                  l10n.forgotPasswordTitle,
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
                                  l10n.forgotPasswordSubtitle,
                                  style: GoogleFonts.inter(
                                    fontSize: AppTextSize.sm,
                                    color: AppColors.secondary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 40),

                              StitchTextField(
                                controller: _emailCtrl,
                                placeholder: l10n.emailAddress,
                                keyboardType: TextInputType.emailAddress,
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
                                label: l10n.sendResetCode,
                                onPressed: _submit,
                                isLoading: _loading,
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(0, 48, 0, 32),
              child: TextButton(
                onPressed: () => context.go('/login'),
                child: Builder(builder: (ctx) => Text(
                  AppLocalizations.of(ctx)!.backToSignIn,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.sm,
                    color: AppColors.outline,
                  ),
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
