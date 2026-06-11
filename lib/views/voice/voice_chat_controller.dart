import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/voice_websocket_service.dart';

class VoiceChatController extends GetxController {
  final VoiceWebSocketService _voiceService = VoiceWebSocketService();

  // 观察状态变量
  final RxString statusText = "轻触下方开始与 AI 助手语音对话".obs;
  final RxBool isConnected = false.obs;
  final RxBool isConnecting = false.obs;
  final RxBool isMuted = false.obs;
  final RxBool hasVoiceActivity = false.obs;
  final RxInt elapsedSeconds = 0.obs;
  final RxDouble visualRms = 0.05.obs; // 用于控制波纹大小

  // 计时器与波纹模拟定时器
  Timer? _rmsTimer;

  @override
  void onInit() {
    super.onInit();
    _setupServiceListeners();
  }

  @override
  void onClose() {
    _rmsTimer?.cancel();
    _voiceService.disconnect();
    super.onClose();
  }

  /// 🌟 建立服务层的双端通知监听
  void _setupServiceListeners() {
    _voiceService.onTick = (seconds) {
      elapsedSeconds.value = seconds;
    };

    _voiceService.onVoiceActivityChanged = (active) {
      hasVoiceActivity.value = active;
    };

    _voiceService.onError = (errorMsg) {
      statusText.value = "异常: $errorMsg";
      _resetStates();
    };

    _voiceService.onSessionClosed = () {
      _resetStates();
    };
  }

  /// 🌟 一键发起 AI 语音通话 (包含麦克风权限请求)
  Future<void> startCall({required String contactName, required String characterName}) async {
    if (isConnecting.value || isConnected.value) return;

    isConnecting.value = true;
    statusText.value = "正在申请麦克风权限...";

    // 1. 请求物理麦克风特权
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      isConnecting.value = false;
      statusText.value = "麦克风权限被拒绝，无法建立语音";
      Fluttertoast.showToast(msg: "请在系统设置中开放麦克风权限");
      return;
    }

    statusText.value = "代签握手中，即将接通...";
    HapticFeedback.mediumImpact(); // 开启清脆的物理马达回弹振动

    // 2. 调起 WSS 安全信道
    await _voiceService.startVoiceSession(
      contactName: contactName,
      characterName: characterName,
    );

    // 双端成功握手并接通后
    isConnected.value = true;
    isConnecting.value = false;
    statusText.value = "已接通，开始倾听您的观点";

    // 3. 启动本地波纹平滑插值模拟计时器
    _startRmsSimulator();
  }

  /// 🌟 一键挂断物理 WSS 会话
  Future<void> endCall() async {
    statusText.value = "正在断开语音链路...";
    HapticFeedback.mediumImpact();
    await _voiceService.disconnect();
    _resetStates();
  }

  /// 🌟 极速静音/取消静音控制
  Future<void> toggleMute() async {
    if (!isConnected.value) return;
    try {
      isMuted.value = !isMuted.value;
      // 呼叫物理底层切换 mute
      const MethodChannel('com.sesame.voicechat/control').invokeMethod('setMute', {'isMuted': isMuted.value});
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  void _startRmsSimulator() {
    _rmsTimer?.cancel();
    _rmsTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (!isConnected.value) {
        timer.cancel();
        return;
      }
      // 如果检测到用户在说话，大幅波动机率，否则呈静默呼吸微幅波澜
      final double targetRms = hasVoiceActivity.value
          ? (0.2 + (DateTime.now().millisecondsSinceEpoch % 100) / 150.0)
          : 0.05;

      // 线性插值（lerp）计算，彻底消灭帧抖动，实现平滑呼吸
      visualRms.value = visualRms.value * 0.75 + targetRms * 0.25;
    });
  }

  void _resetStates() {
    isConnected.value = false;
    isConnecting.value = false;
    isMuted.value = false;
    hasVoiceActivity.value = false;
    elapsedSeconds.value = 0;
    visualRms.value = 0.05;
    statusText.value = "轻触下方开始与 AI 助手语音对话";
    _rmsTimer?.cancel();
  }
}