import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ble_service.dart';
import '../device_repository.dart';
import '../models/device_pair_out.dart';
import '../models/provision_payload.dart';
import 'ble_scan_provider.dart';

// ── State machine ──────────────────────────────────────────────────────────

sealed class ProvisioningState {
  const ProvisioningState();
}

class ProvisioningIdle extends ProvisioningState {
  const ProvisioningIdle();
}

class ProvisioningScanning extends ProvisioningState {
  const ProvisioningScanning();
}

class ProvisioningSelected extends ProvisioningState {
  const ProvisioningSelected(this.device);
  final BluetoothDevice device;
}

class ProvisioningFetchingDeviceId extends ProvisioningState {
  const ProvisioningFetchingDeviceId(this.device);
  final BluetoothDevice device;
}

class ProvisioningPairedWithBackend extends ProvisioningState {
  const ProvisioningPairedWithBackend({
    required this.device,
    required this.deviceId,
    required this.pairOut,
  });
  final BluetoothDevice device;
  final String deviceId;
  final DevicePairOut pairOut;
}

class ProvisioningConnectingWifi extends ProvisioningState {
  const ProvisioningConnectingWifi({
    required this.deviceId,
    required this.pairOut,
  });
  final String deviceId;
  final DevicePairOut pairOut;
}

class ProvisioningConnectingMqtt extends ProvisioningState {
  const ProvisioningConnectingMqtt({
    required this.deviceId,
    required this.pairOut,
  });
  final String deviceId;
  final DevicePairOut pairOut;
}

class ProvisioningSuccess extends ProvisioningState {
  const ProvisioningSuccess({
    required this.deviceId,
    required this.pairOut,
  });
  final String deviceId;
  final DevicePairOut pairOut;
}

class ProvisioningFailure extends ProvisioningState {
  const ProvisioningFailure(this.reason);
  final String reason;
}

// Retryable WiFi failure — BLE session still open, user can edit creds + retry.
class ProvisioningWifiFailedRetryable extends ProvisioningState {
  const ProvisioningWifiFailedRetryable({
    required this.lastSsid,
    required this.deviceId,
    required this.pairOut,
  });
  final String lastSsid;
  final String deviceId;
  final DevicePairOut pairOut;
}

// Retryable MQTT failure — same shape; distinct so UI can show proper message.
class ProvisioningMqttFailedRetryable extends ProvisioningState {
  const ProvisioningMqttFailedRetryable({
    required this.lastSsid,
    required this.deviceId,
    required this.pairOut,
  });
  final String lastSsid;
  final String deviceId;
  final DevicePairOut pairOut;
}

// ── Notifier ───────────────────────────────────────────────────────────────

class ProvisioningNotifier extends Notifier<ProvisioningState> {
  @override
  ProvisioningState build() => const ProvisioningIdle();

  BleService get _ble => ref.read(bleServiceProvider);
  DeviceRepository get _repo => DeviceRepository();

  // Cached across retries so writeProvisioningChars can reuse values the user
  // isn't editing (server host, MQTT creds).
  BluetoothDevice? _activeDevice;
  String? _activeDeviceId;
  DevicePairOut? _activePairOut;

  void reset() {
    _activeDevice = null;
    _activeDeviceId = null;
    _activePairOut = null;
    state = const ProvisioningIdle();
  }

  // User cancels from error UI — closes BLE session and resets to idle.
  // Firmware treats BLE disconnect as cancel → erases NVS → restarts into
  // fresh BLE advertising mode.
  Future<void> cancel() async {
    try {
      await _ble.closeProvisioningSession();
    } catch (_) {}
    reset();
  }

  void selectDevice(BluetoothDevice device) {
    state = ProvisioningSelected(device);
  }

