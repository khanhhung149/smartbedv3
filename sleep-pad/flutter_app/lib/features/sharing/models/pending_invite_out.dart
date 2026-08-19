// Pending invite — a share record the current user has not yet accepted.
// Derived from ShareOut fields; the backend returns the same ShareOut shape
// when listing pending invites (accepted=false, from another owner).
class PendingInviteOut {
  const PendingInviteOut({
    required this.shareId,
    required this.deviceId,
    required this.deviceName,
    required this.ownerEmail,
    required this.createdAt,
  });

  final String shareId;
  final String deviceId;
  final String deviceName;
  final String ownerEmail;
  final DateTime createdAt;

  factory PendingInviteOut.fromJson(Map<String, dynamic> json) =>
      PendingInviteOut(
        shareId: json['share_id'] as String,
        deviceId: json['device_id'] as String,
        deviceName: json['device_name'] as String? ?? json['device_id'] as String,
        ownerEmail: json['owner_email'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
