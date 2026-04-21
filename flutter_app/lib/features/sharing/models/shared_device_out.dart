// Response model for GET /share/my-devices — devices shared with current user.
// Matches backend SharedDeviceOut schema.
class SharedDeviceOut {
  const SharedDeviceOut({
    required this.shareId,
    required this.deviceId,
    required this.deviceName,
    required this.ownerEmail,
    required this.online,
    this.lastSeen,
  });

  final String shareId;
  final String deviceId;
  final String deviceName;
  final String ownerEmail;
  final bool online;
  final String? lastSeen;

  factory SharedDeviceOut.fromJson(Map<String, dynamic> json) =>
      SharedDeviceOut(
        shareId: json['share_id'] as String,
        deviceId: json['device_id'] as String,
        deviceName: json['device_name'] as String,
        ownerEmail: json['owner_email'] as String,
        online: json['online'] as bool? ?? false,
        lastSeen: json['last_seen'] as String?,
      );
}
