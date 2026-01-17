import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'overlay_main.dart';
import 'declaration.dart';
import 'app_config.dart';
import 'stats_service.dart';

@pragma("vm:entry-point")
void overlayMain() {
  // 1. 显式初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  print("LOG: [Overlay] 物理入口触发");

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      // 这里的 Scaffold 必须有，否则透明背景和手势可能冲突
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: BossOverlayWindow(),
      ),
    ),
  );
}

void main() async {
  // 1. 立即初始化并启动 UI
  WidgetsFlutterBinding.ensureInitialized();
  
  // 加载持久化设置
  await GlobalStore.loadSettings();
  
  // 启动统计上报 (不阻塞UI)
  StatsService.checkAndUpload();
  
  runApp(const MaterialApp(home: MainScreen()));

  // 2. 异步启动桥接服务器
  try {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0); 
    GlobalStore.bridgePort = server.port;
    print("DEBUG: [Main] Bridge Server started on port: ${GlobalStore.bridgePort}");

    server.listen((HttpRequest request) {
      final action = request.uri.queryParameters['action'];
      if (action != null) {
        print("DEBUG: [Main Bridge] Received command: $action");
        _handleGlobalAction(action);
      }
      request.response.statusCode = HttpStatus.ok;
      request.response.close();
    });
  } catch (e) {
    print("DEBUG: [Main] Bridge Server failed to start: $e");
  }
}

// 全局存储位置
class GlobalStore {
  static OverlayPosition? lastPosition;
  static int? bridgePort;

  // 默认值常量
  static const int defaultBallDiameter = 300;
  static const int defaultBossWidth = 2000;
  static const int defaultBossHeight = 4000;
  static const String defaultBallColor = "#448AFF"; // blueAccent
  static const double defaultBallOpacity = 1.0;

  // 默认尺寸配置（可持久化）
  static int ballDiameter = defaultBallDiameter;
  static int bossWidth = defaultBossWidth;
  static int bossHeight = defaultBossHeight;
  static String ballColor = defaultBallColor;
  static double ballOpacity = defaultBallOpacity;

  static Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    ballDiameter = prefs.getInt('ballDiameter') ?? defaultBallDiameter;
    bossWidth = prefs.getInt('bossWidth') ?? defaultBossWidth;
    bossHeight = prefs.getInt('bossHeight') ?? defaultBossHeight;
    ballColor = prefs.getString('ballColor') ?? defaultBallColor;
    ballOpacity = prefs.getDouble('ballOpacity') ?? defaultBallOpacity;

    final double? x = prefs.getDouble('lastPositionX');
    final double? y = prefs.getDouble('lastPositionY');
    if (x != null && y != null) {
      lastPosition = OverlayPosition(x, y);
      print("DEBUG: [Settings] Loaded last position: ($x, $y)");
    }
  }

  static Future<void> savePosition(OverlayPosition? pos) async {
    if (pos == null) return;
    lastPosition = pos;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('lastPositionX', pos.x);
    await prefs.setDouble('lastPositionY', pos.y);
    print("DEBUG: [Settings] Saved last position: (${pos.x}, ${pos.y})");
  }

  static Future<void> clearPosition() async {
    lastPosition = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lastPositionX');
    await prefs.remove('lastPositionY');
    print("DEBUG: [Settings] Cleared last position");
  }
}

// 同步状态给悬浮窗
void _updateOverlayState(bool isBoss) async {
  // 给 Overlay Isolate 一点启动时间
  //await Future.delayed(const Duration(milliseconds: 300)); 
  print("DEBUG: [Main] Syncing Port and Mode (isBoss: $isBoss) to Overlay");
  FlutterOverlayWindow.shareData("SET_PORT:${GlobalStore.bridgePort}");
  FlutterOverlayWindow.shareData("SET_MODE:${isBoss ? 'BOSS' : 'NORMAL'}");
  FlutterOverlayWindow.shareData("SET_STYLE:${GlobalStore.ballColor},${GlobalStore.ballOpacity}");
}

