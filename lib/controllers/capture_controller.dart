import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/capture_state.dart';
import '../services/udp_capture_service.dart';

/// 采集控制器
/// 管理采集状态和 UDP 服务
class CaptureController extends ChangeNotifier {
  final UdpCaptureService _udpService = UdpCaptureService();

  CaptureState _state = const CaptureState();
  CaptureState get state => _state;

  StreamSubscription? _statsSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _stoppedSubscription;
  Timer? _durationTimer;

  /// 点云监听端口
  final int pointCloudPort;

  /// IMU 监听端口
  final int imuPort;

  /// 获取保存文件的目录路径
  final Future<String> Function() getStorageDirectory;

  CaptureController({
    this.pointCloudPort = 56301,
    this.imuPort = 56401,
    required this.getStorageDirectory,
  }) {
    _setupListeners();
  }

  void _setupListeners() {
    // 监听统计数据
    _statsSubscription = _udpService.statsStream.listen((stats) {
      _state = _state.copyWith(
        pointCloudPacketCount: stats.pointCloudPacketCount,
        pointCloudBytes: stats.pointCloudBytes,
        imuPacketCount: stats.imuPacketCount,
        imuBytes: stats.imuBytes,
      );
      notifyListeners();
    });

    // 监听错误
    _errorSubscription = _udpService.errorStream.listen((error) {
      _state = _state.copyWith(errorMessage: error, isCapturing: false);
      _stopDurationTimer();
      notifyListeners();
    });

    // 监听停止通知
    _stoppedSubscription = _udpService.stoppedStream.listen((_) {
      _state = _state.copyWith(isCapturing: false);
      _stopDurationTimer();
      notifyListeners();
    });
  }

  /// 检查本机是否有 192.168.1.50 的 IP 地址
  Future<bool> _checkLocalIP() async {
    const requiredIP = '192.168.1.50';
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.address == requiredIP) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// 获取当前所有 IP 地址（用于错误提示）
  Future<List<String>> _getAllLocalIPs() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final ips = <String>[];
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          ips.add('${interface.name}: ${addr.address}');
        }
      }
      return ips;
    } catch (e) {
      return [];
    }
  }

  /// 开始采集
  Future<void> startCapture() async {
    if (_state.isCapturing) return;

    try {
      // 检查 IP 地址
      final hasCorrectIP = await _checkLocalIP();
      if (!hasCorrectIP) {
        final currentIPs = await _getAllLocalIPs();
        final ipList = currentIPs.isEmpty
            ? '无可用网络'
            : currentIPs.join('\n');
        _state = _state.copyWith(
          errorMessage:
              '无法连接雷达：本机IP不是192.168.1.50\n\n当前IP地址:\n$ipList\n\n请确保已正确配置网络连接',
        );
        notifyListeners();
        return;
      }

      // 生成文件名（包含时间戳）
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final directory = await getStorageDirectory();

      final filePath = '$directory/mid360_capture_$timestamp.pcap';

      // 配置 UDP 接收器 - 监听两个端口
      final config = UdpReceiverConfig(
        ports: [
          UdpPortConfig(port: pointCloudPort, name: 'PointCloud'),
          UdpPortConfig(port: imuPort, name: 'IMU'),
        ],
        filePath: filePath,
        bufferSize: 65536,
        flushInterval: 500, // 500ms 刷新一次
      );

      // 更新状态
      _state = CaptureState(
        isCapturing: true,
        pointCloudPacketCount: 0,
        pointCloudBytes: 0,
        imuPacketCount: 0,
        imuBytes: 0,
        filePath: filePath,
        startTime: DateTime.now(),
      );
      notifyListeners();

      // 启动定时器更新时长显示
      _startDurationTimer();

      // 启动 UDP 服务
      await _udpService.startCapture(config);
    } catch (e) {
      _state = _state.copyWith(isCapturing: false, errorMessage: '启动失败: $e');
      _stopDurationTimer();
      notifyListeners();
    }
  }

  /// 停止采集
  Future<void> stopCapture() async {
    if (!_state.isCapturing) return;

    await _udpService.stopCapture();

    _state = _state.copyWith(isCapturing: false);
    _stopDurationTimer();
    notifyListeners();
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // 仅触发重建以更新时长显示
      notifyListeners();
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  /// 清除错误消息
  void clearError() {
    _state = _state.copyWith(errorMessage: null);
    notifyListeners();
  }

  @override
  void dispose() {
    _statsSubscription?.cancel();
    _errorSubscription?.cancel();
    _stoppedSubscription?.cancel();
    _stopDurationTimer();
    _udpService.dispose();
    super.dispose();
  }
}
