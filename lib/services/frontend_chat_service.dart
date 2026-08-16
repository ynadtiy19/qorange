// lib/services/frontend_chat_service.dart (双独立通道定向通配监听 + IM 即时通讯多路复用完全体)
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qorange/models/im_message_model.dart';
import 'package:qorange/services/push_notification_model.dart';
import 'package:version/version.dart';

import '../../user_controller.dart';
import '../controllers/im_chat_controller.dart';
import 'notification_handler_service.dart';

class FrontendChatService extends GetxService {
  static const String myAtsign = '@gemini2banana';
  static const String nameSpace = 'atsign';
  static const String rootDomain = 'root.atsign.org';

  final MessageDeduplicator _deduplicator = MessageDeduplicator();
  final NotificationHandlerService _notificationHandler = Get.put(NotificationHandlerService());

  final RxBool isOnboarded = false.obs;
  AtClient? _atClient;

  // 使用 List 持有多重订阅，便于在登出或切换账号时安全、干净地一次性销毁
  final List<StreamSubscription<dynamic>> _monitorSubscriptions = [];
  Worker? _loginStateWorker;

  @override
  void onInit() {
    super.onInit();
    _loginStateWorker = ever(UserController.to.user, (user) {
      if (UserController.to.isLoggedIn) {
        if (isOnboarded.value) {
          _startFrontendMonitor(_atClient!);
        } else {
          authenticate();
        }
      } else {
        disconnect();
      }
    });

    if (UserController.to.isLoggedIn) {
      authenticate();
    }
  }

  Future<void> authenticate() async {
    if (isOnboarded.value) return;

    if (Platform.isAndroid) {
      await [Permission.storage, Permission.manageExternalStorage].request();
    }

    final supportDir = await getApplicationDocumentsDirectory();
    String keysPath = '${supportDir.path}/${myAtsign}_key.atKeys';

    File keyFile = File(keysPath);
    if (!await keyFile.exists()) {
      debugPrint("⚠️ [Frontend] 密钥文件不存在，正在从 Assets 复制...");
      try {
        final byteData = await rootBundle.load('assets/${myAtsign}_key.atKeys');
        await keyFile.writeAsBytes(
          byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        );
        debugPrint("✅ [Frontend] 密钥文件复制成功: $keysPath");
      } catch (e) {
        debugPrint("❌ [Frontend] 无法从 Assets 复制密钥文件: $e");
        return;
      }
    }

    AtOnboardingPreference config = AtOnboardingPreference()
      ..namespace = nameSpace
      ..hiveStoragePath = '${supportDir.path}/.atsign/$myAtsign/storage'
      ..downloadPath = '${supportDir.path}/.atsign/files'
      ..isLocalStoreRequired = true
      ..rootDomain = rootDomain
      ..atKeysFilePath = keysPath
      ..commitLogPath = '${supportDir.path}/.atsign/$myAtsign/storage/commitLog'
      ..fetchOfflineNotifications = true
      ..atProtocolEmitted = Version(2, 0, 0);

    AtOnboardingService onboardingService = AtOnboardingServiceImpl(myAtsign, config);

    try {
      debugPrint("🤖 [Frontend] 开始认证公共通道: $myAtsign");
      bool authenticated = await onboardingService.authenticate();

      if (authenticated) {
        isOnboarded.value = true;
        debugPrint("✅ [Frontend] 公共通道认证成功");
        _atClient = AtClientManager.getInstance().atClient;
        _startFrontendMonitor(_atClient!);
      }
    } catch (e) {
      debugPrint("AtSign Auth Error: $e");
    }
  }

