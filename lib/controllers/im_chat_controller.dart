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

  ImChatController({
    required this.conversationId,
    required this.partnerId,
    required this.partnerNickname,
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
    textEditingController.dispose();
    scrollController.dispose();
    super.onClose();
  }
}