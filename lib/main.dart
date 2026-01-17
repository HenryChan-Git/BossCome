import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'overlay_main.dart';

@pragma("vm:entry-point")
void overlayMain() {
  // 1. 显式初始化，确保渲染引擎准备就绪
  WidgetsFlutterBinding.ensureInitialized();
  
  // 即使控制台看不到，我们也打这个日志备查
  print("LOG: [Overlay] 物理入口触发");

  runApp(
    // 移除 MaterialApp，改用轻量级的 Directionality + Material
    Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: Colors.transparent,
        child: BossOverlayWindow(),
      ),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: MainScreen()));
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  void _checkPermission() async {
    if (!await FlutterOverlayWindow.isPermissionGranted()) {
      await FlutterOverlayWindow.requestPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("LOG: [Main] MainScreen Build called");
    return Scaffold(
      appBar: AppBar(title: const Text("Boss Come 控制台")),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            debugPrint("LOG: [Main] Toggle Button Pressed");
            if (await FlutterOverlayWindow.isActive()) {
              debugPrint("LOG: [Main] Overlay is active, closing it...");
              await FlutterOverlayWindow.closeOverlay();
            } else {
              debugPrint("LOG: [Main] Overlay not active, showing it (150x150)...");
              // 初始以 150x150 开启
              await FlutterOverlayWindow.showOverlay(
                height: 300,
                width: 300,
                alignment: OverlayAlignment.center,
                enableDrag: true,
                positionGravity: PositionGravity.none,
              );
            }
          },
          child: const Text("启动/关闭悬浮窗"),
        ),
      ),
    );
  }
}