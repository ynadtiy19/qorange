// lib/views/notification/notification_center_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../controllers/notification_center_controller.dart';
import '../../models/notification_model.dart';
import '../post_detail/post_detail_view.dart';
import '../profile/profile_view.dart';
import '../wallet/wallet_view.dart';

class NotificationCenterView extends StatefulWidget {
  const NotificationCenterView({super.key});

  @override
  State<NotificationCenterView> createState() => _NotificationCenterViewState();
}

class _NotificationCenterViewState extends State<NotificationCenterView>
    with SingleTickerProviderStateMixin {
  late NotificationCenterController _controller;
  late TabController _tabController;

  static const Color _primaryTeal = Color.fromRGBO(44, 123, 109, 1.0);
  static const Color _bgSlate = Color(0xFFF8FAFC);

  final List<Map<String, dynamic>> _tabsConfig = [
    {
      'key': 'all',
      'label': '全部',
      'icon': HugeIcons.strokeRoundedGrid,
      'color': const Color(0xFF2C7B6D),
    },
    {
      'key': 'like',
      'label': '赞与收藏',
      'icon': HugeIcons.strokeRoundedFavourite,
      'color': const Color(0xFFEF4444),
    },
    {
      'key': 'comment',
      'label': '评论回复',
      'icon': HugeIcons.strokeRoundedComment01,
      'color': const Color(0xFF3B82F6),
    },
    {
      'key': 'follow',
      'label': '新增关注',
      'icon': HugeIcons.strokeRoundedUserAdd01,
      'color': const Color(0xFF10B981),
    },
    {
      'key': 'system',
      'label': '系统通知',
      'icon': HugeIcons.strokeRoundedNotification03,
      'color': const Color(0xFFF59E0B),
    },
  ];

  @override
  void initState() {
    super.initState();
    _controller = Get.put(NotificationCenterController());
    _tabController = TabController(length: _tabsConfig.length, vsync: this);

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final currentKey = _tabsConfig[_tabController.index]['key'];
        _controller.switchTab(currentKey);
      }
    });

    _controller.markTabAsRead('all');
  }

  @override
  void dispose() {
    _tabController.dispose();
    Get.delete<NotificationCenterController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgSlate,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedArrowLeft01,
            color: Color(0xFF1E293B),
            size: 20,
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            Get.back();
          },
        ),
        title: const Text(
          '通知中心',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedCheckmarkBadge01,
              color: Color(0xFF64748B),
              size: 22,
            ),
            tooltip: '全部标为已读',
            onPressed: () {
              HapticFeedback.mediumImpact();
              _controller.markTabAsRead('all');
              for (final def in _tabsConfig) {
                _controller.fetchTabNotifications(def['key'], isRefresh: true);
              }
              Fluttertoast.showToast(msg: '已全部标为已读');
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              labelColor: _primaryTeal,
              unselectedLabelColor: const Color(0xFF94A3B8),
              indicatorColor: _primaryTeal,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              onTap: (index) => HapticFeedback.selectionClick(),
              tabs: _tabsConfig.map((t) => _buildTabItem(t)).toList(),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabsConfig.map((def) {
          final String tabKey = def['key'];
          return _buildTabListView(tabKey);
        }).toList(),
      ),
    );
  }

  Widget _buildTabItem(Map<String, dynamic> tabConfig) {
    final String key = tabConfig['key'];
    final String label = tabConfig['label'];
    final dynamic iconData = tabConfig['icon'];
    final Color iconColor = tabConfig['color'];

    return Obx(() {
      final summary = _controller.unreadSummary.value;
      int unread = 0;
      if (key == 'all') unread = summary.all;
      if (key == 'like') unread = summary.like;
      if (key == 'comment') unread = summary.comment;
      if (key == 'follow') unread = summary.follow;
      if (key == 'system') unread = summary.system;

      return Tab(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HugeIcon(
              icon: iconData,
              size: 16,
              color: iconColor,
            ),
            const SizedBox(width: 6),
            Text(label),
            if (unread > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  /// 🌟 独立 Tab 列表：绑定独立物理 ScrollController，完美记忆各页面滚动位与分页数
  Widget _buildTabListView(String tabKey) {
    final state = _controller.tabStates[tabKey]!;

    return Obx(() {
      if (state.isLoading.value) {
        return const Center(
          child: CircularProgressIndicator(
            color: _primaryTeal,
            strokeWidth: 2.5,
          ),
        );
      }

      if (state.list.isEmpty) {
        return _buildEmptyState();
      }

      return RefreshIndicator(
        color: _primaryTeal,
        backgroundColor: Colors.white,
        onRefresh: () => _controller.fetchTabNotifications(tabKey, isRefresh: true),
        child: ListView.separated(
          key: PageStorageKey<String>('notif_tab_$tabKey'), // 物理保持视图状态
          controller: state.scrollController,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          itemCount: state.list.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == state.list.length) {
              return Obx(() {
                if (state.isLoadingMore.value) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: _primaryTeal, strokeWidth: 2),
                      ),
                    ),
                  );
                }
                if (!state.hasMore.value && state.list.length >= 10) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        '已加载全部通知',
                        style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              });
            }

            final item = state.list[index];
            return _NotificationCardItem(
              notif: item,
              primaryTeal: _primaryTeal,
            );
          },
        ),
      );
    });
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const HugeIcon(
              icon: HugeIcons.strokeRoundedNotification03,
              color: Color(0xFF94A3B8),
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '暂无相关通知',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '当有互动动态时，会在此处即时提醒',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

/// 🌟 独立卡片组件（层级化评论与富文章元数据）
class _NotificationCardItem extends StatefulWidget {
  final NotificationItemModel notif;
  final Color primaryTeal;

  const _NotificationCardItem({
    required this.notif,
    required this.primaryTeal,
  });

  @override
  State<_NotificationCardItem> createState() => _NotificationCardItemState();
}

class _NotificationCardItemState extends State<_NotificationCardItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final notif = widget.notif;
    final target = notif.target;
    final targetType = target['target_type']?.toString() ?? 'post';
    final targetId = target['target_id']?.toString() ?? '';
    final thumbnail = target['thumbnail']?.toString() ?? '';
    final postTitle = target['title']?.toString() ?? '';
    final category = (target['category']?.toString() ?? '专栏').toUpperCase();
    final avatar = notif.actorAvatars.isNotEmpty ? notif.actorAvatars.first : '';

    final contextData = notif.contextData;
    final isReply = notif.actionType == 'reply_comment';
    final isComment = notif.actionType == 'comment_post';
    final isDeleted = contextData['is_comment_deleted'] == true;

    final String commentText = contextData['comment_content']?.toString() ?? '';
    final String myOriginalComment = contextData['my_original_comment']?.toString() ?? '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.lightImpact();
          if (targetType == 'post' && targetId.isNotEmpty) {
            Get.to(() => PostDetailView(postId: targetId));
          } else if (targetType == 'user' && targetId.isNotEmpty) {
            Get.to(() => ProfileView(profileId: targetId));
          } else if (targetType == 'wallet') {
            Get.to(() => const WalletView());
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: notif.isRead
                  ? const Color(0xFFF1F5F9)
                  : widget.primaryTeal.withOpacity(0.25),
              width: notif.isRead ? 0.8 : 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 发送者头像 + 动作标题 + 时间
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          avatar.isNotEmpty
                              ? avatar
                              : 'https://api.dicebear.com/7.x/micah/png?seed=${notif.id.hashCode}',
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 40,
                            height: 40,
                            color: const Color(0xFFE2E8F0),
                            child: const HugeIcon(
                              icon: HugeIcons.strokeRoundedUser,
                              size: 20,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: _getActionColor(notif.actionType),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: HugeIcon(
                            icon: _getActionHugeIcon(notif.actionType),
                            color: Colors.white,
                            size: 9,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notif.displayTitle,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: notif.isRead ? FontWeight.w600 : FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatTime(notif.updatedAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // 2. 评论与回复展示
              if (isComment || isReply) ...[
                const SizedBox(height: 12),
                if (isDeleted)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.remove_circle_outline_rounded, size: 14, color: Color(0xFF94A3B8)),
                        SizedBox(width: 6),
                        Text(
                          '该评论已被作者删除',
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Text(
                    commentText,
                    maxLines: _isExpanded ? 10 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1E293B),
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (commentText.length > 60)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _isExpanded = !_isExpanded);
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          _isExpanded ? '收起' : '显示更多',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: widget.primaryTeal),
                        ),
                      ),
                    ),
                ],

                if (isReply && myOriginalComment.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: const Border(left: BorderSide(color: Color(0xFF3B82F6), width: 3)),
                    ),
                    child: Text(
                      '我的评论: $myOriginalComment',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
                    ),
                  ),
                ],
              ],

              // 3. 富参数文章卡片
              if (targetType == 'post' && postTitle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      if (thumbnail.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            thumbnail,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 48,
                              height: 48,
                              color: widget.primaryTeal.withOpacity(0.08),
                              child: const Icon(Icons.article_rounded, color: Color(0xFF2C7B6D), size: 20),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: widget.primaryTeal.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.article_rounded, color: Color(0xFF2C7B6D), size: 20),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: widget.primaryTeal.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                category,
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: widget.primaryTeal),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              postTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms);
  }

  dynamic _getActionHugeIcon(String type) {
    if (type.contains('like')) return HugeIcons.strokeRoundedFavourite;
    if (type.contains('collect')) return HugeIcons.strokeRoundedBookmark02;
    if (type.contains('comment') || type.contains('reply')) return HugeIcons.strokeRoundedComment01;
    if (type.contains('follow')) return HugeIcons.strokeRoundedUserAdd01;
    return HugeIcons.strokeRoundedNotification03;
  }

  Color _getActionColor(String type) {
    if (type.contains('like')) return const Color(0xFFEF4444);
    if (type.contains('collect')) return const Color(0xFFD97706);
    if (type.contains('comment') || type.contains('reply')) return const Color(0xFF3B82F6);
    if (type.contains('follow')) return const Color(0xFF10B981);
    return widget.primaryTeal;
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0 && now.day == dt.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}月${dt.day}日';
  }
}