// lib/services/notification_handler_service.dart (社交通知与落地页跳转完全体)
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart'; // 🌟 用于三方落地页链接安全调起

import '../views/post_detail/post_detail_view.dart'; // 🌟 帖子详情视图路径
import '../views/profile/profile_view.dart';
import 'push_notification_model.dart'; // 🌟 用户空间专页路径

class NotificationHandlerService extends GetxService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void onInit() {
    super.onInit();
    _initializeNotifications();
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImplementation?.requestNotificationsPermission();
    }
  }

  Future<void> _initializeNotifications() async {
    await requestPermissions();
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/launcher_icon');

    const DarwinInitializationSettings initializationSettingsDarwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    _createNotificationChannel();
  }

  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'googlechat_alerts',
      '同频社交动态',
      description: '点赞、评论、分享、外部链接推送等通知',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// 🌟 处理系统通知栏点击行为，智能分发路由跳转 [2]
  void _onNotificationTap(NotificationResponse response) async {
    if (response.payload == null) return;

    try {
      final Map<String, dynamic> data = jsonDecode(response.payload!);
      final String type = data['type'] ?? '';
      final String targetId = data['target_id'] ?? '';
      final String targetType = data['target_type'] ?? '';
      final String customUrl = data['custom_url'] ?? '';

      if (type == 'externalLink' && customUrl.isNotEmpty) {
        // 场景 A: 外部落地页推送，安全唤起移动端默认浏览器
        final Uri url = Uri.parse(customUrl);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
        return;
      }

      if (targetType == 'user' || type == 'recommendUser') {
        // 场景 B: 用户、粉丝相关通知，一键路由跳转至对应学者空间 [2]
        Get.to(() => ProfileView(profileId: targetId));
      } else if (targetType == 'post' || type == 'recommendPost' || type == 'comment') {
        // 场景 C: 点赞、评论、分享等，一键路由到对应的帖子细节页中 [2]
        Get.to(() => PostDetailView(postId: targetId));
      }
    } catch (e) {
      debugPrint("❌ [NotificationHandler] 路由跳转分发异常: $e");
    }
  }

  Future<String?> _downloadAndSaveFile(String? url, String fileName) async {
    if (url == null || url.isEmpty) return null;
    try {
      final Directory directory = await getTemporaryDirectory();
      final String filePath = '${directory.path}/$fileName';
      final http.Response response = await http.get(Uri.parse(url));
      final File file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      return filePath;
    } catch (e) {
      return null;
    }
  }

  /// 🌟 将后端的规范 JSON 数据转换为美观的本地通知卡片
  Future<void> handleIncomingNotification(PushNotificationModel note) async {
    String title = '🔔 新动态';
    String body = '';

    final nickname = note.sender.nickname;
    final targetTitle = note.target.title;

    // 1. 根据可扩展消息类别动态装配文案
    if (note.category == 'social') {
      switch (note.type) {
        case 'like':
          title = '🔥 点赞通知';
          body = '$nickname 赞了你的观点: "$targetTitle"';
          break;
        case 'collect':
          title = 'bookmark 收藏通知';
          body = '$nickname 收藏了你的帖子: "$targetTitle"';
          break;
        case 'comment':
          title = '💬 新讨论消息';
          body = '$nickname 对你发表了看法: "$targetTitle"';
          break;
        case 'repost':
          title = '🔁 转发通知';
          body = '$nickname 转发同步了你的帖子: "$targetTitle"';
          break;
        case 'follow':
          title = '🎉 关注';
          body = '$nickname 关注了你，开始倾听你的观点';
          break;
      }
    } else if (note.category == 'recommendation') {
      if (note.type == 'recommendPost') {
        title = '💡 个性化学术推荐';
        body = '基于您的研究兴趣，向您推荐好文: "$targetTitle"';
      } else if (note.type == 'recommendUser') {
        title = '🤝 推荐认识的学者';
        body = '推荐您关注同领域的创作者: @$nickname';
      }
    } else if (note.category == 'landingPage') {
      title = '🌐 推荐落地页';
      body = targetTitle.isNotEmpty ? targetTitle : '点击查看最新推荐文章与落地页。';
    } else if (note.category == 'system') {
      title = '📢 系统广播通知';
      body = targetTitle;
    }

    // 2. 异步下载大图标（用户头像）
    final String? avatarPath = await _downloadAndSaveFile(
      note.sender.avatar,
      'avatar_${note.sender.id}.png',
    );

    // 3. 注入系统级高阶通知配置
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'googlechat_alerts',
      '同频社交动态',
      channelDescription: '点赞、评论、关注、推荐等通知提示',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      color: const Color(0xFF2C7B6D),
      largeIcon: avatarPath != null ? FilePathAndroidBitmap(avatarPath) : null,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: '观点同频通知',
      ),
    );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      attachments: avatarPath != null ? [DarwinNotificationAttachment(avatarPath)] : null,
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // 4. 发送通知给本地底层
    await _notificationsPlugin.show(
      note.hashCode,
      title,
      body,
      platformDetails,
      payload: jsonEncode({
        'type': note.type,
        'target_id': note.target.id,
        'target_type': note.target.type,
        'custom_url': note.customData['url'] ?? '',
      }),
    );
  }
}