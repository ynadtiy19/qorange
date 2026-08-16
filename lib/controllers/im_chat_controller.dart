// lib/controllers/im_chat_controller.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qorange/models/im_message_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final RxBool isUploadingMedia = false.obs;

  // 🌟 陌生人单条防骚扰状态管控
  final RxString relationshipStatus = 'friend'.obs; // friend, stranger_pending, accepted, blocked
  final RxInt strangerMessageCount = 0.obs;
  final RxBool canSend = true.obs;

  // 🌟 个性化聊天背景状态
  final RxString customBgPath = ''.obs;
  final RxString customBgUrl = ''.obs;

  // 展开底部附件面板控制
  final RxBool isAttachmentOpen = false.obs;

  final TextEditingController textEditingController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  int _currentPage = 1;
  bool _hasMore = true;

  @override
  void onInit() {
    super.onInit();
    loadCustomBackground();
    if (relationshipStatus.value == 'stranger_pending' && strangerMessageCount.value >= 1) {
      canSend.value = false;
    }
    fetchHistoryMessages(refresh: true);
  }

  /// 分页拉取历史聊天记录
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
      debugPrint("🔴 [ImChatController] 拉取记录异常: $e");
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
        Fluttertoast.showToast(msg: '网络连接异常，发送失败');
      }
    } finally {
      isSending.value = false;
    }
  }

  /// 🌟 从本地相册/相机选取图片，直传后端二进制接口并发送
  Future<void> pickAndSendImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );

      if (pickedFile == null) return;

      isUploadingMedia.value = true;
      Fluttertoast.showToast(msg: '正在上传图片...');

      final Uint8List imageBytes = await pickedFile.readAsBytes();

      // 向后端二进制接口 POST 上传
      final res = await HttpClient.instance.postBinary<Map<String, dynamic>>(
        '/api-im/upload?type=image&ext=jpg',
        data: imageBytes,
      );

      if (res.datas != null && res.datas!['url'] != null) {
        final String uploadedUrl = res.datas!['url'].toString();
        final int width = res.datas!['width'] as int? ?? 1080;
        final int height = res.datas!['height'] as int? ?? 720;

        await sendMessage(
          msgType: 'image',
          payload: {
            'url': uploadedUrl,
            'width': width,
            'height': height,
          },
        );
      } else {
        Fluttertoast.showToast(msg: '图片上传失败');
      }
    } catch (e) {
      Fluttertoast.showToast(msg: '处理图片异常: $e');
    } finally {
      isUploadingMedia.value = false;
    }
  }

  /// 🌟 直接发送青橙币 (Token Transfer / 红包)
  Future<void> sendTokenTransfer({required double tokens, String remark = '请喝咖啡'}) async {
    if (tokens <= 0) return;
    await sendMessage(
      msgType: 'token_transfer',
      payload: {
        'tokens': tokens,
        'remark': remark.isEmpty ? '请喝咖啡' : remark,
      },
    );
  }

  /// 🌟 发起青橙币请款单 (Token Payment Request)
  Future<void> sendTokenRequest({required double tokens, String remark = '稿费结算'}) async {
    if (tokens <= 0) return;
    await sendMessage(
      msgType: 'token_request',
      payload: {
        'tokens': tokens,
        'remark': remark.isEmpty ? '款项结算' : remark,
      },
    );
  }

  /// 🌟 在聊天气泡内点击【立即支付请款】完成原子扣款
  Future<void> payTokenRequest(String messageId) async {
    try {
      final res = await HttpClient.instance.post<Map<String, dynamic>>(
        '/api-im/token-action',
        data: {
          'message_id': messageId,
          'action': 'pay',
        },
      );

      if (res.respCode == 0) {
        // 本地即时更新该条消息的气泡状态
        final index = messages.indexWhere((m) => m.messageId == messageId);
        if (index != -1) {
          final old = messages[index];
          final updatedPayload = Map<String, dynamic>.from(old.payload);
          updatedPayload['status'] = 'paid';
          updatedPayload['paid_at'] = DateTime.now().toIso8601String();

          messages[index] = ImMessageModel(
            messageId: old.messageId,
            conversationId: old.conversationId,
            senderId: old.senderId,
            recipientId: old.recipientId,
            msgType: old.msgType,
            payload: updatedPayload,
            isRead: old.isRead,
            isRevoked: old.isRevoked,
            createdAt: old.createdAt,
          );
        }
        Fluttertoast.showToast(msg: '青橙币支付成功！');
      } else {
        Fluttertoast.showToast(msg: res.respMsg);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: '支付执行异常: $e');
    }
  }

  /// 🌟 自定义并持久化当前聊天的背景壁纸
  Future<void> setCustomBackground({String? filePath, String? networkUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    if (filePath != null && filePath.isNotEmpty) {
      customBgPath.value = filePath;
      customBgUrl.value = '';
      await prefs.setString('chat_bg_path_$conversationId', filePath);
      await prefs.remove('chat_bg_url_$conversationId');
    } else if (networkUrl != null && networkUrl.isNotEmpty) {
      customBgUrl.value = networkUrl;
      customBgPath.value = '';
      await prefs.setString('chat_bg_url_$conversationId', networkUrl);
      await prefs.remove('chat_bg_path_$conversationId');
    } else {
      // 恢复默认背景
      customBgPath.value = '';
      customBgUrl.value = '';
      await prefs.remove('chat_bg_path_$conversationId');
      await prefs.remove('chat_bg_url_$conversationId');
    }
    Fluttertoast.showToast(msg: '聊天背景已更新');
  }

  Future<void> loadCustomBackground() async {
    final prefs = await SharedPreferences.getInstance();
    customBgPath.value = prefs.getString('chat_bg_path_$conversationId') ?? '';
    customBgUrl.value = prefs.getString('chat_bg_url_$conversationId') ?? '';
  }

  /// 接收到 AtSign 推过来的实时新消息
  void onIncomingMessage(ImMessageModel newMsg) {
    messages.add(newMsg);
    _scrollToBottom();

    if (relationshipStatus.value == 'stranger_pending' && newMsg.senderId == partnerId) {
      relationshipStatus.value = 'accepted';
      canSend.value = true;
    }

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

  /// 同意陌生人沟通请求
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