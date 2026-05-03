import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/status_badge.dart';
import '../data/models/realtime_data.dart';
import '../data/providers/history_provider.dart';
import '../data/providers/realtime_provider.dart';
import 'home_app_bar.dart';
import 'home_metrics_section.dart';
import 'home_offline_banner.dart';
import 'home_status_section.dart';

// Main home content widget — shown when a device is selected.
// Owns sparkline buffers and WS stream subscription.
// Parent keys on deviceId so state resets cleanly on device switch.

class HomeContent extends ConsumerStatefulWidget {
  const HomeContent({
    super.key,
    required this.deviceName,
    required this.deviceId,
    required this.onDeviceTap,
  });

  final String deviceName;
  final String deviceId;
  final VoidCallback onDeviceTap;

  @override
  ConsumerState<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<HomeContent> {
  // Sparkline buffers — reset automatically when parent rebuilds with new ValueKey.
  final List<double> _hrHistory = [];
  final List<double> _rrHistory = [];
  final List<double> _tempHistory = [];
  static const int _sparklineMax = 60;
  static const int _tempSparklineMax = 60;
  RealtimeData? _latest;

  @override
  void initState() {
    super.initState();
    // Preload last 1 hour so sparklines aren't empty for 60s before first min frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final history = await ref
            .read(historyProvider(
                    (deviceId: widget.deviceId, range: 'hour'))
                .future);
        if (!mounted) return;
        setState(() {
          for (final p in history.points) {
            if (p.hr != null) _hrHistory.add(p.hr!);
            if (p.rr != null) _rrHistory.add(p.rr!);
            if (p.temp != null) _tempHistory.add(p.temp!);
          }
          final lastTemp = history.points
              .where((p) => p.temp != null)
              .map((p) => p.temp!)
              .lastOrNull;
          if (lastTemp != null) {
            _latest = RealtimeData(
              deviceId: widget.deviceId,
              ts: 0,
              temp: lastTemp,
            );
          }
        });
      } catch (_) {
        // Non-fatal — WS stream fills buffers over time.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<RealtimeData>>(
      realtimeProvider(widget.deviceId),
      (previous, next) {
        next.whenData((data) {
          if (!mounted) return;
          setState(() {
            // Merge fields: min frames carry temp/movement/snore;
            // sec frames carry hr/rr. Preserve last known value for missing fields.
            _latest = RealtimeData(
              deviceId: data.deviceId,
              ts: data.ts,
              hr: data.hr ?? _latest?.hr,
              rr: data.rr ?? _latest?.rr,
              sdata: data.sdata ?? _latest?.sdata,
              pdata: data.pdata ?? _latest?.pdata,
              movement: data.movement ?? _latest?.movement,
              snore: data.snore ?? _latest?.snore,
              respDisorder: data.respDisorder ?? _latest?.respDisorder,
              statusCode: data.statusCode ?? _latest?.statusCode,
              temp: data.temp ?? _latest?.temp,
            );
            if (data.hr != null) {
              _hrHistory.add(data.hr!);
              if (_hrHistory.length > _sparklineMax) _hrHistory.removeAt(0);
            }
            if (data.rr != null) {
              _rrHistory.add(data.rr!);
              if (_rrHistory.length > _sparklineMax) _rrHistory.removeAt(0);
            }
            if (data.temp != null) {
              _tempHistory.add(data.temp!);
              if (_tempHistory.length > _tempSparklineMax) {
                _tempHistory.removeAt(0);
              }
            }
          });
        });
      },
    );
    final streamAsync = ref.watch(realtimeProvider(widget.deviceId));

    final connection = switch (streamAsync) {
      AsyncError() => DeviceLinkState.disconnected,
      AsyncData() when _latest != null => DeviceLinkState.connected,
      _ => DeviceLinkState.connecting,
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: HomeAppBar(
        deviceName: widget.deviceName,
        onDeviceTap: widget.onDeviceTap,
      ),
      body: Column(
        children: [
          if (streamAsync is AsyncError)
            HomeOfflineBanner(
                message: AppLocalizations.of(context)!.reconnectingTo(widget.deviceName)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      height: 72 + MediaQuery.of(context).padding.top + 4),
                  HomeStatusSection(
                    statusCode: _latest?.statusCode,
                    connection: connection,
                  ),
                  const SizedBox(height: 10),
                  HomeMetricsSection(
                    latest: _latest,
                    hrHistory: _hrHistory,
                    rrHistory: _rrHistory,
                    tempHistory: _tempHistory,
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
