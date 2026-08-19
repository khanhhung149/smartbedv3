import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/providers/app_env_provider.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/services/fcm_service.dart';
import '../../shared/widgets/primary_button.dart';
import 'auth_repository_impl.dart' show AuthException;
import 'providers/auth_repository_provider.dart';
import 'widgets/otp_input_field.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});
  final String email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _otpKey = GlobalKey<OtpInputFieldState>();
  bool _loading = false;
  String? _errorMsg;

  static const int _countdownSeconds = 60;
  int _remaining = _countdownSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _remaining = _countdownSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_remaining <= 1) {
        t.cancel();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining--);
      }
    });
  }

  Future<void> _resend() async {
    try {
      await ref.read(authRepositoryProvider).resendOtp(widget.email);
      _otpKey.currentState?.clear();
      setState(() => _errorMsg = null);
      _startTimer();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = e.message);
    }
  }

  Future<void> _submit() async {
    final otp = _otpKey.currentState?.value ?? '';
    if (otp.length < 6) {
      setState(() => _errorMsg = AppLocalizations.of(context)!.enterSixDigitCode);
      return;
    }
    setState(() {
      _errorMsg = null;
      _loading = true;
    });
    try {
      final token =
          await ref.read(authRepositoryProvider).verifyEmail(widget.email, otp);
      if (!mounted) return;
      ref.read(authProvider.notifier).setToken(token);
      FcmService.syncAfterLogin(ref.read(appEnvProvider));
      context.go('/home');
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
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                onPressed: () => context.go('/register'),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 384),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 32),
                        Row(
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
                              'Sleep Tech',
                              style: GoogleFonts.inter(
                                fontSize: 28,
                                fontWeight: AppFontWeight.bold,
                                color: AppColors.primary,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 64),

                        Builder(builder: (ctx) {
                          final l10n = AppLocalizations.of(ctx)!;
                          return Column(children: [
                            Text(
                              l10n.checkYourEmail,
                              style: GoogleFonts.inter(
                                fontSize: AppTextSize.xl3,
                                fontWeight: AppFontWeight.medium,
                                color: AppColors.onSurface,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.verifyEmailSubtitle(widget.email),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: AppTextSize.sm,
                                color: AppColors.secondary,
                              ),
                            ),
                          ]);
                        }),
                        const SizedBox(height: 40),

                        OtpInputField(
                          key: _otpKey,
                          onCompleted: (_) => _submit(),
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

                        Builder(builder: (ctx) {
                          final l10n = AppLocalizations.of(ctx)!;
                          return Column(children: [
                            PrimaryButton(
                              label: l10n.verify,
                              onPressed: _submit,
                              isLoading: _loading,
                            ),

                            const SizedBox(height: 24),

                            _remaining > 0
                                ? Text(
                                    l10n.resendIn(_remaining),
                                    style: GoogleFonts.inter(
                                      fontSize: AppTextSize.sm,
                                      color: AppColors.outline,
                                    ),
                                  )
                                : TextButton(
                                    onPressed: _resend,
                                    child: Text(
                                      l10n.resendCode,
                                      style: GoogleFonts.inter(
                                        fontSize: AppTextSize.sm,
                                        fontWeight: AppFontWeight.medium,
                                        color: AppColors.secondary,
                                      ),
                                    ),
                                  ),
                          ]);
                        }),
                      ],
                    ),
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