  void _startFrontendMonitor(AtClient atClient) async {
    if (_monitorSubscriptions.isNotEmpty) {
      for (var sub in _monitorSubscriptions) {
        await sub.cancel();
      }
      _monitorSubscriptions.clear();
    }

    final myRealIdStr = UserController.to.user.value?.id ?? 'none';

    // 🌟 1. 离线缓存双源拉取
    if (myRealIdStr != 'none') {
      await _pullKeysByRegex(atClient, 'push_message_$myRealIdStr');
      await _pullKeysByRegex(atClient, 'push_message_all');
      await _pullKeysByRegex(atClient, 'im_msg_$myRealIdStr');
    }

    // 🌟 2. 注册多路复用正则通道（包含系统广播、个人社交通知、即时通讯私聊、即时状态回执）
    final String broadcastRegex = 'push_message_all.*\\.$nameSpace@';
    final String personalRegex = 'push_message_$myRealIdStr.*\\.$nameSpace@';
    final String imMessageRegex = 'im_msg_$myRealIdStr.*\\.$nameSpace@';
    final String imStatusRegex = 'im_status_$myRealIdStr.*\\.$nameSpace@';

    debugPrint("🎧 [Frontend] 开启监听 - 广播通道: $broadcastRegex");
    debugPrint("🎧 [Frontend] 开启监听 - 社交通道: $personalRegex");
    debugPrint("🎧 [Frontend] 开启监听 - IM私聊通道: $imMessageRegex");

    try {
      final broadcastSub = atClient.notificationService
          .subscribe(regex: broadcastRegex, shouldDecrypt: true)
          .listen(_onNotificationReceived, onError: (e) => debugPrint("🔴 广播通道监听错误: $e"));

      final personalSub = atClient.notificationService
          .subscribe(regex: personalRegex, shouldDecrypt: true)
          .listen(_onNotificationReceived, onError: (e) => debugPrint("🔴 个人通道监听错误: $e"));

      // 🌟 3. 专属 IM 私聊消息监听
      final imSub = atClient.notificationService
          .subscribe(regex: imMessageRegex, shouldDecrypt: true)
          .listen(_onImMessageReceived, onError: (e) => debugPrint("🔴 IM通道监听错误: $e"));

      // 🌟 4. 专属 IM 状态回执 (已读/撤回/打字中) 监听
      final statusSub = atClient.notificationService
          .subscribe(regex: imStatusRegex, shouldDecrypt: true)
          .listen(_onImStatusReceived, onError: (e) => debugPrint("🔴 状态通道监听错误: $e"));

      _monitorSubscriptions.addAll([broadcastSub, personalSub, imSub, statusSub]);
    } catch (e) {
      debugPrint("❌ [Frontend] 注册 AtSign 订阅服务发生异常: $e");
    }
  }

  /// 🌟 处理 IM 即时通讯私聊流（使用 fromJson 彻底消除类名冲突）
  void _onImMessageReceived(AtNotification notification) async {
    final String? jsonVal = notification.value;
    if (jsonVal == null || jsonVal.isEmpty) return;

    try {
      final Map<String, dynamic> payload = jsonDecode(jsonVal);
      final imMsg = ImMessageModel.fromJson(payload);

      if (_deduplicator.isDuplicate(imMsg.messageId)) return;

      // 1. 如果用户当前正停留在该聊天窗口，直接无缝在聊天窗口内上屏
      if (Get.isRegistered<ImChatController>()) {
        final chatCtrl = Get.find<ImChatController>();
        if (chatCtrl.conversationId == imMsg.conversationId) {
          chatCtrl.onIncomingMessage(imMsg);
          return; // 已在当前聊天中，不弹出顶部通知打扰
        }
      }

      // 2. 如果用户在 App 其他页面或后台，组装通知并弹出本地状态栏通知
      final String senderName = payload['sender_nickname']?.toString() ?? '用户';
      String preview = '[新私信]';
      if (imMsg.msgType == 'text') {
        preview = imMsg.payload['text']?.toString() ?? '';
      } else if (imMsg.msgType == 'image') {
        preview = '[图片]';
      } else if (imMsg.msgType == 'voice') {
        preview = '[语音]';
      } else if (imMsg.msgType == 'post_card') {
        preview = '[文章分享]';
      }

      // 🌟 核心修复：直接通过 fromJson 构建模型，杜绝 SenderModel / TargetModel 报错
      final note = PushNotificationModel.fromJson({
        'notification_id': imMsg.messageId,
        'recipient_id': imMsg.recipientId,
        'category': 'social',
        'type': 'im_chat',
        'sender': {
          'id': imMsg.senderId,
          'nickname': senderName,
          'avatar': payload['sender_avatar']?.toString() ?? '',
          'atsign': '',
        },
        'target': {
          'id': imMsg.conversationId,
          'title': preview,
          'type': 'conversation',
        },
        'custom_data': {
          'title': senderName,
          'content': preview,
        },
        'timestamp': DateTime.now().toIso8601String(),
      });

      _notificationHandler.handleIncomingNotification(note);
    } catch (e) {
      debugPrint("🔴 [Frontend] IM 消息解析错误: $e");
    }
  }

