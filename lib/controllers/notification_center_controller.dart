// lib/controllers/notification_center_controller.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../models/notification_model.dart';
import '../../network/http_client.dart';
import '../../user_controller.dart';
import 'im_conversation_controller.dart';

/// 🌟 独立 Tab 状态容器
class TabNotificationState {
  final String tabKey;
  final RxList<NotificationItemModel> list = <NotificationItemModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = true.obs;
  int page = 1;
  final int limit = 20;

  TabNotificationState({required this.tabKey});

  void reset() {
    page = 1;
    hasMore.value = true;
    isLoading.value = true;
    isLoadingMore.value = false;
  }
}

class NotificationCenterController extends GetxController with GetSingleTickerProviderStateMixin {
  static NotificationCenterController get to => Get.find<NotificationCenterController>();

  final List<Map<String, String>> tabDefs = [
    {'key': 'all', 'label': 'notif_tab_all'.tr},
    {'key': 'like', 'label': 'notif_tab_like'.tr},
    {'key': 'comment', 'label': 'notif_tab_comment'.tr},
    {'key': 'follow', 'label': 'notif_tab_follow'.tr},
    {'key': 'system', 'label': 'notif_tab_system'.tr},
  ];

  late final Map<String, TabNotificationState> tabStates;
  final Rx<NotificationSummaryModel> unreadSummary = NotificationSummaryModel().obs;
  final RxInt totalUnreadBadge = 0.obs;
  final RxString activeTab = 'all'.obs;

  Worker? _userLoginWorker;
  bool _isFetching = false;

  @override
  void onInit() {
    super.onInit();

    tabStates = {
      for (final def in tabDefs) def['key']!: TabNotificationState(tabKey: def['key']!),
    };

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

  /// 🌟 同步大厅铃铛红点状态
  void _syncBellBadge(int count) {
    if (Get.isRegistered<ImConversationController>()) {
      ImConversationController.to.unreadNotifCount.value = count;
    }
  }

  /// AtSign 实时事件驱动
  void onAtSignEventReceived(Map<String, dynamic> eventPayload) {
    final String eventType = eventPayload['event_type']?.toString() ?? 'upsert_notif';
    final dynamic data = eventPayload['data'];
    final dynamic summaryData = eventPayload['unread_summary'];

    if (summaryData is Map<String, dynamic>) {
      unreadSummary.value = NotificationSummaryModel.fromJson(summaryData);
      totalUnreadBadge.value = unreadSummary.value.all;
      _syncBellBadge(totalUnreadBadge.value);
    } else if (summaryData is Map) {
      unreadSummary.value = NotificationSummaryModel.fromJson(Map<String, dynamic>.from(summaryData));
      totalUnreadBadge.value = unreadSummary.value.all;
      _syncBellBadge(totalUnreadBadge.value);
    }

    if (data is! Map) return;
    final mapData = Map<String, dynamic>.from(data);

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
            updatedNames.add(actorCopy['nickname']?.toString() ?? 'user'.tr);
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
              createdAt: item.createdAt,
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

    if (eventType == 'delete_notif') {
      final String groupKey = mapData['group_key']?.toString() ?? '';
      final String notifId = mapData['id']?.toString() ?? '';

      for (final state in tabStates.values) {
        state.list.removeWhere((item) => item.groupKey == groupKey || item.id == notifId);
        state.list.refresh();
      }
      return;
    }

    // 🌟 收到点赞或收藏通知：实时插入对应的 Tab（包含 like 和 all）
    if (eventType == 'upsert_notif') {
      final notifItem = NotificationItemModel.fromJson(mapData);
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
      return count > 1 ? 'notif_like_multi'.trParams({'names': names.join(', '), 'count': count.toString()}) : 'notif_like_one'.trParams({'name': names.firstOrNull ?? 'user'.tr});
    }
    if (actionType == 'collect_post') {
      return count > 1 ? 'notif_collect_multi'.trParams({'names': names.join(', '), 'count': count.toString()}) : 'notif_collect_one'.trParams({'name': names.firstOrNull ?? 'user'.tr});
    }
    if (actionType == 'comment_post') return 'notif_comment_one'.trParams({'name': names.firstOrNull ?? 'user'.tr});
    if (actionType == 'reply_comment') return 'notif_reply_one'.trParams({'name': names.firstOrNull ?? 'user'.tr});
    if (actionType == 'follow_user') return 'notif_follow_one'.trParams({'name': names.firstOrNull ?? 'user'.tr});
    return targetTitle;
  }

  Future<void> fetchUnreadBadgeOnly() async {
    if (!UserController.to.isLoggedIn) return;
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>('/api-notifications/badge');
      if (res.datas != null) {
        final summaryMap = res.datas!['unread_summary'] as Map<String, dynamic>? ?? {};
        unreadSummary.value = NotificationSummaryModel.fromJson(summaryMap);
        totalUnreadBadge.value = unreadSummary.value.all;
        _syncBellBadge(totalUnreadBadge.value);
      }
    } catch (_) {}
  }

  Future<void> fetchTabNotifications(String tabKey, {bool isRefresh = false}) async {
    if (!UserController.to.isLoggedIn) return;

    final state = tabStates[tabKey];
    if (state == null) return;

    if (isRefresh) {
      state.reset();
    } else {
      if (!state.hasMore.value || state.isLoadingMore.value || _isFetching) return;
      state.isLoadingMore.value = true;
    }

    _isFetching = true;

    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-notifications',
        queryParameters: {
          'tab': tabKey,
          'page': state.page.toString(),
          'limit': state.limit.toString(),
        },
      );

      if (res.respCode == 0 && res.datas != null) {
        final datas = res.datas!;
        final rawList = datas['notifications'] as List? ?? [];
        final summaryMap = datas['unread_summary'] as Map<String, dynamic>? ?? {};

        final List<NotificationItemModel> fetched = rawList
            .map((item) => NotificationItemModel.fromJson(item as Map<String, dynamic>))
            .toList();

        unreadSummary.value = NotificationSummaryModel.fromJson(summaryMap);
        totalUnreadBadge.value = unreadSummary.value.all;
        _syncBellBadge(totalUnreadBadge.value);

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
      _isFetching = false;
    }
  }

  Future<void> fetchMore(String tabKey) async {
    await fetchTabNotifications(tabKey, isRefresh: false);
  }

  void switchTab(String tabKey) {
    if (activeTab.value == tabKey) return;
    activeTab.value = tabKey;

    final state = tabStates[tabKey];
    if (state != null && state.list.isEmpty) {
      fetchTabNotifications(tabKey, isRefresh: true);
    }

    if (tabKey != 'all') {
      _zeroOutLocalTabBadge(tabKey);
      markTabAsRead(tabKey);
    }
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
    _syncBellBadge(newAll);
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
    _syncBellBadge(0);
  }

  @override
  void onClose() {
    // 🌟 退出时仅标记当前正在看的具体子分类已读，绝不误杀其他未读 Tab
    if (activeTab.value != 'all') {
      markTabAsRead(activeTab.value);
    }
    _syncBellBadge(totalUnreadBadge.value);
    _userLoginWorker?.dispose();
    super.onClose();
  }
}