# Livox MID-360 点云数据采集应用

基于 Flutter 开发的 Android 应用，用于接收并保存 Livox MID-360 激光雷达的 UDP 点云数据。

## 功能特性

- ✅ 通过 UDP Socket 直接接收雷达点云数据
- ✅ 支持 UDP 单播模式
- ✅ 高效的数据写入，避免丢包
- ✅ **支持 PCAP 格式保存**（可用 Wireshark 打开分析）
- ✅ 支持原始二进制格式保存
- ✅ 实时显示采集状态和统计信息

## 项目结构

```
lib/
├── main.dart                          # 应用入口和主界面
├── models/
│   └── capture_state.dart             # 采集状态模型
├── controllers/
│   └── capture_controller.dart        # 采集控制器
├── services/
│   └── udp_capture_service.dart       # UDP 接收服务（核心）
├── utils/
│   └── pcap_writer.dart               # PCAP 格式写入工具
└── widgets/
    ├── capture_control_card.dart      # 控制按钮组件
    ├── stats_card.dart                # 统计信息组件
    └── config_card.dart               # 配置信息组件
```

## 保存格式说明

### PCAP 格式（推荐）
- 标准网络抓包格式，可用 **Wireshark** 直接打开
- 包含完整的 IP 头和 UDP 头信息
- 文件扩展名: `.pcap`
- 包含时间戳、源/目标 IP、端口等元数据

### RAW 格式
- 原始 UDP payload 数据
- 不包含任何协议头
- 文件扩展名: `.bin`
- 文件体积更小

## PCAP 文件结构

```
┌─────────────────────────────────────┐
│      PCAP Global Header (24B)       │  ← 文件头，只写一次
├─────────────────────────────────────┤
│      Packet Header (16B)            │  ← 每个UDP包的头
│      IP Header (20B)                │
│      UDP Header (8B)                │
│      UDP Payload (变长)              │  ← 点云数据
├─────────────────────────────────────┤
│      Packet Header (16B)            │
│      IP Header (20B)                │
│      UDP Header (8B)                │
│      UDP Payload (变长)              │
├─────────────────────────────────────┤
│              ...                    │
└─────────────────────────────────────┘
```

## 核心架构设计

### 1. 线程/Isolate 模型

```
┌─────────────────────────────────────────────────────────────┐
│                      Main Isolate (UI)                       │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │ CaptureController│───▶│ UdpCaptureService              │ │
│  │   (状态管理)     │    │  - 启动/停止 Isolate           │ │
│  └─────────────────┘    │  - 接收统计数据                 │ │
│                         └─────────────────────────────────┘ │
└───────────────────────────────────┬─────────────────────────┘
                                    │ SendPort/ReceivePort
                                    ▼
┌─────────────────────────────────────────────────────────────┐
│                   Worker Isolate (UDP接收)                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                                                          ││
│  │  RawDatagramSocket ─▶ PcapWriter ─▶ BytesBuilder ─▶ File││
│  │     (UDP接收)        (封装PCAP)    (写入缓冲区)   (磁盘) ││
│  │                                                          ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### 2. 关键组件说明

| 组件 | 职责 |
|------|------|
| `UdpCaptureService` | 管理 Isolate 生命周期，与 Worker 通信 |
| `Worker Isolate` | 独立线程执行 UDP 接收和文件写入 |
| `PcapWriter` | 生成标准 PCAP 格式数据 |
| `CaptureController` | 业务逻辑控制，状态管理 |
| `CaptureState` | 不可变状态模型 |

## 防丢包策略

### 1. 使用独立 Isolate 接收数据
- UDP 接收在独立 Isolate 中运行，**完全不受 UI 线程影响**
- 即使 UI 卡顿，数据接收也不会中断

### 2. 批量写入策略
```dart
// 使用 BytesBuilder 累积数据
final writeBuffer = BytesBuilder(copy: false);
const writeBufferThreshold = 256 * 1024; // 256KB 缓冲区阈值

