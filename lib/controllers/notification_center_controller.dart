// lib/controllers/notification_center_controller.dart (热重绘 + 零漂移红点完全体)
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../models/notification_model.dart';
import '../../network/http_client.dart';
import '../../user_controller.dart';
import 'im_conversation_controller.dart';

class NotificationCenterController extends GetxController {
  static NotificationCenterController get to => Get.find<NotificationCenterController>();

  final RxList<NotificationItemModel> notifications = <NotificationItemModel>[].obs;
  final Rx<NotificationSummaryModel> unreadSummary = NotificationSummaryModel().obs;
  final RxInt totalUnreadBadge = 0.obs;

  final RxString activeTab = 'all'.obs;
  final RxBool isLoading = false.obs;
  final RxBool isLoadingMore = false.obs;
  bool _hasMore = true;
  int _currentPage = 1;

  Worker? _userLoginWorker;

  @override
  void onInit() {
    super.onInit();
    _userLoginWorker = ever(UserController.to.user, (user) {
      if (UserController.to.isLoggedIn) {
        fetchUnreadBadgeOnly();
      } else {
        clearState();
      }
    });

    if (UserController.to.isLoggedIn) {
      fetchUnreadBadgeOnly();
    }
  }

  /// 🌟 核心修复：纯事件驱动局部增删改，并强刷 UI
  void onAtSignEventReceived(Map<String, dynamic> eventPayload) {
    final String eventType = eventPayload['event_type']?.toString() ?? 'upsert_notif';
    final dynamic data = eventPayload['data'];
    final dynamic summaryData = eventPayload['unread_summary'];

    // 1. 🌟 严格对齐后端权威未读细分字典，彻底杜绝小红点数字漂移！
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
    // 场景 A: 对方修改头像昵称 ➔ 根据 user_id 0ms 精准热更新！
    // =========================================================
    if (eventType == 'profile_updated_in_notif') {
      final String targetUserId = mapData['user_id']?.toString() ?? '';
      final String newNick = mapData['nickname']?.toString() ?? '';
      final String newAvatar = mapData['avatar']?.toString() ?? '';

      bool anyUpdated = false;

      for (int i = 0; i < notifications.length; i++) {
        final item = notifications[i];
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
          notifications[i] = NotificationItemModel(
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
          anyUpdated = true;
        }
      }

      if (anyUpdated) {
        notifications.refresh(); // 🌟 强制 GetX 响应式重绘！
      }
      return;
    }

    // =========================================================
    // 场景 B: 取消点赞人数归零 ➔ 原地平滑移除
    // =========================================================
    if (eventType == 'delete_notif') {
      final String groupKey = mapData['group_key']?.toString() ?? '';
      final String notifId = mapData['id']?.toString() ?? '';

      notifications.removeWhere((item) => item.groupKey == groupKey || item.id == notifId);
      notifications.refresh();
      return;
    }

    // =========================================================
    // 场景 C: 点赞增加 / 评论到达 / 删评平滑变灰色
    // =========================================================
    if (eventType == 'upsert_notif') {
      final notifItem = NotificationItemModel.fromJson(mapData);
      final index = notifications.indexWhere((item) => item.groupKey == notifItem.groupKey || item.id == notifItem.id);

      if (index != -1) {
        notifications[index] = notifItem;
      } else {
        if (activeTab.value == 'all' || activeTab.value == notifItem.tabCategory) {
          notifications.insert(0, notifItem);
        }
      }
      notifications.refresh();
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

  Future<void> fetchUnreadBadgeOnly() async {
    if (!UserController.to.isLoggedIn) return;
    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>('/api-notifications/badge');
      if (res.datas != null) {
        final summaryMap = res.datas!['unread_summary'] as Map<String, dynamic>? ?? {};
        unreadSummary.value = NotificationSummaryModel.fromJson(summaryMap);
        totalUnreadBadge.value = unreadSummary.value.all;

        // 同步大厅铃铛红点
        if (Get.isRegistered<ImConversationController>()) {
          ImConversationController.to.unreadNotifCount.value = totalUnreadBadge.value;
        }
      }
    } catch (_) {}
  }

  Future<void> fetchNotifications({bool isRefresh = false}) async {
    if (!UserController.to.isLoggedIn) return;

    if (isRefresh) {
      _currentPage = 1;
      _hasMore = true;
      isLoading.value = true;
    } else {
      if (!_hasMore || isLoadingMore.value) return;
      isLoadingMore.value = true;
    }

    try {
      final res = await HttpClient.instance.get<Map<String, dynamic>>(
        '/api-notifications',
        queryParameters: {
          'tab': activeTab.value,
          'page': _currentPage.toString(),
          'limit': '20',
        },
      );

      if (res.datas != null) {
        final datas = res.datas!;
        final rawList = datas['notifications'] as List? ?? [];
        final summaryMap = datas['unread_summary'] as Map<String, dynamic>? ?? {};

        final List<NotificationItemModel> list = rawList
            .map((item) => NotificationItemModel.fromJson(item as Map<String, dynamic>))
            .toList();

        unreadSummary.value = NotificationSummaryModel.fromJson(summaryMap);
        totalUnreadBadge.value = unreadSummary.value.all;

        if (Get.isRegistered<ImConversationController>()) {
          ImConversationController.to.unreadNotifCount.value = totalUnreadBadge.value;
        }

        if (isRefresh) {
          notifications.assignAll(list);
        } else {
          notifications.addAll(list);
        }

        if (list.length < 20) _hasMore = false;
        _currentPage++;
      }
    } catch (e) {
      debugPrint("🔴 [NotificationCenter] 拉取通知异常: $e");
    } finally {
      isLoading.value = false;
      isLoadingMore.value = false;
    }
  }

  void switchTab(String tab) {
    if (activeTab.value == tab) return;
    activeTab.value = tab;
    _zeroOutLocalTabBadge(tab);
    fetchNotifications(isRefresh: true);
    markTabAsRead(tab);
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

    if (Get.isRegistered<ImConversationController>()) {
      ImConversationController.to.unreadNotifCount.value = newAll;
    }
  }

  Future<void> markTabAsRead(String tab) async {
    try {
      await HttpClient.instance.put('/api-notifications', data: {'tab': tab});
      fetchUnreadBadgeOnly();
    } catch (_) {}
  }

  void clearState() {
    notifications.clear();
    unreadSummary.value = NotificationSummaryModel();
    totalUnreadBadge.value = 0;
  }

  @override
  void onClose() {
    markTabAsRead(activeTab.value);
    _userLoginWorker?.dispose();
    super.onClose();
  }
}