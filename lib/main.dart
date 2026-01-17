import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'controllers/capture_controller.dart';
import 'widgets/capture_control_card.dart';
import 'widgets/stats_card.dart';
import 'widgets/config_card.dart';
import 'pages/file_manager_page.dart';

void main() {
  runApp(const MID360CaptureApp());
}

class MID360CaptureApp extends StatelessWidget {
  const MID360CaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MID-360 点云采集',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late CaptureController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = CaptureController(
      pointCloudPort: 56301,
      imuPort: 56401,
      getStorageDirectory: _getStorageDirectory,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 当应用进入后台或被销毁时，停止采集
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_controller.state.isCapturing) {
        _controller.stopCapture();
      }
    }
  }

  /// 获取存储目录
  Future<String> _getStorageDirectory() async {
    Directory directory;

    if (Platform.isAndroid) {
      // Android: 使用外部存储的 Documents 目录
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        directory = Directory('${externalDir.path}/MID360');
      } else {
        // 回退到应用私有目录
        final appDir = await getApplicationDocumentsDirectory();
        directory = Directory('${appDir.path}/MID360');
      }
    } else {
      // 其他平台：使用 Documents 目录
      final docDir = await getApplicationDocumentsDirectory();
      directory = Directory('${docDir.path}/MID360');
    }

    // 确保目录存在
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory.path;
  }

  /// 打开文件管理器
  Future<void> _openFileManager(BuildContext context) async {
    final storageDir = await _getStorageDirectory();
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FileManagerPage(storageDirectory: storageDir),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              Icon(Icons.radar),
              SizedBox(width: 8),
              Text('MID-360 点云采集'),
            ],
          ),
          elevation: 2,
          actions: [
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: '文件管理',
              onPressed: () => _openFileManager(context),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 采集控制卡片
                const CaptureControlCard(),
                const SizedBox(height: 16),

                // 统计信息卡片
                const StatsCard(),
                const SizedBox(height: 16),

                // 配置信息卡片
                const ConfigCard(pointCloudPort: 56301, imuPort: 56401),
                const SizedBox(height: 16),

                // 文件管理快捷入口
                _buildFileManagerCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileManagerCard() {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () => _openFileManager(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.folder_open,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '文件管理',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '查看和管理已采集的数据文件',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey.shade400,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
