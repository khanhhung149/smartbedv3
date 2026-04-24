import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/primary_button.dart';
import 'onboarding_sleep_slide.dart';
import 'onboarding_alerts_slide.dart';
import 'onboarding_sharing_slide.dart';

// Onboarding container — 3-slide PageView.
// Bottom area hosts pagination dots + CTA buttons (shared across slides).
// Dot styles per each slide's HTML:
//   Slide 1: active dot = primary-container (w-2.5 h-2.5), inactive = #1F2833
//   Slide 2: active dot = primary-container with glow, inactive = surface-variant
//   Slide 3: active dot = gradient from-primary to-primary-container (w-8), inactive = surface-container-highest
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const List<Widget> _slides = [
    OnboardingSleepSlide(),
    OnboardingAlertsSlide(),
    OnboardingSharingSlide(),
  ];

  void _next() {
    if (_currentPage < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      context.go('/login');
    }
  }

  void _goToLogin() => context.go('/login');
  void _goToRegister() => context.go('/register');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      body: Column(
        children: [
          // Slide content takes all remaining space above the fixed controls,
          // so slide text never overlaps the CTA buttons regardless of device size.
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _currentPage = i),
              children: _slides,
            ),
          ),

          // Bottom controls — fixed height, shared across slides.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PaginationDots(
                    count: _slides.length,
                    currentIndex: _currentPage,
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: 'Get started',
                    onPressed: _next,
                  ),
                  const SizedBox(height: 12),
                  _SecondaryButton(
                    pageIndex: _currentPage,
                    onLogin: _goToLogin,
                    onRegister: _goToRegister,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Pagination dots matching per-slide spec:
//   Slide 0: w-2.5/h-2.5, active=primary-container, inactive=#1F2833
//   Slide 1: w-2/h-2, active=primary-container+glow, inactive=surface-variant
//   Slide 2: active=gradient pill w-8/h-2, inactive=surface-container-highest
class _PaginationDots extends StatelessWidget {
  const _PaginationDots({required this.count, required this.currentIndex});

  final int count;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == currentIndex;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: currentIndex == 2 ? 6 : 6,
          ),
          child: _dot(i, isActive),
        );
      }),
    );
  }

  Widget _dot(int index, bool isActive) {
    // Slide 2 (sharing): active dot is a wide gradient pill
    if (currentIndex == 2 && isActive) {
      return Container(
        width: 32, // w-8
        height: 8,  // h-2
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.full),
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryContainer],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66A4FFF8), // rgba(164,255,248,0.4)
              blurRadius: 12,
            ),
          ],
        ),
      );
    }

    // Slide 1 (alerts): w-2/h-2
    if (currentIndex == 1) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? AppColors.primaryContainer
              : AppColors.surfaceVariant,
          boxShadow: isActive
              ? const [
                  BoxShadow(
                    color: Color(0x995EE7DF), // glow
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
      );
    }

    // Slide 0 (sleep): w-2.5/h-2.5
    return Container(
      width: 10,  // w-2.5
      height: 10, // h-2.5
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive
            ? AppColors.primaryContainer
            : const Color(0xFF1F2833),
      ),
    );
  }
}

// Secondary CTA varies per page
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.pageIndex,
    required this.onLogin,
    required this.onRegister,
  });

  final int pageIndex;
  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    // Slide 0: plain text button "I already have an account"
    if (pageIndex == 0) {
      return TextButton(
        onPressed: onLogin,
        child: Text(
          'I already have an account',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: AppFontWeight.medium,
            color: AppColors.secondary,
          ),
        ),
      );
    }

    // Slides 1 & 2: outlined border button
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onLogin,
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: AppColors.outline.withValues(alpha: 0.2), // border-outline/20
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          backgroundColor: Colors.transparent,
        ),
        child: Text(
          'I already have an account',
          style: GoogleFonts.inter(
            fontSize: AppTextSize.sm,
            fontWeight: AppFontWeight.medium,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
