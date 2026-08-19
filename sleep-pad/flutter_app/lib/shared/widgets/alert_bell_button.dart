import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';
import '../../features/alerts/providers/alert_history_provider.dart';
import '../../features/data/providers/selected_device_provider.dart';

// Tracks the "last seen alerts at" timestamp — used to compute unread count.
// Session-local (no persistence): after app restart every alert is unread
// until the bell is tapped. Good enough for MVP; upgrade to secure_storage
// if users complain about dot flickering between launches.
final _lastSeenAlertsProvider =
    StateProvider<DateTime>((_) => DateTime.fromMillisecondsSinceEpoch(0));

// Top-bar bell button with a red dot when there are unread alerts.
// Tapping marks all current alerts as read + navigates to /alerts.
class AlertBellButton extends ConsumerWidget {
  const AlertBellButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tint = color ?? AppColors.onSurfaceVariant;
    final selected = ref.watch(selectedDeviceProvider).valueOrNull;
    final lastSeen = ref.watch(_lastSeenAlertsProvider);

    int unread = 0;
    if (selected != null) {
      final historyAsync = ref.watch(alertHistoryProvider(selected.deviceId));
      unread = historyAsync.maybeWhen(
        data: (list) => list.where((a) => a.triggeredAt.isAfter(lastSeen)).length,
        orElse: () => 0,
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(Icons.notifications_outlined, color: tint, size: 24),
          onPressed: () {
            // Mark read the moment the user leaves for the alerts screen.
            ref.read(_lastSeenAlertsProvider.notifier).state = DateTime.now();
            context.go('/alerts');
          },
        ),
        if (unread > 0)
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.background, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
