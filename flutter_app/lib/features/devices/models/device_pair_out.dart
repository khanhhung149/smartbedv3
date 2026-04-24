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
  // Nullable per backend schema — device can be paired without a custom name.
  final String? name;

  // Non-null name for display. Falls back to device_id when name is unset.
  String get displayName => (name != null && name!.isNotEmpty) ? name! : deviceId;
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
        name: json['name'] as String?,
        pairedAt: json['paired_at'] as String,
        online: json['online'] as bool,
        mqttUsername: json['mqtt_username'] as String? ?? '',
        mqttPassword: json['mqtt_password'] as String? ?? '',
        mqttHost: json['mqtt_host'] as String,
        mqttScheme: json['mqtt_scheme'] as String,
        lastSeen: json['last_seen'] as String?,
      );
}
