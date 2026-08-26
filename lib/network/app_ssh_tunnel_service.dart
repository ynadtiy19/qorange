import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:noports_core/npt.dart';

import 'app_http_overrides.dart';
import 'local_media_proxy_server.dart';

class AppSshTunnelService extends GetxService {
  static AppSshTunnelService get to => Get.find<AppSshTunnelService>();

  static const String remoteDeviceAtsign = '@absolute3140';
  static const String deviceName = 'zeabur';
  static const String srvdAtsign = '@rv_am';
  static const int remoteSshPort = 22;

  final RxBool isTunnelActive = false.obs;
  final RxInt currentSocks5Port = 0.obs;

  Npt? _npt;
  SSHClient? _sshClient;
  SSHDynamicForward? _dynamicForward;

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

  /// 🌟 启动与 Mac 终端 -D 100% 一致的标准 SOCKS5 隧道
  Future<bool> startTunnel(AtClient atClient) async {
    if (isTunnelActive.value) return true;

    try {
      _showToast("🔄 正在向 Atsign 节点发起握手...", const Color(0xFFE59819));

      final String clientSign = atClient.getCurrentAtSign() ?? '@gemini2banana';

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
        throw Exception("未获取到有效的本地端口");
      }

      // 1. 连接 SSH
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
          if (attempt == 6) rethrow;
        }
      }

      if (sshSocket == null) throw Exception("SSH 套接字连接失败");

      _sshClient = SSHClient(
        sshSocket,
        username: 'root',
        onPasswordRequest: () => 'noports123',
      );

      await _sshClient?.authenticated;
      debugPrint("✅ [AppSshTunnel] SSH 鉴权成功！");

      // 🌟 2. 开启 dartssh2 内置的 RFC 标准 SOCKS5 端口
      _dynamicForward = await _sshClient!.forwardDynamic(
        bindHost: '127.0.0.1',
        bindPort: 0,
      );

      final int socksPort = _dynamicForward!.port;
      currentSocks5Port.value = socksPort;
      debugPrint("🚀 [AppSshTunnel] 原生 SOCKS5 代理已就绪: 127.0.0.1:$socksPort");

      // 🌟 3. 使用 socks5_proxy 接管全局 Dart 网络
      HttpOverrides.global = AppHttpOverrides(socks5Port: socksPort);

      // 🌟 4. 启动本地媒体中继
      await LocalMediaProxyServer.instance.start();

      isTunnelActive.value = true;
      _showToast("✅ SOCKS5 极速隧道已就绪！", const Color(0xFF2E7D32), length: Toast.LENGTH_LONG);
      return true;
    } catch (e, stackTrace) {
      debugPrint("❌ [AppSshTunnel] 启动失败: $e\n$stackTrace");
      _showToast("❌ 连接失败: $e", const Color(0xFFC62828));
      await stopTunnel();
      return false;
    }
  }

  /// 关闭并释放隧道
  Future<void> stopTunnel() async {
    HttpOverrides.global = null;

    _dynamicForward?.close();
    _dynamicForward = null;

    _sshClient?.close();
    _sshClient = null;

    await _npt?.close();
    _npt = null;

    await LocalMediaProxyServer.instance.stop();

    isTunnelActive.value = false;
    currentSocks5Port.value = 0;
    debugPrint("🔌 [AppSshTunnel] 隧道已彻底关闭");
    _showToast("🔌 专用安全隧道已断开", const Color(0xFF424242));
  }

  @override
  void onClose() {
    stopTunnel();
    super.onClose();
  }
}