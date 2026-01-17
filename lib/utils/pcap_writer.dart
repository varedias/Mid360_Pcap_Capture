import 'dart:typed_data';

/// PCAP 文件格式工具类
/// 支持生成标准 PCAP 文件格式，可被 Wireshark 等工具解析
class PcapWriter {
  /// PCAP 魔数（小端序）
  static const int pcapMagicNumber = 0xa1b2c3d4;

  /// PCAP 主版本号
  static const int versionMajor = 2;

  /// PCAP 次版本号
  static const int versionMinor = 4;

  /// 最大捕获长度
  static const int snapLen = 65535;

  /// 链路层类型：Raw IP (101) - 不包含以太网头
  static const int linkTypeRawIP = 101;

  /// 链路层类型：Ethernet (1) - 包含以太网头
  static const int linkTypeEthernet = 1;

  /// IP 协议版本 4
  static const int ipVersion = 4;

  /// UDP 协议号
  static const int ipProtocolUDP = 17;

  /// 生成 PCAP 全局文件头（24字节）
  ///
  /// 文件头结构:
  /// - magic_number: 4字节
  /// - version_major: 2字节
  /// - version_minor: 2字节
  /// - thiszone: 4字节 (GMT偏移)
  /// - sigfigs: 4字节 (时间戳精度)
  /// - snaplen: 4字节 (最大捕获长度)
  /// - network: 4字节 (链路层类型)
  static Uint8List generateGlobalHeader({bool useEthernet = false}) {
    final buffer = ByteData(24);

    // Magic number (小端序)
    buffer.setUint32(0, pcapMagicNumber, Endian.little);

    // Version major
    buffer.setUint16(4, versionMajor, Endian.little);

    // Version minor
    buffer.setUint16(6, versionMinor, Endian.little);

    // Timezone offset (GMT)
    buffer.setInt32(8, 0, Endian.little);

    // Timestamp accuracy
    buffer.setUint32(12, 0, Endian.little);

    // Snap length
    buffer.setUint32(16, snapLen, Endian.little);

    // Link-layer type
    buffer.setUint32(
      20,
      useEthernet ? linkTypeEthernet : linkTypeRawIP,
      Endian.little,
    );

    return buffer.buffer.asUint8List();
  }

  /// 生成 PCAP 数据包（包头 + IP头 + UDP头 + 数据）
  ///
  /// [payload] - UDP 负载数据
  /// [srcIp] - 源 IP 地址
  /// [dstIp] - 目标 IP 地址
  /// [srcPort] - 源端口
  /// [dstPort] - 目标端口
  /// [timestamp] - 时间戳（可选，默认当前时间）
  static Uint8List generatePacket({
    required Uint8List payload,
    required String srcIp,
    required String dstIp,
    required int srcPort,
    required int dstPort,
    DateTime? timestamp,
  }) {
    timestamp ??= DateTime.now();

    // 计算各部分长度
    const ipHeaderLen = 20;
    const udpHeaderLen = 8;
    final udpLen = udpHeaderLen + payload.length;
    final ipTotalLen = ipHeaderLen + udpLen;
    final packetLen = ipTotalLen; // Raw IP 模式不含以太网头

    // PCAP 包头（16字节）+ IP头（20字节）+ UDP头（8字节）+ 数据
    final totalLen = 16 + packetLen;
    final buffer = ByteData(totalLen);
    var offset = 0;

    // === PCAP Packet Header (16 bytes) ===
    // 时间戳（秒）
    buffer.setUint32(
      offset,
      timestamp.millisecondsSinceEpoch ~/ 1000,
      Endian.little,
    );
    offset += 4;

    // 时间戳（微秒）
    buffer.setUint32(
      offset,
      (timestamp.microsecondsSinceEpoch % 1000000),
      Endian.little,
    );
    offset += 4;

    // 捕获的数据长度
    buffer.setUint32(offset, packetLen, Endian.little);
    offset += 4;

    // 原始数据长度
    buffer.setUint32(offset, packetLen, Endian.little);
    offset += 4;

    // === IP Header (20 bytes) ===
    // Version (4) + IHL (5) = 0x45
    buffer.setUint8(offset, 0x45);
    offset += 1;

    // DSCP + ECN
    buffer.setUint8(offset, 0x00);
    offset += 1;

    // Total Length (大端序)
    buffer.setUint16(offset, ipTotalLen, Endian.big);
    offset += 2;

    // Identification
    buffer.setUint16(offset, 0, Endian.big);
    offset += 2;

    // Flags + Fragment Offset
    buffer.setUint16(offset, 0x4000, Endian.big); // Don't fragment
    offset += 2;

    // TTL
    buffer.setUint8(offset, 64);
    offset += 1;

    // Protocol (UDP = 17)
    buffer.setUint8(offset, ipProtocolUDP);
    offset += 1;

    // Header Checksum (先设为0，后面计算)
    final checksumOffset = offset;
    buffer.setUint16(offset, 0, Endian.big);
    offset += 2;

    // Source IP
    final srcIpBytes = _parseIpAddress(srcIp);
    for (var i = 0; i < 4; i++) {
      buffer.setUint8(offset + i, srcIpBytes[i]);
    }
    offset += 4;

    // Destination IP
    final dstIpBytes = _parseIpAddress(dstIp);
    for (var i = 0; i < 4; i++) {
      buffer.setUint8(offset + i, dstIpBytes[i]);
    }
    offset += 4;

    // 计算 IP 头校验和
    final ipChecksum = _calculateIPChecksum(buffer, 16, ipHeaderLen);
    buffer.setUint16(checksumOffset, ipChecksum, Endian.big);

    // === UDP Header (8 bytes) ===
    // Source Port
    buffer.setUint16(offset, srcPort, Endian.big);
    offset += 2;

    // Destination Port
    buffer.setUint16(offset, dstPort, Endian.big);
    offset += 2;

    // UDP Length
    buffer.setUint16(offset, udpLen, Endian.big);
    offset += 2;

    // UDP Checksum (设为0，UDP校验和可选)
    buffer.setUint16(offset, 0, Endian.big);
    offset += 2;

    // === UDP Payload ===
    final result = buffer.buffer.asUint8List();

    // 复制 payload 数据
    for (var i = 0; i < payload.length; i++) {
      result[offset + i] = payload[i];
    }

    return result;
  }

  /// 解析 IP 地址字符串为字节数组
  static List<int> _parseIpAddress(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return [0, 0, 0, 0];
    }
    return parts.map((p) => int.tryParse(p) ?? 0).toList();
  }

  /// 计算 IP 头校验和
  static int _calculateIPChecksum(ByteData buffer, int offset, int length) {
    var sum = 0;

    for (var i = 0; i < length; i += 2) {
      sum += buffer.getUint16(offset + i, Endian.big);
    }

    // 将进位加回
    while (sum > 0xFFFF) {
      sum = (sum & 0xFFFF) + (sum >> 16);
    }

    // 取反
    return (~sum) & 0xFFFF;
  }
}

/// PCAP 数据包信息
class PcapPacketInfo {
  final String srcIp;
  final String dstIp;
  final int srcPort;
  final int dstPort;

  const PcapPacketInfo({
    required this.srcIp,
    required this.dstIp,
    required this.srcPort,
    required this.dstPort,
  });
}
