// lib/models/notification_model.dart
import 'package:get/get.dart';

class NotificationItemModel {
  final String id;
  final String recipientId;
  final String groupKey;
  final String tabCategory;
  final String actionType;
  final int actorCount;
  final List<Map<String, dynamic>> latestActors; // 完整包含 user_id, nickname, avatar
  final List<String> actorNames;
  final List<String> actorAvatars;
  final String displayTitle;
  final Map<String, dynamic> target;
  final Map<String, dynamic> contextData;
  final bool isRead;
  final DateTime updatedAt;
  final DateTime createdAt;

  NotificationItemModel({
    required this.id,
    required this.recipientId,
    required this.groupKey,
    required this.tabCategory,
    required this.actionType,
    required this.actorCount,
    required this.latestActors,
    required this.actorNames,
    required this.actorAvatars,
    required this.displayTitle,
    required this.target,
    required this.contextData,
    required this.isRead,
    required this.updatedAt,
    required this.createdAt,
  });

  factory NotificationItemModel.fromJson(Map<String, dynamic> json) {
    final rawActors = json['latest_actors'] as List? ?? [];
    final List<Map<String, dynamic>> actorsList = [];
    final List<String> names = [];
    final List<String> avatars = [];

    for (final a in rawActors) {
      if (a is Map) {
        final actorMap = Map<String, dynamic>.from(a);
        actorsList.add(actorMap);
        names.add(actorMap['nickname']?.toString() ?? 'user'.tr);
        avatars.add(actorMap['avatar']?.toString() ?? '');
      }
    }

    return NotificationItemModel(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      recipientId: json['recipient_id']?.toString() ?? '',
      groupKey: json['group_key']?.toString() ?? '',
      tabCategory: json['tab_category']?.toString() ?? 'system',
      actionType: json['action_type']?.toString() ?? 'system_alert',
      actorCount: int.tryParse(json['actor_count']?.toString() ?? '1') ?? 1,
      latestActors: actorsList,
      actorNames: names,
      actorAvatars: avatars,
      displayTitle: json['display_title']?.toString() ?? (json['target']?['title']?.toString() ?? 'notif_new'.tr),
      target: json['target'] is Map ? Map<String, dynamic>.from(json['target'] as Map) : {},
      contextData: json['context_data'] is Map ? Map<String, dynamic>.from(json['context_data'] as Map) : {},
      isRead: json['is_read'] == true,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'recipient_id': recipientId,
      'group_key': groupKey,
      'tab_category': tabCategory,
      'action_type': actionType,
      'actor_count': actorCount,
      'latest_actors': latestActors,
      'actor_names': actorNames,
      'actor_avatars': actorAvatars,
      'display_title': displayTitle,
      'target': target,
      'context_data': contextData,
      'is_read': isRead,
      'updated_at': updatedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class NotificationSummaryModel {
  final int all;
  final int comment;
  final int follow;
  final int like;
  final int system;

  NotificationSummaryModel({
    this.all = 0,
    this.comment = 0,
    this.follow = 0,
    this.like = 0,
    this.system = 0,
  });

  factory NotificationSummaryModel.fromJson(Map<String, dynamic> json) {
    return NotificationSummaryModel(
      all: int.tryParse(json['all']?.toString() ?? '0') ?? 0,
      comment: int.tryParse(json['comment']?.toString() ?? '0') ?? 0,
      follow: int.tryParse(json['follow']?.toString() ?? '0') ?? 0,
      like: int.tryParse(json['like']?.toString() ?? '0') ?? 0,
      system: int.tryParse(json['system']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'all': all,
      'comment': comment,
      'follow': follow,
      'like': like,
      'system': system,
    };
  }
}