/// 采集状态模型
class CaptureState {
  final bool isCapturing;
  final int pointCloudPacketCount;
  final int pointCloudBytes;
  final int imuPacketCount;
  final int imuBytes;
  final String? filePath;
  final String? errorMessage;
  final DateTime? startTime;

  const CaptureState({
    this.isCapturing = false,
    this.pointCloudPacketCount = 0,
    this.pointCloudBytes = 0,
    this.imuPacketCount = 0,
    this.imuBytes = 0,
    this.filePath,
    this.errorMessage,
    this.startTime,
  });

  /// 总包数
  int get totalPacketCount => pointCloudPacketCount + imuPacketCount;

  /// 总字节数
  int get totalBytes => pointCloudBytes + imuBytes;

  CaptureState copyWith({
    bool? isCapturing,
    int? pointCloudPacketCount,
    int? pointCloudBytes,
    int? imuPacketCount,
    int? imuBytes,
    String? filePath,
    String? errorMessage,
    DateTime? startTime,
  }) {
    return CaptureState(
      isCapturing: isCapturing ?? this.isCapturing,
      pointCloudPacketCount:
          pointCloudPacketCount ?? this.pointCloudPacketCount,
      pointCloudBytes: pointCloudBytes ?? this.pointCloudBytes,
      imuPacketCount: imuPacketCount ?? this.imuPacketCount,
      imuBytes: imuBytes ?? this.imuBytes,
      filePath: filePath ?? this.filePath,
      errorMessage: errorMessage,
      startTime: startTime ?? this.startTime,
    );
  }

  /// 获取已写入数据大小（MB）
  double get totalMB => totalBytes / (1024 * 1024);

  /// 格式化字节数
  static String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 获取格式化的总数据大小
  String get formattedSize => formatBytes(totalBytes);

  /// 获取格式化的点云数据大小
  String get formattedPointCloudSize => formatBytes(pointCloudBytes);

  /// 获取格式化的 IMU 数据大小
  String get formattedImuSize => formatBytes(imuBytes);

  /// 获取运行时长
  String get runningDuration {
    if (startTime == null) return '--:--:--';
    final duration = DateTime.now().difference(startTime!);
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
