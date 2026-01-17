import 'dart:io';

/// 采集文件模型
class CaptureFile {
  final String name;
  final String path;
  final int size;
  final DateTime modifiedTime;
  final String extension;

  CaptureFile({
    required this.name,
    required this.path,
    required this.size,
    required this.modifiedTime,
    required this.extension,
  });

  /// 从 File 创建 CaptureFile
  static Future<CaptureFile> fromFile(File file) async {
    final stat = await file.stat();
    final name = file.path.split(Platform.pathSeparator).last;
    final extension = name.contains('.') ? name.split('.').last : '';

    return CaptureFile(
      name: name,
      path: file.path,
      size: stat.size,
      modifiedTime: stat.modified,
      extension: extension,
    );
  }

  /// 格式化文件大小
  String get formattedSize {
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(2)} KB';
    } else if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 格式化修改时间
  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(modifiedTime);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes} 分钟前';
    } else if (diff.inDays < 1) {
      return '${diff.inHours} 小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    } else {
      return '${modifiedTime.year}-${modifiedTime.month.toString().padLeft(2, '0')}-${modifiedTime.day.toString().padLeft(2, '0')}';
    }
  }

  /// 获取详细的修改时间
  String get detailedTime {
    return '${modifiedTime.year}-${modifiedTime.month.toString().padLeft(2, '0')}-${modifiedTime.day.toString().padLeft(2, '0')} '
        '${modifiedTime.hour.toString().padLeft(2, '0')}:${modifiedTime.minute.toString().padLeft(2, '0')}:${modifiedTime.second.toString().padLeft(2, '0')}';
  }

  /// 获取文件类型图标
  String get fileTypeDescription {
    switch (extension.toLowerCase()) {
      case 'pcap':
        return 'PCAP 网络数据包';
      case 'bin':
        return '二进制数据';
      default:
        return '未知类型';
    }
  }
}
