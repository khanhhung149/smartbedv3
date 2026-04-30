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

    if (!_isValidEmail(email)) {
      setState(() => _errorMsg = 'Enter a valid email address.');
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

    setState(() => _loading = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.register(email, pass);
      if (!mounted) return;
      // Auto-login after successful registration
      final token = await authRepo.login(email, pass);
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
                  Text(
                    'Create your account',
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.xl2, // text-2xl = 24sp
                      fontWeight: AppFontWeight.semiBold,
                      color: AppColors.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 48), // gap-12

                  // Form fields — gap-5
                  StitchTextField(
                    controller: _emailCtrl,
                    placeholder: 'Email address',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 20),
                  StitchTextField(
                    controller: _passCtrl,
                    placeholder: 'Password',
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

                  const SizedBox(height: 24), // h-2 spacer + extra

                  // Create account button
                  PrimaryButton(
                    label: 'Create account',
                    onPressed: _submit,
                    isLoading: _loading,
                  ),

                  const SizedBox(height: 48), // gap-12

                  // Footer link
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.inter(
                        fontSize: AppTextSize.sm,
                        fontWeight: AppFontWeight.medium,
                        color: AppColors.onSurfaceVariant,
                      ),
                      children: [
                        const TextSpan(text: 'Already have an account? '),
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () => context.go('/login'),
                            child: Text(
                              'Log in',
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
