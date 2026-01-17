import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class AppDeclarations {
  static const String title = "使用说明";

  static Future<String> loadInstructions() async {
    return await rootBundle.loadString('assets/instructions.md');
  }

  static Widget buildUsageWidget() {
    return FutureBuilder<String>(
      future: loadInstructions(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Text("无法加载说明文件");
        }
        
        final content = snapshot.data ?? "";
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: content.split('\n').map((line) {
            if (line.startsWith('# ')) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  line.replaceFirst('# ', ''),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              );
            } else if (line.startsWith('### ')) {
              return Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Text(
                  line.replaceFirst('### ', ''),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            } else if (line.trim() == '---') {
              return const Divider();
            } else if (line.trim().isEmpty) {
              return const SizedBox(height: 5);
            } else {
              return Text(
                line,
                style: line.contains('开发者声明') 
                    ? const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                    : (line.length < 50 ? null : const TextStyle(fontSize: 14)),
              );
            }
          }).toList(),
        );
      },
    );
  }
}

class InstructionOverlay extends StatefulWidget {
  final bool isVisible;
  final GlobalKey targetKey;
  final VoidCallback onDismissed;

  const InstructionOverlay({
    super.key,
    required this.isVisible,
    required this.targetKey,
    required this.onDismissed,
  });

  @override
  State<InstructionOverlay> createState() => _InstructionOverlayState();
}

class _InstructionOverlayState extends State<InstructionOverlay> {
  bool _isAnimating = false;

  void _startDismissAnimation() {
    setState(() {
      _isAnimating = true;
    });
  }

  @override
  void didUpdateWidget(InstructionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 如果外部重新显示弹窗，重置内部动画状态
    if (widget.isVisible && !oldWidget.isVisible) {
      _isAnimating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) return const SizedBox.shrink();

    final screenSize = MediaQuery.of(context).size;
    const double dialogWidth = 320;
    const double dialogHeight = 450;
    final double startTop = (screenSize.height - dialogHeight) / 2;
    final double startLeft = (screenSize.width - dialogWidth) / 2;

    double endTop = 50;
    double endLeft = screenSize.width - 50;

    if (widget.targetKey.currentContext != null) {
      final RenderBox box = widget.targetKey.currentContext!.findRenderObject() as RenderBox;
      final Offset pos = box.localToGlobal(Offset.zero);
      endTop = pos.dy;
      endLeft = pos.dx;
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _startDismissAnimation,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: _isAnimating ? 0 : 1,
              child: Container(color: Colors.black54),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 600),
          curve: Curves.fastOutSlowIn,
          top: _isAnimating ? endTop : startTop,
          left: _isAnimating ? endLeft : startLeft,
          width: _isAnimating ? 10 : dialogWidth,
          height: _isAnimating ? 10 : dialogHeight,
          onEnd: () {
            if (_isAnimating) {
              widget.onDismissed();
            }
          },
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 400),
            opacity: _isAnimating ? 0 : 1,
            child: Material(
              elevation: 10,
              borderRadius: BorderRadius.circular(15),
              clipBehavior: Clip.antiAlias,
              child: FittedBox(
                fit: BoxFit.fill,
                child: Container(
                  width: dialogWidth,
                  height: dialogHeight,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.help_outline, color: Colors.blue),
                          SizedBox(width: 10),
                          Text(AppDeclarations.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: SingleChildScrollView(
                          child: AppDeclarations.buildUsageWidget(),
                        ),
                      ),
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _startDismissAnimation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text("我已阅读并确认"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