// 当缓冲区达到阈值时批量写入
if (writeBuffer.length >= writeBufferThreshold) {
  final data = writeBuffer.takeBytes();
  file.writeFromSync(data);
}
```

### 3. 连续读取模式
```dart
// 一次事件中读取所有可用数据
while (running) {
  final datagram = socket.receive();
  if (datagram == null) break;
  writeBuffer.add(datagram.data);
}
```

### 4. 定时刷新
```dart
// 每 500ms 刷新一次缓冲区，确保数据不会长时间停留在内存
Timer.periodic(Duration(milliseconds: 500), (timer) {
  if (writeBuffer.length > 0) {
    final data = writeBuffer.takeBytes();
    file.writeFromSync(data);
  }
});
```

## 数据完整性保证

### 1. 正确的关闭流程
```dart
finally {
  // 1. 写入剩余缓冲区数据
  if (writeBuffer.length > 0 && file != null) {
    final data = writeBuffer.takeBytes();
    file.writeFromSync(data);
  }
  
  // 2. 显式刷新文件缓冲区
  file.flushSync();
  
  // 3. 关闭文件句柄
  file.closeSync();
  
  // 4. 关闭 Socket
  socket?.close();
}
```

### 2. 生命周期管理
```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  // 应用进入后台时自动停止采集
  if (state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached) {
    if (_controller.state.isCapturing) {
      _controller.stopCapture();
    }
  }
}
```

## 端口配置

| 参数 | 值 | 说明 |
|------|------|------|
| 雷达源端口 | 56300 | Livox MID-360 发送数据的端口 |
| 本机监听端口 | 56301 | Android 设备接收数据的端口 |

## 所需权限

```xml
<!-- AndroidManifest.xml -->

<!-- 网络权限 - UDP Socket 通信必需 -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />

<!-- 存储权限 - 用于保存点云数据文件 -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />

<!-- 保持唤醒 - 长时间采集时防止休眠 -->
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

## 数据存储

- **PCAP 格式**: `.pcap` 文件（可用 Wireshark 打开）
- **RAW 格式**: `.bin` 原始二进制文件
- **文件命名**: `mid360_pointcloud_<timestamp>.<pcap|bin>`
- **存储路径**: `/Android/data/com.livox.mid360_capture/files/MID360/`

## 使用 Wireshark 查看 PCAP 文件

1. 将 `.pcap` 文件从手机复制到电脑
2. 用 Wireshark 打开文件
3. 可以看到每个 UDP 数据包的：
   - 时间戳
   - 源 IP 和端口
   - 目标 IP 和端口  
   - UDP payload（点云数据）
4. 使用过滤器 `udp.port == 56301` 筛选数据

## 编译运行

```bash
# 获取依赖
flutter pub get

# 分析代码
flutter analyze

# 编译 APK
flutter build apk --release

# 或直接运行
flutter run
```

## 使用流程

1. **网络配置**: 确保 Android 设备与 MID-360 在同一局域网
2. **雷达配置**: 将雷达的目标 IP 设置为 Android 设备 IP，目标端口设置为 56301
3. **开始采集**: 点击"开始采集"按钮
4. **监控状态**: 观察 UDP 包数量和数据大小是否增长
5. **停止采集**: 点击"停止采集"按钮，数据将自动保存

## 性能指标

- **设计目标**: 支持 MID-360 最大数据速率 (~10MB/s)
- **缓冲区大小**: 256KB 写入缓冲区
- **刷新间隔**: 500ms 统计更新，1000ms 定时刷盘
- **支持时长**: 理论上可支持数小时连续采集（取决于存储空间）

## 技术栈

- **Flutter**: 跨平台 UI 框架
- **Dart Isolate**: 多线程处理
- **RawDatagramSocket**: UDP 网络通信
- **Provider**: 状态管理
- **path_provider**: 文件路径管理
