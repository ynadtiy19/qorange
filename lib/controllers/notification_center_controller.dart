// lib/controllers/notification_center_controller.dart (独立多Tab分页流 + 滚动记忆 + 热重绘完全体)
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../models/notification_model.dart';
import '../../network/http_client.dart';
import '../../user_controller.dart';

/// 🌟 独立 Tab 状态容器：维护各自的滚动位置、独立分页计数与数据流
class TabNotificationState {
  final String tabKey;
  final RxList<NotificationItemModel> list = <NotificationItemModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = true.obs;
  int page = 1;
  final int limit = 20;
  final ScrollController scrollController = ScrollController();

  TabNotificationState({required this.tabKey});

  void dispose() {
    scrollController.dispose();
  }

  void reset() {
    page = 1;
    hasMore.value = true;
    isLoading.value = true;
    isLoadingMore.value = false;
  }
}

class NotificationCenterController extends GetxController with GetSingleTickerProviderStateMixin {
  static NotificationCenterController get to => Get.find<NotificationCenterController>();

  // 5 大 Tab 定义
  final List<Map<String, String>> tabDefs = [
    {'key': 'all', 'label': '全部'},
    {'key': 'like', 'label': '赞与收藏'},
    {'key': 'comment', 'label': '评论回复'},
    {'key': 'follow', 'label': '新增关注'},
    {'key': 'system', 'label': '系统通知'},
  ];

  late final Map<String, TabNotificationState> tabStates;
  final Rx<NotificationSummaryModel> unreadSummary = NotificationSummaryModel().obs;
  final RxInt totalUnreadBadge = 0.obs;
  final RxString activeTab = 'all'.obs;

  Worker? _userLoginWorker;

  @override
  void onInit() {
    super.onInit();

    // 1. 初始化 5 大 Tab 独立状态容器与滚动监听
    tabStates = {
      for (final def in tabDefs) def['key']!: TabNotificationState(tabKey: def['key']!),
    };

    for (final state in tabStates.values) {
      state.scrollController.addListener(() {
        if (state.scrollController.position.pixels >=
            state.scrollController.position.maxScrollExtent - 200) {
          fetchMore(state.tabKey);
        }
      });
    }

    // 2. 监听用户状态
    _userLoginWorker = ever(UserController.to.user, (user) {
      if (UserController.to.isLoggedIn) {
        fetchUnreadBadgeOnly();
        fetchTabNotifications(activeTab.value, isRefresh: true);
      } else {
        clearState();
      }
    });

    if (UserController.to.isLoggedIn) {
      fetchUnreadBadgeOnly();
      fetchTabNotifications('all', isRefresh: true);
    }
  }

