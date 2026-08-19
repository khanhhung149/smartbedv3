import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ble_service.dart';

// Singleton BleService shared across providers.
final bleServiceProvider = Provider<BleService>((_) => BleService());

// StreamProvider that emits deduplicated ScanResult items while scanning.
// The screen subscribes to this and builds its device list reactively.
// Scan auto-stops after 30s (BleService default timeout).
final bleScanProvider = StreamProvider.autoDispose<ScanResult>((ref) {
  final service = ref.watch(bleServiceProvider);
  return service.scanForDevices(timeout: const Duration(seconds: 30));
});

// Tracks whether a BLE scan is currently active.
final bleIsScanningProvider = StreamProvider.autoDispose<bool>((ref) {
  return FlutterBluePlus.isScanning;
});
