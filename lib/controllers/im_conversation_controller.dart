// lib/controllers/im_conversation_controller.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:qorange/models/im_message_model.dart';
import '../../network/http_client.dart';
import '../../user_controller.dart';
import 'im_chat_controller.dart';

class ImConversationController extends GetxController {
  static ImConversationController get to => Get.find<ImConversationController>();

  final RxList<ImConversationModel> conversations = <ImConversationModel>[].obs;
  final RxInt totalUnreadCount = 0.obs;
  final RxBool isLoading = false.obs;

  Worker? _userSwitchWorker;

  // 🌟 统一管理：顶部铃铛通知未读红点
  final RxInt unreadNotifCount = 0.obs;

  /// 🌟 轻量拉取铃铛未读数
  Future<void> fetchNotificationBadge() async {
    if (!UserController.to.isLoggedIn) return;
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>('/api-notifications/badge');
      if (res.datas != null) {
        unreadNotifCount.value = int.tryParse(res.datas!['unread_total']?.toString() ?? '0') ?? 0;
      }
    } catch (_) {}
  }
  @override
  void onInit() {
    super.onInit();
    // 监听用户登录状态：切换账号时自动隔离未读数据与刷新会话
    _userSwitchWorker = ever(UserController.to.user, (user) {
      if (UserController.to.isLoggedIn) {
        fetchConversations(refresh: true);
        fetchNotificationBadge(); // 登录时顺便拉取铃铛红点
      } else {
        clearLocalState();
      }
    });

    if (UserController.to.isLoggedIn) {
      fetchConversations(refresh: true);
    }
  }

  /// 🌟 拉取会话列表并计算总未读小红点
  Future<void> fetchConversations({bool refresh = false}) async {
    if (!UserController.to.isLoggedIn) return;

    if (refresh) isLoading.value = true;
    try {
      final res = await HttpClient.instance.get<List<dynamic>>(
        '/api-im/conversations',
        queryParameters: {'page': '1', 'limit': '30'},
      );

      if (res.datas != null) {
        final List<ImConversationModel> list = res.datas!
            .map((e) => ImConversationModel.fromJson(e as Map<String, dynamic>))
            .toList();

        conversations.assignAll(list);
        _recalculateTotalUnread();
      }
    } catch (e) {
      debugPrint("🔴 [ConversationController] 拉取会话列表异常: $e");
    } finally {
      isLoading.value = false;
    }
  }

  /// 🌟 收到 AtSign 实时私聊通知时：动态更新会话最后一条消息并原子累加未读红点
  void onNewMessageReceived(ImMessageModel newMsg, String senderNickname, String senderAvatar) {
    final index = conversations.indexWhere((c) => c.conversationId == newMsg.conversationId);

    String preview = '[新消息]';
    if (newMsg.msgType == 'text') preview = newMsg.payload['text']?.toString() ?? '';
    if (newMsg.msgType == 'image') preview = '[图片]';
    if (newMsg.msgType == 'voice') preview = '[语音]';
    if (newMsg.msgType == 'post_card') preview = '[文章推荐]';
    if (newMsg.msgType == 'poll_card') preview = '[投票邀请]';

    // 检查当前用户是否正打开着这个会话窗口
    bool isCurrentChatActive = false;
    if (Get.isRegistered<ImChatController>(tag: newMsg.conversationId)) {
      isCurrentChatActive = true;
    }

    final int unreadIncrement = isCurrentChatActive ? 0 : 1;

    if (index != -1) {
      final old = conversations[index];
      final updated = ImConversationModel(
        conversationId: old.conversationId,
        partnerId: old.partnerId,
        partnerNickname: old.partnerNickname,
        partnerAvatar: old.partnerAvatar,
        partnerUsername: old.partnerUsername,
        lastMsgPreview: preview,
        lastMsgType: newMsg.msgType,
        unreadCount: old.unreadCount + unreadIncrement,
        relationshipStatus: old.relationshipStatus,
        strangerMessageCount: old.strangerMessageCount,
        updatedAt: DateTime.now(),
      );
      // 移到列表最顶部
      conversations.removeAt(index);
      conversations.insert(0, updated);
    } else {
      // 产生新会话
      final newConv = ImConversationModel(
        conversationId: newMsg.conversationId,
        partnerId: newMsg.senderId,
        partnerNickname: senderNickname,
        partnerAvatar: senderAvatar,
        partnerUsername: '',
        lastMsgPreview: preview,
        lastMsgType: newMsg.msgType,
        unreadCount: unreadIncrement,
        relationshipStatus: 'stranger_pending',
        strangerMessageCount: 1,
        updatedAt: DateTime.now(),
      );
      conversations.insert(0, newConv);
    }

    _recalculateTotalUnread();
  }


  /// 🌟 修复问题 ②：收到撤回事件时，精确判断是否为最新消息才更新列表预览
  void onMessageRevokedInConversation(String conversationId, String revokedMsgId, {bool isLatestMessage = true}) {
    final index = conversations.indexWhere((c) => c.conversationId == conversationId);
    if (index != -1) {
      final old = conversations[index];
      // 只有被撤回的是最新一条，预览才变成“此消息已被撤回”；否则保留原最新预览！
      final String updatedPreview = isLatestMessage ? '此消息已被撤回' : old.lastMsgPreview;

      conversations[index] = ImConversationModel(
        conversationId: old.conversationId,
        partnerId: old.partnerId,
        partnerNickname: old.partnerNickname,
        partnerAvatar: old.partnerAvatar,
        partnerUsername: old.partnerUsername,
        lastMsgPreview: updatedPreview,
        lastMsgType: old.lastMsgType,
        unreadCount: old.unreadCount > 0 ? old.unreadCount - 1 : 0,
        relationshipStatus: old.relationshipStatus,
        strangerMessageCount: old.strangerMessageCount,
        updatedAt: old.updatedAt,
      );
      _recalculateTotalUnread();
    }
  }

  /// 🌟 实现问题 ③：收到对方修改个人资料的 AtSign 信号，毫秒级就地更新头像与昵称（0 接口开销）
  void onPartnerProfileUpdated(String partnerUserId, String newNickname, String newAvatar) {
    for (int i = 0; i < conversations.length; i++) {
      if (conversations[i].partnerId == partnerUserId) {
        final old = conversations[i];
        conversations[i] = ImConversationModel(
          conversationId: old.conversationId,
          partnerId: old.partnerId,
          partnerNickname: newNickname.isNotEmpty ? newNickname : old.partnerNickname,
          partnerAvatar: newAvatar.isNotEmpty ? newAvatar : old.partnerAvatar,
          partnerUsername: old.partnerUsername,
          lastMsgPreview: old.lastMsgPreview,
          lastMsgType: old.lastMsgType,
          unreadCount: old.unreadCount,
          relationshipStatus: old.relationshipStatus,
          strangerMessageCount: old.strangerMessageCount,
          updatedAt: old.updatedAt,
        );
        debugPrint("✨ [Conversation] 实时同步联系人资料成功: $newNickname");
      }
    }
  }
  /// 🌟 进入单聊窗口时：消除该会话的未读数，底部导航栏小红点同步扣减
  void markConversationAsRead(String conversationId) {
    final index = conversations.indexWhere((c) => c.conversationId == conversationId);
    if (index != -1 && conversations[index].unreadCount > 0) {
      final old = conversations[index];
      conversations[index] = ImConversationModel(
        conversationId: old.conversationId,
        partnerId: old.partnerId,
        partnerNickname: old.partnerNickname,
        partnerAvatar: old.partnerAvatar,
        partnerUsername: old.partnerUsername,
        lastMsgPreview: old.lastMsgPreview,
        lastMsgType: old.lastMsgType,
        unreadCount: 0, // 消除未读
        relationshipStatus: old.relationshipStatus,
        strangerMessageCount: old.strangerMessageCount,
        updatedAt: old.updatedAt,
      );
      _recalculateTotalUnread();
    }
  }

  void _recalculateTotalUnread() {
    int sum = 0;
    for (var c in conversations) {
      sum += c.unreadCount;
    }
    totalUnreadCount.value = sum;
  }

  void clearLocalState() {
    conversations.clear();
    totalUnreadCount.value = 0;
    unreadNotifCount.value = 0;
  }

  @override
  void onClose() {
    _userSwitchWorker?.dispose();
    super.onClose();
  }
}