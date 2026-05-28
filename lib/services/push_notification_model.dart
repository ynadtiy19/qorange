// 统一社交通知 / 个性推荐 / 系统广播消息实体模型
class PushNotificationModel {
  final String notificationId;
  final String recipientId; // 🌟 核心新增：真正用来比对过滤的接收人 MongoDB ID
  final String category; // "social" | "recommendation" | "system" | "landingPage"
  final String type; // "like" | "collect" | "comment" | "repost" | "follow" | "recommendPost" | "recommendUser" | "externalLink"
  final NotificationSender sender;
  final NotificationTarget target;
  final Map<String, dynamic> customData;
  final String timestamp;

  PushNotificationModel({
    required this.notificationId,
    required this.recipientId,
    required this.category,
    required this.type,
    required this.sender,
    required this.target,
    required this.customData,
    required this.timestamp,
  });

  factory PushNotificationModel.fromJson(Map<String, dynamic> json) {
    return PushNotificationModel(
      notificationId: json['notification_id'] ?? '',
      recipientId: json['recipient_id'] ?? '', // 🌟 解析目标接收人 ID
      category: json['category'] ?? '',
      type: json['type'] ?? '',
      sender: NotificationSender.fromJson(json['sender'] ?? {}),
      target: NotificationTarget.fromJson(json['target'] ?? {}),
      customData: Map<String, dynamic>.from(json['custom_data'] ?? {}),
      timestamp: json['timestamp'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notification_id': notificationId,
      'recipient_id': recipientId,
      'category': category,
      'type': type,
      'sender': sender.toJson(),
      'target': target.toJson(),
      'custom_data': customData,
      'timestamp': timestamp,
    };
  }
}

class NotificationSender {
  final String id;
  final String nickname;
  final String avatar;
  final String atsign;

  NotificationSender({
    required this.id,
    required this.nickname,
    required this.avatar,
    required this.atsign,
  });

  factory NotificationSender.fromJson(Map<String, dynamic> json) {
    return NotificationSender(
      id: json['id'] ?? '',
      nickname: json['nickname'] ?? '学者',
      avatar: json['avatar'] ?? '',
      atsign: json['atsign'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nickname': nickname,
      'avatar': avatar,
      'atsign': atsign,
    };
  }
}

class NotificationTarget {
  final String id;
  final String title;
  final String type; // "post" | "comment" | "user"

  NotificationTarget({
    required this.id,
    required this.title,
    required this.type,
  });

  factory NotificationTarget.fromJson(Map<String, dynamic> json) {
    return NotificationTarget(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      type: json['type'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
    };
  }
}