  // Full provisioning sequence starting from a selected device + WiFi creds.
  // Transitions state machine through each step, emitting intermediate states
  // so the pairing screen can show live progress bullets.
  Future<void> startProvisioning({
    required BluetoothDevice device,
    required String ssid,
    required String wifiPassword,
    String deviceName = 'New Device',
  }) async {
    try {
      // ONE BLE connection for the whole flow — avoids iOS reconnect flakiness
      // (the peripheral takes 1-2s to release state after disconnect; a quick
      // re-connect can drop silently before writes land).
      state = ProvisioningFetchingDeviceId(device);
      await _ble.openProvisioningSession(device);
      final deviceId = await _ble.readDeviceIdFromSession();

      final pairOut = await _repo.pairDevice(
        deviceId: deviceId,
        name: deviceName,
      );

      _activeDevice = device;
      _activeDeviceId = deviceId;
      _activePairOut = pairOut;

      await _writeAndAwait(ssid: ssid, password: wifiPassword);
    } on DioException catch (e, st) {
      // ignore: avoid_print
      print('[provisioning] DioException: ${e.message} ${e.response?.statusCode}\n$st');
      await _ble.closeProvisioningSession();
      state = ProvisioningFailure(
        'Server error: ${e.response?.statusCode ?? "no response"}. ${e.message ?? ""}',
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('[provisioning] error: $e\n$st');
      await _ble.closeProvisioningSession();
      state = ProvisioningFailure('Pairing failed: $e');
    }
  }

  // User edited creds on the failure UI and tapped Retry.  BLE stays connected.
  Future<void> retryWithCreds({
    required String ssid,
    required String password,
  }) async {
    if (_activeDevice == null || _activePairOut == null) {
      state = const ProvisioningFailure('Session expired. Please start over.');
      return;
    }
    try {
      await _writeAndAwait(ssid: ssid, password: password);
    } catch (e, st) {
      // ignore: avoid_print
      print('[provisioning] retry error: $e\n$st');
      await _ble.closeProvisioningSession();
      state = ProvisioningFailure('Retry failed: $e');
    }
  }

  Future<void> _writeAndAwait({
    required String ssid,
    required String password,
  }) async {
    final deviceId = _activeDeviceId!;
    final pairOut = _activePairOut!;

    state = ProvisioningConnectingWifi(deviceId: deviceId, pairOut: pairOut);

    await _ble.writeProvisioningChars(ProvisionPayload(
      ssid: ssid,
      password: password,
      serverHost: pairOut.mqttHost,
      mqttScheme: pairOut.mqttScheme,
      mqttUser: pairOut.mqttUsername,
      mqttPassword: pairOut.mqttPassword,
    ));

    final bleStatus = await _ble.awaitProvisioningStatus(
      onUpdate: (status) {
        switch (status) {
          case 'wifi_connected':
          case 'mqtt_connecting':
            state = ProvisioningConnectingMqtt(deviceId: deviceId, pairOut: pairOut);
          case 'wifi_connecting':
            state = ProvisioningConnectingWifi(deviceId: deviceId, pairOut: pairOut);
        }
      },
    );

    if (bleStatus == 'wifi_failed') {
      state = ProvisioningWifiFailedRetryable(
        lastSsid: ssid,
        deviceId: deviceId,
        pairOut: pairOut,
      );
      return;
    }
    if (bleStatus == 'mqtt_failed') {
      state = ProvisioningMqttFailedRetryable(
        lastSsid: ssid,
        deviceId: deviceId,
        pairOut: pairOut,
      );
      return;
    }

    // bleStatus == 'connected' — close session, finalize
    await _ble.closeProvisioningSession();

    final onlineConfirmed = await _pollUntilOnline(deviceId);
    if (!onlineConfirmed) {
      // BLE reported success — treat as success even if Redis TTL hasn't
      // flipped yet. Backend LWT usually arrives within a few seconds.
    }
    state = ProvisioningSuccess(deviceId: deviceId, pairOut: pairOut);
  }

  // Rename device after provisioning (called from success screen).
  // Re-pairs with updated name — idempotent per backend contract.
  Future<void> renameDevice({
    required String deviceId,
    required String newName,
  }) async {
    try {
      await _repo.pairDevice(deviceId: deviceId, name: newName);
    } catch (_) {
      // Non-fatal: name update failure should not block navigation to home
    }
  }

  // Polls GET /devices/mine every 2s up to 15 iterations (30s).
  // Returns true if the device appears with online=true.
  Future<bool> _pollUntilOnline(String deviceId) async {
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final devices = await _repo.getMyDevices();
        final match = devices.where((d) => d.deviceId == deviceId).firstOrNull;
        if (match != null && match.online) return true;
      } catch (_) {
        // Ignore transient network errors during polling
      }
    }
    return false;
  }
}

final provisioningProvider =
    NotifierProvider<ProvisioningNotifier, ProvisioningState>(
  ProvisioningNotifier.new,
);
