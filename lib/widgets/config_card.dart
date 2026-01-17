import 'package:flutter/material.dart';

/// 配置信息卡片（可折叠）
class ConfigCard extends StatefulWidget {
  final int pointCloudPort;
  final int imuPort;

  const ConfigCard({
    super.key,
    this.pointCloudPort = 56301,
    this.imuPort = 56401,
  });

  @override
  State<ConfigCard> createState() => _ConfigCardState();
}

class _ConfigCardState extends State<ConfigCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏（可点击展开/收起）
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.settings,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '连接配置',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 可展开的内容区域
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  _buildConfigItem(
                    icon: Icons.radar,
                    label: '点云数据端口',
                    value: widget.pointCloudPort.toString(),
                    color: Colors.blue,
                  ),
                  const Divider(height: 24),
                  _buildConfigItem(
                    icon: Icons.sensors,
                    label: 'IMU 数据端口',
                    value: widget.imuPort.toString(),
                    color: Colors.orange,
                  ),
                  const Divider(height: 24),
                  _buildConfigItem(
                    icon: Icons.wifi,
                    label: '传输协议',
                    value: 'UDP 单播',
                    color: Colors.grey,
                  ),
                  const Divider(height: 24),
                  _buildConfigItem(
                    icon: Icons.save_alt,
                    label: '保存格式',
                    value: 'PCAP',
                    color: Colors.green,
                  ),
                ],
              ),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigItem({
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: TextStyle(color: Colors.grey.shade600)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: (color ?? Colors.blue).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color ?? Colors.blue.shade700,
            ),
          ),
        ),
      ],
    );
  }
}