  /// 🌟 核心：AtSign 实时事件驱动，穿透多 Tab 精准热重绘
  void onAtSignEventReceived(Map<String, dynamic> eventPayload) {
    final String eventType = eventPayload['event_type']?.toString() ?? 'upsert_notif';
    final dynamic data = eventPayload['data'];
    final dynamic summaryData = eventPayload['unread_summary'];

    // 1. 严格对齐未读细分字典，彻底杜绝小红点数字漂移
    if (summaryData is Map<String, dynamic>) {
      unreadSummary.value = NotificationSummaryModel.fromJson(summaryData);
      totalUnreadBadge.value = unreadSummary.value.all;
    } else if (summaryData is Map) {
      unreadSummary.value = NotificationSummaryModel.fromJson(Map<String, dynamic>.from(summaryData));
      totalUnreadBadge.value = unreadSummary.value.all;
    }

    if (data is! Map) return;
    final mapData = Map<String, dynamic>.from(data);

    // =========================================================
    // 场景 A: 对方修改头像昵称 ➔ 0ms 穿透全 Tab 局部热替换！
    // =========================================================
    if (eventType == 'profile_updated_in_notif') {
      final String targetUserId = mapData['user_id']?.toString() ?? '';
      final String newNick = mapData['nickname']?.toString() ?? '';
      final String newAvatar = mapData['avatar']?.toString() ?? '';

      for (final state in tabStates.values) {
        bool tabChanged = false;
        for (int i = 0; i < state.list.length; i++) {
          final item = state.list[i];
          bool itemChanged = false;

          final updatedActors = <Map<String, dynamic>>[];
          final updatedNames = <String>[];
          final updatedAvatars = <String>[];

          for (final actor in item.latestActors) {
            final actorCopy = Map<String, dynamic>.from(actor);
            if (actorCopy['user_id'] == targetUserId) {
              if (newNick.isNotEmpty) actorCopy['nickname'] = newNick;
              if (newAvatar.isNotEmpty) actorCopy['avatar'] = newAvatar;
              itemChanged = true;
            }
            updatedActors.add(actorCopy);
            updatedNames.add(actorCopy['nickname']?.toString() ?? '用户');
            updatedAvatars.add(actorCopy['avatar']?.toString() ?? '');
          }

          if (itemChanged) {
            state.list[i] = NotificationItemModel(
              id: item.id,
              recipientId: item.recipientId,
              groupKey: item.groupKey,
              tabCategory: item.tabCategory,
              actionType: item.actionType,
              actorCount: item.actorCount,
              latestActors: updatedActors,
              actorNames: updatedNames,
              actorAvatars: updatedAvatars,
              displayTitle: _regenerateDisplayTitle(item.actionType, item.actorCount, updatedNames, item.target['title']?.toString() ?? ''),
              target: item.target,
              contextData: item.contextData,
              isRead: item.isRead,
              updatedAt: item.updatedAt,
            );
            tabChanged = true;
          }
        }
        if (tabChanged) {
          state.list.refresh();
        }
      }
      return;
    }

    // =========================================================
    // 场景 B: 取消点赞人数归零 ➔ 原地平滑移除
    // =========================================================
    if (eventType == 'delete_notif') {
      final String groupKey = mapData['group_key']?.toString() ?? '';
      final String notifId = mapData['id']?.toString() ?? '';

      for (final state in tabStates.values) {
        state.list.removeWhere((item) => item.groupKey == groupKey || item.id == notifId);
        state.list.refresh();
      }
      return;
    }

    // =========================================================
    // 场景 C: 点赞增加 / 评论到达 / 删评平滑变灰色
    // =========================================================
    if (eventType == 'upsert_notif') {
      final notifItem = NotificationItemModel.fromJson(mapData);

      // 同步插入/更新到全部页 (all) 以及其归属的独立分类页
      final targetTabs = {'all', notifItem.tabCategory};

      for (final tab in targetTabs) {
        final state = tabStates[tab];
        if (state != null) {
          final index = state.list.indexWhere((item) => item.groupKey == notifItem.groupKey || item.id == notifItem.id);
          if (index != -1) {
            state.list[index] = notifItem;
          } else {
            state.list.insert(0, notifItem);
          }
          state.list.refresh();
        }
      }
    }
  }

  String _regenerateDisplayTitle(String actionType, int count, List<String> names, String targetTitle) {
    if (actionType == 'like_post') {
      return count > 1 ? '${names.join('、')} 等 $count 人赞了你的文章' : '${names.firstOrNull ?? '用户'} 赞了你的文章';
    }
    if (actionType == 'collect_post') {
      return count > 1 ? '${names.join('、')} 等 $count 人收藏了你的文章' : '${names.firstOrNull ?? '用户'} 收藏了你的文章';
    }
    if (actionType == 'comment_post') return '${names.firstOrNull ?? '用户'} 评论了你的文章';
    if (actionType == 'reply_comment') return '${names.firstOrNull ?? '用户'} 回复了你的评论';
    if (actionType == 'follow_user') return '${names.firstOrNull ?? '用户'} 关注了你';
    return targetTitle;
  }

