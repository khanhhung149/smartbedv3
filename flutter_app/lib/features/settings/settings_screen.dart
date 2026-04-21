import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/services/fcm_service.dart';
import '../../shared/widgets/app_bottom_nav.dart';

// Settings screen.
// Source: settings_synced/code.html
// Sections: Account | Notifications | Appearance | Device Connection | About | Logout
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _pushEnabled = true;
  bool _quietHours = false;
  int _themeIndex = 2; // 0=System, 1=Light, 2=Dark (default Dark per spec)
  String _serverUrl = AppConstants.apiBaseUrl;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _loadPersistedSettings();
  }

  Future<void> _loadPersistedSettings() async {
    // Server URL could be stored in secure storage in production.
    // For POC, we read the compile-time constant.
    setState(() => _serverUrl = AppConstants.apiBaseUrl);
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      await FcmService.clearToken();
      final storage = ref.read(authStorageProvider);
      await storage.deleteToken();
      ref.read(authProvider.notifier).clearToken();
      if (mounted) context.go('/login');
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 4,
        onTap: (i) => _handleNavTap(context, i),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 88, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 1: Account
            const _SectionLabel(label: 'Account'),
            _GroupCard(children: [
              _InfoRow(
                leading: _Avatar(),
                title: 'Account',
                subtitle: 'user@example.com',
              ),
              _DividerRow(),
              _TappableRow(
                label: 'Change password',
                onTap: () {},
              ),
            ]),
            const SizedBox(height: 32),

            // Section 2: Notifications
            const _SectionLabel(label: 'Notifications'),
            _GroupCard(children: [
              _ToggleRow(
                label: 'Enable push notifications',
                value: _pushEnabled,
                onChanged: (v) => setState(() => _pushEnabled = v),
              ),
              _DividerRow(),
              _ToggleRow(
                label: 'Quiet hours',
                subtitle: '10pm — 7am',
                value: _quietHours,
                onChanged: (v) => setState(() => _quietHours = v),
              ),
            ]),
            const SizedBox(height: 32),

            // Section 3: Appearance
            const _SectionLabel(label: 'Appearance'),
            _GroupCard(children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: _ThemeSegment(
                  selected: _themeIndex,
                  onChanged: (i) => setState(() => _themeIndex = i),
                ),
              ),
            ]),
            const SizedBox(height: 32),

            // Section 4: Device Connection
            const _SectionLabel(label: 'Device Connection'),
            _GroupCard(children: [
              _ServerUrlRow(
                url: _serverUrl,
                onEdit: () => _editServerUrl(context),
              ),
            ]),
            const SizedBox(height: 32),

            // Section 5: About
            const _SectionLabel(label: 'About'),
            _GroupCard(children: [
              const _LabelValueRow(label: 'App version', value: 'v1.0.0'),
              _DividerRow(),
              _TappableRow(label: 'Terms of Service', onTap: () {}),
              _DividerRow(),
              _TappableRow(label: 'Privacy Policy', onTap: () {}),
              _DividerRow(),
              _TappableRow(
                label: 'Support Email',
                trailingIcon: Symbols.mail,
                onTap: () {},
              ),
            ]),
            const SizedBox(height: 32),

            // Section 6: Logout
            _LogoutCard(
              isLoading: _loggingOut,
              onLogout: _logout,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _editServerUrl(BuildContext context) async {
    final controller = TextEditingController(text: _serverUrl);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (_) => _ServerUrlDialog(controller: controller),
      );
      if (result == null || result.isEmpty || !mounted) return;
      // Validate URL format
      final uri = Uri.tryParse(result);
      if (uri == null || !uri.hasScheme) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Invalid URL format')),
        );
        return;
      }
      // NOTE: in-memory only in this POC; persistence + Dio rebuild deferred.
      setState(() => _serverUrl = result);
    } finally {
      controller.dispose();
    }
  }

  void _handleNavTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
      case 1:
        context.go('/history');
      case 2:
        context.go('/alerts');
      case 3:
        context.go('/devices');
      case 4:
        break; // already here
    }
  }
}

// ── App bar ───────────────────────────────────────────────────────────────────

PreferredSizeWidget _buildAppBar() {
  return PreferredSize(
    preferredSize: const Size.fromHeight(64),
    child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF101419),
                const Color(0xFF101419).withValues(alpha: 0),
              ],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Symbols.menu,
                      color: AppColors.primaryContainer, size: 24),
                  onPressed: () {},
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Settings',
                        style: GoogleFonts.inter(
                          fontSize: AppTextSize.xl2,
                          fontWeight: AppFontWeight.semiBold,
                          color: AppColors.primaryContainer,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Symbols.notifications,
                      color: AppColors.primaryContainer, size: 24),
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: AppTextSize.sm,
            fontWeight: AppFontWeight.semiBold,
            color: AppColors.onSurfaceVariant,
            letterSpacing: 1,
          ),
        ),
      );
}

// ── Group card wrapper ────────────────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: AppRadius.defaultBr,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

class _DividerRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: Color(0x0DFFFFFF), thickness: 1);
}

