import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_colors.dart';
import '../data/providers/selected_device_provider.dart';
import '../devices/models/device_pair_out.dart';

// Modal bottom sheet: lists owned devices, tap selects active device.
// Source: home prompt spec — device-selector chip opens bottom sheet.
// Uses SelectedDeviceNotifier to fetch + persist selection.

class DeviceSelectorSheet extends ConsumerStatefulWidget {
  const DeviceSelectorSheet({super.key});

  @override
  ConsumerState<DeviceSelectorSheet> createState() =>
      _DeviceSelectorSheetState();
}

class _DeviceSelectorSheetState extends ConsumerState<DeviceSelectorSheet> {
  List<DevicePairOut>? _devices;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final notifier = ref.read(selectedDeviceProvider.notifier);
      final devices = await notifier.listDevices();
      if (mounted) setState(() { _devices = devices; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedAsync = ref.watch(selectedDeviceProvider);
    final selected = selectedAsync.valueOrNull;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Select Device',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryContainer,
                  strokeWidth: 2,
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _error!,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.error,
                ),
              ),
            )
          else if (_devices == null || _devices!.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No devices found.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            )
          else
            ..._devices!.map(
              (device) => _DeviceTile(
                device: device,
                isSelected: selected?.deviceId == device.deviceId,
                onTap: () async {
                  await ref
                      .read(selectedDeviceProvider.notifier)
                      .selectDevice(device);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isSelected,
    required this.onTap,
  });

  final DevicePairOut device;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryContainer.withValues(alpha: 0.15)
              : AppColors.surfaceContainerHigh,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Symbols.bed,
          size: 20,
          color: isSelected
              ? AppColors.primaryContainer
              : AppColors.onSurfaceVariant,
        ),
      ),
      title: Text(
        device.name,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: AppColors.onSurface,
        ),
      ),
      subtitle: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: device.online ? const Color(0xFF34D399) : AppColors.outline,
            ),
          ),
          Text(
            device.online ? 'Online' : 'Offline',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: device.online
                  ? const Color(0xFF34D399)
                  : AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: isSelected
          ? const Icon(
              Symbols.check_circle,
              size: 20,
              color: AppColors.primaryContainer,
              fill: 1,
            )
          : null,
    );
  }
}
