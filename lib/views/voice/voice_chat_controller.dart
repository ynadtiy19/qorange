import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../network/http_client.dart';
import '../../network/secure_storage_manager.dart';
import '../../services/voice_websocket_service.dart';

class VoiceChatController extends GetxController {
  final VoiceWebSocketService _voiceService = VoiceWebSocketService();
  WebSocketChannel? _translateWsChannel;

  // 观察状态变量
  final RxString statusText = "轻触下方开始与 AI 助手语音对话".obs;
  final RxBool isConnected = false.obs;
  final RxBool isConnecting = false.obs;
  final RxBool isMuted = false.obs;
  final RxBool hasVoiceActivity = false.obs;
  final RxInt elapsedSeconds = 0.obs;
  final RxDouble visualRms = 0.05.obs; // 用于控制波纹大小

  // 实时翻译同传流核心状态
  final RxBool isTranslationActive = false.obs; // 是否开启了实时转文本
  final RxBool isTranslationConnecting = false.obs; // 翻译 WSS 连接中
  final RxString transcribedText = "".obs; // 实时回显翻译的文本块

  // 计时器与波纹模拟定时器
  Timer? _rmsTimer;
  int _audioPacketCount = 0; // 🌟 统计发送给谷歌的音频包数量，用于节流日志

  @override
  void onInit() {
    super.onInit();
    _setupServiceListeners();
  }

  @override
  void onClose() {
    _rmsTimer?.cancel();
    _voiceService.disconnect();
    _closeTranslationChannel();
    super.onClose();
  }

  /// 建立服务层的双端通知监听
  void _setupServiceListeners() {
    _voiceService.onTick = (seconds) {
      elapsedSeconds.value = seconds;
    };

    _voiceService.onVoiceActivityChanged = (active) {
      hasVoiceActivity.value = active;
    };

    // 🌟 在服务层事件通道拦截原始 PCM 字节流进行翻译分发（注入高亮发送日志）
    _voiceService.onAudioBytesReceived = (audioData) {
      if (isTranslationActive.value && _translateWsChannel != null && isConnected.value) {
        // 实时向 Zeabur 翻译网关灌入麦克风流
        _translateWsChannel!.sink.add(audioData);

        _audioPacketCount++;
        // 🌟 节流打印：每 50 个音频包（约1.5秒数据）打印一次，既看得到实时流又防止控制台刷屏卡顿
        if (_audioPacketCount % 50 == 0) {
          print('📤 [WSS 同传发送] -> 已向国外服务器中继投递第 $_audioPacketCount 个原始 PCM 声波字节包 (${audioData.length} 字节)');
        }
      }
    };

    _voiceService.onError = (errorMsg) {
      statusText.value = "异常: $errorMsg";
      _resetStates();
    };

    _voiceService.onSessionClosed = () {
      _resetStates();
    };
  }

  /// 一键发起 AI 语音通话 (包含麦克风权限请求)
  Future<void> startCall({required String contactName, required String characterName}) async {
    if (isConnecting.value || isConnected.value) return;

    isConnecting.value = true;
    statusText.value = "正在申请麦克风权限...";

    final permission = await Permission.microphone.request();
    if (!permission.isGranted) {
      isConnecting.value = false;
      statusText.value = "麦克风权限被拒绝，无法建立语音";
      Fluttertoast.showToast(msg: "请在系统设置中开放麦克风权限");
      return;
    }

    statusText.value = "代签握手中，即将接通...";
    HapticFeedback.mediumImpact(); // 开启清脆的物理马达回弹振动

    await _voiceService.startVoiceSession(
      contactName: contactName,
      characterName: characterName,
    );

    isConnected.value = true;
    isConnecting.value = false;
    statusText.value = "已接通，开始倾听您的观点";

    _startRmsSimulator();
  }

  /// 一键挂断物理 WSS 会话
  Future<void> endCall() async {
    statusText.value = "正在断开语音链路...";
    HapticFeedback.mediumImpact();
    await _voiceService.disconnect();
    _resetStates();
  }

