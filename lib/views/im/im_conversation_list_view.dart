// lib/views/im/im_conversation_list_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../controllers/im_conversation_controller.dart';
import '../../models/im_message_model.dart';
import 'im_chat_view.dart';

class ImConversationListView extends StatelessWidget {
  const ImConversationListView({super.key});

  static const Color _primaryTeal = Color.fromRGBO(44, 123, 109, 1.0);
  static const Color _bgSlate = Color(0xFFF8FAFC);

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(ImConversationController());

    return Scaffold(
      backgroundColor: _bgSlate,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        title: Row(
          children: [
            const Text(
              '消息',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 8),
            Obx(() {
              if (controller.totalUnreadCount.value == 0) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${controller.totalUnreadCount.value}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              );
            }),
          ],
        ),
        actions: [
          IconButton(
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh, color: Color(0xFF64748B), size: 20),
            onPressed: () {
              HapticFeedback.lightImpact();
              controller.fetchConversations(refresh: true);
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator(color: _primaryTeal, strokeWidth: 2.5));
        }

        if (controller.conversations.isEmpty) {
          return _buildEmptyState();
        }

        return RefreshIndicator(
          color: _primaryTeal,
          onRefresh: () => controller.fetchConversations(refresh: true),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            itemCount: controller.conversations.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final conv = controller.conversations[index];
              return _buildConversationCard(context, conv, controller);
            },
          ),
        );
      }),
    );
  }

  Widget _buildConversationCard(BuildContext context, ImConversationModel conv, ImConversationController controller) {
    final avatar = conv.partnerAvatar.isNotEmpty
        ? conv.partnerAvatar
        : 'https://api.dicebear.com/7.x/micah/png?seed=${conv.partnerNickname.hashCode}';

    final isStranger = conv.relationshipStatus == 'stranger_pending';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.lightImpact();
          controller.markConversationAsRead(conv.conversationId);
          Get.to(
                () => ImChatView(
              conversationId: conv.conversationId,
              partnerId: conv.partnerId,
              partnerNickname: conv.partnerNickname,
              partnerAvatar: avatar,
              initialRelationshipStatus: conv.relationshipStatus,
            ),
            routeName: '/im_chat_${conv.conversationId}', // 🌟 加上这一行
            transition: Transition.cupertino,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Row(
            children: [
              // 1. 头像 + 陌生人标识
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(avatar, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
                      return Container(width: 48, height: 48, color: const Color(0xFFE2E8F0));
                    }),
                  ),
                  if (isStranger)
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(Icons.help_outline_rounded, color: Colors.white, size: 10),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),

              // 2. 昵称 + 消息预览
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            conv.partnerNickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                          ),
                        ),
                        Text(
                          _formatTime(conv.updatedAt),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            conv.lastMsgPreview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: conv.unreadCount > 0 ? const Color(0xFF334155) : const Color(0xFF64748B),
                              fontWeight: conv.unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        // 3. 单会话未读红点徽标
                        if (conv.unreadCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _primaryTeal,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${conv.unreadCount}',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
            child: const HugeIcon(icon: HugeIcons.strokeRoundedBubbleChat, color: Color(0xFF94A3B8), size: 36),
          ),
          const SizedBox(height: 16),
          const Text('暂无私信消息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
          const SizedBox(height: 6),
          const Text('去创作者主页或社群，开启第一句思想交流吧', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0 && now.day == dt.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}/${dt.day}';
  }
}