import 'dart:convert';
import 'dart:io';
// 🌟 核心修复 1：hide NotificationConfig 避免与 singbox 的通知类冲突
import 'package:at_client/at_client.dart' hide NotificationConfig;
import 'package:flutter/foundation.dart';
import 'package:flutter_singbox_client/flutter_singbox_client.dart';
import 'package:get/get.dart';
import 'package:noports_core/npt.dart';

class AppSshTunnelService extends GetxService {
  static AppSshTunnelService get to => Get.find<AppSshTunnelService>();

  // 节点配置（与服务端一致）
  static const String remoteDeviceAtsign = '@absolute3140';
  static const String deviceName = 'zeabur';
  static const String srvdAtsign = '@rv_am';
  static const int remoteSshPort = 22; // 容器内默认 SSH 端口

  final RxBool isTunnelActive = false.obs;

  Npt? _npt;
  final SingboxClient _singboxClient = SingboxClient();

  @override
  void onInit() {
    super.onInit();
    _initSingbox();
  }

  Future<void> _initSingbox() async {
    try {
      await _singboxClient.initialize();
      _singboxClient.serviceStateStream.listen((state) {
        debugPrint("📡 [SingBox State] 状态变更: $state");
        // 🌟 核心修复 2：使用正确的 ServiceState 枚举值 (started / stopped)
        if (state == ServiceState.started) {
          isTunnelActive.value = true;
        } else if (state == ServiceState.stopped) {
          isTunnelActive.value = false;
        }
      });
    } catch (e) {
      debugPrint("🔴 [SingBox Init] 初始化失败: $e");
    }
  }

  /// 🌟 启动 Atsign + Singbox 核心 SSH 全局 TUN 隧道
  Future<bool> startTunnel(AtClient atClient) async {
    if (isTunnelActive.value) return true;

    try {
      // 🌟 1. 提取 clientAtSign
      final String clientSign = atClient.getCurrentAtSign() ?? '@gemini2banana';

      debugPrint("🚀 [AppSshTunnel] 正在向 $remoteDeviceAtsign:$remoteSshPort 发起 Atsign 加密隧道握手 (客户端: $clientSign)...");

      final nptParams = NptParams(
        clientAtSign: clientSign,
        sshnpdAtSign: remoteDeviceAtsign,
        srvdAtSign: srvdAtsign,
        device: deviceName,
        localPort: 0, // 0 代表让系统自动分配空闲端口
        remotePort: remoteSshPort,
        remoteHost: 'localhost',
        localHost: '127.0.0.1',
        rootDomain: 'root.atsign.org',
        inline: true,
        timeout: const Duration(seconds: 30),
      );

      _npt = Npt.create(params: nptParams, atClient: atClient);

      // 🌟 2. 握手并在空安全下解析真实监听端口
      final dynamic runResult = await _npt?.run();

      int actualPort = 0;
      if (runResult is int && runResult > 0) {
        actualPort = runResult;
      } else if (runResult != null) {
        try {
          actualPort = (runResult as dynamic).port ?? 0;
        } catch (_) {}
      }

      if (actualPort <= 0 && _npt != null) {
        try {
          actualPort = (_npt as dynamic).port ?? (_npt as dynamic).localPort ?? 0;
        } catch (_) {}
      }

      if (actualPort <= 0) {
        throw Exception("未能从 Atsign Npt 获取到有效的本地监听端口 (runResult: $runResult)");
      }

      debugPrint("🔑 [AppSshTunnel] Atsign 隧道已打通！真实监听端口: $actualPort，正在通过 Sing-box 建立全局 TUN 路由...");

      // 🌟 3. 申请系统 VPN 权限 (仅在 VPN 模式下必须)
      final hasPermission = await _singboxClient.requestVPNPermission();
      if (!hasPermission) {
        throw Exception("用户拒绝了 VPN 授权申请");
      }

      // 🌟 4. 构造 Sing-box 内核配置 (TUN 入站 + SSH 出站)
      final configMap = {
        "log": {
          "level": "warn",
          "timestamp": true
        },
        "dns": {
          "servers": [
            {
              "tag": "google-dns",
              "address": "tls://8.8.8.8"
            }
          ]
        },
        "inbounds": [
          {
            "type": "tun",
            "tag": "tun-in",
            "interface_name": "tun0",
            "inet4_address": "172.19.0.1/30",
            "auto_route": true,
            "strict_route": false,
            "stack": "system",
            "sniff": true,
            "sniff_override_destination": true
          }
        ],
        "outbounds": [
          {
            "type": "ssh",
            "tag": "ssh-out",
            "server": "127.0.0.1",
            "server_port": actualPort,
            "user": "root",
            "password": "noports123"
          }
        ],
        "route": {
          "auto_detect_interface": true,
          "final": "ssh-out"
        }
      };

      final configJson = jsonEncode(configMap);

      // 校验配置
      await _singboxClient.checkConfig(configJson);

      // 🌟 5. 连接并开启全局 VPN 模式
      await _singboxClient.connect(SessionOptions(
        config: configJson,
        networkMode: NetworkMode.vpn,
        notification: const NotificationConfig(
          title: 'Omni Stream 安全连接',
          channelName: 'VPN Service',
          showTrafficStats: true,
          showStopButton: false,
        ),
      ));

      isTunnelActive.value = true;
      debugPrint("🎉 [AppSshTunnel] Sing-box 全局 VPN 隧道已就绪！原生播放器及 Dart 层所有流量已全面接管！");
      return true;
    } catch (e, stackTrace) {
      debugPrint("❌ [AppSshTunnel] 隧道启动失败: $e\n$stackTrace");
      await stopTunnel();
      return false;
    }
  }

  /// 关闭并释放隧道
  Future<void> stopTunnel() async {
    try {
      await _singboxClient.disconnect();
    } catch (_) {}

    await _npt?.close();
    _npt = null;

    isTunnelActive.value = false;
    debugPrint("🔌 [AppSshTunnel] 隧道已彻底关闭并释放内存资源");
  }

  @override
  void onClose() {
    stopTunnel();
    super.onClose();
  }
}