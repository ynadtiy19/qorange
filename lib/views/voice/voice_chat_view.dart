import 'dart:ui'; // 用于 BackdropFilter 毛玻璃
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
    String currentCharacter = 'Maya';
    String currentKey = 'Maya-EN';

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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
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
                                  Fluttertoast.showToast(msg: 'agent_selected'.trParams({'name': char}));
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
                        label: Text('select_assistant'.tr, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
      // 🌟🌟 核心安全修正：使用 SingleChildScrollView 搭配 NeverScrollable 阻尼，无缝吸收 sub-pixel 物理溢出 🌟🌟
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(), // 阻断物理拖拽，让界面维持 Native 通话般坚固静止
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. 顶部的毛玻璃实时同传翻译滚动卡片面板
              Obx(() {
                final active = controller.isTranslationActive.value;
                final connecting = controller.isTranslationConnecting.value;
                final text = controller.transcribedText.value;

                return AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  child: Container(
                    height: (active || connecting) ? 140 : 0,
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(color: goldColor, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('live_captions'.tr, style: TextStyle(color: goldColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                  const Spacer(),
                                  if (connecting)
                                    SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(color: goldColor, strokeWidth: 1.5),
                                    )
                                ],
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: SingleChildScrollView(
                                  reverse: true,
                                  physics: const BouncingScrollPhysics(),
                                  child: Text(
                                    text.isEmpty ? (connecting ? 'captions_connecting'.tr : 'captions_waiting'.tr) : text,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: text.isEmpty ? Colors.grey : Colors.white,
                                      fontWeight: FontWeight.w500,
                                      height: 1.5,
                                      fontFamily: 'ShantellSans',
                                    ),
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),

              // 🌟 物理对齐：采用响应式 SizedBox 替换 Spacer，在小屏幕上自动缩放
              const SizedBox(height: 24),

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
                              'images/sesame.json',
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
              const SizedBox(height: 24),

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

              // 🌟 物理对齐：底部栏防挤压
              const SizedBox(height: 24),

              // --- 底部控制按盘（药丸形气泡三按键对齐设计） ---
              Obx(() {
                if (!controller.isConnected.value) return const SizedBox.shrink();
                final bool muted = controller.isMuted.value;
                final bool transActive = controller.isTranslationActive.value;
                final bool transConnecting = controller.isTranslationConnecting.value;

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 1. Mute Button（静音）
                      GestureDetector(
                        onTap: controller.toggleMute,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: muted ? Colors.orange.withOpacity(0.12) : Colors.white.withOpacity(0.05),
                                shape: BoxShape.circle,
                              ),
                              child: HugeIcon(
                                icon: muted ? HugeIcons.strokeRoundedHeadphoneMute : HugeIcons.strokeRoundedMic01,
                                color: muted ? Colors.orange : goldColor,
                                size: 20.0,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              muted ? 'muted'.tr : 'mute'.tr,
                              style: TextStyle(fontSize: 10, color: muted ? Colors.orange : Colors.grey, fontWeight: FontWeight.bold),
                            )
                          ],
                        ),
                      ),

                      // 2. Hang Up / End Call（挂断）
                      GestureDetector(
                        onTap: controller.endCall,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: const BoxDecoration(
                                color: Color(0xFF4A1E24), // 曜石暗红
                                shape: BoxShape.circle,
                              ),
                              child: const HugeIcon(
                                icon: HugeIcons.strokeRoundedCall02,
                                color: Colors.redAccent,
                                size: 26.0,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'hang_up'.tr,
                              style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                            )
                          ],
                        ),
                      ),

                      // 3. 实时语音转文本（同传翻译开启/关闭开关）
                      GestureDetector(
                        onTap: transConnecting ? null : controller.toggleTranslationStream,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: transActive ? primaryTeal.withOpacity(0.12) : Colors.white.withOpacity(0.05),
                                shape: BoxShape.circle,
                              ),
                              child: transConnecting
                                  ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: goldColor, strokeWidth: 1.5),
                              )
                                  : HugeIcon(
                                icon: HugeIcons.strokeRoundedTranslation,
                                color: transActive ? primaryTeal : goldColor,
                                size: 20.0,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              transActive ? 'captions_off'.tr : 'captions_on'.tr,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: transActive ? primaryTeal : Colors.grey,
                                  fontWeight: FontWeight.bold
                              ),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 10),
            ],
          ),
        ),
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