// 全局处理逻辑
void _handleGlobalAction(String action) async {
  if (action == "OPEN_APP") {
    const channel = MethodChannel('com.example.bosscome/launcher');
    try {
      await channel.invokeMethod('bringToForeground');
    } catch (e) {
      print("DEBUG: [Main] Failed to open app: $e");
    }
  } else if (action == "CLOSE_OVERLAY") {
    if (await FlutterOverlayWindow.isActive()) {
      final currentPos = await FlutterOverlayWindow.getOverlayPosition();
      await GlobalStore.savePosition(currentPos);
      await FlutterOverlayWindow.closeOverlay();
    }
  } else if (action == "ENTER_BOSS") {
    // 统计黑屏次数
    StatsService.recordBossEnter();

    // 记录并保存当前位置
    final currentPos = await FlutterOverlayWindow.getOverlayPosition();
    await GlobalStore.savePosition(currentPos);
    
    await FlutterOverlayWindow.closeOverlay();
    //await Future.delayed(const Duration(milliseconds: 100));
    _updateOverlayState(true);
    
    await FlutterOverlayWindow.showOverlay(
      height: GlobalStore.bossHeight,
      width: GlobalStore.bossWidth,
      alignment: OverlayAlignment.center,
      enableDrag: false,
      positionGravity: PositionGravity.none,
    );
  } else if (action == "EXIT_BOSS") {
    await FlutterOverlayWindow.closeOverlay();
    //await Future.delayed(const Duration(milliseconds: 100));
    _updateOverlayState(false);
    
    await FlutterOverlayWindow.showOverlay(
      height: GlobalStore.ballDiameter,
      width: GlobalStore.ballDiameter,
      alignment: OverlayAlignment.center,
      enableDrag: true,
      positionGravity: PositionGravity.none,
      startPosition: GlobalStore.lastPosition,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _diameterController = TextEditingController();
  final TextEditingController _bossWidthController = TextEditingController();
  final TextEditingController _bossHeightController = TextEditingController();
  Color _pickerColor = Colors.blueAccent;
  double _currentOpacity = 1.0;

  bool _showInstructions = false;
  final GlobalKey _infoIconKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _diameterController.text = GlobalStore.ballDiameter.toString();
    _bossWidthController.text = GlobalStore.bossWidth.toString();
    _bossHeightController.text = GlobalStore.bossHeight.toString();
    _pickerColor = _parseHexColor(GlobalStore.ballColor);
    // 透明度越大越透明，所以 UI 上的值 = 1.0 - 实际不透明度
    _currentOpacity = 1.0 - GlobalStore.ballOpacity;

    // 延迟一会显示说明，确保 UI 已加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() => _showInstructions = true);
    });
  }

  Color _parseHexColor(String hex) {
    hex = hex.replaceAll("#", "");
    if (hex.length == 6) hex = "FF$hex";
    return Color(int.parse(hex, radix: 16));
  }

  String _toHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择悬浮球颜色'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: _pickerColor,
            onColorChanged: (color) => setState(() => _pickerColor = color),
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            child: const Text('确定'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _checkPermission() async {
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      await FlutterOverlayWindow.requestPermission();
    }
  }

  Future<void> _saveSizes() async {
    final d = int.tryParse(_diameterController.text) ?? 300;
    final bw = int.tryParse(_bossWidthController.text) ?? 2000;
    final bh = int.tryParse(_bossHeightController.text) ?? 4000;
    final color = _toHex(_pickerColor);
    // UI 是透明度(1.0=全透)，保存的是不透明度(v = 1.0 - UI)
    final opacity = 1.0 - _currentOpacity;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('ballDiameter', d);
    await prefs.setInt('bossWidth', bw);
    await prefs.setInt('bossHeight', bh);
    await prefs.setString('ballColor', color);
    await prefs.setDouble('ballOpacity', opacity);

    setState(() {
      GlobalStore.ballDiameter = d;
      GlobalStore.bossWidth = bw;
      GlobalStore.bossHeight = bh;
      GlobalStore.ballColor = color;
      GlobalStore.ballOpacity = opacity;
    });

    if (await FlutterOverlayWindow.isActive()) {
      _updateOverlayState(false);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("设置已保存")),
    );
  }

  Future<void> _showResetConfirmDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("确认恢复默认？"),
          content: const Text("这将重置所有尺寸、颜色、透明度并清空悬浮球的记忆位置。"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("取消"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _resetSettings();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text("重置"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. 清空位置
    await GlobalStore.clearPosition();
    
    // 2. 恢复默认值
    await prefs.setInt('ballDiameter', GlobalStore.defaultBallDiameter);
    await prefs.setInt('bossWidth', GlobalStore.defaultBossWidth);
    await prefs.setInt('bossHeight', GlobalStore.defaultBossHeight);
    await prefs.setString('ballColor', GlobalStore.defaultBallColor);
    await prefs.setDouble('ballOpacity', GlobalStore.defaultBallOpacity);

    setState(() {
      GlobalStore.ballDiameter = GlobalStore.defaultBallDiameter;
      GlobalStore.bossWidth = GlobalStore.defaultBossWidth;
      GlobalStore.bossHeight = GlobalStore.defaultBossHeight;
      GlobalStore.ballColor = GlobalStore.defaultBallColor;
      GlobalStore.ballOpacity = GlobalStore.defaultBallOpacity;
      
      _diameterController.text = GlobalStore.ballDiameter.toString();
      _bossWidthController.text = GlobalStore.bossWidth.toString();
      _bossHeightController.text = GlobalStore.bossHeight.toString();
      _pickerColor = _parseHexColor(GlobalStore.ballColor);
      _currentOpacity = 1.0 - GlobalStore.ballOpacity;
    });

    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("已重置为默认配置")),
    );
  }

  Future<void> _resetPositionOnly() async {
    await GlobalStore.clearPosition();
    
    if (await FlutterOverlayWindow.isActive()) {
      // 如果当前悬浮窗开启中，重启它以应用位置更新
      await FlutterOverlayWindow.closeOverlay();
      _updateOverlayState(false);
      await FlutterOverlayWindow.showOverlay(
        height: GlobalStore.ballDiameter,
        width: GlobalStore.ballDiameter,
        alignment: OverlayAlignment.center,
        enableDrag: true,
        positionGravity: PositionGravity.none,
        startPosition: null, // 强制置空，使其回到 alignment 指定的 center
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("悬浮球位置已恢复到屏幕中央")),
    );
  }

  void _showAboutDialog() {
    Widget buildCopyableRow(String label, String value) {
      return InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("$label 已复制到剪贴板"),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              Text("$label: "),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.copy, size: 16, color: Colors.grey),
            ],
          ),
        ),
      );
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text("关于项目"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Boss Come", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Text("版本: ${AppConfig.version}"),
              const Divider(),
              Text("作者: ${AppConfig.author}"),
              const SizedBox(height: 5),
              buildCopyableRow("QQ群", AppConfig.qqGroup),
              buildCopyableRow("邮箱", AppConfig.email),
              buildCopyableRow("Git地址", AppConfig.githubUrl),
              const SizedBox(height: 10),
              const Text("开源协议: GNU GPLv3", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              const Text("(遵循 GPLv3 协议开源)"),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("LOG: [Main] MainScreen Build called");

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text("Boss Come 控制台"),
            actions: [
              IconButton(
                icon: const Icon(Icons.bar_chart),
                tooltip: "统计信息",
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("统计信息"),
                      content: FutureBuilder<int>(
                        future: StatsService.getLocalTotal(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const SizedBox(
                              height: 50,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return Text(
                            "本机累计摸鱼(切黑屏)次数: ${snapshot.data ?? 0}",
                            style: const TextStyle(fontSize: 16),
                          );
                        },
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text("关闭"),
                        ),
                      ],
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: "关于",
                onPressed: _showAboutDialog,
              ),
              IconButton(
                key: _infoIconKey,
                icon: const Icon(Icons.info_outline),
                tooltip: "使用说明",
                onPressed: () {
                  setState(() {
                    _showInstructions = true;
                  });
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text("悬浮球尺寸设置", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextField(
                  controller: _diameterController,
                  decoration: const InputDecoration(labelText: "直径 (Diameter)"),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _showColorPicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: _pickerColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text("点击选择颜色"),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("透明度: ${(_currentOpacity * 100).toInt()}%"),
                          Slider(
                            value: _currentOpacity,
                            onChanged: (v) => setState(() => _currentOpacity = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text("黑屏尺寸设置", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _bossWidthController,
                        decoration: const InputDecoration(labelText: "宽度"),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: TextField(
                        controller: _bossHeightController,
                        decoration: const InputDecoration(labelText: "高度"),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saveSizes,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("保存设置"),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _showResetConfirmDialog,
                        child: const Text("恢复默认参数"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _resetPositionOnly,
                    icon: const Icon(Icons.center_focus_strong_outlined, size: 18),
                    label: const Text("恢复悬浮球位置到中央"),
                  ),
                ),
                const Divider(height: 40),
                ElevatedButton(
                  onPressed: () async {
                    debugPrint("LOG: [Main] Toggle Button Pressed");
                    if (await FlutterOverlayWindow.isActive()) {
                      debugPrint("LOG: [Main] Overlay is active, saving position and closing...");
                      final currentPos = await FlutterOverlayWindow.getOverlayPosition();
                      await GlobalStore.savePosition(currentPos);
                      await FlutterOverlayWindow.closeOverlay();
                    } else {
                      _updateOverlayState(false);

                      debugPrint("LOG: [Main] Overlay not active, showing it...");
                      await FlutterOverlayWindow.showOverlay(
                        height: GlobalStore.ballDiameter,
                        width: GlobalStore.ballDiameter,
                        alignment: OverlayAlignment.center,
                        enableDrag: true,
                        positionGravity: PositionGravity.none,
                        startPosition: GlobalStore.lastPosition,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text("启动/关闭悬浮窗"),
                ),
              ],
            ),
          ),
        ),
        InstructionOverlay(
          isVisible: _showInstructions,
          targetKey: _infoIconKey,
          onDismissed: () => setState(() => _showInstructions = false),
        ),
      ],
    );
  }
}