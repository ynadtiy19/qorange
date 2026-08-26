// lib/network/app_ssh_tunnel_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:get/get.dart';
import 'package:noports_core/npt.dart';

import 'http_proxy_server.dart';

class AppSshTunnelService extends GetxService {
  static AppSshTunnelService get to => Get.find<AppSshTunnelService>();

  // 节点配置（与服务端一致）
  static const String remoteDeviceAtsign = '@absolute3140';
  static const String deviceName = 'zeabur';
  static const String srvdAtsign = '@rv_am';
  static const int remoteSshPort = 22;

  final RxBool isTunnelActive = false.obs;
  final RxBool isVpnConnected = false.obs;
  final RxInt currentSocks5Port = 0.obs;
  final Rx<V2RayStatus> v2rayStatus = V2RayStatus().obs;

  Npt? _npt;
  SSHClient? _sshClient;
  HttpProxyServer? _proxyServer;

  // 🌟 声明 flutter_v2ray_client 核心实例
  late final V2ray _v2ray = V2ray(
    onStatusChanged: (status) {
      v2rayStatus.value = status;
      isVpnConnected.value = status.state == 'CONNECTED';
      debugPrint("🛡️ [V2Ray VPN] 状态更新: ${status.state} (上行: ${status.uploadSpeed} | 下行: ${status.downloadSpeed})");
    },
  );

  @override
  void onInit() {
    super.onInit();
    // 初始化 V2Ray 核心与通知栏图标
    _v2ray
        .initialize(
      notificationIconResourceType: "mipmap",
      notificationIconResourceName: "ic_launcher",
    )
        .then((_) async {
      final version = await _v2ray.getCoreVersion();
      debugPrint("✅ [V2Ray Core] 初始化完成，核心版本: $version");
    })
        .catchError((e) {
      debugPrint("⚠️ [V2Ray Core] 初始化异常: $e");
    });
  }

  /// 🌟 启动 SSH 动态隧道并自动开启底层 VPN 网卡接管全流量
  Future<bool> startTunnel(AtClient atClient) async {
    if (isTunnelActive.value && isVpnConnected.value) return true;

    try {
      final String clientSign = atClient.getCurrentAtSign() ?? '@gemini2banana';
      debugPrint("🚀 [AppSshTunnel] 正在向 $remoteDeviceAtsign:$remoteSshPort 发起 Atsign 隧道握手 (客户端: $clientSign)...");

      final nptParams = NptParams(
        clientAtSign: clientSign,
        sshnpdAtSign: remoteDeviceAtsign,
        srvdAtSign: srvdAtsign,
        device: deviceName,
        localPort: 0,
        remotePort: remoteSshPort,
        remoteHost: 'localhost',
        localHost: '127.0.0.1',
        rootDomain: 'root.atsign.org',
        inline: true,
        timeout: const Duration(seconds: 30),
      );

      _npt = Npt.create(params: nptParams, atClient: atClient);
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
        throw Exception("未能从 Atsign Npt 获取到有效的本地监听端口");
      }

      debugPrint("🔑 [AppSshTunnel] Atsign 隧道建立成功！监听端口: 127.0.0.1:$actualPort，正在建立 SSH 连接...");

      // 连接本地 SSH Socket
      SSHSocket? sshSocket;
      for (int attempt = 1; attempt <= 6; attempt++) {
        try {
          await Future.delayed(Duration(milliseconds: attempt == 1 ? 500 : 800));
          sshSocket = await SSHSocket.connect('127.0.0.1', actualPort, timeout: const Duration(seconds: 5));
          break;
        } catch (e) {
          if (attempt == 6) rethrow;
        }
      }

      _sshClient = SSHClient(
        sshSocket!,
        username: 'root',
        onPasswordRequest: () => 'noports123',
      );
      await _sshClient?.authenticated;

      if (_sshClient != null) {
        _proxyServer = HttpProxyServer(sshClient: _sshClient!);
        final int proxyPort = await _proxyServer!.start();
        currentSocks5Port.value = proxyPort;
        isTunnelActive.value = true;

        debugPrint("🎉 [AppSshTunnel] SSH 代理已就绪 (127.0.0.1:$proxyPort)，正在启动 flutter_v2ray_client VPN 全局接管...");

        // 🌟 自动启动系统级 VPN，将全 App 原生流量导入 127.0.0.1:$proxyPort
        await _startVpnService(proxyPort);

        return true;
      }
      return false;
    } catch (e, stackTrace) {
      debugPrint("❌ [AppSshTunnel] 隧道/VPN启动失败: $e\n$stackTrace");
      await stopTunnel();
      return false;
    }
  }

  /// 🌟 将 V2Ray 出口对准本地 SSH 代理端口并启动 TUN 网卡
  Future<void> _startVpnService(int proxyPort) async {
    try {
      final hasPermission = await _v2ray.requestPermission();
      if (!hasPermission) {
        debugPrint("⚠️ [V2Ray VPN] 用户拒绝了 VPN 授权申请");
        return;
      }

      // 构造将全局流量导入 127.0.0.1:$proxyPort 的标准 V2Ray 路由配置
      final Map<String, dynamic> configJson = {
        "log": {"loglevel": "warning"},
        "inbounds": [
          {
            "tag": "socks-in",
            "port": 10808,
            "listen": "127.0.0.1",
            "protocol": "socks",
            "settings": {"auth": "noauth", "udp": true},
            "sniffing": {
              "enabled": true,
              "destOverride": ["http", "tls"]
            }
          }
        ],
        "outbounds": [
          {
            "tag": "proxy",
            "protocol": "http", // HttpProxyServer 接收 HTTP/CONNECT 流量
            "settings": {
              "servers": [
                {
                  "address": "127.0.0.1",
                  "port": proxyPort
                }
              ]
            }
          },
          {
            "tag": "direct",
            "protocol": "freedom"
          }
        ],
        "routing": {
          "domainStrategy": "AsIs",
          "rules": [
            {
              "type": "field",
              "outboundTag": "proxy",
              "network": "tcp,udp"
            }
          ]
        }
      };

      await _v2ray.startV2Ray(
        remark: "QOrange Global Stream Tunnel",
        config: jsonEncode(configJson),
        proxyOnly: false, // 🌟 false 代表开启系统级 VPN 模式（全 App 原生接管）
        notificationDisconnectButtonName: "DISCONNECT",
      );

      debugPrint("🚀 [V2Ray VPN] 系统 VPN 网卡已启动！所有原生 ExoPlayer/AVPlayer/WebView 均已无感出海！");
    } catch (e) {
      debugPrint("🔴 [V2Ray VPN] 启动异常: $e");
    }
  }

  /// 关闭并释放隧道与 VPN 网卡
  Future<void> stopTunnel() async {
    try {
      await _v2ray.stopV2Ray();
    } catch (_) {}

    await _proxyServer?.stop();
    _proxyServer = null;

    _sshClient?.close();
    _sshClient = null;

    await _npt?.close();
    _npt = null;

    isTunnelActive.value = false;
    isVpnConnected.value = false;
    currentSocks5Port.value = 0;
    debugPrint("🔌 [AppSshTunnel] 隧道与 V2Ray VPN 已安全关闭");
  }

  @override
  void onClose() {
    stopTunnel();
    super.onClose();
  }
}