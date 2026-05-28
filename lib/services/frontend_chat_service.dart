// lib/services/frontend_chat_service.dart (双独立通道定向通配监听 + 离线缓存双向全兼容拉取完全体)
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qorange/services/push_notification_model.dart';
import 'package:version/version.dart';

import '../../user_controller.dart';
import 'notification_handler_service.dart';

class FrontendChatService extends GetxService {
  static const String myAtsign = '@gemini2banana';
  static const String nameSpace = 'atsign';
  static const String rootDomain = 'root.atsign.org';

  final MessageDeduplicator _deduplicator = MessageDeduplicator();
  final NotificationHandlerService _notificationHandler = Get.put(NotificationHandlerService());

  final RxBool isOnboarded = false.obs;
  AtClient? _atClient;

  // 使用 List 持有多重订阅，便于在登出或切换账号时安全、干净地一次性销毁
  final List<StreamSubscription<dynamic>> _monitorSubscriptions = [];
  Worker? _loginStateWorker;

  @override
  void onInit() {
    super.onInit();
    // 监听本地用户登录状态 [1]
    _loginStateWorker = ever(UserController.to.user, (user) {
      if (UserController.to.isLoggedIn) {
        if (isOnboarded.value) {
          // 如果账号发生切换或重新登录，直接重启 Monitor，使用新用户的 ID 重新注册监听
          _startFrontendMonitor(_atClient!);
        } else {
          authenticate();
        }
      } else {
        disconnect();
      }
    });

    if (UserController.to.isLoggedIn) {
      authenticate();
    }
  }

  Future<void> authenticate() async {
    if (isOnboarded.value) return;

    if (Platform.isAndroid) {
      await [Permission.storage, Permission.manageExternalStorage].request();
    }

    final supportDir = await getApplicationDocumentsDirectory();
    String keysPath = '${supportDir.path}/${myAtsign}_key.atKeys';

    File keyFile = File(keysPath);
    if (!await keyFile.exists()) {
      debugPrint("⚠️ [Frontend] 密钥文件不存在，正在从 Assets 复制...");
      try {
        final byteData = await rootBundle.load('assets/${myAtsign}_key.atKeys');
        await keyFile.writeAsBytes(
          byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
        );
        debugPrint("✅ [Frontend] 密钥文件复制成功: $keysPath");
      } catch (e) {
        debugPrint("❌ [Frontend] 无法从 Assets 复制密钥文件: $e");
        return;
      }
    }

    AtOnboardingPreference config = AtOnboardingPreference()
      ..namespace = nameSpace
      ..hiveStoragePath = '${supportDir.path}/.atsign/$myAtsign/storage'
      ..downloadPath = '${supportDir.path}/.atsign/files'
      ..isLocalStoreRequired = true
      ..rootDomain = rootDomain
      ..atKeysFilePath = keysPath
      ..commitLogPath = '${supportDir.path}/.atsign/$myAtsign/storage/commitLog'
      ..fetchOfflineNotifications = true // 启用离线通知拉取同步机制
      ..atProtocolEmitted = Version(2, 0, 0);

    AtOnboardingService onboardingService = AtOnboardingServiceImpl(myAtsign, config);

    try {
      debugPrint("🤖 [Frontend] 开始认证公共通道: $myAtsign");
      bool authenticated = await onboardingService.authenticate();

      if (authenticated) {
        isOnboarded.value = true;
        debugPrint("✅ [Frontend] 公共通道认证成功");
        _atClient = AtClientManager.getInstance().atClient;
        _startFrontendMonitor(_atClient!);
      }
    } catch (e) {
      debugPrint("AtSign Auth Error: $e");
    }
  }

  void _startFrontendMonitor(AtClient atClient) async {
    // 1. 先安全取消并清空上一个账号注册的所有 Monitor 订阅
    if (_monitorSubscriptions.isNotEmpty) {
      for (var sub in _monitorSubscriptions) {
        await sub.cancel();
      }
      _monitorSubscriptions.clear();
    }

    final myRealIdStr = UserController.to.user.value?.id ?? 'none';

    // 🌟 核心改进 1：开启双源离线同步拉取，支持通配，一站式拉取个人和广播未读！🌟
    if (myRealIdStr != 'none') {
      await _pullKeysByRegex(atClient, 'push_message_$myRealIdStr');
      await _pullKeysByRegex(atClient, 'push_message_all');
    }

    // 🌟 核心改进 2：在命名空间之前全部引入 .* 通配符，以便完美匹配后端生成的带有唯一尾缀的广播与个人实时推送！
    final String broadcastRegex = 'push_message_all.*\\.$nameSpace@';
    final String personalRegex = 'push_message_$myRealIdStr.*\\.$nameSpace@';

    debugPrint("🎧 [Frontend] 开启共享通道定向监听 - 广播通道: $broadcastRegex");
    debugPrint("🎧 [Frontend] 开启共享通道定向监听 - 专属个人通道: $personalRegex");

    try {
      // 订阅全员广播通道并监听
      final broadcastSub = atClient.notificationService
          .subscribe(regex: broadcastRegex, shouldDecrypt: true)
          .listen(_onNotificationReceived, onError: (e) => debugPrint("🔴 广播通道监听错误: $e"));

      // 订阅当前登录学者的专属个人通道并监听
      final personalSub = atClient.notificationService
          .subscribe(regex: personalRegex, shouldDecrypt: true)
          .listen(_onNotificationReceived, onError: (e) => debugPrint("🔴 个人通道监听错误: $e"));

      // 将这两个活跃订阅托管到集合中
      _monitorSubscriptions.addAll([broadcastSub, personalSub]);
    } catch (e) {
      debugPrint("❌ [Frontend] 注册 AtSign 订阅服务发生异常: $e");
    }
  }

