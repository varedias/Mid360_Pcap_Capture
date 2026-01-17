import 'dart:io';
import '../models/capture_file.dart';

/// 文件管理服务
class FileManagerService {
  final String storageDirectory;

  FileManagerService({required this.storageDirectory});

  /// 获取所有采集文件
  Future<List<CaptureFile>> getAllFiles() async {
    final directory = Directory(storageDirectory);

    if (!await directory.exists()) {
      return [];
    }

    final files = <CaptureFile>[];

    await for (final entity in directory.list()) {
      if (entity is File) {
        final name = entity.path.split(Platform.pathSeparator).last;
        // 只显示 pcap 和 bin 文件
        if (name.endsWith('.pcap') || name.endsWith('.bin')) {
          files.add(await CaptureFile.fromFile(entity));
        }
      }
    }

    // 按修改时间倒序排列（最新的在前面）
    files.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));

    return files;
  }

  /// 删除文件
  Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 删除多个文件
  Future<int> deleteFiles(List<String> filePaths) async {
    int deletedCount = 0;
    for (final path in filePaths) {
      if (await deleteFile(path)) {
        deletedCount++;
      }
    }
    return deletedCount;
  }

  /// 获取目录总大小
  Future<int> getTotalSize() async {
    final files = await getAllFiles();
    return files.fold<int>(0, (sum, file) => sum + file.size);
  }

  /// 格式化总大小
  static String formatSize(int bytes) {
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

  /// 重命名文件
  Future<bool> renameFile(String oldPath, String newName) async {
    try {
      final file = File(oldPath);
      if (!await file.exists()) return false;

      final directory = file.parent.path;
      final newPath = '$directory${Platform.pathSeparator}$newName';

      await file.rename(newPath);
      return true;
    } catch (e) {
      return false;
    }
  }
}
