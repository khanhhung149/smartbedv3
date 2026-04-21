// Data class for the 6 fields Flutter writes over BLE GATT characteristics.
// Field order matches the SEQUENTIAL write order per protocol contract:
// SSID → password → serverHost → mqttScheme → mqttUser → mqttPassword
class ProvisionPayload {
  const ProvisionPayload({
    required this.ssid,
    required this.password,
    required this.serverHost,
    required this.mqttScheme,
    required this.mqttUser,
    required this.mqttPassword,
  });

  final String ssid;
  final String password;
  // MQTT host only — no scheme prefix (e.g. "mqtt.yourdomain.com" or "192.168.1.100:9001")
  final String serverHost;
  final String mqttScheme;
  final String mqttUser;
  final String mqttPassword;
}
