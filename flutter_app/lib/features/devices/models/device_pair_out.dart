// Response model for POST /devices/pair (DevicePairOut).
// Fields match backend schema exactly per ble-provisioning-and-mqtt-auth.md.
class DevicePairOut {
  const DevicePairOut({
    required this.deviceId,
    required this.name,
    required this.pairedAt,
    required this.online,
    required this.mqttUsername,
    required this.mqttPassword,
    required this.mqttHost,
    required this.mqttScheme,
    this.lastSeen,
  });

  final String deviceId;
  final String name;
  final String pairedAt;
  final bool online;
  final String mqttUsername;
  final String mqttPassword;
  final String mqttHost;
  // "tcp" | "ws" | "wss"
  final String mqttScheme;
  final String? lastSeen;

  factory DevicePairOut.fromJson(Map<String, dynamic> json) => DevicePairOut(
        deviceId: json['device_id'] as String,
        name: json['name'] as String,
        pairedAt: json['paired_at'] as String,
        online: json['online'] as bool,
        mqttUsername: json['mqtt_username'] as String? ?? '',
        mqttPassword: json['mqtt_password'] as String? ?? '',
        mqttHost: json['mqtt_host'] as String,
        mqttScheme: json['mqtt_scheme'] as String,
        lastSeen: json['last_seen'] as String?,
      );
}
