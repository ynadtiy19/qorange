// lib/controllers/im_chat_controller.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:qorange/models/im_message_model.dart';
import '../../network/http_client.dart';
import '../../user_controller.dart';

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
      Fluttertoast.showToast(msg:'网络异常');
    } finally {
      isSending.value = false;
    }
  }

  /// 接收到 AtSign 推过来的实时新消息
  void onIncomingMessage(ImMessageModel newMsg) {
    messages.add(newMsg);
    _scrollToBottom();

    // 如果对方回复了，陌生人锁定自动解除
    if (relationshipStatus.value == 'stranger_pending' && newMsg.senderId == partnerId) {
      relationshipStatus.value = 'accepted';
      canSend.value = true;
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
        Fluttertoast.showToast(msg:'已同意沟通');
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
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