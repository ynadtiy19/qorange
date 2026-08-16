// lib/views/im/im_chat_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../controllers/im_chat_controller.dart';
import '../../models/im_message_model.dart';
import '../../user_controller.dart';
import '../post_detail/post_detail_view.dart';

class ImChatView extends StatelessWidget {
  final String conversationId;
  final String partnerId;
  final String partnerNickname;
  final String partnerAvatar;
  final String initialRelationshipStatus;

  const ImChatView({
    super.key,
    required this.conversationId,
    required this.partnerId,
    required this.partnerNickname,
    required this.partnerAvatar,
    this.initialRelationshipStatus = 'friend',
  });

  static const Color _primaryTeal = Color.fromRGBO(44, 123, 109, 1.0);
  static const Color _bgSlate = Color(0xFFF8FAFC);

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(
      ImChatController(
        conversationId: conversationId,
        partnerId: partnerId,
        partnerNickname: partnerNickname,
      ),
      tag: conversationId, // 标签隔离，防止多会话串流
    );

    controller.relationshipStatus.value = initialRelationshipStatus;
    final myId = UserController.to.user.value?.id ?? '';

    return Scaffold(
      backgroundColor: _bgSlate,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF1E293B)),
          onPressed: () => Get.back(),
        ),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(partnerAvatar, width: 34, height: 34, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  partnerNickname,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Obx(() => Text(
                  controller.relationshipStatus.value == 'stranger_pending' ? '陌生人消息请求' : '在线',
                  style: TextStyle(
                    fontSize: 11,
                    color: controller.relationshipStatus.value == 'stranger_pending' ? const Color(0xFFD97706) : _primaryTeal,
                    fontWeight: FontWeight.w600,
                  ),
                )),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreHorizontal, color: Color(0xFF64748B), size: 22),
            onPressed: () => _showMoreOptionsModal(context, controller),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // 1. 陌生人审核提示悬浮横幅
          Obx(() {
            if (controller.relationshipStatus.value == 'stranger_pending') {
              return _buildStrangerBanner(controller);
            }
            return const SizedBox.shrink();
          }),

          // 2. 消息气泡流
          Expanded(
            child: Obx(() {
              if (controller.isLoadingHistory.value && controller.messages.isEmpty) {
                return const Center(child: CircularProgressIndicator(color: _primaryTeal, strokeWidth: 2));
              }

              return ListView.builder(
                controller: controller.scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: controller.messages.length,
                itemBuilder: (context, index) {
                  final msg = controller.messages[index];
                  final bool isMe = msg.senderId == myId;
                  return _buildMessageBubble(context, msg, isMe);
                },
              );
            }),
          ),

          // 3. 底部自适应输入工具栏
          _buildInputBar(context, controller),
        ],
      ),
    );
  }

  /// 陌生人审核横幅
  Widget _buildStrangerBanner(ImChatController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFBEB),
        border: Border(bottom: BorderSide(color: Color(0xFFFDE68A))),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFFD97706), size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '对方为未互关陌生人，仅可发送 1 条打招呼私信',
              style: TextStyle(fontSize: 12, color: Color(0xFF92400E), fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () => controller.acceptStrangerRequest(),
            style: TextButton.styleFrom(
              backgroundColor: _primaryTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('同意沟通', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// 多模态气泡构建器
  Widget _buildMessageBubble(BuildContext context, ImMessageModel msg, bool isMe) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: isMe ? _primaryTeal : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 18),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: _buildBubbleContent(msg, isMe),
          ),
        ],
      ),
    );
  }

  Widget _buildBubbleContent(ImMessageModel msg, bool isMe) {
    final textColor = isMe ? Colors.white : const Color(0xFF1E293B);

    if (msg.msgType == 'text') {
      return Text(
        msg.payload['text']?.toString() ?? '',
        style: TextStyle(fontSize: 14.5, height: 1.5, color: textColor, fontWeight: FontWeight.w500),
      );
    } else if (msg.msgType == 'image') {
      final imgUrl = msg.payload['url']?.toString() ?? '';
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(imgUrl, fit: BoxFit.cover),
      );
    } else if (msg.msgType == 'post_card') {
      // 🌟 文章分享卡片
      final title = msg.payload['title']?.toString() ?? '文章推荐';
      final postId = msg.payload['post_id']?.toString() ?? '';
      return InkWell(
        onTap: () => Get.to(() => PostDetailView(postId: postId)),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isMe ? Colors.white.withOpacity(0.15) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.article_rounded, size: 16, color: isMe ? Colors.white70 : _primaryTeal),
                  const SizedBox(width: 6),
                  Text('文章推荐', style: TextStyle(fontSize: 11, color: isMe ? Colors.white70 : _primaryTeal, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: textColor)),
            ],
          ),
        ),
      );
    }

    return Text(msg.payload['text']?.toString() ?? '[消息]', style: TextStyle(color: textColor));
  }

  /// 底部工具输入栏
  Widget _buildInputBar(BuildContext context, ImChatController controller) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: controller.textEditingController,
                textInputAction: TextInputAction.send,
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    controller.sendMessage(msgType: 'text', payload: {'text': val.trim()});
                  }
                },
                decoration: const InputDecoration(
                  hintText: '输入消息...',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _primaryTeal,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                HapticFeedback.lightImpact();
                final text = controller.textEditingController.text.trim();
                if (text.isNotEmpty) {
                  controller.sendMessage(msgType: 'text', payload: {'text': text});
                }
              },
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreOptionsModal(BuildContext context, ImChatController controller) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.block_flipped, color: Color(0xFFEF4444)),
              title: const Text('拉黑此用户', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
              onTap: () {
                Get.back();
                // 触发拉黑 API
              },
            ),
          ],
        ),
      ),
    );
  }
}