import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:noports_core/npt.dart';

import 'app_http_overrides.dart';
import 'http_proxy_server.dart';
import 'local_media_proxy_server.dart';

class AppSshTunnelService extends GetxService {
  static AppSshTunnelService get to => Get.find<AppSshTunnelService>();

  // 节点配置（与服务端一致）
  static const String remoteDeviceAtsign = '@absolute3140';
  static const String deviceName = 'zeabur';
  static const String srvdAtsign = '@rv_am';
  static const int remoteSshPort = 22; // 容器内默认 SSH 端口

  final RxBool isTunnelActive = false.obs;
  final RxInt currentProxyPort = 0.obs;

  Npt? _npt;
  SSHClient? _sshClient;
  HttpProxyServer? _proxyServer;

  /// 🌟 统一封装 Toast 提示
  void _showToast(String msg, Color bgColor, {Toast length = Toast.LENGTH_SHORT}) {
    Fluttertoast.cancel();
    Fluttertoast.showToast(
      msg: msg,
      toastLength: length,
      gravity: ToastGravity.BOTTOM,
      backgroundColor: bgColor,
      textColor: Colors.white,
      fontSize: 13.0,
    );
  }

  /// 🌟 启动 SSH 稳定隧道与应用内分流
  Future<bool> startTunnel(AtClient atClient) async {
    if (isTunnelActive.value) return true;

    try {
      _showToast("🔄 正在向 Atsign 节点发起加密握手...", const Color(0xFFE59819));

      final String clientSign = atClient.getCurrentAtSign() ?? '@gemini2banana';
      debugPrint("🚀 [AppSshTunnel] 正在向 $remoteDeviceAtsign:$remoteSshPort 发起 Atsign 加密隧道握手 (客户端: $clientSign)...");

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
        throw Exception("未能从 Atsign Npt 获取到有效的本地监听端口 (runResult: $runResult)");
      }

      debugPrint("🔑 [AppSshTunnel] Atsign 隧道已打通！真实监听端口: $actualPort，正在进行 SSH 鉴权握手...");

      // 🌟 3. 连接 SSH（带重试）
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

      // 🌟 4. 启动应用内本地 HTTP/CONNECT 代理
      _proxyServer = HttpProxyServer(sshClient: _sshClient!);
      final int proxyPort = await _proxyServer!.start();
      currentProxyPort.value = proxyPort;

      // 🌟 5. 挂载 Dart 全局网络代理拦截
      HttpOverrides.global = AppHttpOverrides(proxyPort: proxyPort);
      AppHttpOverrides.enableProxy();

      // 🌟 6. 启动原生媒体播放流中继服务
      await LocalMediaProxyServer.instance.start();

      isTunnelActive.value = true;
      debugPrint("🎉 [AppSshTunnel] 全局安全隧道已就绪 (代理端口: 127.0.0.1:$proxyPort)！");

      _showToast("✅ 全局安全隧道已就绪！", const Color(0xFF2E7D32), length: Toast.LENGTH_LONG);
      return true;
    } catch (e, stackTrace) {
      debugPrint("❌ [AppSshTunnel] 隧道启动失败: $e\n$stackTrace");
      _showToast("❌ 连接失败: ${e.toString().replaceAll('Exception:', '').trim()}", const Color(0xFFC62828));
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

    await LocalMediaProxyServer.instance.stop();

    isTunnelActive.value = false;
    currentProxyPort.value = 0;
    debugPrint("🔌 [AppSshTunnel] 隧道已彻底关闭并释放内存资源");

    _showToast("🔌 专用安全隧道已断开", const Color(0xFF424242));
  }

  @override
  void onClose() {
    stopTunnel();
    super.onClose();
  }
}