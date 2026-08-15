import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart'; // 🌟 引入打开文件的插件
import 'package:package_info_plus/package_info_plus.dart'; // 🌟 引入获取本地包信息插件
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🌟 引入轻量存储插件
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart'; // 引入 WebSocket 工具

import '../views/post_detail/post_detail_view.dart';
import '../views/profile/profile_view.dart';
import 'push_notification_model.dart';

class NotificationHandlerService extends GetxService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // 当前分支与更新配置（可按需指定对应的打包分支）
  static const String appBranch = 'arena/01a004f0-qorange';
  static const String backendApiUrl = 'https://googlechat.zeabur.app';

  // 记录本轮应用生命周期是否已完成检查，防止每次切屏或返回重复弹窗打扰用户
  bool _hasPromptedThisSession = false;

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

  /// 🌟 启动时自动检查更新：提取本地真实 App 版本和 Commit 上报给后端 MongoDB 进行精准比对
  Future<void> checkForUpdate({bool isManualCheck = false}) async {
    if (_hasPromptedThisSession && !isManualCheck) return;

    try {
      // 1. 获取本地真实的应用包信息及上次安装的 Commit
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String localInstalledCommit = prefs.getString('installed_commit_sha') ?? '';

      // 2. 向后端发起带有完整设备环境信息的 POST 校验请求
      final response = await http.post(
        Uri.parse('$backendApiUrl/api/check-update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'branch': appBranch,
          'version': packageInfo.version,
          'build_number': packageInfo.buildNumber,
          'commit_sha': localInstalledCommit,
          'arch': 'arm64-v8a',
        }),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        final datas = json['datas'] as Map<String, dynamic>?;

        if (datas != null && datas['has_update'] == true) {
          _hasPromptedThisSession = true;

          final String latestCommit = datas['commit_sha'] ?? '';
          final String wssUrl = datas['wss_download_url'] ?? '';
          final String fallbackUrl = datas['download_url'] ?? '';
          final String tag = datas['tag_name'] ?? 'New Version';
          final String rawChangelog = datas['changelog'] ?? datas['release_notes'] ?? '优化系统流畅度与稳定性';

          // 清洗文本中的 Markdown 标记字符，保证界面极度干净
          final String cleanChangelog = _cleanMarkdownText(rawChangelog);

          // 🌟 弹出高颜值、无乱码的更新提示对话框
          _showRefinedUpdateDialog(
            tag: tag,
            changelog: cleanChangelog,
            onConfirm: () async {
              Get.back();
              // 本地持久化记录本次更新的 Commit，防止下次启动再次误弹
              if (latestCommit.isNotEmpty) {
                await prefs.setString('installed_commit_sha', latestCommit);
              }

              // 优先走后端 WSS 高速管道中转下载
              if (wssUrl.isNotEmpty) {
                _startAppUpdateDownloadWss(wssUrl, fallbackUrl);
              } else if (fallbackUrl.isNotEmpty) {
                _startAppUpdateDownload(fallbackUrl);
              }
            },
          );

          // 同时在系统通知栏留存一份更新提示卡片
          await _showUpdateAvailableNotification(
            tag: tag,
            notes: cleanChangelog,
            downloadUrl: fallbackUrl,
            wssUrl: wssUrl,
          );
        } else if (isManualCheck) {
          Get.snackbar('检查更新', '当前已是最新版本，无需升级！', snackPosition: SnackPosition.BOTTOM);
        }
      }
    } catch (e) {
      debugPrint("❌ [AppUpdate] 自动检查更新异常: $e");
    }
  }

  /// 🌟 净化原始 Markdown 文本，转换为优雅易读的纯文本换行
  String _cleanMarkdownText(String raw) {
    return raw
        .replaceAll(RegExp(r'#{1,6}\s*'), '') // 去除标题 ###
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1') // 去除加粗 **
        .replaceAll(RegExp(r'__([^_]+)__'), r'$1')
        .replaceAll(RegExp(r'[-*]\s+'), '• ') // 转换列表符为圆点
        .trim();
  }

  /// 🌟 设计精致、排版舒适、符合青橙主题色彩的更新弹窗
  void _showRefinedUpdateDialog({
    required String tag,
    required String changelog,
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
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Get.back();
                        },
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
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          onConfirm();
                        },
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

  /// 🌟 直接展示新版本发现的通知卡片
  Future<void> _showUpdateAvailableNotification({
    required String tag,
    required String notes,
    required String downloadUrl,
    required String wssUrl,
  }) async {
    const int updateNoticeId = 9999;
    final String title = '发现新版本 [$tag]';
    final String body = '$notes\n点击通知栏将自动通过后端高速通道极速更新！';

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'googlechat_alerts',
      'notif_channel_social'.tr,
      channelDescription: 'notif_channel_social_desc2'.tr,
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      color: const Color(0xFF2C7B6D),
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: '版本更新'.tr,
      ),
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // 发送通知，payload 里携带 wss_url 和 custom_url 供点击时直接拉起下载
    await _notificationsPlugin.show(
      updateNoticeId,
      title,
      body,
      platformDetails,
      payload: jsonEncode({
        'type': 'appUpdate',
        'target_id': tag,
        'target_type': 'system',
        'custom_url': downloadUrl,
        'wss_url': wssUrl,
      }),
    );
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
      final String wssUrl = data['wss_url'] ?? '';
      final String filePath = data['file_path'] ?? '';

      // 点击更新通知：优先启动 WSS 后端高速中转代理下载，失败则平滑回退 HTTP
      if (type == 'appUpdate') {
        if (wssUrl.isNotEmpty) {
          _startAppUpdateDownloadWss(wssUrl, customUrl);
        } else if (customUrl.isNotEmpty) {
          _startAppUpdateDownload(customUrl);
        }
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

  /// 🌟 核心升级：通过 WSS WebSocket 管道流式下载 APK，彻底突破国内直连 GitHub 慢的问题
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
            // 收到 Raw 二进制字节分片，直接流式写入文件
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

      // 等待 WebSocket 传输完成
      await completer.future;
      await fileSink.flush();
      await fileSink.close();
      fileSink = null;
      channel.sink.close();

      // 清除进度通知并拉起安装
      await _notificationsPlugin.cancel(updateNotificationId);
      await _installApk(filePath);
      await _showDownloadCompleteNotification(filePath);

    } catch (e) {
      debugPrint("⚠️ [WSS Update] WebSocket 下载异常，降级切换到 HTTP: $e");
      await fileSink?.close();
      channel?.sink.close();
      // 降级使用 HTTP 重试
      if (fallbackHttpUrl.isNotEmpty) {
        _startAppUpdateDownload(fallbackHttpUrl);
      } else {
        await _showDownloadFailedNotification(updateNotificationId);
      }
    }
  }

  // 执行 OTA HTTP 下载兜底主逻辑
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
        'type': note.type,
        'target_id': note.target.id,
        'target_type': note.target.type,
        'custom_url': note.customData['url'] ?? '',
        'wss_url': note.customData['wss_url'] ?? '',
      }),
    );
  }
}