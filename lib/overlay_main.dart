import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

// Project: BossCome
// Author: {{HenryChan}}
// This source code is licensed under the GNU GPLv3 License.

class BossOverlayWindow extends StatefulWidget {
  const BossOverlayWindow({super.key});
  @override
  State<BossOverlayWindow> createState() => _BossOverlayWindowState();
}

class _BossOverlayWindowState extends State<BossOverlayWindow> {
  int? _mainBridgePort;
  bool isBossMode = false;
  Color ballColor = Colors.blueAccent;
  double ballOpacity = 1.0;

  Color _parseHexColor(String hex) {
    hex = hex.replaceAll("#", "");
    if (hex.length == 6) {
      hex = "FF$hex";
    }
    return Color(int.parse(hex, radix: 16));
  }

  @override
  void initState() {
    super.initState();

    // 监听来自主程序的端口和状态配置消息
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is String) {
        if (event.startsWith("SET_PORT:")) {
          final portStr = event.split(":")[1];
          _mainBridgePort = int.tryParse(portStr);
          print("DEBUG: [Overlay] Connected to Main Bridge Port: $_mainBridgePort");
        } else if (event.startsWith("SET_MODE:")) {
          final mode = event.split(":")[1];
          print("DEBUG: [Overlay] Mode update from main: $mode");
          setState(() {
            isBossMode = (mode == 'BOSS');
          });
        } else if (event.startsWith("SET_STYLE:")) {
          final parts = event.split(":")[1].split(",");
          if (parts.length >= 2) {
            setState(() {
              ballColor = _parseHexColor(parts[0]);
              ballOpacity = double.tryParse(parts[1]) ?? 1.0;
            });
            print("DEBUG: [Overlay] Style updated: $ballColor, $ballOpacity");
          }
        }
      }
    });
  }

  void _sendToMain(String action) async {
    if (_mainBridgePort == null) {
      print("DEBUG: [Overlay] Error: Bridge port unknown, cannot send $action");
      return;
    }

    print("DEBUG: [Overlay] Starting to send $action...");

    try {
      final client = HttpClient();
      // 设置超时防止卡死
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(
        Uri.parse("http://127.0.0.1:$_mainBridgePort?action=$action"),
      );
      final response = await request.close();
      print("DEBUG: [Overlay] HTTP Request sent, response: ${response.statusCode}");
    } catch (e) {
      print("DEBUG: [Overlay] HTTP Bridge failure: $e");
    }
  }
  
  void _enterBossMode() => _sendToMain("ENTER_BOSS");
  void _exitBossMode() => _sendToMain("EXIT_BOSS");
  void _closeOverlay() => _sendToMain("CLOSE_OVERLAY");
  void _openMainApp() => _sendToMain("OPEN_APP");

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: isBossMode ? _buildBossContent() : _buildNormalContent(),
    );
  }

  void _showOverlayMenu(BuildContext context, Offset globalPos) {
    // 确保我们使用的是该 Widget 树中的正确的 context
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    // 根据当前悬浮窗大小动态调整菜单样式，并设置合理的上限
    final overlayWidth = overlay.size.width;
    // 允许菜单宽度缩小到 20 像素，最大 220 像素
    final menuWidth = (overlayWidth * 0.9).clamp(20.0, 220.0);
    // 字体和图标大小根据菜单宽度缩放，取消过高的下限，确保在小窗口能显示
    final fontSize = (menuWidth / 12).clamp(2.0, 16.0);
    final iconSize = (menuWidth / 10).clamp(2.0, 20.0);
    final itemHeight = (menuWidth / 5).clamp(4.0, 48.0);

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      color: Colors.white.withOpacity(0.95),
      elevation: 8,
      constraints: BoxConstraints(
        maxWidth: menuWidth,
        minWidth: menuWidth,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: isBossMode 
      ? [
        PopupMenuItem(
          onTap: _closeOverlay,
          height: itemHeight,
          padding: EdgeInsets.symmetric(horizontal: menuWidth * 0.1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.xCircle, color: Colors.red, size: iconSize),
              SizedBox(width: menuWidth * 0.05),
              Flexible(
                child: Text(
                  '关闭悬浮窗',
                  style: TextStyle(fontSize: fontSize),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ]
      : [
        PopupMenuItem(
          onTap: _openMainApp,
          height: itemHeight,
          padding: EdgeInsets.symmetric(horizontal: menuWidth * 0.1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.externalLink,
                color: Colors.blue,
                size: iconSize,
              ),
              SizedBox(width: menuWidth * 0.05),
              Flexible(
                child: Text(
                  '打开主界面',
                  style: TextStyle(fontSize: fontSize),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBossContent() {
    return GestureDetector(
      onDoubleTap: _exitBossMode,
      onLongPressStart: (details) => _showOverlayMenu(context, details.globalPosition),
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.all(40),
        child: const Center(child: SizedBox.shrink()),
      ),
    );
  }

  Widget _buildNormalContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 自动获取悬浮窗的最小边长，确保悬浮球是圆形的并填满窗口
        final size = constraints.maxWidth < constraints.maxHeight 
            ? constraints.maxWidth 
            : constraints.maxHeight;

        return Center(
          child: GestureDetector(
            onTap: _enterBossMode,
            onLongPressStart: (details) => _showOverlayMenu(context, details.globalPosition),
            child: Opacity(
              opacity: ballOpacity,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: ballColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: size * 0.1, // 阴影大小也随之变化
                    )
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(size * 0.2), // 留出 20% 的边距防止图标太靠边
                  child: const FittedBox(
                    fit: BoxFit.contain,
                    child: Icon(LucideIcons.airplay, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}