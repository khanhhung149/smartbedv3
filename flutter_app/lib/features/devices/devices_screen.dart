import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../sharing/providers/sharing_providers.dart';
import 'devices_list_widgets.dart';
import 'devices_my_section.dart';
import 'devices_pending_invites_section.dart';
import 'devices_shared_section.dart';
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
    final pendingAsync = ref.watch(pendingInvitesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: RefreshIndicator(
        color: AppColors.primaryContainer,
        backgroundColor: AppColors.surfaceContainer,
        onRefresh: () async {
          ref.invalidate(devicesListProvider);
          ref.invalidate(mySharedDevicesProvider);
          ref.invalidate(pendingInvitesProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 88), // clear app bar
              // PENDING INVITES — only renders when there are pending invites.
              pendingAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (invites) {
                  if (invites.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DevicesSectionHeader(label: AppLocalizations.of(context)!.pendingInvites),
                        const SizedBox(height: 16),
                        ...invites.map((inv) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: PendingInviteTile(invite: inv),
                            )),
                      ],
                    ),
                  );
                },
              ),
              // MY DEVICES
              DevicesSectionHeader(label: AppLocalizations.of(context)!.devices.toUpperCase()),
              const SizedBox(height: 16),
              myDevicesAsync.when(
                loading: () => const DevicesLoadingRow(),
                error: (e, _) => DevicesErrorRow(message: e.toString()),
                data: (devices) {
                  final l10n = AppLocalizations.of(context)!;
                  return devices.isEmpty
                    ? DevicesEmptyHint(
                        message: l10n.noDevicesPaired,
                        onAction: () => context.push('/devices/add'),
                        actionLabel: l10n.addDevice,
                      )
                    : Column(
                        children: devices
                            .map((d) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: MyDeviceTile(
                                    device: d,
                                    onTap: () =>
                                        context.push('/devices/${d.deviceId}'),
                                  ),
                                ))
                            .toList(),
                      );
                },
              ),
              const SizedBox(height: 32),
              // SHARED WITH ME
              const DevicesSectionHeader(label: 'SHARED WITH ME'),
              const SizedBox(height: 16),
              sharedAsync.when(
                loading: () => const DevicesLoadingRow(),
                error: (e, _) => DevicesErrorRow(message: e.toString()),
                data: (shared) => shared.isEmpty
                    ? DevicesEmptyHint(
                        message: AppLocalizations.of(context)!.noDevicesShared)
                    : Column(
                        children: shared
                            .map((s) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: SharedDeviceTile(device: s),
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
}

// ── App bar ───────────────────────────────────────────────────────────────────

PreferredSizeWidget _buildAppBar(BuildContext context) {
  final topInset = MediaQuery.of(context).padding.top;
  final totalHeight = 64 + topInset;
  return PreferredSize(
    preferredSize: Size.fromHeight(totalHeight),
    child: ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: totalHeight,
          color: const Color(0xCC020617),
          padding: EdgeInsets.only(top: topInset, left: 8, right: 8),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.devices,
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
                  icon: const Icon(Icons.add,
                      color: AppColors.primaryContainer, size: 28),
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
