import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/providers/app_env_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/widgets/auth_logo.dart';
import '../../shared/services/fcm_service.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/stitch_text_field.dart';
import 'auth_repository_impl.dart' show AuthException;
import 'providers/auth_repository_provider.dart';

// Login screen matching login/code.html:
// - bg-background, centered max-w-sm column
// - Branding: monitoring icon + "Sleep Tech" in primary color
// - h2 "Welcome back" text-3xl font-medium
// - Email + password fields (password has eye toggle)
// - "Sign in" gradient button rounded-full
// - "New here? Sign up" secondary link
// - "Forgot password?" footer link
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String v) =>
      RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim());

  Future<void> _submit() async {
    setState(() => _errorMsg = null);

    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    final l10n = AppLocalizations.of(context)!;
    if (!_isValidEmail(email)) {
      setState(() => _errorMsg = l10n.enterValidEmail);
      return;
    }
    if (pass.length < 8) {
      setState(() => _errorMsg = l10n.passwordTooShort);
      return;
    }

    setState(() => _loading = true);
    try {
      final token = await ref.read(authRepositoryProvider).login(email, pass);
      if (!mounted) return;
      ref.read(authProvider.notifier).setToken(token);
      FcmService.syncAfterLogin(ref.read(appEnvProvider));
      context.go('/home');
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                        const Center(child: AuthLogo()),
                        const SizedBox(height: 64),

                        Center(
                          child: Text(
                            l10n.welcomeBack,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: AppTextSize.xl3,
                              fontWeight: AppFontWeight.medium,
                              color: AppColors.onSurface,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),

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
                          label: l10n.signIn,
                          onPressed: _submit,
                          isLoading: _loading,
                        ),

                        const SizedBox(height: 32),

                        Center(
                          child: TextButton(
                            onPressed: () => context.go('/register'),
                            child: Text(
                              l10n.newHereSignUp,
                              style: GoogleFonts.inter(
                                fontSize: AppTextSize.sm,
                                fontWeight: AppFontWeight.medium,
                                color: AppColors.secondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(0, 48, 0, 32),
              child: TextButton(
                onPressed: () => context.go('/forgot-password'),
                child: Text(
                  l10n.forgotPassword,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.sm,
                    color: AppColors.outline,
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
