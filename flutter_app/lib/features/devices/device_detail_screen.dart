import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../../core/app_theme.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../../shared/widgets/primary_button.dart';
import '../alerts/providers/thresholds_provider.dart' show thresholdsProvider;
import '../sharing/invite_family_sheet.dart';
import '../sharing/models/share_out.dart';
import '../sharing/providers/sharing_providers.dart';
import '../sharing/sharing_repository.dart';
import 'device_repository.dart';
import 'models/device_pair_out.dart';
import 'providers/devices_list_provider.dart';

// Device detail screen: rename, sharing management, danger zone.
// Source: device_detail/code.html
// Route: /devices/:deviceId
class DeviceDetailScreen extends ConsumerStatefulWidget {
  const DeviceDetailScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<DeviceDetailScreen> createState() =>
      _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  bool _revoking = false;
  bool _removing = false;

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(devicesListProvider);
    final sharesAsync = ref.watch(deviceSharesProvider(widget.deviceId));
    final thresholdsAsync = ref.watch(thresholdsProvider(widget.deviceId));

    final device = devicesAsync.valueOrNull?.firstWhere(
      (d) => d.deviceId == widget.deviceId,
      orElse: () => _placeholder(widget.deviceId),
    );

    return LoadingOverlay(
      isLoading: _revoking || _removing,
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBodyBehindAppBar: true,
        appBar: _buildAppBar(context),
        bottomNavigationBar: AppBottomNav(
          currentIndex: 3,
          onTap: (i) => _handleNavTap(context, i),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 88, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + device ID
              _HeaderSection(
                device: device,
                onEditName: () => _showRenameSheet(context, device),
              ),
              const SizedBox(height: 32),
              // Status card
              _StatusCard(device: device),
              const SizedBox(height: 32),
              // Alert thresholds preview
              _ThresholdsSection(
                thresholdsAsync: thresholdsAsync,
                onEdit: () => context.push('/alerts'),
              ),
              const SizedBox(height: 32),
              // Sharing section (owner only)
              _SharingSection(
                deviceId: widget.deviceId,
                sharesAsync: sharesAsync,
                onInvite: () => _showInviteSheet(context),
                onRevoke: (shareId) => _revokeShare(context, shareId),
              ),
              const SizedBox(height: 48),
              // Danger zone
              _DangerZone(
                onRemove: () => _confirmRemove(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DevicePairOut _placeholder(String deviceId) => DevicePairOut(
        deviceId: deviceId,
        name: deviceId,
        pairedAt: DateTime.now().toIso8601String(),
        online: false,
        mqttUsername: '',
        mqttPassword: '',
        mqttHost: '',
        mqttScheme: 'tcp',
      );

  Future<void> _showRenameSheet(BuildContext context, DevicePairOut? device) async {
    if (device == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: device.name);
    try {
      final result = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _RenameSheet(controller: controller),
      );
      if (result == null || result.isEmpty || !mounted) return;
      // Re-pair with the new name — backend /devices/pair is an upsert that
      // preserves owner_id and refreshes the row's name atomically. See
      // backend/app/devices/service.py::pair_device.
      try {
        await DeviceRepository().pairDevice(
          deviceId: widget.deviceId,
          name: result,
        );
        ref.invalidate(devicesListProvider);
        if (mounted) messenger.showSnackBar(_snackBar('Device renamed'));
      } catch (_) {
        if (mounted) {
          messenger.showSnackBar(_errorSnackBar('Could not rename device'));
        }
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showInviteSheet(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InviteFamilySheet(deviceId: widget.deviceId),
    );
    if (result == true && mounted) {
      messenger.showSnackBar(_snackBar('Invite sent'));
    }
  }

  Future<void> _revokeShare(BuildContext context, String shareId) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _revoking = true);
    try {
      final repo = ref.read(sharingRepositoryProvider);
      await repo.deleteShare(shareId);
      ref.invalidate(deviceSharesProvider(widget.deviceId));
      if (mounted) {
        messenger.showSnackBar(_snackBar('Share revoked'));
      }
    } on SharingException catch (e) {
      if (mounted) {
        messenger.showSnackBar(_errorSnackBar(e.message));
      }
    } finally {
      if (mounted) setState(() => _revoking = false);
    }
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final router = GoRouter.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _RemoveConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing = true);
    try {
      // Placeholder: backend DELETE /devices/{deviceId} endpoint
      // not yet in phase-08 spec; navigate back on success
      ref.invalidate(devicesListProvider);
      if (mounted) router.go('/devices');
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  SnackBar _snackBar(String message) => SnackBar(
        content: Text(message,
            style: GoogleFonts.inter(color: AppColors.onPrimaryFixed)),
        backgroundColor: AppColors.primaryContainer,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.defaultRadius)),
      );

  SnackBar _errorSnackBar(String message) => SnackBar(
        content: Text(message,
            style: GoogleFonts.inter(color: AppColors.onErrorContainer)),
        backgroundColor: AppColors.errorContainer,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.defaultRadius)),
      );

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
          color: const Color(0xB3101419),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Symbols.arrow_back,
                      color: AppColors.primaryContainer, size: 24),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/devices');
                    }
                  },
                ),
                Expanded(
                  child: Text(
                    'Device Details',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: AppTextSize.xl,
                      fontWeight: AppFontWeight.bold,
                      color: AppColors.onSurface,
                      letterSpacing: -0.3,
                    ),
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

// ── Header section ────────────────────────────────────────────────────────────

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.device, required this.onEditName});
  final DevicePairOut? device;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context) {
    final name = device?.name ?? '—';
    final id = device?.deviceId ?? '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.inter(
                fontSize: AppTextSize.xl3,
                fontWeight: AppFontWeight.bold,
                color: AppColors.onSurface,
                letterSpacing: -0.5,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Symbols.edit,
                color: AppColors.onSurfaceVariant, size: 20),
            onPressed: onEditName,
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text(
            id,
            style: GoogleFonts.inter(
              fontSize: AppTextSize.sm,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: id));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Device ID copied'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: const Icon(Symbols.content_copy,
                color: AppColors.onSurfaceVariant, size: 16),
          ),
        ]),
      ],
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.device});
  final DevicePairOut? device;

  @override
  Widget build(BuildContext context) {
    final online = device?.online ?? false;
    final lastSeen = device?.lastSeen;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: AppRadius.defaultBr,
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: online ? AppColors.primary : AppColors.onSurfaceVariant,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              online ? 'Online' : 'Offline',
              style: GoogleFonts.inter(
                fontWeight: AppFontWeight.medium,
                color: online ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            lastSeen != null ? 'Last seen: $lastSeen' : 'Last seen: Unknown',
            style: GoogleFonts.inter(
              fontSize: AppTextSize.sm,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'SLEEP PAD V2',
            style: GoogleFonts.inter(
              fontSize: AppTextSize.xs,
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
              letterSpacing: 1.2,
              fontWeight: AppFontWeight.semiBold,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Thresholds preview section ────────────────────────────────────────────────

class _ThresholdsSection extends StatelessWidget {
  const _ThresholdsSection(
      {required this.thresholdsAsync, required this.onEdit});
  final AsyncValue thresholdsAsync;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Alert Thresholds',
                style: GoogleFonts.inter(
                    fontSize: AppTextSize.lg,
                    fontWeight: AppFontWeight.medium,
                    color: AppColors.onSurface)),
            GestureDetector(
              onTap: onEdit,
              child: Text('Edit',
                  style: GoogleFonts.inter(
                      fontSize: AppTextSize.sm,
                      fontWeight: AppFontWeight.medium,
                      color: AppColors.primaryContainer)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: AppRadius.defaultBr,
            border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.15)),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Symbols.vital_signs,
                  color: AppColors.primaryContainer, size: 22),
            ),
            const SizedBox(width: 16),
            thresholdsAsync.when(
              loading: () => Text('Loading…',
                  style: GoogleFonts.inter(
                      fontSize: AppTextSize.sm,
                      color: AppColors.onSurfaceVariant)),
              error: (_, __) => Text('Unavailable',
                  style: GoogleFonts.inter(
                      fontSize: AppTextSize.sm,
                      color: AppColors.onSurfaceVariant)),
              data: (t) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HR: ${t.hrLow.round()}–${t.hrHigh.round()} bpm  ·  RR: ${t.rrLow.round()}–${t.rrHigh.round()} brpm',
                    style: GoogleFonts.inter(
                        fontSize: AppTextSize.base,
                        color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text('Active notifications enabled',
                      style: GoogleFonts.inter(
                          fontSize: AppTextSize.sm,
                          color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

// ── Sharing section ───────────────────────────────────────────────────────────

class _SharingSection extends StatelessWidget {
  const _SharingSection({
    required this.deviceId,
    required this.sharesAsync,
    required this.onInvite,
    required this.onRevoke,
  });

  final String deviceId;
  final AsyncValue<List<ShareOut>> sharesAsync;
  final VoidCallback onInvite;
  final ValueChanged<String> onRevoke;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sharing',
            style: GoogleFonts.inter(
                fontSize: AppTextSize.lg,
                fontWeight: AppFontWeight.medium,
                color: AppColors.onSurface)),
        const SizedBox(height: 16),
        sharesAsync.when(
          loading: () => const Center(
              child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(
                color: AppColors.primaryContainer, strokeWidth: 2),
          )),
          error: (e, _) => Text(e.toString(),
              style: GoogleFonts.inter(
                  color: AppColors.error, fontSize: AppTextSize.sm)),
          data: (shares) => Column(
            children: [
              ...shares.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ShareRow(share: s, onRevoke: () => onRevoke(s.id)),
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
        // Invite button
        PrimaryButton(
          label: 'Invite family member',
          onPressed: onInvite,
        ),
      ],
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.share, required this.onRevoke});
  final ShareOut share;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: AppRadius.defaultBr,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            shape: BoxShape.circle,
          ),
          child: const Icon(Symbols.person,
              color: AppColors.onSurfaceVariant, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(share.invitedEmail,
                style: GoogleFonts.inter(
                    fontSize: AppTextSize.sm,
                    fontWeight: AppFontWeight.medium,
                    color: AppColors.onSurface)),
            const SizedBox(height: 2),
            Text(share.accepted ? 'Accepted' : 'Pending',
                style: GoogleFonts.inter(
                    fontSize: AppTextSize.xs,
                    color: share.accepted
                        ? AppColors.primaryContainer
                        : AppColors.onSurfaceVariant)),
          ]),
        ),
        TextButton(
          onPressed: onRevoke,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
          child: Text(share.accepted ? 'Revoke' : 'Cancel',
              style: GoogleFonts.inter(
                  fontSize: AppTextSize.sm, fontWeight: AppFontWeight.medium)),
        ),
      ]),
    );
  }
}

