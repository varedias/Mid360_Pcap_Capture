import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../utils/pcap_writer.dart';

/// UDP 端口配置
class UdpPortConfig {
  final int port;
  final String name;

  const UdpPortConfig({required this.port, required this.name});
}

/// UDP 接收器配置
class UdpReceiverConfig {
  final List<UdpPortConfig> ports;
  final String filePath;
  final int bufferSize;
  final int flushInterval; // 毫秒
  final String? localIp; // 本机 IP，用于 PCAP 记录

  const UdpReceiverConfig({
    required this.ports,
    required this.filePath,
    this.bufferSize = 65536, // 64KB 接收缓冲区
    this.flushInterval = 1000, // 每秒刷新一次
    this.localIp,
  });
}

/// Isolate 间通信消息类型
enum MessageType { start, stop, stats, error, stopped }

/// Isolate 间通信消息
class IsolateMessage {
  final MessageType type;
  final dynamic data;

  IsolateMessage(this.type, [this.data]);
}

/// 统计数据
class CaptureStats {
  final int pointCloudPacketCount;
  final int pointCloudBytes;
  final int imuPacketCount;
  final int imuBytes;

  CaptureStats({
    this.pointCloudPacketCount = 0,
    this.pointCloudBytes = 0,
    this.imuPacketCount = 0,
    this.imuBytes = 0,
  });

  int get totalPacketCount => pointCloudPacketCount + imuPacketCount;
  int get totalBytes => pointCloudBytes + imuBytes;
}

/// UDP 点云数据接收服务
/// 使用 Isolate 实现高性能异步接收，避免阻塞 UI
class UdpCaptureService {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;

  final StreamController<CaptureStats> _statsController =
      StreamController<CaptureStats>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  final StreamController<bool> _stoppedController =
      StreamController<bool>.broadcast();

  /// 统计数据流
  Stream<CaptureStats> get statsStream => _statsController.stream;

  /// 错误流
  Stream<String> get errorStream => _errorController.stream;

  /// 停止通知流
  Stream<bool> get stoppedStream => _stoppedController.stream;

  /// 启动 UDP 接收
  Future<void> startCapture(UdpReceiverConfig config) async {
    // 清理之前的 Isolate
    await stopCapture();

    _receivePort = ReceivePort();

    // 启动 Isolate
    _isolate = await Isolate.spawn(
      _udpReceiverIsolate,
      _IsolateStartParams(sendPort: _receivePort!.sendPort, config: config),
    );

    // 监听 Isolate 消息
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
      } else if (message is IsolateMessage) {
        switch (message.type) {
          case MessageType.stats:
            final stats = message.data as CaptureStats;
            _statsController.add(stats);
            break;
          case MessageType.error:
            _errorController.add(message.data as String);
            break;
          case MessageType.stopped:
            _stoppedController.add(true);
            break;
          default:
            break;
        }
      }
    });
  }

  /// 停止 UDP 接收
  Future<void> stopCapture() async {
    if (_sendPort != null) {
      _sendPort!.send(IsolateMessage(MessageType.stop));
      // 等待停止完成
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;
  }

  /// 释放资源
  void dispose() {
    stopCapture();
    _statsController.close();
    _errorController.close();
    _stoppedController.close();
  }
}

/// Isolate 启动参数
class _IsolateStartParams {
  final SendPort sendPort;
  final UdpReceiverConfig config;

  _IsolateStartParams({required this.sendPort, required this.config});
}

