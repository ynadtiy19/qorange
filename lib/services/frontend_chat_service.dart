// lib/services/frontend_chat_service.dart (双独立通道定向通配监听 + IM 私聊 + 通知中心全模态监听完全体)
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

import '../../controllers/im_chat_controller.dart';
import '../../controllers/im_conversation_controller.dart';
import '../../controllers/notification_center_controller.dart';
import '../../user_controller.dart';
import 'notification_handler_service.dart';

class FrontendChatService extends GetxService {
  static const String myAtsign = '@gemini2banana';
  static const String nameSpace = 'atsign';
  static const String rootDomain = 'root.atsign.org';

  final MessageDeduplicator _deduplicator = MessageDeduplicator();
  final NotificationHandlerService _notificationHandler = Get.put(NotificationHandlerService());

  final RxBool isOnboarded = false.obs;
  AtClient? _atClient;

  final List<StreamSubscription<dynamic>> _monitorSubscriptions = [];
  Worker? _loginStateWorker;

  @override
  void onInit() {
    super.onInit();
    _loginStateWorker = ever(UserController.to.user, (user) {
      if (UserController.to.isLoggedIn) {
        if (isOnboarded.value && _atClient != null) {
          Future.microtask(() => _startFrontendMonitor(_atClient!));
        } else {
          authenticate();
        }

        // 🌟 账号切换时重载会话列表
        if (Get.isRegistered<ImConversationController>()) {
          ImConversationController.to.fetchConversations(refresh: true);
        }
      } else {
        disconnect();
        // 🌟 账号登出时清空会话数据
        if (Get.isRegistered<ImConversationController>()) {
          ImConversationController.to.clearLocalState();
        }
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
    if (myRealIdStr == 'none' || myRealIdStr.isEmpty) return;

    // 1. 离线缓存拉取 (包含 notif_msg_ 与 im_msg_)
    await _pullKeysByRegex(atClient, 'push_message_$myRealIdStr');
    await _pullKeysByRegex(atClient, 'push_message_all');
    await _pullKeysByRegex(atClient, 'im_msg_$myRealIdStr');
    await _pullKeysByRegex(atClient, 'notif_msg_$myRealIdStr');

    // 2. 注册多路复用正则监听通道
    final String broadcastRegex = 'push_message_all.*\\.$nameSpace@';
    final String personalRegex = 'push_message_$myRealIdStr.*\\.$nameSpace@';
    final String imMessageRegex = 'im_msg_$myRealIdStr.*\\.$nameSpace@';
    final String imStatusRegex = 'im_status_$myRealIdStr.*\\.$nameSpace@';
    final String notifCenterRegex = 'notif_msg_$myRealIdStr.*\\.$nameSpace@';

    debugPrint("🎧 [Frontend] 开启监听 - 广播通道: $broadcastRegex");
    debugPrint("🎧 [Frontend] 开启监听 - 社交通道: $personalRegex");
    debugPrint("🎧 [Frontend] 开启监听 - IM私聊通道: $imMessageRegex");
    debugPrint("🎧 [Frontend] 开启监听 - 通知中心通道: $notifCenterRegex");

    try {
      final broadcastSub = atClient.notificationService
          .subscribe(regex: broadcastRegex, shouldDecrypt: true)
          .listen(_onNotificationReceived, onError: (e) => debugPrint("🔴 广播通道监听错误: $e"));

      final personalSub = atClient.notificationService
          .subscribe(regex: personalRegex, shouldDecrypt: true)
          .listen(_onNotificationReceived, onError: (e) => debugPrint("🔴 个人通道监听错误: $e"));

      final imSub = atClient.notificationService
          .subscribe(regex: imMessageRegex, shouldDecrypt: true)
          .listen(_onImMessageReceived, onError: (e) => debugPrint("🔴 IM通道监听错误: $e"));

      final statusSub = atClient.notificationService
          .subscribe(regex: imStatusRegex, shouldDecrypt: true)
          .listen(_onImStatusReceived, onError: (e) => debugPrint("🔴 状态通道监听错误: $e"));

      final notifSub = atClient.notificationService
          .subscribe(regex: notifCenterRegex, shouldDecrypt: true)
          .listen(_onNotifCenterMessageReceived, onError: (e) => debugPrint("🔴 通知中心监听错误: $e"));

      _monitorSubscriptions.addAll([broadcastSub, personalSub, imSub, statusSub, notifSub]);
    } catch (e) {
      debugPrint("❌ [Frontend] 注册 AtSign 订阅服务发生异常: $e");
    }
  }

  void _onNotifCenterMessageReceived(AtNotification notification) async {
    final String? jsonVal = notification.value;
    if (jsonVal == null || jsonVal.isEmpty) return;

    try {
      final Map<String, dynamic> eventPayload = jsonDecode(jsonVal);
      final String eventType = eventPayload['event_type']?.toString() ?? 'upsert_notif';
      final dynamic rawData = eventPayload['data'];

      // 1. 通知大厅与铃铛红点同步
      if (Get.isRegistered<NotificationCenterController>()) {
        NotificationCenterController.to.onAtSignEventReceived(eventPayload);
      }

      final int unreadTotal = int.tryParse(eventPayload['unread_total']?.toString() ?? '') ?? -1;
      if (unreadTotal >= 0 && Get.isRegistered<ImConversationController>()) {
        ImConversationController.to.unreadNotifCount.value = unreadTotal;
      }

      // 2. 状态栏通知唤醒
      if (eventType == 'upsert_notif' && rawData is Map) {
        final Map<String, dynamic> payload = Map<String, dynamic>.from(rawData);
        final String notifId = payload['id']?.toString() ?? payload['_id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
        if (_deduplicator.isDuplicate(notifId)) return;

        final String displayTitle = payload['display_title']?.toString() ?? '新社交动态';
        final String category = payload['tab_category']?.toString() ?? 'social';
        final String actionType = payload['action_type']?.toString() ?? 'like';
        final target = payload['target'] as Map? ?? {};
        final actors = payload['latest_actors'] as List? ?? [];
        final firstActor = actors.isNotEmpty ? (actors.first as Map) : {};

        final String contentSnippet = payload['context_data']?['comment_content']?.toString() ??
            target['title']?.toString() ??
            target['snippet']?.toString() ??
            '';

        final note = PushNotificationModel.fromJson({
          'notification_id': notifId,
          'recipient_id': payload['recipient_id'] ?? '',
          'category': category,
          'type': actionType,
          'sender': {
            'id': firstActor['user_id'] ?? '',
            'nickname': firstActor['nickname'] ?? '用户',
            'avatar': firstActor['avatar'] ?? '',
            'atsign': '',
          },
          'target': {
            'id': target['target_id'] ?? '',
            'title': target['title'] ?? '',
            'type': target['target_type'] ?? 'post',
          },
          'custom_data': {
            'title': displayTitle,
            'content': contentSnippet,
          },
          'timestamp': DateTime.now().toIso8601String(),
        });

        _notificationHandler.handleIncomingNotification(note);
      }
    } catch (e) {
      debugPrint("🔴 [Frontend] 通知中心 AtSign 事件解析异常: $e");
    }
  }

  void _onImMessageReceived(AtNotification notification) async {
    final String? jsonVal = notification.value;
    if (jsonVal == null || jsonVal.isEmpty) return;

    try {
      final Map<String, dynamic> payload = jsonDecode(jsonVal);
      final imMsg = ImMessageModel.fromJson(payload);

      if (_deduplicator.isDuplicate(imMsg.messageId)) return;

      final String senderName = payload['sender_nickname']?.toString() ?? '用户';
      final String senderAvatar = payload['sender_avatar']?.toString() ?? '';

      if (Get.isRegistered<ImChatController>(tag: imMsg.conversationId)) {
        final chatCtrl = Get.find<ImChatController>(tag: imMsg.conversationId);
        chatCtrl.onIncomingMessage(imMsg);

        if (Get.isRegistered<ImConversationController>()) {
          ImConversationController.to.onNewMessageReceived(imMsg, senderName, senderAvatar);
        }
        return;
      }

      if (Get.isRegistered<ImConversationController>()) {
        ImConversationController.to.onNewMessageReceived(imMsg, senderName, senderAvatar);
      }

      String preview = '[新私信]';
      if (imMsg.msgType == 'text') {
        preview = imMsg.payload['text']?.toString() ?? '';
      } else if (imMsg.msgType == 'image') {
        preview = '[图片]';
      } else if (imMsg.msgType == 'voice') {
        preview = '[语音]';
      } else if (imMsg.msgType == 'token_transfer') {
        preview = '[青橙币转账]';
      } else if (imMsg.msgType == 'token_request') {
        preview = '[收款请款单]';
      } else if (imMsg.msgType == 'post_card') {
        preview = '[文章推荐]';
      }

      final note = PushNotificationModel.fromJson({
        'notification_id': imMsg.messageId,
        'recipient_id': imMsg.recipientId,
        'category': 'social',
        'type': 'im_chat',
        'sender': {
          'id': imMsg.senderId,
          'nickname': senderName,
          'avatar': senderAvatar,
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

  void _onImStatusReceived(AtNotification notification) async {
    final String? jsonVal = notification.value;
    if (jsonVal == null || jsonVal.isEmpty) return;

    try {
      final Map<String, dynamic> data = jsonDecode(jsonVal);
      final signalType = data['signal_type']?.toString();
      final conversationId = data['conversation_id']?.toString();

      if (conversationId == null) return;

      final String targetUserId = data['extra']?['user_id']?.toString() ?? '';
      final String newNick = data['extra']?['nickname']?.toString() ?? '';
      final String newAvatar = data['extra']?['avatar']?.toString() ?? '';

      if (Get.isRegistered<ImChatController>(tag: conversationId)) {
        final chatCtrl = Get.find<ImChatController>(tag: conversationId);

        if (signalType == 'revoke') {
          final String msgId = data['extra']?['message_id']?.toString() ?? '';
          chatCtrl.onMessageRevoked(msgId);
        } else if (signalType == 'token_request_status_change') {
          final String msgId = data['extra']?['message_id']?.toString() ?? '';
          final String status = data['extra']?['status']?.toString() ?? 'paid';
          chatCtrl.onTokenRequestStatusChanged(msgId, status);
        } else if (signalType == 'profile_updated') {
          if (chatCtrl.partnerId == targetUserId || targetUserId.isEmpty) {
            chatCtrl.onPartnerProfileUpdated(newNick, newAvatar);
          }
        }
      }

      if (Get.isRegistered<ImConversationController>()) {
        if (signalType == 'revoke') {
          final String msgId = data['extra']?['message_id']?.toString() ?? '';
          final bool isLatest = data['extra']?['is_latest_message'] == true;
          ImConversationController.to.onMessageRevokedInConversation(
            conversationId,
            msgId,
            isLatestMessage: isLatest,
          );
        } else if (signalType == 'profile_updated') {
          if (targetUserId.isNotEmpty) {
            ImConversationController.to.onPartnerProfileUpdated(targetUserId, newNick, newAvatar);
          }
        }
      }
    } catch (e) {
      debugPrint("🔴 [Frontend] 状态信号解析异常: $e");
    }
  }

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

            if (rawKeyStr.contains('im_msg_')) {
              final imMsg = ImMessageModel.fromJson(payload);
              if (!_deduplicator.isDuplicate(imMsg.messageId)) {
                _onImMessageReceived(AtNotification.empty()..value = jsonVal);
              }
            } else if (rawKeyStr.contains('notif_msg_')) {
              _onNotifCenterMessageReceived(AtNotification.empty()..value = jsonVal);
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