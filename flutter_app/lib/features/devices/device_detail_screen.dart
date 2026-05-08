import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/loading_overlay.dart';
import '../alerts/providers/thresholds_provider.dart' show thresholdsProvider;
import '../data/providers/selected_device_provider.dart';
import '../sharing/invite_family_sheet.dart';
import '../sharing/providers/sharing_providers.dart';
import '../sharing/providers/sharing_repository_provider.dart' show sharingRepositoryProvider;
import '../sharing/sharing_repository_impl.dart' show SharingException;
import 'device_detail_app_bar.dart';
import 'device_detail_danger_zone.dart';
import 'device_detail_info_card.dart';
import 'device_detail_sharing_card.dart';
import 'device_detail_snackbars.dart';
import 'device_detail_thresholds_card.dart';
import 'device_repository_impl.dart' show DeviceException;
import 'models/device_out.dart';
import 'providers/device_repository_provider.dart';
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
        appBar: buildDeviceDetailAppBar(context),
        bottomNavigationBar: AppBottomNav(
          currentIndex: 3,
          onTap: (i) => _handleNavTap(context, i),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 88, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DeviceDetailInfoCard(
                device: device,
                onEditName: () => _showRenameSheet(context, device),
              ),
              const SizedBox(height: 32),
              DeviceDetailStatusCard(device: device),
              const SizedBox(height: 16),
              DeviceDetailThresholdsCard(
                thresholdsAsync: thresholdsAsync,
                onEdit: () => context.push('/alerts'),
              ),
              const SizedBox(height: 32),
              DeviceDetailSharingCard(
                sharesAsync: sharesAsync,
                onInvite: () => _showInviteSheet(context),
                onRevoke: (shareId) => _revokeShare(context, shareId),
              ),
              const SizedBox(height: 48),
              DeviceDetailDangerZone(
                onRemove: () => _confirmRemove(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DeviceOut _placeholder(String deviceId) => DeviceOut(
        deviceId: deviceId,
        name: deviceId,
        pairedAt: DateTime.now().toIso8601String(),
        online: false,
      );

  Future<void> _showRenameSheet(BuildContext context, DeviceOut? device) async {
    if (device == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: device.name ?? '');
    try {
      final result = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => DeviceRenameSheet(controller: controller),
      );
      if (result == null || result.isEmpty || !mounted) return;
      try {
        await ref.read(deviceRepositoryProvider).pairDevice(
          deviceId: widget.deviceId,
          name: result,
        );
        ref.invalidate(devicesListProvider);
        ref.invalidate(selectedDeviceProvider);
        if (mounted) messenger.showSnackBar(deviceDetailSnackBar('Device renamed'));
      } catch (_) {
        if (mounted) {
          messenger.showSnackBar(deviceDetailErrorSnackBar('Could not rename device'));
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
      messenger.showSnackBar(deviceDetailSnackBar('Invite sent'));
    }
  }

  Future<void> _revokeShare(BuildContext context, String shareId) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _revoking = true);
    try {
      final repo = ref.read(sharingRepositoryProvider);
      await repo.deleteShare(shareId);
      ref.invalidate(deviceSharesProvider(widget.deviceId));
      if (mounted) messenger.showSnackBar(deviceDetailSnackBar('Share revoked'));
    } on SharingException catch (e) {
      if (mounted) messenger.showSnackBar(deviceDetailErrorSnackBar(e.message));
    } finally {
      if (mounted) setState(() => _revoking = false);
    }
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const DeviceRemoveConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing = true);
    try {
      await ref.read(deviceRepositoryProvider).deleteDevice(widget.deviceId);
      ref.invalidate(devicesListProvider);
      if (mounted) {
        messenger.showSnackBar(deviceDetailSnackBar(
          'Device removed. It will reset when it next comes online.',
        ));
        router.go('/devices');
      }
    } on DeviceException catch (e) {
      if (mounted) messenger.showSnackBar(deviceDetailErrorSnackBar(e.message));
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  void _handleNavTap(BuildContext context, int index) {
    switch (index) {
      case 0: context.go('/home');
      case 1: context.go('/history');
      case 2: context.go('/alerts');
      case 3: context.go('/devices');
      case 4: context.go('/settings');
    }
  }
}
