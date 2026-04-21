import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/stitch_text_field.dart';
import 'auth_repository.dart';

// Login screen matching login/code.html:
// - bg-background, centered max-w-sm column
// - Branding: monitoring icon + "Sleep Pad" in primary color
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

    if (!_isValidEmail(email)) {
      setState(() => _errorMsg = 'Enter a valid email address.');
      return;
    }
    if (pass.length < 8) {
      setState(() => _errorMsg = 'Password must be at least 8 characters.');
      return;
    }

    setState(() => _loading = true);
    try {
      final token = await AuthRepository().login(email, pass);
      if (!mounted) return;
      ref.read(authProvider.notifier).setToken(token);
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24), // p-6
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 384), // max-w-sm
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Branding — centered, mb-16 mt-8
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
                              const SizedBox(width: 8), // gap-2
                              Text(
                                'Sleep Pad',
                                style: GoogleFonts.inter(
                                  fontSize: 28,
                                  fontWeight: AppFontWeight.bold,
                                  color: AppColors.primary,
                                  letterSpacing: -0.5, // tracking-tight
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 64), // mb-16

                        // Greeting — pl-2 mb-10
                        Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Text(
                            'Welcome back',
                            style: GoogleFonts.inter(
                              fontSize: AppTextSize.xl3, // text-3xl = 30sp
                              fontWeight: AppFontWeight.medium,
                              color: AppColors.onSurface,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 40), // mb-10

                        // Form fields — gap-5
                        StitchTextField(
                          controller: _emailCtrl,
                          placeholder: 'Email address',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 20), // gap-5
                        StitchTextField(
                          controller: _passCtrl,
                          placeholder: 'Password',
                          obscureText: true,
                          showToggle: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                        ),

                        // Inline error
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

                        const SizedBox(height: 36), // mt-4 + spacing

                        // Sign in button
                        PrimaryButton(
                          label: 'Sign in',
                          onPressed: _submit,
                          isLoading: _loading,
                        ),

                        const SizedBox(height: 32), // mt-8

                        // Secondary: sign up link
                        Center(
                          child: TextButton(
                            onPressed: () => context.go('/register'),
                            child: Text(
                              'New here? Sign up',
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

            // Footer — mt-auto pb-8 pt-12
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 48, 0, 32),
              child: TextButton(
                onPressed: () {}, // forgot password — future impl
                child: Text(
                  'Forgot password?',
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
