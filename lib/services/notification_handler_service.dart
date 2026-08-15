import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart'; // 🌟 引入打开文件的插件
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../views/post_detail/post_detail_view.dart';
import '../views/profile/profile_view.dart';
import 'push_notification_model.dart';

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
    final AndroidNotificationChannel channel = AndroidNotificationChannel(
      'googlechat_alerts',
      'notif_channel_social'.tr,
      description: 'notif_channel_social_desc'.tr,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    // 独立创建一个用于更新下载进度的低重要度通道（不发出持续的响铃打扰用户）
    final AndroidNotificationChannel updateChannel = AndroidNotificationChannel(
      'app_update_channel',
      'notif_channel_update'.tr,
      description: 'notif_channel_update_desc'.tr,
      importance: Importance.low, // 设为 low，防止进度每次变更都发出叮咚声
      playSound: false,
      enableVibration: false,
    );

    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.createNotificationChannel(channel);
    await androidImplementation?.createNotificationChannel(updateChannel);
  }

  /// 🌟 处理系统通知栏点击行为，智能分发路由跳转与更新下载
  void _onNotificationTap(NotificationResponse response) async {
    if (response.payload == null) return;

    try {
      final Map<String, dynamic> data = jsonDecode(response.payload!);
      final String type = data['type'] ?? '';
      final String targetId = data['target_id'] ?? '';
      final String targetType = data['target_type'] ?? '';
      final String customUrl = data['custom_url'] ?? '';
      final String filePath = data['file_path'] ?? '';

      // 点击更新通知，启动后台流式下载
      if (type == 'appUpdate' && customUrl.isNotEmpty) {
        _startAppUpdateDownload(customUrl);
        return;
      }

      // 点击下载完成的通知，直接重新拉起安装界面
      if (type == 'installApk' && filePath.isNotEmpty) {
        _installApk(filePath);
        return;
      }

      if (type == 'externalLink' && customUrl.isNotEmpty) {
        final Uri url = Uri.parse(customUrl);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
        return;
      }

      if (targetType == 'user' || type == 'recommendUser') {
        Get.to(() => ProfileView(profileId: targetId));
      } else if (targetType == 'post' || type == 'recommendPost' || type == 'comment') {
        Get.to(() => PostDetailView(postId: targetId));
      }
    } catch (e) {
      debugPrint("❌ [NotificationHandler] 路由跳转分发异常: $e");
    }
  }

  // 执行 OTA 下载主逻辑
  Future<void> _startAppUpdateDownload(String url) async {
    const int updateNotificationId = 8888; // 固定的下载通知 ID
    try {
      // 1. 初始化通知栏进度为 0%
      await _updateDownloadNotification(0, updateNotificationId);

      // 2. 获取临时存储目录并建立 APK 文件，确保覆盖旧文件
      final Directory tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/qorange_update.apk';
      final File file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      // 3. 建立流式 HTTP 下载请求
      final http.Client client = http.Client();
      final http.Request request = http.Request('GET', Uri.parse(url));
      final http.StreamedResponse response = await client.send(request);

      if (response.statusCode != 200) {
        throw HttpException('err_download_status'.trParams({'code': '${response.statusCode}'}));
      }

      final int totalBytes = response.contentLength ?? 0;
      int downloadedBytes = 0;
      final List<int> bytes = [];
      int lastProgressPercent = -1;

      // 4. 流式接收数据，并在收到时计算进度
      await for (final List<int> chunk in response.stream) {
        bytes.addAll(chunk);
        downloadedBytes += chunk.length;

        if (totalBytes > 0) {
          final int percentage = ((downloadedBytes / totalBytes) * 100).toInt();
          // 节流优化：只有百分比整数变动时才调用 show()，避免卡顿
          if (percentage > lastProgressPercent) {
            lastProgressPercent = percentage;
            await _updateDownloadNotification(percentage, updateNotificationId);
          }
        } else {
          // 如果服务器没有返回真实长度，显示无上限的默认进度条
          await _updateDownloadNotification(-1, updateNotificationId);
        }
      }

      // 5. 保存字节数组为本地 APK 文件
      await file.writeAsBytes(bytes);

      // 6. 成功下载后清除下载进度通知
      await _notificationsPlugin.cancel(updateNotificationId);

      // 7. 调用安装逻辑（直接拉起底部安装询问弹窗）
      await _installApk(filePath);

      // 8. 同时在通知栏展现“下载完成”，万一用户在弹窗中不小心取消了，还可以通过通知点击重新调起
      await _showDownloadCompleteNotification(filePath);

    } catch (e) {
      debugPrint("❌ [AppUpdate] 后台下载失败: $e");
      await _showDownloadFailedNotification(updateNotificationId);
    }
  }

  // 向通知栏发送并刷新当前的下载进度
  Future<void> _updateDownloadNotification(int progress, int notificationId) async {
    final bool isIndeterminate = progress < 0; // 是否显示无进度滚动条
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'app_update_channel',
      'notif_channel_update'.tr,
      channelDescription: 'notif_update_progress_desc'.tr,
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: isIndeterminate ? 0 : progress,
      indeterminate: isIndeterminate,
      ongoing: true, // 强制常驻通知栏，不允许用户通过左滑手势删除
      onlyAlertOnce: true, // 确保进度刷新时手机不会重复响铃/振动
    );

    final NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(
      notificationId,
      'notif_downloading_update'.tr,
      isIndeterminate ? 'notif_downloading'.tr : 'notif_download_percent'.trParams({'progress': '$progress'}),
      platformDetails,
    );
  }

  // 唤起系统 PackageInstaller 开始安装
  Future<void> _installApk(String filePath) async {
    try {
      final File file = File(filePath);
      if (await file.exists()) {
        // 利用 open_filex 安全唤起系统安装面板
        final result = await OpenFilex.open(filePath);
        debugPrint("ℹ️ [AppUpdate] 系统安装面板调用结果: ${result.message} (ResultType: ${result.type})");
      } else {
        debugPrint("❌ [AppUpdate] 未能找到 APK 文件");
      }
    } catch (e) {
      debugPrint("❌ [AppUpdate] 唤起系统安装弹窗异常: $e");
    }
  }

  // 下载成功但用户取消后，常驻在通知栏的备份入口
  Future<void> _showDownloadCompleteNotification(String filePath) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'app_update_channel',
      'notif_channel_update'.tr,
      channelDescription: 'notif_download_done_desc'.tr,
      importance: Importance.max,
      priority: Priority.high,
      ongoing: false,
    );

    await _notificationsPlugin.show(
      8889, // 独立 ID
      'notif_update_ready'.tr,
      'notif_update_ready_body'.tr,
      NotificationDetails(android: androidDetails),
      payload: jsonEncode({
        'type': 'installApk',
        'file_path': filePath,
      }),
    );
  }

  // 下载失败处理通知
  Future<void> _showDownloadFailedNotification(int notificationId) async {
    await _notificationsPlugin.show(
      notificationId,
      'notif_update_failed'.tr,
      'notif_update_failed_body'.tr,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'app_update_channel',
          'notif_channel_update'.tr,
          importance: Importance.max,
          priority: Priority.high,
          ongoing: false,
        ),
      ),
    );
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
    String title = 'notif_default_title'.tr;
    String body = '';

    final nickname = note.sender.nickname;
    final targetTitle = note.target.title;

    // 🌟🌟 核心安全修正：优先提取 customData 中由后端统一设计好的定制化交易/提现文案
    // 这完美解决并消除了客户端硬编码造成的交易字段对不上、展现单调不美观的底层局限性 [1]！
    if (note.customData.containsKey('title') && note.customData['title'].toString().isNotEmpty) {
      title = note.customData['title'].toString();
    }
    if (note.customData.containsKey('content') && note.customData['content'].toString().isNotEmpty) {
      body = note.customData['content'].toString();
    }

    // 🌟 降级机制：如果后端没有提供自定义文案，无缝退回到原先的社交通知/个性化学术推荐翻译中
    if (body.isEmpty) {
      if (note.category == 'social') {
        switch (note.type) {
          case 'like':
            title = 'notif_like_title'.tr;
            body = 'notif_like_body'.trParams({'nickname': nickname, 'title': targetTitle});
            break;
          case 'collect':
            title = 'notif_collect_title'.tr;
            body = 'notif_collect_body'.trParams({'nickname': nickname, 'title': targetTitle});
            break;
          case 'comment':
            title = 'notif_comment_title'.tr;
            body = 'notif_comment_body'.trParams({'nickname': nickname, 'title': targetTitle});
            break;
          case 'repost':
            title = 'notif_repost_title'.tr;
            body = 'notif_repost_body'.trParams({'nickname': nickname, 'title': targetTitle});
            break;
          case 'follow':
            title = 'notif_follow_title'.tr;
            body = 'notif_follow_body'.trParams({'nickname': nickname});
            break;
        }
      } else if (note.category == 'recommendation') {
        if (note.type == 'recommendPost') {
          title = 'notif_rec_post_title'.tr;
          body = 'notif_rec_post_body'.trParams({'title': targetTitle});
        } else if (note.type == 'recommendUser') {
          title = 'notif_rec_user_title'.tr;
          body = 'notif_rec_user_body'.trParams({'nickname': nickname});
        }
      } else if (note.category == 'landingPage') {
        title = 'notif_landing_title'.tr;
        body = targetTitle.isNotEmpty ? targetTitle : 'notif_landing_body'.tr;
      } else if (note.category == 'system') {
        if (note.type == 'appUpdate') {
          title = 'notif_new_version_title'.tr;
          body = targetTitle.isNotEmpty ? targetTitle : 'notif_new_version_body'.tr;
        } else {
          title = 'notif_broadcast_title'.tr;
          body = targetTitle;
        }
      }
    }

    final String? avatarPath = await _downloadAndSaveFile(
      note.sender.avatar,
      'avatar_${note.sender.id}.png',
    );

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'googlechat_alerts',
      'notif_channel_social'.tr,
      channelDescription: 'notif_channel_social_desc2'.tr,
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      color: const Color(0xFF2C7B6D),
      largeIcon: avatarPath != null ? FilePathAndroidBitmap(avatarPath) : null,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'notif_summary'.tr,
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

    // 发送通知给本地底层
    await _notificationsPlugin.show(
      note.hashCode,
      title,
      body,
      platformDetails,
      payload: jsonEncode({
        'type': note.type, // 如果为 system/appUpdate，点击将正确触发响应
        'target_id': note.target.id,
        'target_type': note.target.type,
        'custom_url': note.customData['url'] ?? '',
      }),
    );
  }
}