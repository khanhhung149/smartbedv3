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
//
// Two usage modes:
//   1. readDeviceId()         — one-shot connect+read+disconnect (before pairing)
//   2. provision()            — one-shot pair with automatic disconnect on success
//   3. Session-style retry    — openProvisioningSession() + writeProvisioningChars()
//                                + awaitProvisioningStatus() + closeProvisioningSession()
//                               keeps BLE connection alive across retries.
class BleService {
  // Session state — only populated during an active retry-friendly session.
  BluetoothDevice? _sessionDevice;
  BluetoothService? _sessionService;
  StreamSubscription<List<int>>? _sessionStatusSub;
  // Scan for SleepPad-* devices. Filters by advertisement name prefix.
  // Caller subscribes to the stream; caller is responsible for calling
  // FlutterBluePlus.stopScan() when done (e.g. on screen dispose).
  //
  // iOS note: on first entry to the scan screen the CBCentralManager is still
  // transitioning to .poweredOn (takes ~0.5-1s).  Calling startScan before
  // that silently fails.  We wait for the adapter to be on before starting.
  Stream<ScanResult> scanForDevices({
    Duration timeout = const Duration(seconds: 30),
  }) async* {
    await FlutterBluePlus.adapterState
        .firstWhere((s) => s == BluetoothAdapterState.on)
        .timeout(const Duration(seconds: 5), onTimeout: () => BluetoothAdapterState.on);
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: false,
    );
    yield* FlutterBluePlus.scanResults.expand((results) => results).where(
          (r) =>
              r.device.platformName.startsWith(AppConstants.bleDevicePrefix) ||
              (r.advertisementData.advName
                  .startsWith(AppConstants.bleDevicePrefix)),
        );
  }

  // DEPRECATED one-shot: connects, reads, disconnects.  Kept for screens
  // that don't need a persistent session. For full provisioning flow, use
  // openProvisioningSession + readDeviceIdFromSession instead — that keeps
  // the BLE link alive across the backend pair call + credential writes,
  // avoiding iOS reconnect churn (the peripheral takes 1-2s to release
  // state after disconnect and a fast reconnect can drop silently).
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
      try { await device.disconnect(); } catch (_) {}
    }
  }

  // Read device_id from the currently-open session (no disconnect).
  Future<String> readDeviceIdFromSession() async {
    final svc = _sessionService;
    if (svc == null) throw const BleException('No active provisioning session.');
    try {
      final char = _findChar(svc, AppConstants.bleDeviceIdCharUuid);
      final bytes = await char.read();
      return utf8.decode(bytes);
    } catch (e) {
      throw BleException('Failed to read device ID: $e');
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

      // Contract with firmware (see main.cpp setup):
      //   waiting → wifi_connecting → wifi_connected → mqtt_connecting → connected
      //   or any *_failed terminal state.
      // We forward every status upstream for granular UI, and complete only on
      // a terminal status ("connected" | "wifi_failed" | "mqtt_failed").
      sub = statusChar.lastValueStream.listen((bytes) {
        if (bytes.isEmpty) return;
        final status = utf8.decode(bytes);
        onStatusUpdate?.call(status);
        const terminal = {'connected', 'wifi_failed', 'mqtt_failed'};
        if (terminal.contains(status) && !completer.isCompleted) {
          completer.complete(status);
        }
      });

      // Timeout budget: 45s WiFi-connect + 15s MQTT + 5s slack.
      final result = await completer.future.timeout(
        const Duration(seconds: 65),
        onTimeout: () {
          throw const BleException('Provisioning timed out. Check WiFi signal and try again.');
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

  // ── Session-style API for in-place retry ───────────────────────────────
  //
  // openProvisioningSession → writeProvisioningChars → awaitProvisioningStatus
  // If the status is "connected": call closeProvisioningSession() (cleanup).
  // If the status is "wifi_failed" or "mqtt_failed": call writeProvisioningChars
  // again with new creds, then awaitProvisioningStatus again. Loop.
  // User cancel: call closeProvisioningSession() — firmware's onDisconnect
  // treats disconnect as cancel, erases NVS, restarts BLE.

  Future<void> openProvisioningSession(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
      final services = await device.discoverServices();
      _sessionDevice = device;
      _sessionService = _findService(services);
    } catch (e) {
      _sessionDevice = null;
      _sessionService = null;
      try { await device.disconnect(); } catch (_) {}
      throw BleException('Could not connect to device: $e');
    }
  }

  Future<void> writeProvisioningChars(ProvisionPayload payload) async {
    final svc = _sessionService;
    if (svc == null) throw const BleException('No active provisioning session.');
    try {
      // Sequential writes so firmware's "last write triggers attempt" ordering holds.
      await _writeChar(svc, AppConstants.bleSsidCharUuid, payload.ssid);
      await _writeChar(svc, AppConstants.blePasswordCharUuid, payload.password);
      await _writeChar(svc, AppConstants.bleServerHostCharUuid, payload.serverHost);
      await _writeChar(svc, AppConstants.bleMqttSchemeCharUuid, payload.mqttScheme);
      await _writeChar(svc, AppConstants.bleMqttUserCharUuid, payload.mqttUser);
      await _writeChar(svc, AppConstants.bleMqttPassCharUuid, payload.mqttPassword);
    } catch (e) {
      throw BleException('Failed to send credentials: $e');
    }
  }

  // Subscribes (once per session) to the Status notify char, emits each update
  // via onUpdate, and completes when a terminal status arrives.
  Future<String> awaitProvisioningStatus({
    required void Function(String status) onUpdate,
    Duration timeout = const Duration(seconds: 65),
  }) async {
    final svc = _sessionService;
    if (svc == null) throw const BleException('No active provisioning session.');

    final statusChar = _findChar(svc, AppConstants.bleStatusCharUuid);
    // Enable notify once per session — re-subscribing across retries is fine
    // but we only need one listener.
    if (_sessionStatusSub == null) {
      await statusChar.setNotifyValue(true);
    } else {
      await _sessionStatusSub!.cancel();
      _sessionStatusSub = null;
    }

    final completer = Completer<String>();
    _sessionStatusSub = statusChar.lastValueStream.listen((bytes) {
      if (bytes.isEmpty) return;
      final status = utf8.decode(bytes);
      onUpdate(status);
      const terminal = {'connected', 'wifi_failed', 'mqtt_failed'};
      if (terminal.contains(status) && !completer.isCompleted) {
        completer.complete(status);
      }
    });

    return completer.future.timeout(
      timeout,
      onTimeout: () => throw const BleException(
        'Provisioning timed out. Check WiFi signal and try again.',
      ),
    );
  }

  Future<void> closeProvisioningSession() async {
    await _sessionStatusSub?.cancel();
    _sessionStatusSub = null;
    final dev = _sessionDevice;
    _sessionDevice = null;
    _sessionService = null;
    if (dev != null) {
      try { await dev.disconnect(); } catch (_) {}
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
