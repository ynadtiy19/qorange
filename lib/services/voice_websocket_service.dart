import 'dart:async';
import 'dart:typed_data'; // 🌟 核心引入：用于高能物理字节流 Uint8List [1]
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import '../network/api_exception.dart';
import '../network/http_client.dart';
import '../../views/voice/voice_chat_controller.dart';

class VoiceWebSocketService {
  static const MethodChannel _controlChannel = MethodChannel('com.sesame.voicechat/control');
  static const EventChannel _eventChannel = EventChannel('com.sesame.voicechat/events');

  StreamSubscription<dynamic>? _eventSubscription;
  Timer? _billingTimer;

  int _elapsedSeconds = 0;
  int _maxSecondsAllowed = 0;
  bool _isSessionActive = false;

  // 状态流回调，供前台渲染
  Function(int)? onTick;
  Function(bool)? onVoiceActivityChanged;
  Function(String)? onError;
  VoidCallback? onSessionClosed;

  // 🌟🌟 核心新增：原始麦克风 PCM 字节流向 Flutter 中继抛出的专用回调 🌟🌟 [1]
  Function(Uint8List)? onAudioBytesReceived;

  /// 🌟 1. 开启 WSS 实时语音流闭环（自动拉取 Zeabur 临时安全 Token 并代扣检查）
  Future<void> startVoiceSession({required String contactName, required String characterName}) async {
    if (_isSessionActive) return;

    try {
      // a. 从 Zeabur 后台安全环境获取临时 ID Token 以及该学者的最大通话秒数
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-ai/voice',
        data: {'action': 'init'},
      );

      if (res.respCode != 0 || res.datas == null) {
        Fluttertoast.showToast(msg: res.respMsg ?? 'voice_init_failed'.tr);
        return;
      }

      _maxSecondsAllowed = int.parse(res.datas!['max_seconds'].toString());
      final String idToken = res.datas!['id_token'].toString();

      // b. 物理激活底层原生事件流监听
      _eventSubscription?.cancel();
      // 🌟 请寻找 VoiceWebSocketService 内的 _eventSubscription 监听段，将 if (data is Map) 内部修改为如下：
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
            (data) {
          if (data is Map) {
            final type = data['type']?.toString() ?? '';
            final val = data['value'];

            if (type == 'voice_activity') {
              if (val is Map) {
                final bool hasVoice = val['hasVoice'] == true;
                if (onVoiceActivityChanged != null) {
                  onVoiceActivityChanged!(hasVoice);
                }
                // 此时如果是处于正常的 Saysay 录音状态，保留麦克风数据回调
                // final dynamic audioData = val['audio_data'];
              } else {
                if (onVoiceActivityChanged != null) {
                  onVoiceActivityChanged!(val as bool? ?? false);
                }
              }
            } else if (type == 'ai_audio_data') {
              // 🌟🌟 核心对齐：收到来自原生层重采样后的 AI 助手播放声波字节流，直接通过回调发送至翻译 WebSocket 🌟🌟 [2]
              final dynamic audioData = val;
              if (audioData != null && onAudioBytesReceived != null) {
                final Uint8List bytes = Uint8List.fromList(List<int>.from(audioData));
                onAudioBytesReceived!(bytes);
              }
            } else if (type == 'error') {
              if (onError != null) {
                onError!(val.toString());
              }
            } else if (type == 'status' && val == 'Disconnected') {
              _handleSessionEnd(reason: 'voice_call_ended'.tr);
            }
          }
        },
        onError: (err) => _handleSessionEnd(reason: 'voice_disconnected_err'.trParams({'error': '$err'})),
      );

      // c. 通过平台通道向 Android 原生发起连接（免去预热直接开启）
      final bool success = await _controlChannel.invokeMethod<bool>(
        'connect',
        {
          'contactName': contactName,
          'characterName': characterName,
          'token': idToken, // 使用安全下发的 ID Token
        },
      ) ?? false;

      if (!success) {
        _cleanupSession();
        Fluttertoast.showToast(msg: 'voice_channel_failed'.tr);
        return;
      }

      _isSessionActive = true;
      _elapsedSeconds = 0;

      // d. 🌟 启动客户端高精准秒级计费守护计时器
      _billingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!_isSessionActive) {
          timer.cancel();
          return;
        }

        _elapsedSeconds++;
        if (onTick != null) {
          onTick!(_elapsedSeconds);
        }

        // 临界预警：最后 5 秒提示
        if (_maxSecondsAllowed - _elapsedSeconds == 5) {
          Fluttertoast.showToast(msg: 'voice_low_balance'.tr);
        }

        // 🌟 物理阻断保护点：代币扣尽，客户端强制强行物理切断底层 WSS 链路！
        if (_elapsedSeconds >= _maxSecondsAllowed) {
          _billingTimer?.cancel();
          _billingTimer = null;
          disconnect(); // 🌟 物理强斩
          _handleSessionEnd(reason: 'voice_no_balance'.tr);
        }
      });

    } catch (e) {
      _cleanupSession();
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: 'voice_engine_error'.trParams({'error': '$e'}));
      }
    }
  }

  /// 🌟 2. 挂断通话（通过平台通道向原生发出 disconnect）
  Future<void> disconnect() async {
    if (!_isSessionActive) return;
    try {
      await _controlChannel.invokeMethod<bool>('disconnect');
    } catch (_) {}
    _handleSessionEnd(reason: 'voice_call_ended'.tr);
  }

  /// 🌟 3. 通话完结处理并向 Zeabur 后台提交实扣对账单
  Future<void> _handleSessionEnd({required String reason}) async {
    if (!_isSessionActive) return;

    final int finalDuration = _elapsedSeconds;

    // 通过 Get.find 动态读取全局 UI 状态
    bool wasConnected = false;
    try {
      final controller = Get.find<VoiceChatController>();
      wasConnected = controller.isConnected.value;
    } catch (_) {
      wasConnected = false;
    }

    _cleanupSession();

    Fluttertoast.showToast(msg: reason);

    if (onSessionClosed != null) {
      onSessionClosed!();
    }

    // 核心防护拦截：未成功通电话或者时长在1秒及以内，不予计费上报，100%保护学者资金安全
    if (!wasConnected || finalDuration < 2) {
      print('ℹ️ [VoiceChat] 语音通道未建立或时长过短 (${finalDuration}秒)，本次已免除扣费核销。');
      return;
    }

    // 在后台向应用服务器上报结算（消耗 totalDuration * 0.1 币）
    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-ai/voice',
        data: {
          'action': 'report',
          'duration': finalDuration.toString(),
        },
      );
      if (res.respCode == 0) {
        final deducted = res.datas!['deducted'];
        print('✅ 语音通话安全扣费结算完成，共扣减 $deducted 个代币');
      }
    } catch (e) {
      if (e is ApiException) {
        print('$e');
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: 'err_unknown_with_msg'.trParams({'error': '$e'}));
      }
    }
  }

  void _cleanupSession() {
    _isSessionActive = false;
    _billingTimer?.cancel();
    _billingTimer = null;
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }
}