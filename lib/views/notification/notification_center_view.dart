// lib/views/notification/notification_center_view.dart
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:qorange/theme.dart';

import '../../controllers/im_conversation_controller.dart';
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

  static Color get _primaryTeal => AppColors.primary;
  static Color get _bgSlate => AppColors.background;

  final List<Map<String, dynamic>> _tabsConfig = [
    {
      'key': 'all',
      'label': 'notif_tab_all'.tr,
      'icon': HugeIcons.strokeRoundedGrid,
      'color': AppColors.primary,
    },
    {
      'key': 'like',
      'label': 'notif_tab_like'.tr,
      'icon': HugeIcons.strokeRoundedFavourite,
      'color': const Color(0xFFEF4444),
    },
    {
      'key': 'comment',
      'label': 'notif_tab_comment'.tr,
      'icon': HugeIcons.strokeRoundedComment01,
      'color': const Color(0xFF3B82F6),
    },
    {
      'key': 'follow',
      'label': 'notif_tab_follow'.tr,
      'icon': HugeIcons.strokeRoundedUserAdd01,
      'color': const Color(0xFF10B981),
    },
    {
      'key': 'system',
      'label': 'notif_tab_system'.tr,
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
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (Get.isRegistered<ImConversationController>()) {
      ImConversationController.to.unreadNotifCount.value = _controller.totalUnreadBadge.value;
    }
    Get.delete<NotificationCenterController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgSlate,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: HugeIcon(
            icon: HugeIcons.strokeRoundedArrowLeft01,
            color: AppColors.textPrimary,
            size: 20,
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            Get.back();
          },
        ),
        title: Text(
          'notification_center'.tr,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedCheckmarkBadge01,
              color: AppColors.textSecondary,
              size: 22,
            ),
            tooltip: 'notif_mark_all_read'.tr,
            onPressed: () {
              HapticFeedback.mediumImpact();
              _controller.markTabAsRead('all');
              for (final def in _tabsConfig) {
                _controller.fetchTabNotifications(def['key'], isRefresh: true);
              }
              Fluttertoast.showToast(msg: 'notif_marked_all'.tr);
            },
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(color: AppColors.surface,
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              labelColor: _primaryTeal,
              unselectedLabelColor: AppColors.textHint,
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

  Widget _buildTabListView(String tabKey) {
    final state = _controller.tabStates[tabKey]!;

    return Obx(() {
      if (state.isLoading.value) {
        return Center(
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
        backgroundColor: AppColors.surface,
        onRefresh: () => _controller.fetchTabNotifications(tabKey, isRefresh: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            if (scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
              _controller.fetchMore(tabKey);
            }
            return false;
          },
          child: ListView.separated(
            key: PageStorageKey<String>('notif_tab_$tabKey'),
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            itemCount: state.list.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == state.list.length) {
                return Obx(() {
                  if (state.isLoadingMore.value) {
                    return Padding(
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
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'notif_loaded_all'.tr,
                          style: TextStyle(fontSize: 11, color: AppColors.textHint),
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
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedNotification03,
              color: AppColors.textHint,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'notif_empty_title'.tr,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'notif_empty_sub'.tr,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

/// 🌟 高阶自适应通知卡片
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
    final category = (target['category']?.toString() ?? 'im_category_column'.tr).toUpperCase();

    final contextData = notif.contextData;
    final isReply = notif.actionType == 'reply_comment';
    final isComment = notif.actionType == 'comment_post';
    final isDeleted = contextData['is_comment_deleted'] == true;

    final String commentText = contextData['comment_content']?.toString() ?? '';
    final String myOriginalComment = contextData['my_original_comment']?.toString() ?? '';

    return Material(color: AppColors.surface,
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
                  ? AppColors.surfaceAlt
                  : widget.primaryTeal.withOpacity(0.25),
              width: notif.isRead ? 0.8 : 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 顶部：层叠头像/单头像 + 动作标题 + 时间
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🌟 高级自适应层叠头像群（支持点击直达主页或展开互动清单）
                  _InteractiveAvatarStack(
                    notif: notif,
                    primaryTeal: widget.primaryTeal,
                  ),
                  const SizedBox(width: 12),

                  // 动作标题文案与时间
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notif.displayTitle,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: notif.isRead ? FontWeight.w600 : FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatRelativeTime(notif.updatedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textHint,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // 2. 评论与回复内容展示
              if (isComment || isReply) ...[
                const SizedBox(height: 12),
                if (isDeleted)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.remove_circle_outline_rounded, size: 14, color: AppColors.textHint),
                        SizedBox(width: 6),
                        Text(
                          'notif_comment_deleted'.tr,
                          style: TextStyle(fontSize: 12, color: AppColors.textHint, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Text(
                    commentText,
                    maxLines: _isExpanded ? 10 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
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
                          _isExpanded ? 'notif_collapse'.tr : 'notif_expand'.tr,
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
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: const Border(left: BorderSide(color: Color(0xFF3B82F6), width: 3)),
                    ),
                    child: Text(
                      'notif_my_comment'.trParams({'text': myOriginalComment}),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
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
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      if (thumbnail.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            thumbnail,
                            width: 46,
                            height: 46,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 46,
                              height: 46,
                              color: widget.primaryTeal.withOpacity(0.08),
                              child: Icon(Icons.article_rounded, color: AppColors.primary, size: 20),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: widget.primaryTeal.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.article_rounded, color: AppColors.primary, size: 20),
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
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.textHint),
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

  String _formatRelativeTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'time_just_now'.tr;
    if (diff.inMinutes < 60) return 'time_minutes_ago'.trParams({'count': diff.inMinutes.toString()});
    if (diff.inHours < 24 && now.day == dt.day) return 'time_hours_ago'.trParams({'count': diff.inHours.toString()});
    if (diff.inDays < 7) return 'time_days_ago'.trParams({'count': diff.inDays.toString()});
    return 'time_month_day'.trParams({'month': dt.month.toString(), 'day': dt.day.toString()});
  }
}

/// 🌟 核心设计：智能自适应层叠头像群（支持单人主页跳转 + 多人展开互动学者清单抽屉）
class _InteractiveAvatarStack extends StatelessWidget {
  final NotificationItemModel notif;
  final Color primaryTeal;

  const _InteractiveAvatarStack({
    required this.notif,
    required this.primaryTeal,
  });

  @override
  Widget build(BuildContext context) {
    final actors = notif.latestActors;
    final int count = notif.actorCount;

    // 场景 A: 只有单个用户互动 -> 显示单一大头像并挂载操作角标
    if (actors.isEmpty || (actors.length == 1 && count <= 1)) {
      final actor = actors.isNotEmpty ? actors.first : <String, dynamic>{};
      final String avatar = actor['avatar']?.toString() ?? (notif.actorAvatars.isNotEmpty ? notif.actorAvatars.first : '');
      final String userId = actor['user_id']?.toString() ?? '';

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (userId.isNotEmpty) {
            HapticFeedback.lightImpact();
            Get.to(() => ProfileView(profileId: userId));
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                avatar.isNotEmpty ? avatar : 'https://api.dicebear.com/7.x/micah/png?seed=${notif.id.hashCode}',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 40,
                  height: 40,
                  color: AppColors.divider,
                  child: HugeIcon(icon: HugeIcons.strokeRoundedUser, size: 20, color: AppColors.textHint),
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
      );
    }

    // 场景 B: 多人互动（如 2~50 人点赞/收藏） -> 高质感错位 3 环层叠头像
    final displayActors = actors.take(3).toList();
    final double stackWidth = 40.0 + (displayActors.length - 1) * 16.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openActorsListSheet(context),
      child: SizedBox(
        width: stackWidth,
        height: 42,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (int i = 0; i < displayActors.length; i++)
              Positioned(
                left: i * 16.0,
                top: 0,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.network(
                      displayActors[i]['avatar']?.toString() ?? '',
                      width: 34,
                      height: 34,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 34,
                        height: 34,
                        color: AppColors.divider,
                        child: HugeIcon(icon: HugeIcons.strokeRoundedUser, size: 16, color: AppColors.textHint),
                      ),
                    ),
                  ),
                ),
              ),
            // 角落展示动作角标与气泡
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: _getActionColor(notif.actionType),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: _getActionHugeIcon(notif.actionType),
                      color: Colors.white,
                      size: 8,
                    ),
                    if (count > displayActors.length) ...[
                      const SizedBox(width: 2),
                      Text(
                        '+$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openActorsListSheet(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _ActorsBottomSheet(
          notif: notif,
          primaryTeal: primaryTeal,
        );
      },
    );
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
    return primaryTeal;
  }
}

/// 🌟 已修复 Material 水波纹层级、支持 Bio 真实展示与 AtSign 打开状态下毫秒级实时热重绘）
class _ActorsBottomSheet extends StatelessWidget {
  final NotificationItemModel notif;
  final Color primaryTeal;

  const _ActorsBottomSheet({
    super.key,
    required this.notif,
    required this.primaryTeal,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // 🌟 1. 实时绑定 Controller 活跃队列，即便在弹窗展开时收到 AtSign 改名改头像推送也会瞬间热重绘！
      final controller = NotificationCenterController.to;
      NotificationItemModel currentNotif = notif;

      // 在当前已激活的通知列表中检索最新活体数据
      for (final state in controller.tabStates.values) {
        final index = state.list.indexWhere(
              (item) => item.id == notif.id || item.groupKey == notif.groupKey,
        );
        if (index != -1) {
          currentNotif = state.list[index];
          break;
        }
      }

      final String actionLabel = currentNotif.actionType.contains('like')
          ? 'notif_action_liked'.tr
          : (currentNotif.actionType.contains('collect') ? 'notif_action_collected'.tr : 'notif_action_interacted'.tr);
      final String targetTitle =
          currentNotif.target['title']?.toString() ?? 'notif_article_fallback'.tr;

      return Container(
        decoration: BoxDecoration(color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          top: 14,
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部拖拽手柄
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 头部标题与互动总数（🌟 已修复水平溢出问题）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const HugeIcon(
                          icon: HugeIcons.strokeRoundedFavourite,
                          color: Color(0xFFEF4444),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'notif_actors_title'.tr,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'notif_users_action'.trParams({'count': currentNotif.actorCount.toString(), 'action': actionLabel, 'target': targetTitle}),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: AppColors.textHint,
                    size: 22,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: AppColors.surfaceAlt),
            const SizedBox(height: 8),

            // 动态滚动列表（放宽最大高度并解决 ListTile Material 警告）
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: currentNotif.latestActors.length,
                separatorBuilder: (_, __) =>
                Divider(height: 1, color: AppColors.background),
                itemBuilder: (context, index) {
                  final actor = currentNotif.latestActors[index];
                  final String userId = actor['user_id']?.toString() ?? '';
                  final String nickname =
                      actor['nickname']?.toString() ?? 'user'.tr;
                  final String avatar = actor['avatar']?.toString() ?? '';

                  // 🌟 2. 优先提取学者的真实个性签名与简介，不再全部硬编码
                  final String bio = actor['bio']?.toString().trim() ?? '';
                  final String location =
                      actor['location']?.toString().trim() ?? '';
                  final String subtitleText = bio.isNotEmpty
                      ? bio
                      : (location.isNotEmpty
                      ? 'notif_lives_in'.trParams({'location': location})
                      : 'notif_users_interacted'.tr);

                  return Material(
                    color: Colors.transparent, // 🌟 3. 解决 ListTile 依赖 Material 导致的断言报错
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          avatar.isNotEmpty
                              ? avatar
                              : 'https://api.dicebear.com/7.x/micah/png?seed=${userId.hashCode}',
                          width: 42,
                          height: 42,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 42,
                            height: 42,
                            color: AppColors.divider,
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedUser,
                              size: 20,
                              color: AppColors.textHint,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        subtitleText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                      trailing: ElevatedButton(
                        onPressed: () {
                          if (userId.isNotEmpty) {
                            Navigator.pop(context);
                            Get.to(() => ProfileView(profileId: userId));
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceAlt,
                          foregroundColor: AppColors.primary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                        child: Text(
                          'notif_profile_btn'.tr,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      onTap: () {
                        if (userId.isNotEmpty) {
                          Navigator.pop(context);
                          Get.to(() => ProfileView(profileId: userId));
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    });
  }
}