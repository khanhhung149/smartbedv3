import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../core/constants.dart';
import 'models/provision_payload.dart';

class BleException implements Exception {
  const BleException(this.message);
  final String message;
  @override
  String toString() => message;
}

// Wraps flutter_blue_plus for Sleep Pad BLE provisioning operations.
// All public methods throw BleException on failure — callers handle display.
class BleService {
  // Scan for SleepPad-* devices. Filters by advertisement name prefix.
  // Caller subscribes to the stream; caller is responsible for calling
  // FlutterBluePlus.stopScan() when done (e.g. on screen dispose).
  Stream<ScanResult> scanForDevices({
    Duration timeout = const Duration(seconds: 30),
  }) {
    FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: false,
    );
    return FlutterBluePlus.scanResults.expand((results) => results).where(
          (r) =>
              r.device.platformName.startsWith(AppConstants.bleDevicePrefix) ||
              (r.advertisementData.advName
                  .startsWith(AppConstants.bleDevicePrefix)),
        );
  }

  // Connects to device, discovers services, reads DeviceId characteristic,
  // then disconnects. Returns the device_id string (e.g. "CNU2000001").
  Future<String> readDeviceId(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
      final services = await device.discoverServices();
      final service = _findService(services);
      final char = _findChar(service, AppConstants.bleDeviceIdCharUuid);
      final bytes = await char.read();
      return utf8.decode(bytes);
    } on BleException {
      rethrow;
    } catch (e) {
      throw BleException('Failed to read device ID: $e');
    } finally {
      // Always disconnect, even on error
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  // Connects to device, writes all 6 provisioning characteristics SEQUENTIALLY
  // (order required: SSID→Password→ServerHost→MqttScheme→MqttUser→MqttPassword),
  // then subscribes to Status notify char and waits up to 60s for "connected".
  // Disconnects BLE when done (success or timeout/failure).
  // Returns the final status string ("connected", "wifi_failed", "mqtt_failed").
  Future<String> provision(
    BluetoothDevice device,
    ProvisionPayload payload, {
    void Function(String status)? onStatusUpdate,
  }) async {
    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
      final services = await device.discoverServices();
      final service = _findService(services);

      // Sequential writes — order matters (last write triggers ESP32 connect)
      await _writeChar(service, AppConstants.bleSsidCharUuid, payload.ssid);
      await _writeChar(service, AppConstants.blePasswordCharUuid, payload.password);
      await _writeChar(service, AppConstants.bleServerHostCharUuid, payload.serverHost);
      await _writeChar(service, AppConstants.bleMqttSchemeCharUuid, payload.mqttScheme);
      await _writeChar(service, AppConstants.bleMqttUserCharUuid, payload.mqttUser);
      await _writeChar(service, AppConstants.bleMqttPassCharUuid, payload.mqttPassword);

      // Subscribe to Status NOTIFY and wait up to 60s for terminal status
      final statusChar = _findChar(service, AppConstants.bleStatusCharUuid);
      await statusChar.setNotifyValue(true);

      final completer = Completer<String>();
      late StreamSubscription<List<int>> sub;

      sub = statusChar.lastValueStream.listen((bytes) {
        if (bytes.isEmpty) return;
        final status = utf8.decode(bytes);
        onStatusUpdate?.call(status);
        if (status == 'connected' ||
            status == 'wifi_failed' ||
            status == 'mqtt_failed') {
          if (!completer.isCompleted) {
            completer.complete(status);
          }
        }
      });

      // 60-second timeout per protocol spec
      final result = await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw const BleException('Provisioning timed out after 60 seconds.');
        },
      );

      await sub.cancel();
      return result;
    } on BleException {
      rethrow;
    } catch (e) {
      throw BleException('Provisioning failed: $e');
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  // Finds the Sleep Pad GATT service by UUID in discovered services list.
  BluetoothService _findService(List<BluetoothService> services) {
    try {
      return services.firstWhere(
        (s) => s.serviceUuid.toString().toLowerCase() ==
            AppConstants.bleServiceUuid.toLowerCase(),
      );
    } catch (_) {
      throw const BleException(
        'Sleep Pad service not found. Ensure the device is in provisioning mode.',
      );
    }
  }

  // Finds a characteristic by UUID within a service.
  BluetoothCharacteristic _findChar(BluetoothService service, String uuid) {
    try {
      return service.characteristics.firstWhere(
        (c) =>
            c.characteristicUuid.toString().toLowerCase() ==
            uuid.toLowerCase(),
      );
    } catch (_) {
      throw BleException('Characteristic $uuid not found on device.');
    }
  }

  // Writes a UTF-8 string to a characteristic with response confirmation.
  Future<void> _writeChar(
    BluetoothService service,
    String uuid,
    String value,
  ) async {
    final char = _findChar(service, uuid);
    await char.write(utf8.encode(value), withoutResponse: false);
  }
}
