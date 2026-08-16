// lib/models/im_message_model.dart
class ImMessageModel {
  final String messageId;
  final String conversationId;
  final String senderId;
  final String recipientId;
  final String msgType; // text, image, voice, post_card, poll_card, token_transfer
  final Map<String, dynamic> payload;
  final bool isRead;
  final bool isRevoked;
  final DateTime createdAt;

  ImMessageModel({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.recipientId,
    required this.msgType,
    required this.payload,
    required this.isRead,
    required this.isRevoked,
    required this.createdAt,
  });

  factory ImMessageModel.fromJson(Map<String, dynamic> json) {
    return ImMessageModel(
      messageId: json['id']?.toString() ?? json['message_id']?.toString() ?? '',
      conversationId: json['conversation_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      recipientId: json['recipient_id']?.toString() ?? '',
      msgType: json['msg_type']?.toString() ?? 'text',
      payload: json['payload'] is Map<String, dynamic>
          ? json['payload'] as Map<String, dynamic>
          : (json['payload'] is Map ? Map<String, dynamic>.from(json['payload'] as Map) : {}),
      isRead: json['is_read'] == true,
      isRevoked: json['is_revoked'] == true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': messageId,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'recipient_id': recipientId,
    'msg_type': msgType,
    'payload': payload,
    'is_read': isRead,
    'is_revoked': isRevoked,
    'created_at': createdAt.toIso8601String(),
  };
}

class ImConversationModel {
  final String conversationId;
  final String partnerId;
  final String partnerNickname;
  final String partnerAvatar;
  final String partnerUsername;
  final String lastMsgPreview;
  final String lastMsgType;
  final int unreadCount;
  final String relationshipStatus;
  final int strangerMessageCount;
  final DateTime updatedAt;

  ImConversationModel({
    required this.conversationId,
    required this.partnerId,
    required this.partnerNickname,
    required this.partnerAvatar,
    required this.partnerUsername,
    required this.lastMsgPreview,
    required this.lastMsgType,
    required this.unreadCount,
    required this.relationshipStatus,
    required this.strangerMessageCount,
    required this.updatedAt,
  });

  factory ImConversationModel.fromJson(Map<String, dynamic> json) {
    final partner = json['partner'] as Map? ?? {};
    final lastMsg = json['last_message'] as Map? ?? {};

    return ImConversationModel(
      conversationId: json['conversation_id']?.toString() ?? '',
      partnerId: partner['id']?.toString() ?? '',
      partnerNickname: partner['nickname']?.toString() ?? '用户',
      partnerAvatar: partner['avatar']?.toString() ?? '',
      partnerUsername: partner['username']?.toString() ?? '',
      lastMsgPreview: lastMsg['preview_text']?.toString() ?? '',
      lastMsgType: lastMsg['msg_type']?.toString() ?? 'text',
      unreadCount: int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
      relationshipStatus: json['relationship_status']?.toString() ?? 'friend',
      strangerMessageCount: int.tryParse(json['stranger_message_count']?.toString() ?? '0') ?? 0,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}