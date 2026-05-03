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

// Register screen matching register/code.html:
// - bg-surface-container-lowest, centered max-w-[360px]
// - Header: vital_signs icon + "Sleep Pad" in primary-container,
//   h2 "Create your account" text-2xl font-semibold
// - Email, Password, Confirm Password fields rounded-[20px]
// - "Create account" gradient button rounded-full h-[52px]
// - Footer: "Already have an account? Log in"
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String v) =>
      RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim());

  Future<void> _submit() async {
    setState(() => _errorMsg = null);

    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    final l10n = AppLocalizations.of(context)!;
    if (!_isValidEmail(email)) {
      setState(() => _errorMsg = l10n.enterValidEmail);
      return;
    }
    if (pass.length < 8) {
      setState(() => _errorMsg = l10n.passwordTooShort);
      return;
    }
    if (pass != confirm) {
      setState(() => _errorMsg = l10n.passwordsDoNotMatch);
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).register(email, pass);
      if (!mounted) return;
      context.go('/verify-email', extra: email);
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
      backgroundColor: AppColors.surfaceContainerLowest,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360), // max-w-[360px]
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Header section — gap-4
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Symbols.vital_signs,
                        size: 24,
                        color: AppColors.primaryContainer,
                        weight: 600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Sleep Pad',
                        style: GoogleFonts.inter(
                          fontSize: 28,
                          fontWeight: AppFontWeight.bold,
                          color: AppColors.primaryContainer,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Builder(builder: (ctx) {
                    final l10n = AppLocalizations.of(ctx)!;
                    return Text(
                      l10n.createYourAccount,
                      style: GoogleFonts.inter(
                        fontSize: AppTextSize.xl2,
                        fontWeight: AppFontWeight.semiBold,
                        color: AppColors.onSurface,
                        letterSpacing: -0.5,
                      ),
                    );
                  }),

                  const SizedBox(height: 48),

                  Builder(builder: (ctx) {
                    final l10n = AppLocalizations.of(ctx)!;
                    return Column(
                      children: [
                        StitchTextField(
                          controller: _emailCtrl,
                          placeholder: l10n.emailAddress,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 20),
                        StitchTextField(
                          controller: _passCtrl,
                          placeholder: l10n.password,
                          obscureText: true,
                          showToggle: true,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 20),
                        StitchTextField(
                          controller: _confirmCtrl,
                          placeholder: l10n.confirmPassword,
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

                        const SizedBox(height: 24),

                        PrimaryButton(
                          label: l10n.createAccount,
                          onPressed: _submit,
                          isLoading: _loading,
                        ),

                        const SizedBox(height: 48),

                        RichText(
                          text: TextSpan(
                            style: GoogleFonts.inter(
                              fontSize: AppTextSize.sm,
                              fontWeight: AppFontWeight.medium,
                              color: AppColors.onSurfaceVariant,
                            ),
                            children: [
                              TextSpan(text: l10n.alreadyHaveAccount),
                              WidgetSpan(
                                child: GestureDetector(
                                  onTap: () => context.go('/login'),
                                  child: Text(
                                    l10n.logIn,
                                    style: GoogleFonts.inter(
                                      fontSize: AppTextSize.sm,
                                      fontWeight: AppFontWeight.medium,
                                      color: AppColors.primaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
    );
  }
}
