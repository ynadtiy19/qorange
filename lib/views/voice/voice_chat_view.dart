import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:lottie/lottie.dart';
import 'voice_chat_controller.dart';
import 'select_agent_sheet.dart';

class VoiceChatView extends StatelessWidget {
  const VoiceChatView({super.key});

  @override
  Widget build(BuildContext context) {
    // 实例化 GetX 控制器
    final controller = Get.put(VoiceChatController());

    final Color obsidianBg = const Color(0xFF0F172A); // 曜石黑
    final Color goldColor = const Color(0xFFE2B04E);  // 奢华金
    final Color primaryTeal = const Color.fromRGBO(44, 123, 109, 1.0);

    // 默认选用 Simone
    String currentCharacter = 'Simone';
    String currentKey = 'Simone-EN';

    return Scaffold(
      backgroundColor: obsidianBg, // 曜石黑底色，营造沉浸感
      appBar: AppBar(
        backgroundColor: obsidianBg,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
        ),
        actions: [
          // 右上角：精美选择助理小药丸
          Obx(() {
            final bool disabled = controller.isConnected.value || controller.isConnecting.value;
            return IgnorePointer(
              ignoring: disabled,
              child: Opacity(
                opacity: disabled ? 0.3 : 1.0,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16.0, top: 12, bottom: 12),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showModalBottomSheet<void>(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (context) {
                          return SelectAgentBottomSheet(
                            onAgentSelected: (char, key) {
                              currentCharacter = char;
                              currentKey = key;
                              Fluttertoast.showToast(msg: "已选中角色: $char");
                            },
                          );
                        },
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.06),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: HugeIcon(icon: HugeIcons.strokeRoundedLanguageSkill, color: goldColor, size: 14.0),
                    label: const Text('选择助手', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),

          // --- 核心球体动效区域（Lottie 与 手画 60 帧波纹重叠） ---
          SizedBox(
            width: 340,
            height: 340,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. 成功接通时：绘制动态呼吸波纹
                Obx(() {
                  if (!controller.isConnected.value) return const SizedBox.shrink();
                  return CustomPaint(
                    size: const Size(340, 340),
                    painter: _VoiceWavePainter(
                      visualRms: controller.visualRms.value,
                      hasVoiceActivity: controller.hasVoiceActivity.value,
                      waveColor: primaryTeal,
                    ),
                  );
                }),

                // 2. 未连接时：渲染 Lottie 按钮
                Obx(() {
                  final bool isConnected = controller.isConnected.value;
                  final bool isConnecting = controller.isConnecting.value;
                  return AnimatedOpacity(
                    opacity: isConnected ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 400),
                    child: IgnorePointer(
                      ignoring: isConnected || isConnecting,
                      child: GestureDetector(
                        onTap: () => controller.startCall(
                          contactName: currentKey,
                          characterName: currentCharacter,
                        ),
                        child: Lottie.asset(
                          'images/sesame.json', // 🌟 请确保在 assets 路径下有此动画
                          fit: BoxFit.fill,
                          animate: !isConnected,
                        ),
                      ),
                    ),
                  );
                }),

                // 3. 登录请求/签名创单加载圈
                Obx(() {
                  if (!controller.isConnecting.value) return const SizedBox.shrink();
                  return const SizedBox(
                    width: 300,
                    height: 300,
                    child: CircularProgressIndicator(
                      color: Color.fromRGBO(44, 123, 109, 1.0),
                      strokeWidth: 2,
                    ),
                  );
                }),

                // 4. 中心圆核：可视化的状态反馈
                Obx(() {
                  if (!controller.isConnected.value) return const SizedBox.shrink();
                  return Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: obsidianBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: goldColor.withOpacity(0.4), width: 1.5),
                    ),
                    child: Center(
                      child: HugeIcon(
                        icon: controller.hasVoiceActivity.value
                            ? HugeIcons.strokeRoundedAiGame // 说话时波形指示
                            : HugeIcons.strokeRoundedMic01, // 聆听时麦克风指示
                        color: controller.hasVoiceActivity.value ? goldColor : primaryTeal,
                        size: 32.0,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 40),

          // --- 状态文字与计时器 ---
          Obx(() => Text(
            controller.statusText.value,
            style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, letterSpacing: 0.5),
            textAlign: TextAlign.center,
          )),
          const SizedBox(height: 12),

          Obx(() {
            if (!controller.isConnected.value) return const SizedBox.shrink();
            final int sec = controller.elapsedSeconds.value;
            final m = (sec ~/ 60).toString().padLeft(2, '0');
            final s = (sec % 60).toString().padLeft(2, '0');
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Text(
                '$m:$s',
                style: TextStyle(
                  color: goldColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            );
          }),

          const Spacer(flex: 1),

          // --- 底部出众的控制按盘（药丸形气泡） ---
          Obx(() {
            if (!controller.isConnected.value) return const SizedBox.shrink();
            final bool muted = controller.isMuted.value;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute Button
                  GestureDetector(
                    onTap: controller.toggleMute,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: muted ? Colors.orange.withOpacity(0.12) : Colors.white.withOpacity(0.05),
                            shape: BoxShape.circle,
                          ),
                          child: HugeIcon(
                            icon: muted ? HugeIcons.strokeRoundedHeadphoneMute : HugeIcons.strokeRoundedMic01,
                            color: muted ? Colors.orange : goldColor,
                            size: 24.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          muted ? '已静音' : '开启静音',
                          style: TextStyle(fontSize: 11, color: muted ? Colors.orange : Colors.grey, fontWeight: FontWeight.bold),
                        )
                      ],
                    ),
                  ),

                  // Payout / Hang Up
                  GestureDetector(
                    onTap: controller.endCall,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: Color(0xFF4A1E24), // 曜石暗红
                            shape: BoxShape.circle,
                          ),
                          child: const HugeIcon(
                            icon: HugeIcons.strokeRoundedCall02, // 挂断
                            color: Colors.redAccent,
                            size: 28.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '结束通话',
                          style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                        )
                      ],
                    ),
                  )
                ],
              ),
            );
          }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// 🌟 曜石曜绿高颜值手画波纹绘制器（支持 Lerp 缓动消灭卡顿）
class _VoiceWavePainter extends CustomPainter {
  final double visualRms;
  final bool hasVoiceActivity;
  final Color waveColor;

  _VoiceWavePainter({
    required this.visualRms,
    required this.hasVoiceActivity,
    required this.waveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const baseRadius = 80.0;

    // 1. 绘制极深曜绿基底圆核
    final basePaint = Paint()
      ..color = waveColor.withOpacity(0.1)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, baseRadius, basePaint);

    // 2. 绘制多层扩散呼吸涟漪
    final wavePaint = Paint()
      ..color = waveColor.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // 动态外圈半径计算，完美结合 rms
    final dynamicOffset = visualRms * 100.0; // 最大可扩散 100 像素
    canvas.drawCircle(center, baseRadius + dynamicOffset, wavePaint);

    // 绘制第二层细润涟漪
    final secondPaint = Paint()
      ..color = waveColor.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, baseRadius + (dynamicOffset * 1.5), secondPaint);
  }

  @override
  bool shouldRepaint(covariant _VoiceWavePainter old) => true;
}