// lib/views/im/im_conversation_list_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:qorange/theme.dart';
import '../../controllers/im_conversation_controller.dart';
import '../../controllers/notification_center_controller.dart';
import '../../models/im_message_model.dart';
import '../notification/notification_center_view.dart';
import 'im_chat_view.dart';

class ImConversationListView extends StatelessWidget {
  const ImConversationListView({super.key});

  static Color get _primaryTeal => AppColors.primary;
  static Color get _bgSlate => AppColors.background;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(ImConversationController());

    return Scaffold(
      backgroundColor: _bgSlate,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        title: Row(
          children: [
            Text(
              'nav_messages'.tr,
              style: TextStyle(
                color: AppColors.textPrimary,
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
          // 🌟 核心修复：直接使用当前大厅控制器的 unreadNotifCount，干干净净，杜绝重复注入！
          Obx(() {
            final unreadCount = controller.unreadNotifCount.value;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedNotification03,
                    color: AppColors.textPrimary,
                    size: 22,
                  ),
                  tooltip: 'notification_center'.tr,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Get.to(
                          () => const NotificationCenterView(),
                      transition: Transition.cupertino,
                    );
                  },
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Center(
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),

          IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, color: AppColors.textSecondary, size: 20),
            onPressed: () {
              HapticFeedback.lightImpact();
              controller.fetchConversations(refresh: true);
              controller.fetchNotificationBadge(); // 刷新时同步刷新铃铛
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return Center(child: CircularProgressIndicator(color: _primaryTeal, strokeWidth: 2.5));
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

    return Material(color: AppColors.surface,
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
            border: Border.all(color: AppColors.surfaceAlt),
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
                      return Container(width: 48, height: 48, color: AppColors.divider);
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
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                          ),
                        ),
                        Text(
                          _formatTime(conv.updatedAt),
                          style: TextStyle(fontSize: 11, color: AppColors.textHint, fontWeight: FontWeight.w500),
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
                              color: conv.unreadCount > 0 ? AppColors.textPrimary : AppColors.textSecondary,
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
            decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
            child: HugeIcon(icon: HugeIcons.strokeRoundedBubbleChat, color: AppColors.textHint, size: 36),
          ),
          const SizedBox(height: 16),
          Text('im_empty_title'.tr, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text('im_empty_sub'.tr, style: TextStyle(fontSize: 13, color: AppColors.textHint)),
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