/// UDP 接收 Isolate 入口函数
/// 在独立线程中运行，不影响 UI
void _udpReceiverIsolate(_IsolateStartParams params) async {
  final sendPort = params.sendPort;
  final config = params.config;

  // 创建接收端口用于接收停止命令
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  final sockets = <int, RawDatagramSocket>{};
  RandomAccessFile? file;
  bool running = true;

  // 分类统计
  int pointCloudPacketCount = 0;
  int pointCloudBytes = 0;
  int imuPacketCount = 0;
  int imuBytes = 0;

  // 端口映射
  final portNameMap = <int, String>{};
  for (final portConfig in config.ports) {
    portNameMap[portConfig.port] = portConfig.name;
  }

  // 点云端口（56301）和 IMU 端口（56401）
  const pointCloudPort = 56301;
  const imuPort = 56401;

  // 写入缓冲区 - 使用较大的缓冲区减少系统调用
  final writeBuffer = BytesBuilder(copy: false);
  const writeBufferThreshold = 256 * 1024; // 256KB 缓冲区阈值

  // 获取本机 IP
  String localIp = config.localIp ?? '0.0.0.0';

  try {
    // 尝试获取本机实际 IP
    if (localIp == '0.0.0.0') {
      try {
        final interfaces = await NetworkInterface.list();
        for (final interface in interfaces) {
          for (final addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
              localIp = addr.address;
              break;
            }
          }
          if (localIp != '0.0.0.0') break;
        }
      } catch (_) {}
    }

    // 绑定所有 UDP 端口
    for (final portConfig in config.ports) {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        portConfig.port,
        reuseAddress: true,
        reusePort: true,
      );
      socket.readEventsEnabled = true;
      sockets[portConfig.port] = socket;
    }

    // 打开文件进行写入
    file = await File(config.filePath).open(mode: FileMode.write);

    // 写入 PCAP 全局文件头
    final globalHeader = PcapWriter.generateGlobalHeader();
    file.writeFromSync(globalHeader);

    // 监听停止命令
    receivePort.listen((message) {
      if (message is IsolateMessage && message.type == MessageType.stop) {
        running = false;
      }
    });

    // 定时发送统计数据并刷新缓冲区
    Timer.periodic(Duration(milliseconds: config.flushInterval), (timer) {
      if (!running) {
        timer.cancel();
        return;
      }

      // 刷新缓冲区
      if (writeBuffer.length > 0) {
        final data = writeBuffer.takeBytes();
        file?.writeFromSync(data);
      }

      // 发送统计
      sendPort.send(
        IsolateMessage(
          MessageType.stats,
          CaptureStats(
            pointCloudPacketCount: pointCloudPacketCount,
            pointCloudBytes: pointCloudBytes,
            imuPacketCount: imuPacketCount,
            imuBytes: imuBytes,
          ),
        ),
      );
    });

    // 为每个 socket 设置监听
    final socketSubscriptions = <StreamSubscription>[];

    for (final entry in sockets.entries) {
      final port = entry.key;
      final socket = entry.value;

      final subscription = socket.listen((event) {
        if (!running) return;

        if (event == RawSocketEvent.read) {
          // 持续读取直到没有数据
          while (running) {
            final datagram = socket.receive();
            if (datagram == null) break;

            final now = DateTime.now();

            // PCAP 格式：生成完整的数据包（包头 + IP头 + UDP头 + 数据）
            final pcapPacket = PcapWriter.generatePacket(
              payload: datagram.data,
              srcIp: datagram.address.address,
              dstIp: localIp,
              srcPort: datagram.port,
              dstPort: port,
              timestamp: now,
            );
            writeBuffer.add(pcapPacket);

            // 根据端口分类统计
            if (port == pointCloudPort) {
              pointCloudPacketCount++;
              pointCloudBytes += pcapPacket.length;
            } else if (port == imuPort) {
              imuPacketCount++;
              imuBytes += pcapPacket.length;
            }

            // 当缓冲区达到阈值时写入文件
            if (writeBuffer.length >= writeBufferThreshold) {
              final data = writeBuffer.takeBytes();
              file?.writeFromSync(data);
            }
          }
        }
      });
      socketSubscriptions.add(subscription);
    }

    // 等待直到停止
    while (running) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 取消所有订阅
    for (final sub in socketSubscriptions) {
      await sub.cancel();
    }
  } catch (e) {
    sendPort.send(IsolateMessage(MessageType.error, e.toString()));
  } finally {
    // 清理资源

    // 写入剩余缓冲区数据
    if (writeBuffer.length > 0 && file != null) {
      final data = writeBuffer.takeBytes();
      file.writeFromSync(data);
    }

    // 刷新并关闭文件
    if (file != null) {
      file.flushSync();
      file.closeSync();
    }

    // 关闭所有 Socket
    for (final socket in sockets.values) {
      socket.close();
    }

    // 发送最终统计
    sendPort.send(
      IsolateMessage(
        MessageType.stats,
        CaptureStats(
          pointCloudPacketCount: pointCloudPacketCount,
          pointCloudBytes: pointCloudBytes,
          imuPacketCount: imuPacketCount,
          imuBytes: imuBytes,
        ),
      ),
    );

    // 通知已停止
    sendPort.send(IsolateMessage(MessageType.stopped));
  }
}
