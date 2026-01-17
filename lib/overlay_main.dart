import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:lucide_icons/lucide_icons.dart';

class BossOverlayWindow extends StatefulWidget {
  const BossOverlayWindow({super.key});
  @override
  State<BossOverlayWindow> createState() => _BossOverlayWindowState();
}

class _BossOverlayWindowState extends State<BossOverlayWindow> {
  bool isBossMode = false;

  // --- 关键教学：如何修改尺寸 ---
  
  // 1. 进入全屏黑幕
  void _enterBossMode() async {
    debugPrint("LOG: [Overlay] 发送缩放指令...");
    
    if (mounted) {
      setState(() => isBossMode = true);
    }

    final bool? success = await FlutterOverlayWindow.resizeOverlay(
      1000,
      2000,
      false
    );
  }

  // 2. 恢复悬浮小球
  void _exitBossMode() async {
    debugPrint("LOG: [Overlay] Black screen tapped -> Exiting Boss Mode (Normal Ball)");
    setState(() => isBossMode = false);
    // 指令：变回小尺寸，并重新启用拖拽
    await FlutterOverlayWindow.resizeOverlay(150, 150, true);
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("LOG: [Overlay] Main Build called. isBossMode: $isBossMode");
    return Material(
      color: Colors.transparent,
      child: isBossMode ? _buildBossContent() : _buildNormalContent(),
    );
  }

  Widget _buildBossContent() {
    debugPrint("LOG: [Overlay] Building Boss Content layer");
    return GestureDetector(
      onTap: _exitBossMode,
      child: Container(
        color: Colors.black, // 全屏黑色
        child: const Center(
          child: Text("HALT", style: TextStyle(color: Colors.white10, fontSize: 32)),
        ),
      ),
    );
  }

  Widget _buildNormalContent() {
    debugPrint("LOG: [Overlay] Building Normal Content layer");
    return Center(
      child: GestureDetector(
        onTap: _enterBossMode,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.blueAccent,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)],
          ),
          child: const Icon(LucideIcons.airplay, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}