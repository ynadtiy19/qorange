// lib/controllers/im_chat_controller.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
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
  final String partnerAvatar;

  ImChatController({
    required this.conversationId,
    required this.partnerId,
    required this.partnerNickname,
    this.partnerAvatar = '',
  });

  // 🌟 reverse: true 架构下，index 0 为最新消息（位于最底部）
  final RxList<ImMessageModel> messages = <ImMessageModel>[].obs;
  final RxBool isLoadingHistory = false.obs;
  final RxBool isSending = false.obs;
  final RxBool isUploadingMedia = false.obs;

  // 🌟 悬浮回底按钮与未读新消息追踪
  final RxBool showScrollDownBtn = false.obs;
  final RxInt newMessagesWhileBrowsingCount = 0.obs;

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

    _setupScrollListener();
    fetchHistoryMessages(refresh: true);
  }


  // 🌟 新增：独立标记是我拉黑了对方，还是被对方拉黑
  final RxBool isBlockedByMe = false.obs;

  /// 🌟 解除拉黑当前用户
  Future<void> unblockUser() async {
    try {
      final res = await HttpClient.instance.post(
        '/api-im/relationship',
        data: {'action': 'unblock', 'target_user_id': partnerId},
      );
      if (res.respCode == 0) {
        isBlockedByMe.value = false;
        relationshipStatus.value = 'accepted';
        canSend.value = true;
        Fluttertoast.showToast(msg: '已解除拉黑');
      }
    } catch (_) {
      Fluttertoast.showToast(msg: '网络异常');
    }
  }

  /// 🌟 判定最后一条打招呼消息是否是由我发出的
  bool get isLastSenderMe {
    if (messages.isEmpty) return false;
    final myId = UserController.to.user.value?.id ?? '';
    // reverse: true 下 index 0 为最新消息
    return messages.first.senderId == myId;
  }


  /// 🌟 实时向后端发送已读回执 (清零 MongoDB 数据库里的未读数)
  Future<void> sendReadAck() async {
    try {
      await HttpClient.instance.put(
        '/api-im/messages',
        data: {
          'action': 'read_ack',
          'conversation_id': conversationId,
        },
      );
    } catch (_) {}
  }

  /// 🌟 收到对方支付青橙币收款单的实时信号：气泡秒级变为【已完成支付】
  void onTokenRequestStatusChanged(String messageId, String status) {
    final index = messages.indexWhere((m) => m.messageId == messageId);
    if (index != -1) {
      final old = messages[index];
      final updatedPayload = Map<String, dynamic>.from(old.payload);
      updatedPayload['status'] = status;
      if (status == 'paid') {
        updatedPayload['paid_at'] = DateTime.now().toIso8601String();
      }

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

      HapticFeedback.mediumImpact();
      Fluttertoast.showToast(msg: '收款单已到账！');
    }
  }

  /// 监听滚动位置，控制悬浮回底胶囊显隐
  void _setupScrollListener() {
    scrollController.addListener(() {
      if (!scrollController.hasClients) return;
      final offset = scrollController.offset;

      // 在 reverse: true 中，offset > 120 说明用户已向上翻阅历史消息
      if (offset > 120) {
        if (!showScrollDownBtn.value) showScrollDownBtn.value = true;
      } else {
        if (showScrollDownBtn.value) {
          showScrollDownBtn.value = false;
          newMessagesWhileBrowsingCount.value = 0;
        }
      }
    });
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

        // 🌟 转换为 reverse: true 顺序（最新在 0）
        final reversedBatch = loaded.reversed.toList();

        if (refresh) {
          messages.assignAll(reversedBatch);
          if (Get.isRegistered<ImConversationController>()) {
            ImConversationController.to.markConversationAsRead(conversationId);
          }
        } else {
          // 向上加载更多历史：追加在列表尾部（即屏幕顶部）
          messages.addAll(reversedBatch);
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
        // 插入到 index 0（即最底部最新）
        messages.insert(0, sentMsg);
        scrollToBottom();


        // 🌟 核心修复 1：发信成功瞬间，同步将消息大厅该会话的最后一条预览更新为自己刚发的内容！
        if (Get.isRegistered<ImConversationController>()) {
          final myUser = UserController.to.user.value;
          ImConversationController.to.onNewMessageReceived(
            sentMsg,
            partnerNickname, // 保持对方的昵称
            partnerAvatar,   // 保持对方的头像
          );
        }

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

  /// 🌟 撤回消息（2 分钟内）
  Future<void> revokeMessage(String messageId) async {
    try {
      final res = await HttpClient.instance.put<Map<String, dynamic>>(
        '/api-im/messages',
        data: {
          'action': 'revoke',
          'message_id': messageId,
          'conversation_id': conversationId,
        },
      );

      if (res.respCode == 0) {
        onMessageRevoked(messageId);

        // 🌟 核心修复 2：只有当撤回的消息确实是最新一条 (index 0) 时，才把列表卡片改成【此消息已被撤回】！
        final bool isLatest = messages.isNotEmpty && messages.first.messageId == messageId;
        if (Get.isRegistered<ImConversationController>()) {
          ImConversationController.to.onMessageRevokedInConversation(
            conversationId,
            messageId,
            isLatestMessage: isLatest,
          );
        }
        Fluttertoast.showToast(msg: '消息已撤回');
      } else {
        Fluttertoast.showToast(msg: res.respMsg);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: '撤回异常: $e');
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

  /// 🌟 录音二进制数据上传至后端 Cloudinary 并发送语音消息
  Future<void> sendVoiceMessage({
    required Uint8List audioBytes,
    required int durationSec,
  }) async {
    if (audioBytes.isEmpty || durationSec <= 0) return;

    try {
      isUploadingMedia.value = true;
      Fluttertoast.showToast(msg: '正在发送语音...');

      // 1. 发送录音纯二进制流 (type=voice&ext=m4a)
      final res = await HttpClient.instance.postBinary<Map<String, dynamic>>(
        '/api-im/upload?type=voice&ext=m4a',
        data: audioBytes,
      );

      if (res.datas != null && res.datas!['url'] != null) {
        final String audioUrl = res.datas!['url'].toString();
        final int finalDuration = res.datas!['duration_sec'] as int? ?? durationSec;

        // 2. 发送语音消息信封
        await sendMessage(
          msgType: 'voice',
          payload: {
            'url': audioUrl,
            'duration_sec': finalDuration,
          },
        );
      } else {
        Fluttertoast.showToast(msg: '语音上传失败');
      }
    } catch (e) {
      Fluttertoast.showToast(msg: '发送语音异常: $e');
    } finally {
      isUploadingMedia.value = false;
    }
  }

  /// 🌟 保存网络图片到本地设备
  Future<void> saveImageToDevice(String imageUrl) async {
    try {
      Fluttertoast.showToast(msg: '正在保存图片...');
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        Directory? dir;
        if (Platform.isAndroid) {
          dir = await getExternalStorageDirectory();
        } else {
          dir = await getApplicationDocumentsDirectory();
        }

        final fileName = 'qorange_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final savePath = '${dir?.path}/$fileName';
        final file = File(savePath);
        await file.writeAsBytes(response.bodyBytes);

        Fluttertoast.showToast(msg: '图片已保存成功！');
      } else {
        Fluttertoast.showToast(msg: '下载图片失败');
      }
    } catch (e) {
      Fluttertoast.showToast(msg: '保存失败: $e');
    }
  }

  /// 🌟 发送青橙币直接转账
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

  /// 🌟 发起青橙币请款单
  Future<void> sendTokenRequest({required double tokens, String remark = '款项结算'}) async {
    if (tokens <= 0) return;
    await sendMessage(
      msgType: 'token_request',
      payload: {
        'tokens': tokens,
        'remark': remark.isEmpty ? '款项结算' : remark,
      },
    );
  }

  /// 🌟 气泡内点击支付请款
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


  /// 🌟 发送文章推荐卡片
  Future<void> sendPostCard({
    required String postId,
    required String title,
    required String thumbnail,
    String category = 'general',
  }) async {
    await sendMessage(
      msgType: 'post_card',
      payload: {
        'post_id': postId,
        'title': title,
        'thumbnail': thumbnail,
        'category': category,
      },
    );
  }

  /// 🌟 设置并持久化聊天背景
  Future<void> setCustomBackground({String? filePath, String? networkUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    final myId = UserController.to.user.value?.id ?? 'guest';
    final keyPrefix = 'chat_bg_${myId}_$conversationId';

    if (filePath != null && filePath.isNotEmpty) {
      customBgPath.value = filePath;
      customBgUrl.value = '';
      await prefs.setString('${keyPrefix}_path', filePath);
      await prefs.remove('${keyPrefix}_url');
    } else if (networkUrl != null && networkUrl.isNotEmpty) {
      customBgUrl.value = networkUrl;
      customBgPath.value = '';
      await prefs.setString('${keyPrefix}_url', networkUrl);
      await prefs.remove('${keyPrefix}_path');
    } else {
      customBgPath.value = '';
      customBgUrl.value = '';
      await prefs.remove('${keyPrefix}_path');
      await prefs.remove('${keyPrefix}_url');
    }
    Fluttertoast.showToast(msg: '聊天背景已更新');
  }

  Future<void> loadCustomBackground() async {
    final prefs = await SharedPreferences.getInstance();
    final myId = UserController.to.user.value?.id ?? 'guest';
    final keyPrefix = 'chat_bg_${myId}_$conversationId';

    customBgPath.value = prefs.getString('${keyPrefix}_path') ?? '';
    customBgUrl.value = prefs.getString('${keyPrefix}_url') ?? '';
  }

  /// 🌟 收到 AtSign 实时新消息
  void onIncomingMessage(ImMessageModel newMsg) {
    messages.insert(0, newMsg);

    // 如果用户正在向上翻看历史消息，累加未读提醒数；如果在底部，则平滑滚到底部
    if (showScrollDownBtn.value) {
      newMessagesWhileBrowsingCount.value += 1;
      HapticFeedback.lightImpact();
    } else {
      scrollToBottom();
    }

    if (relationshipStatus.value == 'stranger_pending' && newMsg.senderId == partnerId) {
      relationshipStatus.value = 'accepted';
      canSend.value = true;
    }

    if (Get.isRegistered<ImConversationController>()) {
      ImConversationController.to.markConversationAsRead(conversationId);
    }

    // 🌟 核心修复：在聊天窗口中实时收到消息时，静默向后端发送已读回执清空数据库！
    sendReadAck();
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

  /// 滚动到最新底部 (在 reverse: true 中，offset 0 即为最底部)
  void scrollToBottom() {
    newMessagesWhileBrowsingCount.value = 0;
    showScrollDownBtn.value = false;
    Future.delayed(const Duration(milliseconds: 50), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void onClose() {
    // 🌟 核心修复：在聊天窗口中实时收到消息时，静默向后端发送已读回执清空数据库！
    sendReadAck();
    textEditingController.dispose();
    scrollController.dispose();
    super.onClose();
  }
}