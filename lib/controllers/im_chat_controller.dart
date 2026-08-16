// lib/controllers/im_chat_controller.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:qorange/models/im_message_model.dart';
import '../../network/api_exception.dart';
import '../../network/http_client.dart';
import '../../user_controller.dart';
import 'im_conversation_controller.dart';

class ImChatController extends GetxController {
  final String conversationId;
  final String partnerId;
  final String partnerNickname;

  ImChatController({
    required this.conversationId,
    required this.partnerId,
    required this.partnerNickname,
  });

  final RxList<ImMessageModel> messages = <ImMessageModel>[].obs;
  final RxBool isLoadingHistory = false.obs;
  final RxBool isSending = false.obs;

  // 🌟 陌生人单条防骚扰状态管控
  final RxString relationshipStatus = 'friend'.obs; // friend, stranger_pending, accepted, blocked
  final RxInt strangerMessageCount = 0.obs;
  final RxBool canSend = true.obs;

  final TextEditingController textEditingController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  int _currentPage = 1;
  bool _hasMore = true;

  @override
  void onInit() {
    super.onInit();
    // 初始化时如果处于陌生人待批准状态且已有发信记录，锁定发信按钮
    if (relationshipStatus.value == 'stranger_pending' && strangerMessageCount.value >= 1) {
      canSend.value = false;
    }
    fetchHistoryMessages(refresh: true);
  }

  /// 分页拉取历史聊天记录 (上拉加载)
  Future<void> fetchHistoryMessages({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
    }
    if (!_hasMore || isLoadingHistory.value) return;

    isLoadingHistory.value = true;
    try {
      final res = await HttpClient.instance.get<List<dynamic>>(
        '/api-im/messages',
        queryParameters: {
          'conversation_id': conversationId,
          'page': _currentPage.toString(),
          'limit': '25',
        },
      );

      if (res.datas != null) {
        final List<ImMessageModel> loaded = res.datas!
            .map((item) => ImMessageModel.fromJson(item as Map<String, dynamic>))
            .toList();

        if (refresh) {
          messages.assignAll(loaded);
          // 首次进入成功加载后，精准消除本会话未读红点
          if (Get.isRegistered<ImConversationController>()) {
            ImConversationController.to.markConversationAsRead(conversationId);
          }
          _scrollToBottom(immediate: true);
        } else {
          messages.insertAll(0, loaded);
        }

        if (loaded.length < 25) _hasMore = false;
        _currentPage++;
      }
    } catch (e) {
      debugPrint("🔴 [ImChatController] 拉取聊天记录失败: $e");
    } finally {
      isLoadingHistory.value = false;
    }
  }

  /// 🌟 统一发送多模态即时消息
  Future<void> sendMessage({
    required String msgType,
    required Map<String, dynamic> payload,
  }) async {
    if (!canSend.value) {
      Fluttertoast.showToast(msg: '需等待对方回复后方可继续发送消息');
      return;
    }

    isSending.value = true;
    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-im/send',
        data: {
          'recipient_id': partnerId,
          'msg_type': msgType,
          'payload': payload,
        },
      );

      if (res.datas != null) {
        final sentMsg = ImMessageModel.fromJson(res.datas!);
        messages.add(sentMsg);
        _scrollToBottom();

        if (msgType == 'text') textEditingController.clear();

        // 如果是陌生人状态，发完一条立刻置灰锁定
        if (relationshipStatus.value == 'stranger_pending') {
          strangerMessageCount.value += 1;
          canSend.value = false;
        }
      } else {
        if (res.respCode == 429) {
          canSend.value = false;
          Fluttertoast.showToast(msg: res.respMsg);
        }
      }
    } catch (e) {
      if (e is ApiException) {
        Fluttertoast.showToast(msg: e.message);
      } else {
        Fluttertoast.showToast(msg: '网络连接异常，请重试');
      }
    } finally {
      isSending.value = false;
    }
  }

  /// 接收到 AtSign 推过来的实时新消息
  void onIncomingMessage(ImMessageModel newMsg) {
    messages.add(newMsg);
    _scrollToBottom();

    // 对方回复了，解除陌生人锁定
    if (relationshipStatus.value == 'stranger_pending' && newMsg.senderId == partnerId) {
      relationshipStatus.value = 'accepted';
      canSend.value = true;
    }

    // 消除已在查看中的会话红点
    if (Get.isRegistered<ImConversationController>()) {
      ImConversationController.to.markConversationAsRead(conversationId);
    }
  }

  /// 接收到撤回信号
  void onMessageRevoked(String messageId) {
    final index = messages.indexWhere((m) => m.messageId == messageId);
    if (index != -1) {
      final old = messages[index];
      messages[index] = ImMessageModel(
        messageId: old.messageId,
        conversationId: old.conversationId,
        senderId: old.senderId,
        recipientId: old.recipientId,
        msgType: 'text',
        payload: {'text': '此消息已被撤回'},
        isRead: old.isRead,
        isRevoked: true,
        createdAt: old.createdAt,
      );
    }
  }

  /// 同意陌生人沟通请求 (收信人点击)
  Future<void> acceptStrangerRequest() async {
    try {
      final res = await HttpClient.instance.post(
        '/api-im/relationship',
        data: {'action': 'accept_stranger', 'target_user_id': partnerId},
      );
      if (res.respCode == 0) {
        relationshipStatus.value = 'accepted';
        canSend.value = true;
        Fluttertoast.showToast(msg: '已同意沟通，信道已完全解锁');
      }
    } catch (_) {}
  }

  /// 拉黑当前用户
  Future<void> blockUser() async {
    try {
      final res = await HttpClient.instance.post(
        '/api-im/relationship',
        data: {'action': 'block', 'target_user_id': partnerId},
      );
      if (res.respCode == 0) {
        relationshipStatus.value = 'blocked';
        canSend.value = false;
        Fluttertoast.showToast(msg: '已将该用户加入黑名单');
      }
    } catch (_) {}
  }

  void _scrollToBottom({bool immediate = false}) {
    final duration = immediate ? Duration.zero : const Duration(milliseconds: 250);
    Future.delayed(const Duration(milliseconds: 50), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: duration,
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void onClose() {
    textEditingController.dispose();
    scrollController.dispose();
    super.onClose();
  }
}