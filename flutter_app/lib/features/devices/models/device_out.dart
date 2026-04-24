// Response model for GET /devices/mine — matches backend DeviceOut schema.
// Separate from DevicePairOut (pairing response) because /devices/mine does
// NOT include MQTT credentials — those live only in the pairing response
// (written to the ESP32 once over BLE).
class DeviceOut {
  const DeviceOut({
    required this.deviceId,
    required this.name,
    required this.pairedAt,
    required this.online,
    this.lastSeen,
  });

  final String deviceId;
  // Nullable per backend — device can exist without a custom name.
  final String? name;
  final String pairedAt;
  final bool online;
  final String? lastSeen;

  // Non-null name for display. Falls back to device_id when name is unset.
  String get displayName => (name != null && name!.isNotEmpty) ? name! : deviceId;

  factory DeviceOut.fromJson(Map<String, dynamic> json) => DeviceOut(
        deviceId: json['device_id'] as String,
        name: json['name'] as String?,
        pairedAt: json['paired_at'] as String,
        online: json['online'] as bool,
        lastSeen: json['last_seen'] as String?,
      );
}
