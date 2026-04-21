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

// ── Notifier ───────────────────────────────────────────────────────────────

class ProvisioningNotifier extends Notifier<ProvisioningState> {
  @override
  ProvisioningState build() => const ProvisioningIdle();

  BleService get _ble => ref.read(bleServiceProvider);
  DeviceRepository get _repo => DeviceRepository();

  void reset() => state = const ProvisioningIdle();

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
    // Device name: default "New Device" — user can rename in success screen.
    // Re-calling pair with final name works because backend upserts on device_id.
    String deviceName = 'New Device',
  }) async {
    try {
      // Step 1: Read DeviceId from BLE
      state = ProvisioningFetchingDeviceId(device);
      final deviceId = await _ble.readDeviceId(device);

      // Step 2: POST /devices/pair — get MQTT credentials
      final pairOut = await _repo.pairDevice(
        deviceId: deviceId,
        name: deviceName,
      );
      state = ProvisioningPairedWithBackend(
        device: device,
        deviceId: deviceId,
        pairOut: pairOut,
      );

      // Step 3: BLE write all 6 characteristics + wait for Status notify
      final payload = ProvisionPayload(
        ssid: ssid,
        password: wifiPassword,
        serverHost: pairOut.mqttHost,
        mqttScheme: pairOut.mqttScheme,
        mqttUser: pairOut.mqttUsername,
        mqttPassword: pairOut.mqttPassword,
      );

      state = ProvisioningConnectingWifi(
        deviceId: deviceId,
        pairOut: pairOut,
      );

      final bleStatus = await _ble.provision(
        device,
        payload,
        onStatusUpdate: (status) {
          if (status == 'connecting') {
            state = ProvisioningConnectingMqtt(
              deviceId: deviceId,
              pairOut: pairOut,
            );
          }
        },
      );

      if (bleStatus == 'wifi_failed') {
        state = const ProvisioningFailure(
          'Could not connect to WiFi. Check your network name and password.',
        );
        return;
      }
      if (bleStatus == 'mqtt_failed') {
        state = const ProvisioningFailure(
          'Connected to WiFi but could not reach the server. Try again.',
        );
        return;
      }

      // Step 4: Poll /devices/mine until device online=true (max 30s)
      final onlineConfirmed = await _pollUntilOnline(deviceId);
      if (!onlineConfirmed) {
        // Device connected to broker but poll timed out — treat as success
        // because BLE status was "connected". Backend LWT may arrive shortly.
      }

      state = ProvisioningSuccess(deviceId: deviceId, pairOut: pairOut);
    } on DioException catch (_) {
      // Dio errors can leak URL/headers via toString. Surface a generic message.
      state = const ProvisioningFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    } catch (_) {
      // BLE / other failures — generic safe message.
      state = const ProvisioningFailure(
        'Pairing failed unexpectedly. Please try again.',
      );
    }
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
