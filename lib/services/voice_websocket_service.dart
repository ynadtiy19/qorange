import 'dart:async';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart'; // 引入 Get 以获取全局状态控制
import '../network/api_exception.dart';
import '../network/http_client.dart';
import '../../views/voice/voice_chat_controller.dart'; // 引入控制器

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
        Fluttertoast.showToast(msg: res.respMsg ?? "初始化语音失败");
        return;
      }

      _maxSecondsAllowed = int.parse(res.datas!['max_seconds'].toString());
      final String idToken = res.datas!['id_token'].toString();

      // b. 物理激活底层原生事件流监听
      _eventSubscription?.cancel();
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
            (data) {
          if (data is Map) {
            final type = data['type']?.toString() ?? '';
            final val = data['value'];

            if (type == 'voice_activity') {
              if (onVoiceActivityChanged != null) {
                onVoiceActivityChanged!(val as bool? ?? false);
              }
            } else if (type == 'error') {
              if (onError != null) {
                onError!(val.toString());
              }
            } else if (type == 'status' && val == 'Disconnected') {
              _handleSessionEnd(reason: "通话结束");
            }
          }
        },
        onError: (err) => _handleSessionEnd(reason: "通信异常断开: $err"),
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
        Fluttertoast.showToast(msg: "建立语音通道失败");
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
          Fluttertoast.showToast(msg: "⚠️ 您的账户代币余额即将耗尽，通话将在 5 秒后自动关闭！");
        }

        // 🌟 物理阻断保护点：代币扣尽，客户端强制强行物理切断底层 WSS 链路！
        if (_elapsedSeconds >= _maxSecondsAllowed) {
          _billingTimer?.cancel();
          _billingTimer = null;
          disconnect(); // 🌟 物理强斩
          _handleSessionEnd(reason: "代币可用余额不足，已自动断开连接");
        }
      });

    } catch (e) {
      _cleanupSession();
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: "语音引擎初始化异常: $e");
      }
    }
  }

  /// 🌟 2. 挂断通话（通过平台通道向原生发出 disconnect）
  Future<void> disconnect() async {
    if (!_isSessionActive) return;
    try {
      await _controlChannel.invokeMethod<bool>('disconnect');
    } catch (_) {}
    _handleSessionEnd(reason: "通话结束");
  }

  /// 🌟 3. 通话完结处理并向 Zeabur 后台提交实扣对账单
  Future<void> _handleSessionEnd({required String reason}) async {
    if (!_isSessionActive) return;

    final int finalDuration = _elapsedSeconds;

    // 🌟🌟 核心对齐修复：通过 Get.find 动态读取全局 UI 状态
    // 如果 WSS 信道根本没有接通（例如WSS报错401/403/网络断开等），或者通话时长小于 2 秒，直接免单！
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

    // 🌟🌟 核心防护拦截：未成功通电话或者时长在1秒及以内，不予计费上报，100%保护学者资金安全 🌟🌟
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
        Fluttertoast.showToast(msg: "未知异常: $e");
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