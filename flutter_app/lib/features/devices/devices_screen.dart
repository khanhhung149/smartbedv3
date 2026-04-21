import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/primary_button.dart';
import '../sharing/models/shared_device_out.dart';
import '../sharing/providers/sharing_providers.dart';
import 'models/device_pair_out.dart';
import 'providers/devices_list_provider.dart';

// Devices list screen.
// Source: devices/code.html
// Sections: MY DEVICES (owner) | SHARED WITH ME | PENDING INVITES
// Top-right "+" → /devices/add
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myDevicesAsync = ref.watch(devicesListProvider);
    final sharedAsync = ref.watch(mySharedDevicesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 3,
        onTap: (i) => _handleNavTap(context, i),
      ),
      body: RefreshIndicator(
        color: AppColors.primaryContainer,
        backgroundColor: AppColors.surfaceContainer,
        onRefresh: () async {
          ref.invalidate(devicesListProvider);
          ref.invalidate(mySharedDevicesProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 88), // clear app bar
              // MY DEVICES section
              const _SectionHeader(label: 'MY DEVICES'),
              const SizedBox(height: 16),
              myDevicesAsync.when(
                loading: () => const _LoadingRow(),
                error: (e, _) => _ErrorRow(message: e.toString()),
                data: (devices) => devices.isEmpty
                    ? _EmptyHint(
                        message: 'No devices paired yet.',
                        onAction: () => context.push('/devices/add'),
                        actionLabel: 'Add device',
                      )
                    : Column(
                        children: devices
                            .map((d) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _MyDeviceTile(
                                    device: d,
                                    onTap: () =>
                                        context.push('/devices/${d.deviceId}'),
                                  ),
                                ))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 32),
              // SHARED WITH ME section
              const _SectionHeader(label: 'SHARED WITH ME'),
              const SizedBox(height: 16),
              sharedAsync.when(
                loading: () => const _LoadingRow(),
                error: (e, _) => _ErrorRow(message: e.toString()),
                data: (shared) => shared.isEmpty
                    ? const _EmptyHint(message: 'No devices shared with you.')
                    : Column(
                        children: shared
                            .map((s) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _SharedDeviceTile(device: s),
                                ))
                            .toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
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
        break; // already here
      case 4:
        context.go('/settings');
    }
  }
}

// ── App bar ───────────────────────────────────────────────────────────────────

PreferredSizeWidget _buildAppBar(BuildContext context) {
  return PreferredSize(
    preferredSize: const Size.fromHeight(64),
    child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 64,
          // bg-slate-950/80
          color: const Color(0xCC020617),
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
                  child: Text(
                    'Devices',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.lg,
                      fontWeight: AppFontWeight.bold,
                      color: AppColors.primaryContainer,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Symbols.add,
                      color: AppColors.primaryContainer, size: 24),
                  onPressed: () => context.push('/devices/add'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: AppTextSize.sm,
        fontWeight: AppFontWeight.semiBold,
        color: AppColors.secondary,
        letterSpacing: 1.5,
      ),
    );
  }
}

// ── My device tile ────────────────────────────────────────────────────────────

class _MyDeviceTile extends StatelessWidget {
  const _MyDeviceTile({required this.device, required this.onTap});

  final DevicePairOut device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.defaultBr,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: AppRadius.defaultBr,
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 24,
                  offset: Offset(0, 4))
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Symbols.bed,
                    color: AppColors.primaryContainer, size: 24, fill: 1),
              ),
              const SizedBox(width: 16),
              // Name + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name,
                        style: GoogleFonts.inter(
                          fontSize: AppTextSize.lg,
                          fontWeight: AppFontWeight.semiBold,
                          color: AppColors.onSurface,
                        )),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(
                        'Paired ${_formatPairedDate(device.pairedAt)}',
                        style: GoogleFonts.inter(
                          fontSize: AppTextSize.xs,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                              color: AppColors.outlineVariant,
                              shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      if (device.online) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          device.lastSeen != null
                              ? 'Active ${_relativeTime(device.lastSeen!)}'
                              : 'Online',
                          style: GoogleFonts.inter(
                            fontSize: AppTextSize.xs,
                            color: AppColors.primary,
                          ),
                        ),
                      ] else
                        Text('Offline',
                            style: GoogleFonts.inter(
                              fontSize: AppTextSize.xs,
                              color: AppColors.onSurfaceVariant,
                            )),
                    ]),
                  ],
                ),
              ),
              const Icon(Symbols.chevron_right,
                  color: AppColors.onSurfaceVariant, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPairedDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = [
        'Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return iso;
    }
  }

  String _relativeTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 2) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
      return '${diff.inHours}h ago';
    } catch (_) {
      return '';
    }
  }
}

// ── Shared device tile ────────────────────────────────────────────────────────

class _SharedDeviceTile extends StatelessWidget {
  const _SharedDeviceTile({required this.device});
  final SharedDeviceOut device;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: AppRadius.defaultBr,
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Symbols.home,
                color: AppColors.secondary, size: 24, fill: 1),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(device.deviceName,
                      style: GoogleFonts.inter(
                        fontSize: AppTextSize.lg,
                        fontWeight: AppFontWeight.semiBold,
                        color: AppColors.onSurface,
                      )),
                  const SizedBox(width: 8),
                  // "view only" chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                    ),
                    child: Text('view only',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: AppFontWeight.bold,
                          color: AppColors.onSurfaceVariant,
                          letterSpacing: 0.8,
                        )),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('Shared by ${device.ownerEmail}',
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.xs,
                      color: AppColors.onSurfaceVariant,
                    )),
              ],
            ),
          ),
          const Icon(Symbols.chevron_right,
              color: AppColors.onSurfaceVariant, size: 24),
        ],
      ),
    );
  }
}

// ── Utility widgets ───────────────────────────────────────────────────────────

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(
              color: AppColors.primaryContainer, strokeWidth: 2),
        ),
      );
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(message,
            style: GoogleFonts.inter(
                color: AppColors.error, fontSize: AppTextSize.sm)),
      );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message, this.onAction, this.actionLabel});
  final String message;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(message,
                style: GoogleFonts.inter(
                    color: AppColors.onSurfaceVariant,
                    fontSize: AppTextSize.sm)),
          ),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(label: actionLabel!, onPressed: onAction),
            ),
          ],
        ],
      );
}