  /// 极速静音/取消静音控制
  Future<void> toggleMute() async {
    if (!isConnected.value) return;
    try {
      isMuted.value = !isMuted.value;
      const MethodChannel('com.sesame.voicechat/control').invokeMethod('setMute', {'isMuted': isMuted.value});
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// 🌟🌟 核心：在语音进行中，一键开启/关闭实时翻译同传 WSS 管道（注入多维控制台实时调试日志） 🌟🌟
  Future<void> toggleTranslationStream() async {
    if (!isConnected.value) {
      Fluttertoast.showToast(msg: "请先接通语音通话再开启翻译");
      return;
    }

    if (isTranslationActive.value) {
      _closeTranslationChannel();
      Fluttertoast.showToast(msg: "已关闭实时同传翻译");
    } else {
      isTranslationConnecting.value = true;
      transcribedText.value = "";
      _audioPacketCount = 0; // 重置计数

      try {
        final token = await SecureStorageManager.instance.getAccessToken();
        if (token == null || token.isEmpty) {
          isTranslationConnecting.value = false;
          Fluttertoast.showToast(msg: "请登录后使用同传功能");
          return;
        }

        final wsUrl = 'wss://googlechat.zeabur.app/api-ai/translate_stream?token=$token';

        // 🌟🌟 专属控制台高亮调试日志：WSS 同传连接启动 🌟🌟
        print('==================== 🎙️ 谷歌 Gemini Live 实时同传流启动 ====================');
        print('➤ 连接地址  : $wsUrl');
        print('➤ 授权凭证  : ${token.substring(0, min(token.length, 45))}... (已隐藏后段)');
        print('➤ 运行状态  : 正在通过安全网关划扣开机费并握手 Google Bidi 接口...');
        print('========================================================================');

        _translateWsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

        // 监听下发文本
        _translateWsChannel!.stream.listen(
              (message) {
            try {
              // 🌟 打印实时接收的同传下发原始报文
              print('📨 [WSS 同传接收] 原始数据包: $message');

              final Map<String, dynamic> data = jsonDecode(message.toString());
              final String? chunk = data['text']?.toString();
              if (chunk != null) {
                transcribedText.value += chunk;
                print('✨ [同传文字增量]: $chunk');
              }
            } catch (e) {
              print('🔴 解析同传下发数据包异常: $e');
            }
          },
          onError: (err) => _closeTranslationChannel(reason: "翻译网关异常断开"),
          onDone: () => _closeTranslationChannel(reason: "翻译流正常关闭"),
        );

        isTranslationActive.value = true;
        isTranslationConnecting.value = false;
        HapticFeedback.mediumImpact();
        Fluttertoast.showToast(msg: "🎉 实时同传翻译已成功开启，已扣除 5 代币开机费！");

      } catch (e) {
        isTranslationConnecting.value = false;
        _closeTranslationChannel();
        Fluttertoast.showToast(msg: "开启翻译失败: $e");
      }
    }
  }

  void _closeTranslationChannel({String? reason}) {
    isTranslationActive.value = false;
    isTranslationConnecting.value = false;
    _translateWsChannel?.sink.close();
    _translateWsChannel = null;

    // 🌟 专属控制台高亮调试日志：WSS 同传关闭
    print('==================== 🎙️ 谷歌 Gemini Live 实时同传流关闭 ====================');
    print('➤ 原因/状态 : ${reason ?? "用户手动关闭"}');
    print('➤ 累计发送  : $_audioPacketCount 帧声波数据包');
    print('========================================================================');

    if (reason != null) {
      Fluttertoast.showToast(msg: reason);
    }
  }

  void _startRmsSimulator() {
    _rmsTimer?.cancel();
    _rmsTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (!isConnected.value) {
        timer.cancel();
        return;
      }
      final double targetRms = hasVoiceActivity.value
          ? (0.2 + (DateTime.now().millisecondsSinceEpoch % 100) / 150.0)
          : 0.05;

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
    _closeTranslationChannel();
  }
}