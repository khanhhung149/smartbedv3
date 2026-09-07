/// Mẫu mới nhất từ sleep pad, khớp `GET /api/realtime?device_id=` của backend Go.
///
/// Mọi trường số đều nullable vì backend trả NULL khi pad không báo — giữ nguyên
/// thay vì quy về 0, để màn hình phân biệt được "pad báo 0" với "không có số".
class RealtimeSample {
  const RealtimeSample({
    required this.t,
    this.status,
    this.heartRate,
    this.respRate,
    this.sdata,
    this.pdata,
  });

  final DateTime t;
  final int? status;
  final int? heartRate;
  final double? respRate;
  final int? sdata;
  final int? pdata;

  factory RealtimeSample.fromJson(Map<String, dynamic> j) => RealtimeSample(
        t: DateTime.parse(j['t'] as String).toLocal(),
        status: (j['status'] as num?)?.toInt(),
        heartRate: (j['heart_rate'] as num?)?.toInt(),
        respRate: (j['resp_rate'] as num?)?.toDouble(),
        sdata: (j['sdata'] as num?)?.toInt(),
        pdata: (j['pdata'] as num?)?.toInt(),
      );

  /// Theo tài liệu LSM-800-T: 0 = đang nằm trên giường, 1 = đã rời giường.
  /// Rất dễ hiểu ngược nên nhãn được viết ra chứ không để người đọc tự suy.
  String get statusLabel {
    switch (status) {
      case 0:
        return 'Đang nằm';
      case 1:
        return 'Rời giường';
      case null:
        return 'Không rõ';
      default:
        return 'Mã $status';
    }
  }

  bool get onBed => status == 0;

  /// Mẫu cũ hơn ngưỡng này coi như mất tín hiệu. Pad phát 1Hz, nên 10 giây là
  /// đã lỡ khoảng 10 khung — đủ để gọi là đứt mà không báo động vì một khung lỡ.
  bool isStale(DateTime now) => now.difference(t).inSeconds > 10;
}
