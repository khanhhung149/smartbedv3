// Response model for GET /share/my-devices — devices shared with current user.
// Matches backend SharedDeviceOut schema.
class SharedDeviceOut {
  const SharedDeviceOut({
    required this.shareId,
    required this.deviceId,
    required this.name,
    required this.ownerEmail,
    required this.acceptedAt,
  });

  final String shareId;
  final String deviceId;
  // Nullable per backend schema.
  final String? name;
  final String ownerEmail;
  final String acceptedAt;

  // Non-null display name — falls back to device_id when unset.
  String get deviceName =>
      (name != null && name!.isNotEmpty) ? name! : deviceId;

  factory SharedDeviceOut.fromJson(Map<String, dynamic> json) =>
      SharedDeviceOut(
        shareId: json['share_id'] as String,
        deviceId: json['device_id'] as String,
        name: json['name'] as String?,
        ownerEmail: json['owner_email'] as String,
        acceptedAt: json['accepted_at'] as String,
      );
}