  /// 🌟 极简高兼容离线拉取通用方法（加入 .* 通配符匹配唯一尾缀）
  Future<void> _pullKeysByRegex(AtClient atClient, String regexPattern) async {
    try {
      // 🌟 核心修补：在此处加上 .* 通配符，确保模糊正则匹配，把带唯一尾缀的未读 Key 物理扫描出来！
      final List<String> matchingKeys = await atClient.getKeys(
        regex: '$regexPattern.*', // 🌟 加上 .* 允许匹配尾缀
        useRemoteAtServer: true, // 直接扫描云端存储
      );

      debugPrint("📩 [Frontend] 成功检索到云端离线缓存的未读通知数 [$regexPattern]: ${matchingKeys.length}");

      for (final rawKeyStr in matchingKeys) {
        try {
          final atKey = AtKey.fromString(rawKeyStr);

          // 拉取并解密该 Key 对应内容的值
          final AtValue atValue = await atClient.get(atKey);
          final String? jsonVal = atValue.value?.toString();

          if (jsonVal != null && jsonVal.isNotEmpty) {
            debugPrint("📥 [Frontend] 成功提取到云端缓存通知: $jsonVal");

            final Map<String, dynamic> payload = jsonDecode(jsonVal);
            final pushModel = PushNotificationModel.fromJson(payload);

            // 消息层防抖排重
            if (_deduplicator.isDuplicate(pushModel.notificationId)) {
              continue;
            }

            // 3. 升起本地系统通知栏
            _notificationHandler.handleIncomingNotification(pushModel);
          }

          // 成功展示后，立即删除云端的缓存 Key，防止下次登录重复弹窗
          await atClient.delete(atKey);
          debugPrint("🗑️ [Frontend] 已成功清理云端已读通知 Key: $rawKeyStr");

        } catch (e) {
          debugPrint("❌ [Frontend] 处理单条离线缓存通知时出错 ($rawKeyStr): $e");
        }
      }
    } catch (e) {
      debugPrint("🔴 [Frontend] 离线通知拉取同步过程发生异常 [$regexPattern]: $e");
    }
  }

  /// 统一处理接收到的通知载荷
  void _onNotificationReceived(AtNotification notification) async {
    String? jsonVal = notification.value;
    if (jsonVal == null) return;

    try {
      // 核心调试打印：格式化输出接收到的 AtSign 通知结构
      if (kDebugMode) {
        debugPrint('\n==================== AtSign 接收通知 ====================');
        debugPrint('➤ 来自 AtSign : ${notification.from}');
        debugPrint('➤ 原始通知 Key : ${notification.key}');
        debugPrint('➤ 原始 JSON 数据: $jsonVal');
      }

      Map<String, dynamic> payload = jsonDecode(jsonVal);
      final pushModel = PushNotificationModel.fromJson(payload);

      if (kDebugMode) {
        debugPrint('➤ 解析后物理模型 ───');
        debugPrint('  ├─ 消息 ID    : ${pushModel.notificationId}');
        debugPrint('  ├─ 目标接收人 : ${pushModel.recipientId}');
        debugPrint('  ├─ 分类大项   : ${pushModel.category}');
        debugPrint('  ├─ 行为类型   : ${pushModel.type}');
        debugPrint('  ├─ 发送人姓名 : ${pushModel.sender.nickname} (ID: ${pushModel.sender.id})');
        debugPrint('  ├─ 目标载体名 : ${pushModel.target.title} (ID: ${pushModel.target.id}, 载体类型: ${pushModel.target.type})');
        debugPrint('  └─ 附带自定义数据 : ${pushModel.customData}');
        debugPrint('========================================================\n');
      }

      // 消息层排重
      if (_deduplicator.isDuplicate(pushModel.notificationId)) {
        debugPrint("❌ [Frontend] 跳过重复通知");
        return;
      }

      // 过滤自己触发的通知行为
      final myRealIdStr = UserController.to.user.value?.id;
      if (pushModel.sender.id == myRealIdStr) {
        debugPrint("ℹ️ [Frontend] 过滤自己触发的通知行为");
        return;
      }

      // 校验完全通过，确认是发送给本人的通知，升起状态通知栏进行通知
      _notificationHandler.handleIncomingNotification(pushModel);

    } catch (e) {
      debugPrint("❌ [Frontend] 共享消息处理失败: $e");
      if (kDebugMode) {
        debugPrint('========================================================\n');
      }
    }
  }

  void disconnect() async {
    debugPrint("🔌 [Frontend] 断开公共通道连接并清空资源...");
    if (_monitorSubscriptions.isNotEmpty) {
      for (var sub in _monitorSubscriptions) {
        await sub.cancel();
      }
      _monitorSubscriptions.clear();
    }
    _deduplicator.clear();
    isOnboarded.value = false;
    _atClient = null;
  }

  @override
  void onClose() {
    _loginStateWorker?.dispose();
    disconnect();
    super.onClose();
  }
}

/// 消息去重器
class MessageDeduplicator {
  final HashSet<String> _processedIds = HashSet<String>();
  final Duration cacheDuration;

  MessageDeduplicator({this.cacheDuration = const Duration(seconds: 10)});

  bool isDuplicate(String messageId) {
    if (_processedIds.contains(messageId)) {
      return true;
    }
    _processedIds.add(messageId);
    Future.delayed(cacheDuration, () {
      _processedIds.remove(messageId);
    });
    return false;
  }

  void clear() {
    _processedIds.clear();
  }
}