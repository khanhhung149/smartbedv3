// Response model for sharing endpoints.
// Matches backend ShareOut schema defined in backend/app/sharing/models.py:
//   id, device_id, invited_email, accepted, created_at, accepted_at
class ShareOut {
  const ShareOut({
    required this.id,
    required this.deviceId,
    required this.invitedEmail,
    required this.accepted,
    required this.createdAt,
    this.acceptedAt,
  });

  final String id;
  final String deviceId;
  final String invitedEmail;
  final bool accepted;
  final DateTime createdAt;
  final DateTime? acceptedAt;

  factory ShareOut.fromJson(Map<String, dynamic> json) => ShareOut(
        id: json['id'] as String,
        deviceId: json['device_id'] as String,
        invitedEmail: json['invited_email'] as String,
        accepted: json['accepted'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        acceptedAt: json['accepted_at'] == null
            ? null
            : DateTime.parse(json['accepted_at'] as String),
      );
}