// ── Danger zone ───────────────────────────────────────────────────────────────

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.onRemove});
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Color(0x26FFFFFF), thickness: 1),
        const SizedBox(height: 24),
        Text('Danger Zone',
            style: GoogleFonts.inter(
                fontSize: AppTextSize.lg,
                fontWeight: AppFontWeight.medium,
                color: AppColors.error)),
        const SizedBox(height: 4),
        Text('Careful, this cannot be undone.',
            style: GoogleFonts.inter(
                fontSize: AppTextSize.sm, color: AppColors.onSurfaceVariant)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: onRemove,
            icon: const Icon(Symbols.delete_forever,
                color: AppColors.error, size: 20),
            label: Text('Remove device',
                style: GoogleFonts.inter(
                    fontSize: AppTextSize.base,
                    fontWeight: AppFontWeight.semiBold,
                    color: AppColors.error)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: AppColors.error.withValues(alpha: 0.3), width: 1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Rename bottom sheet ───────────────────────────────────────────────────────

class _RenameSheet extends StatelessWidget {
  const _RenameSheet({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A222D),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Rename device',
                style: GoogleFonts.inter(
                    fontSize: 22, fontWeight: AppFontWeight.semiBold,
                    color: AppColors.onSurface)),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              style: GoogleFonts.inter(color: AppColors.onSurface),
              decoration: InputDecoration(
                hintText: 'Device name',
                hintStyle: GoogleFonts.inter(
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.6)),
                filled: true,
                fillColor: AppColors.surfaceContainer,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.4))),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 16),
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Save',
              onPressed: () => Navigator.of(context).pop(controller.text),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Remove confirm dialog ─────────────────────────────────────────────────────

class _RemoveConfirmDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainer,
      title: Text('Remove device?',
          style: GoogleFonts.inter(
              fontWeight: AppFontWeight.semiBold, color: AppColors.error)),
      content: Text(
        'This will unpair the device. Sleep data is not deleted. This cannot be undone.',
        style: GoogleFonts.inter(
            fontSize: AppTextSize.sm, color: AppColors.onSurfaceVariant),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel',
              style: GoogleFonts.inter(color: AppColors.onSurfaceVariant)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Remove',
              style: GoogleFonts.inter(
                  color: AppColors.error,
                  fontWeight: AppFontWeight.semiBold)),
        ),
      ],
    );
  }
}
