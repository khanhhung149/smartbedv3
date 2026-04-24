// App-wide constants: API base URL and BLE UUIDs.
// BLE UUIDs are authoritative from docs/protocols/ble-provisioning-and-mqtt-auth.md
abstract final class AppConstants {
  // API base URL — parameterized for easy env switching (dev LAN default)
  static const String apiBaseUrl = 'http://192.168.1.15:8000';

  // JWT secure storage key
  static const String jwtStorageKey = 'jwt';

  // BLE Service + Characteristic UUIDs
  static const String bleServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String bleSsidCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const String blePasswordCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a9';
  static const String bleServerHostCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26aa';
  static const String bleStatusCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26ab';
  static const String bleMqttUserCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26ac';
  static const String bleMqttPassCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26ad';
  static const String bleMqttSchemeCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26ae';
  // READ-only DeviceId char — Flutter reads this after GATT connect to get device_id
  static const String bleDeviceIdCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26af';

  // BLE device name prefix used for scanning
  static const String bleDevicePrefix = 'SleepPad-';

  // FCM Android notification channel ID.
  // Must match AndroidManifest.xml meta-data value.
  static const String fcmChannelId = 'sleeppad_alerts';

  // Secure storage key for persisting last selected device id
  static const String lastDeviceIdKey = 'last_device_id';

  // WebSocket base URL — derived from apiBaseUrl by swapping http(s) scheme.
  static String get wsBaseUrl {
    return apiBaseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
  }
}