  /// 处理状态信号 (撤回/已读回执)
  void _onImStatusReceived(AtNotification notification) async {
    final String? jsonVal = notification.value;
    if (jsonVal == null) return;
    try {
      final Map<String, dynamic> data = jsonDecode(jsonVal);
      final signalType = data['signal_type']?.toString();
      final conversationId = data['conversation_id']?.toString();

      if (Get.isRegistered<ImChatController>()) {
        final chatCtrl = Get.find<ImChatController>();
        if (chatCtrl.conversationId == conversationId) {
          if (signalType == 'revoke') {
            final String msgId = data['extra']?['message_id']?.toString() ?? '';
            chatCtrl.onMessageRevoked(msgId);
          }
        }
      }
    } catch (_) {}
  }

  /// 极简高兼容离线拉取通用方法
  Future<void> _pullKeysByRegex(AtClient atClient, String regexPattern) async {
    try {
      final List<String> matchingKeys = await atClient.getKeys(
        regex: '$regexPattern.*',
        useRemoteAtServer: true,
      );

      for (final rawKeyStr in matchingKeys) {
        try {
          final atKey = AtKey.fromString(rawKeyStr);
          final AtValue atValue = await atClient.get(atKey);
          final String? jsonVal = atValue.value?.toString();

          if (jsonVal != null && jsonVal.isNotEmpty) {
            final Map<String, dynamic> payload = jsonDecode(jsonVal);

            // 区分是 IM 私聊还是普通社交通知
            if (rawKeyStr.contains('im_msg_')) {
              final imMsg = ImMessageModel.fromJson(payload);
              if (!_deduplicator.isDuplicate(imMsg.messageId)) {
                _onImMessageReceived(AtNotification.empty()..value = jsonVal);
              }
            } else {
              final pushModel = PushNotificationModel.fromJson(payload);
              if (!_deduplicator.isDuplicate(pushModel.notificationId)) {
                _notificationHandler.handleIncomingNotification(pushModel);
              }
            }
          }

          await atClient.delete(atKey);
        } catch (e) {
          debugPrint("❌ [Frontend] 离线通知处理错误 ($rawKeyStr): $e");
        }
      }
    } catch (e) {
      debugPrint("🔴 [Frontend] 离线通知拉取异常 [$regexPattern]: $e");
    }
  }

  /// 统一处理社交通知
  void _onNotificationReceived(AtNotification notification) async {
    String? jsonVal = notification.value;
    if (jsonVal == null) return;

    try {
      Map<String, dynamic> payload = jsonDecode(jsonVal);
      final pushModel = PushNotificationModel.fromJson(payload);

      if (_deduplicator.isDuplicate(pushModel.notificationId)) return;

      final myRealIdStr = UserController.to.user.value?.id;
      if (pushModel.sender.id == myRealIdStr) return;

      _notificationHandler.handleIncomingNotification(pushModel);
    } catch (e) {
      debugPrint("❌ [Frontend] 共享消息处理失败: $e");
    }
  }

  void disconnect() async {
    debugPrint("🔌 [Frontend] 断开连接并清空资源...");
    if (_monitorSubscriptions.isNotEmpty) {
      for (var sub in _monitorSubscriptions) {
        await sub.cancel();
      }
      _monitorSubscriptions.clear();
    }
    _deduplicator.clear();
    isOnboarded.value = false;
    _atClient = null;
  }

  @override
  void onClose() {
    _loginStateWorker?.dispose();
    disconnect();
    super.onClose();
  }
}

class MessageDeduplicator {
  final HashSet<String> _processedIds = HashSet<String>();
  final Duration cacheDuration;

  MessageDeduplicator({this.cacheDuration = const Duration(seconds: 10)});

  bool isDuplicate(String messageId) {
    if (_processedIds.contains(messageId)) return true;
    _processedIds.add(messageId);
    Future.delayed(cacheDuration, () => _processedIds.remove(messageId));
    return false;
  }

  void clear() => _processedIds.clear();
}