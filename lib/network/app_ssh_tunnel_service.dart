import 'dart:async';
import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
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
  Timer? _heartbeatTimer;

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

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (isTunnelActive.value && _sshClient != null) {
        try {
          await _sshClient?.ping();
        } catch (_) {}
      }
    });
  }

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

      _dynamicForward = await _sshClient!.forwardDynamic(
        bindHost: '127.0.0.1',
        bindPort: 0,
      );

      final int socksPort = _dynamicForward!.port;
      currentSocks5Port.value = socksPort;
      debugPrint("🚀 [AppSshTunnel] SOCKS5 代理已启动: 127.0.0.1:$socksPort");

      // 🌟 注入原生 WebView SOCKS5 代理（全量接管 Chromium 网络）
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final isSupported = await WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE);
        if (isSupported) {
          final proxyController = ProxyController.instance();
          await proxyController.setProxyOverride(
            settings: ProxySettings(
              proxyRules: [
                ProxyRule(url: "socks5://127.0.0.1:$socksPort"),
              ],
              bypassRules: [],
            ),
          );
          debugPrint("🌐 [AppSshTunnel] Android WebView 代理注入成功！");
        }
      }

      HttpOverrides.global = AppHttpOverrides(socks5Port: socksPort);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      await LocalMediaProxyServer.instance.start();

      isTunnelActive.value = true;
      _startHeartbeat();

      _showToast("✅ 全端 SOCKS5 隧道已就绪！", const Color(0xFF2E7D32), length: Toast.LENGTH_LONG);
      return true;
    } catch (e, stackTrace) {
      debugPrint("❌ [AppSshTunnel] 启动失败: $e\n$stackTrace");
      _showToast("❌ 连接失败: $e", const Color(0xFFC62828));
      await stopTunnel();
      return false;
    }
  }

  Future<void> stopTunnel() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    HttpOverrides.global = null;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final isSupported = await WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE);
        if (isSupported) {
          await ProxyController.instance().clearProxyOverride();
        }
      } catch (_) {}
    }

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