  /// 纯拉取未读小红点
  Future<void> fetchUnreadBadgeOnly() async {
    if (!UserController.to.isLoggedIn) return;
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>('/api-notifications/badge');
      if (res.datas != null) {
        final summaryMap = res.datas!['unread_summary'] as Map<String, dynamic>? ?? {};
        unreadSummary.value = NotificationSummaryModel.fromJson(summaryMap);
        totalUnreadBadge.value = unreadSummary.value.all;
      }
    } catch (_) {}
  }

  /// 🌟 独立 Tab 分页拉取数据
  Future<void> fetchTabNotifications(String tabKey, {bool isRefresh = false}) async {
    if (!UserController.to.isLoggedIn) return;

    final state = tabStates[tabKey];
    if (state == null) return;

    if (isRefresh) {
      state.reset();
    } else {
      if (!state.hasMore.value || state.isLoadingMore.value) return;
      state.isLoadingMore.value = true;
    }

    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-notifications',
        queryParameters: {
          'tab': tabKey,
          'page': state.page.toString(),
          'limit': state.limit.toString(),
        },
      );

      if (res.datas != null) {
        final datas = res.datas!;
        final rawList = datas['notifications'] as List? ?? [];
        final summaryMap = datas['unread_summary'] as Map<String, dynamic>? ?? {};

        final List<NotificationItemModel> fetched = rawList
            .map((item) => NotificationItemModel.fromJson(item as Map<String, dynamic>))
            .toList();

        // 同步全局未读统计
        unreadSummary.value = NotificationSummaryModel.fromJson(summaryMap);
        totalUnreadBadge.value = unreadSummary.value.all;

        if (isRefresh) {
          state.list.assignAll(fetched);
        } else {
          state.list.addAll(fetched);
        }

        final bool hasMoreFromServer = datas['has_more'] as bool? ?? (fetched.length >= state.limit);
        state.hasMore.value = hasMoreFromServer;
        state.page++;
      }
    } catch (e) {
      debugPrint("🔴 [NotificationCenter] 拉取 Tab [$tabKey] 通知异常: $e");
    } finally {
      state.isLoading.value = false;
      state.isLoadingMore.value = false;
    }
  }

  /// 上拉加载更多
  Future<void> fetchMore(String tabKey) async {
    await fetchTabNotifications(tabKey, isRefresh: false);
  }

  /// 🌟 切换 Tab 并保留原位置、记忆分页状态
  void switchTab(String tabKey) {
    if (activeTab.value == tabKey) return;
    activeTab.value = tabKey;

    final state = tabStates[tabKey];
    if (state != null && state.list.isEmpty) {
      fetchTabNotifications(tabKey, isRefresh: true);
    }

    _zeroOutLocalTabBadge(tabKey);
    markTabAsRead(tabKey);
  }

  void _zeroOutLocalTabBadge(String tab) {
    final cur = unreadSummary.value;
    int newAll = cur.all;
    int newComment = cur.comment;
    int newFollow = cur.follow;
    int newLike = cur.like;
    int newSystem = cur.system;

    if (tab == 'all') {
      newAll = 0;
      newComment = 0;
      newFollow = 0;
      newLike = 0;
      newSystem = 0;
    } else if (tab == 'comment') {
      newAll = (newAll - newComment).clamp(0, 99999);
      newComment = 0;
    } else if (tab == 'follow') {
      newAll = (newAll - newFollow).clamp(0, 99999);
      newFollow = 0;
    } else if (tab == 'like') {
      newAll = (newAll - newLike).clamp(0, 99999);
      newLike = 0;
    } else if (tab == 'system') {
      newAll = (newAll - newSystem).clamp(0, 99999);
      newSystem = 0;
    }

    unreadSummary.value = NotificationSummaryModel(
      all: newAll,
      comment: newComment,
      follow: newFollow,
      like: newLike,
      system: newSystem,
    );
    totalUnreadBadge.value = newAll;
  }

  Future<void> markTabAsRead(String tab) async {
    try {
      await HttpClient.instance.put('/api-notifications', data: {'tab': tab});
      fetchUnreadBadgeOnly();
    } catch (_) {}
  }

  void clearState() {
    for (final state in tabStates.values) {
      state.list.clear();
      state.reset();
    }
    unreadSummary.value = NotificationSummaryModel();
    totalUnreadBadge.value = 0;
  }

  @override
  void onClose() {
    markTabAsRead(activeTab.value);
    _userLoginWorker?.dispose();
    for (final state in tabStates.values) {
      state.dispose();
    }
    super.onClose();
  }
}