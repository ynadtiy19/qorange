// lib/network/app_ssh_tunnel_service.dart
import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:noports_core/npt.dart';

import 'app_http_overrides.dart';
import 'http_proxy_server.dart';

class AppSshTunnelService extends GetxService {
  static AppSshTunnelService get to => Get.find<AppSshTunnelService>();

  // 节点配置（与服务端一致）
  static const String remoteDeviceAtsign = '@absolute3140';
  static const String deviceName = 'zeabur';
  static const String srvdAtsign = '@rv_am';
  static const int remoteSshPort = 22; // 容器内默认 SSH 端口

  final RxBool isTunnelActive = false.obs;
  final RxInt currentSocks5Port = 0.obs;

  Npt? _npt;
  SSHClient? _sshClient;
  HttpProxyServer? _proxyServer;

  /// 动态寻找未占用端口
  Future<int> _findFreePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final freePort = socket.port;
    await socket.close();
    return freePort;
  }

  /// 🌟 启动 SSH 动态隧道（全流程空安全加固版）
  Future<bool> startTunnel(AtClient atClient) async {
    if (isTunnelActive.value) return true;

    try {
      // 🌟 1. 彻底防空：安全提取 clientAtSign，若为空则自动回退为 @gemini2banana
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

      // 🌟 2. 安全执行隧道并在空安全下解析端口
      final dynamic runResult = await _npt?.run();

      int actualPort = 0;
      if (runResult is int && runResult > 0) {
        actualPort = runResult;
      } else if (runResult != null) {
        try {
          actualPort = (runResult as dynamic).port ?? 0;
        } catch (_) {}
      }

      // 如果依然没拿到端口，尝试从 _npt 属性读取
      if (actualPort <= 0 && _npt != null) {
        try {
          actualPort = (_npt as dynamic).port ?? (_npt as dynamic).localPort ?? 0;
        } catch (_) {}
      }

      if (actualPort <= 0) {
        throw Exception("未能从 Atsign Npt 获取到有效的本地监听端口 (runResult: $runResult)");
      }

      debugPrint("🔑 [AppSshTunnel] Atsign 隧道已打通！真实监听端口: $actualPort，正在进行 SSH 免密/密码鉴权握手...");

      // 🌟 3. 安全连接 SSH（带平滑重试）
      SSHSocket? sshSocket;
      for (int attempt = 1; attempt <= 6; attempt++) {
        try {
          await Future.delayed(Duration(milliseconds: attempt == 1 ? 500 : 800));
          sshSocket = await SSHSocket.connect(
            '127.0.0.1',
            actualPort,
            timeout: const Duration(seconds: 5),
          );
          break;
        } catch (e) {
          debugPrint("⏳ [AppSshTunnel] 等待 127.0.0.1:$actualPort 就绪 (尝试 $attempt/6)...");
          if (attempt == 6) rethrow;
        }
      }

      if (sshSocket == null) {
        throw Exception("SSH 套接字连接失败");
      }

      _sshClient = SSHClient(
        sshSocket,
        username: 'root',
        onPasswordRequest: () => 'noports123',
      );

      await _sshClient?.authenticated;
      debugPrint("✅ [AppSshTunnel] SSH 鉴权成功！");

      // 🌟 4. 启动应用内本地 SOCKS5 代理
      if (_sshClient != null) {
        _proxyServer = HttpProxyServer(sshClient: _sshClient!);
        final int proxyPort = await _proxyServer!.start();
        currentSocks5Port.value = proxyPort;

        // 🌟 5. 挂载全局网络代理拦截（由 AppHttpOverrides 精准按白名单分流）
        HttpOverrides.global = AppHttpOverrides(proxyPort: proxyPort);
        isTunnelActive.value = true;

        debugPrint("🎉 [AppSshTunnel] 全局安全隧道已就绪 (代理端口: 127.0.0.1:$proxyPort)！所有海外媒体/YouTube请求将无感代理！");
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      debugPrint("❌ [AppSshTunnel] 隧道启动失败: $e\n$stackTrace");
      await stopTunnel();
      return false;
    }
  }

  /// 关闭并释放隧道
  Future<void> stopTunnel() async {
    HttpOverrides.global = null;
    await _proxyServer?.stop();
    _proxyServer = null;

    _sshClient?.close();
    _sshClient = null;

    await _npt?.close();
    _npt = null;

    isTunnelActive.value = false;
    currentSocks5Port.value = 0;
    debugPrint("🔌 [AppSshTunnel] 隧道已彻底关闭并释放内存资源");
  }

  @override
  void onClose() {
    stopTunnel();
    super.onClose();
  }
}