// ── Row widgets ───────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.leading, required this.title, required this.subtitle});
  final Widget leading;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          leading,
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.inter(
                    fontWeight: AppFontWeight.medium,
                    color: AppColors.onSurface)),
            Text(subtitle,
                style: GoogleFonts.inter(
                    fontSize: AppTextSize.sm,
                    color: AppColors.onSurfaceVariant)),
          ]),
        ]),
      );
}

class _TappableRow extends StatelessWidget {
  const _TappableRow(
      {required this.label, required this.onTap, this.trailingIcon});
  final String label;
  final VoidCallback onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style: GoogleFonts.inter(
                          fontWeight: AppFontWeight.medium,
                          color: AppColors.onSurface)),
                  Icon(trailingIcon ?? Symbols.chevron_right,
                      color: AppColors.onSurfaceVariant, size: 22),
                ]),
          ),
        ),
      );
}

class _LabelValueRow extends StatelessWidget {
  const _LabelValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: GoogleFonts.inter(
                      fontWeight: AppFontWeight.medium,
                      color: AppColors.onSurface)),
              Text(value,
                  style: GoogleFonts.inter(
                      fontSize: AppTextSize.sm,
                      color: AppColors.onSurfaceVariant)),
            ]),
      );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: GoogleFonts.inter(
                        fontWeight: AppFontWeight.medium,
                        color: AppColors.onSurface)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: GoogleFonts.inter(
                          fontSize: AppTextSize.sm,
                          color: AppColors.onSurfaceVariant)),
              ]),
              _StitchSwitch(value: value, onChanged: onChanged),
            ]),
      );
}

// Toggle matching Stitch HTML design: pill with thumb
class _StitchSwitch extends StatelessWidget {
  const _StitchSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 48,
          height: 24,
          decoration: BoxDecoration(
            color: value
                ? AppColors.primaryContainer.withValues(alpha: 0.2)
                : AppColors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value
                  ? AppColors.primaryContainer.withValues(alpha: 0.3)
                  : AppColors.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            alignment:
                value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: value
                      ? AppColors.primaryContainer
                      : AppColors.onSurfaceVariant,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      );
}

class _ServerUrlRow extends StatelessWidget {
  const _ServerUrlRow({required this.url, required this.onEdit});
  final String url;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Server URL',
                            style: GoogleFonts.inter(
                                fontWeight: AppFontWeight.medium,
                                color: AppColors.onSurface)),
                        const SizedBox(height: 4),
                        Text(
                          Uri.tryParse(url)?.host ?? url,
                          style: GoogleFonts.inter(
                            fontSize: AppTextSize.sm,
                            color: AppColors.onSurfaceVariant.withValues(
                                alpha: 0.8),
                          ),
                        ),
                      ]),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: AppColors.outlineVariant
                              .withValues(alpha: 0.2)),
                    ),
                    child: Text('Advanced',
                        style: GoogleFonts.inter(
                            fontSize: AppTextSize.xs,
                            color: AppColors.onSurfaceVariant)),
                  ),
                ]),
          ),
        ),
      );
}

// ── Theme segment ─────────────────────────────────────────────────────────────

class _ThemeSegment extends StatelessWidget {
  const _ThemeSegment({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  static const _labels = ['System', 'Light', 'Dark'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHighest,
        borderRadius: AppRadius.fullBr,
        border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(_labels.length, (i) {
          final isActive = i == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.surfaceContainer
                      : Colors.transparent,
                  borderRadius: AppRadius.fullBr,
                  border: isActive
                      ? Border.all(
                          color: AppColors.outlineVariant.withValues(alpha: 0.3))
                      : null,
                ),
                child: Text(
                  _labels[i],
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: AppTextSize.sm,
                    fontWeight: AppFontWeight.medium,
                    color: isActive
                        ? AppColors.primaryFixed
                        : AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Logout card ───────────────────────────────────────────────────────────────

class _LogoutCard extends StatelessWidget {
  const _LogoutCard({required this.isLoading, required this.onLogout});
  final bool isLoading;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onLogout,
        borderRadius: AppRadius.defaultBr,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: AppRadius.defaultBr,
            border: Border.all(color: AppColors.error.withValues(alpha: 0.1)),
          ),
          padding: const EdgeInsets.all(20),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.error),
                  )
                : Text(
                    'Log out',
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.base,
                      fontWeight: AppFontWeight.semiBold,
                      color: const Color(0xFFF06262),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Avatar placeholder ────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          shape: BoxShape.circle,
          border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: const Icon(Symbols.person,
            color: AppColors.onSurfaceVariant, size: 24),
      );
}

// ── Server URL edit dialog ────────────────────────────────────────────────────

class _ServerUrlDialog extends StatelessWidget {
  const _ServerUrlDialog({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainer,
      title: Text('Server URL',
          style: GoogleFonts.inter(
              fontWeight: AppFontWeight.semiBold,
              color: AppColors.onSurface)),
      content: TextField(
        controller: controller,
        style: GoogleFonts.inter(color: AppColors.onSurface),
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          hintText: 'http://192.168.1.100:8000',
          hintStyle: GoogleFonts.inter(
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.6)),
          filled: true,
          fillColor: AppColors.surfaceContainerHigh,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text('Save',
              style: GoogleFonts.inter(
                  color: AppColors.primaryContainer,
                  fontWeight: AppFontWeight.semiBold)),
        ),
      ],
    );
  }
}
