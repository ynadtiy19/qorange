import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../views/post_detail/post_detail_view.dart';
import '../views/profile/profile_view.dart';
import 'push_notification_model.dart';

class NotificationHandlerService extends GetxService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  static const String appBranch = 'arena/01a004f0-qorange';
  static const String backendApiUrl = 'https://googlechat.zeabur.app';

  // 避免同一次运行期间反复检测打扰
  bool _isChecking = false;

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

    final AndroidNotificationChannel updateChannel = AndroidNotificationChannel(
      'app_update_channel',
      'notif_channel_update'.tr,
      description: 'notif_channel_update_desc'.tr,
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );

    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.createNotificationChannel(channel);
    await androidImplementation?.createNotificationChannel(updateChannel);
  }

  /// 🌟 启动时自动检查更新：精准上报本地编译包信息
  Future<void> checkForUpdate({bool isManualCheck = false}) async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // 如果用户今天点击过“稍后提示”，非手动检查时不重复打扰
      final String lastIgnoredTag = prefs.getString('ignored_update_tag') ?? '';

      final response = await http.post(
        Uri.parse('$backendApiUrl/api/check-update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'branch': appBranch,
          'version': packageInfo.version, // 例如 "1.0.0"
          'build_number': int.tryParse(packageInfo.buildNumber) ?? 1, // 例如 1, 2, 3
          'arch': 'arm64-v8a',
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        final datas = json['datas'] as Map<String, dynamic>?;

        if (datas != null && datas['has_update'] == true) {
          final String tag = datas['tag_name'] ?? 'New Version';

          // 如果该版本被用户暂时忽略过，且非手动点击检查，则静默跳过
          if (!isManualCheck && lastIgnoredTag == tag) {
            _isChecking = false;
            return;
          }

          final String wssUrl = datas['wss_download_url'] ?? '';
          final String fallbackUrl = datas['download_url'] ?? '';
          final String rawChangelog = datas['changelog'] ?? '优化系统流畅度与稳定性';
          final String cleanChangelog = _cleanMarkdownText(rawChangelog);

          // 🌟 只展示精致的更新弹窗，不再无脑向通知栏重复堆叠通知！
          _showRefinedUpdateDialog(
            tag: tag,
            changelog: cleanChangelog,
            onIgnore: () async {
              Get.back();
              await prefs.setString('ignored_update_tag', tag);
            },
            onConfirm: () async {
              Get.back();
              await prefs.remove('ignored_update_tag');
              if (wssUrl.isNotEmpty) {
                _startAppUpdateDownloadWss(wssUrl, fallbackUrl);
              } else if (fallbackUrl.isNotEmpty) {
                _startAppUpdateDownload(fallbackUrl);
              }
            },
          );
        } else if (isManualCheck) {
          Get.snackbar('检查更新', '当前已是最新版本 (${packageInfo.version})', snackPosition: SnackPosition.BOTTOM);
        }
      }
    } catch (e) {
      debugPrint("❌ [AppUpdate] 自动检查更新异常: $e");
    } finally {
      _isChecking = false;
    }
  }

  String _cleanMarkdownText(String raw) {
    return raw
        .replaceAll(RegExp(r'#{1,6}\s*'), '')
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
        .replaceAll(RegExp(r'__([^_]+)__'), r'$1')
        .replaceAll(RegExp(r'[-*]\s+'), '• ')
        .trim();
  }

  /// 🌟 极简高颜值弹窗
  void _showRefinedUpdateDialog({
    required String tag,
    required String changelog,
    required VoidCallback onIgnore,
    required VoidCallback onConfirm,
  }) {
    Get.dialog(
      PopScope(
        canPop: true,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2C7B6D).withOpacity(0.12),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEBF5F3),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.rocket_launch_rounded, color: Color(0xFF2C7B6D), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '发现新版本',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                          ),
                          Text(
                            tag,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF2C7B6D), fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  '更新内容：',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      changelog,
                      style: const TextStyle(fontSize: 13, height: 1.6, color: Color(0xFF334155)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: onIgnore,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF94A3B8),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('稍后提示', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: onConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2C7B6D),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('立即极速升级', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      barrierDismissible: true,
    );
  }

  void _onNotificationTap(NotificationResponse response) async {
    if (response.payload == null) return;
    try {
      final Map<String, dynamic> data = jsonDecode(response.payload!);
      final String type = data['type'] ?? '';
      final String targetId = data['target_id'] ?? '';
      final String targetType = data['target_type'] ?? '';
      final String customUrl = data['custom_url'] ?? '';
      final String wssUrl = data['wss_url'] ?? '';
      final String filePath = data['file_path'] ?? '';

      if (type == 'appUpdate') {
        if (wssUrl.isNotEmpty) {
          _startAppUpdateDownloadWss(wssUrl, customUrl);
        } else if (customUrl.isNotEmpty) {
          _startAppUpdateDownload(customUrl);
        }
        return;
      }

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

  Future<void> _startAppUpdateDownloadWss(String wssUrl, String fallbackHttpUrl) async {
    const int updateNotificationId = 8888;
    WebSocketChannel? channel;
    IOSink? fileSink;

    try {
      Get.snackbar('正在下载更新', '安装包正在后台通过专线高速通道极速下载...', snackPosition: SnackPosition.TOP);
      await _updateDownloadNotification(0, updateNotificationId);

      final Directory tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/qorange_update.apk';
      final File file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      fileSink = file.openWrite();
      final Uri uri = Uri.parse(wssUrl);
      channel = WebSocketChannel.connect(uri);

      int totalBytes = 0;
      int downloadedBytes = 0;
      int lastProgressPercent = -1;
      final Completer<void> completer = Completer<void>();

      channel.stream.listen(
            (dynamic message) async {
          if (message is String) {
            try {
              final Map<String, dynamic> json = jsonDecode(message);
              if (json['type'] == 'meta') {
                totalBytes = json['total_bytes'] ?? 0;
              } else if (json['type'] == 'done') {
                if (!completer.isCompleted) completer.complete();
              } else if (json['type'] == 'error') {
                if (!completer.isCompleted) completer.completeError(json['message'] ?? '下载失败');
              }
            } catch (_) {}
          } else if (message is List<int>) {
            fileSink?.add(message);
            downloadedBytes += message.length;

            if (totalBytes > 0) {
              final int percentage = ((downloadedBytes / totalBytes) * 100).toInt();
              if (percentage > lastProgressPercent) {
                lastProgressPercent = percentage;
                await _updateDownloadNotification(percentage, updateNotificationId);
              }
            } else {
              await _updateDownloadNotification(-1, updateNotificationId);
            }
          }
        },
        onError: (err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
      await fileSink.flush();
      await fileSink.close();
      fileSink = null;
      channel.sink.close();

      await _notificationsPlugin.cancel(updateNotificationId);
      await _installApk(filePath);
      await _showDownloadCompleteNotification(filePath);

    } catch (e) {
      debugPrint("⚠️ [WSS Update] WebSocket 下载异常，降级切换到 HTTP: $e");
      await fileSink?.close();
      channel?.sink.close();
      if (fallbackHttpUrl.isNotEmpty) {
        _startAppUpdateDownload(fallbackHttpUrl);
      } else {
        await _showDownloadFailedNotification(updateNotificationId);
      }
    }
  }

  Future<void> _startAppUpdateDownload(String url) async {
    const int updateNotificationId = 8888;
    try {
      await _updateDownloadNotification(0, updateNotificationId);

      final Directory tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/qorange_update.apk';
      final File file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      final http.Client client = http.Client();
      final http.Request request = http.Request('GET', Uri.parse(url));
      final http.StreamedResponse response = await client.send(request);

      if (response.statusCode != 200) {
        throw HttpException('下载失败 (HTTP ${response.statusCode})');
      }

      final int totalBytes = response.contentLength ?? 0;
      int downloadedBytes = 0;
      final List<int> bytes = [];
      int lastProgressPercent = -1;

      await for (final List<int> chunk in response.stream) {
        bytes.addAll(chunk);
        downloadedBytes += chunk.length;

        if (totalBytes > 0) {
          final int percentage = ((downloadedBytes / totalBytes) * 100).toInt();
          if (percentage > lastProgressPercent) {
            lastProgressPercent = percentage;
            await _updateDownloadNotification(percentage, updateNotificationId);
          }
        } else {
          await _updateDownloadNotification(-1, updateNotificationId);
        }
      }

      await file.writeAsBytes(bytes);
      await _notificationsPlugin.cancel(updateNotificationId);
      await _installApk(filePath);
      await _showDownloadCompleteNotification(filePath);

    } catch (e) {
      debugPrint("❌ [AppUpdate] 后台下载失败: $e");
      await _showDownloadFailedNotification(updateNotificationId);
    }
  }

  Future<void> _updateDownloadNotification(int progress, int notificationId) async {
    final bool isIndeterminate = progress < 0;
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
      ongoing: true,
      onlyAlertOnce: true,
    );

    final NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(
      notificationId,
      'notif_downloading_update'.tr,
      isIndeterminate ? 'notif_downloading'.tr : 'notif_download_percent'.trParams({'progress': '$progress'}),
      platformDetails,
    );
  }

  Future<void> _installApk(String filePath) async {
    try {
      final File file = File(filePath);
      if (await file.exists()) {
        final result = await OpenFilex.open(filePath);
        debugPrint("ℹ️ [AppUpdate] 系统安装面板调用结果: ${result.message}");
      }
    } catch (e) {
      debugPrint("❌ [AppUpdate] 唤起安装异常: $e");
    }
  }

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
      8889,
      'notif_update_ready'.tr,
      'notif_update_ready_body'.tr,
      NotificationDetails(android: androidDetails),
      payload: jsonEncode({
        'type': 'installApk',
        'file_path': filePath,
      }),
    );
  }

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

  /// 社交通知/业务推送处理（100% 保留原有业务逻辑）
  Future<void> handleIncomingNotification(PushNotificationModel note) async {
    String title = 'notif_default_title'.tr;
    String body = '';

    final nickname = note.sender.nickname;
    final targetTitle = note.target.title;

    if (note.customData.containsKey('title') && note.customData['title'].toString().isNotEmpty) {
      title = note.customData['title'].toString();
    }
    if (note.customData.containsKey('content') && note.customData['content'].toString().isNotEmpty) {
      body = note.customData['content'].toString();
    }

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
        title = 'notif_broadcast_title'.tr;
        body = targetTitle;
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

    await _notificationsPlugin.show(
      note.hashCode,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode({
        'type': note.type,
        'target_id': note.target.id,
        'target_type': note.target.type,
        'custom_url': note.customData['url'] ?? '',
        'wss_url': note.customData['wss_url'] ?? '',
      }),
    );
  }
}