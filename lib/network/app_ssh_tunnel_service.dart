// lib/network/app_ssh_tunnel_service.dart
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

class AppSshTunnelService extends GetxService with WidgetsBindingObserver {
  static AppSshTunnelService get to => Get.find<AppSshTunnelService>();

  static const String remoteDeviceAtsign = '@absolute3140';
  static const String deviceName = 'zeabur';
  static const String srvdAtsign = '@rv_am';
  static const int remoteSshPort = 22;

  final RxBool isTunnelActive = false.obs;
  final RxInt currentSocks5Port = 0.obs;
  final RxBool isReconnecting = false.obs;

  Npt? _npt;
  SSHClient? _sshClient;
  SSHDynamicForward? _dynamicForward;
  Timer? _heartbeatTimer;
  AtClient? _cachedAtClient;

  @override
  void onInit() {
    super.onInit();
    // 🌟 注册应用生命周期监听器
    WidgetsBinding.instance.addObserver(this);
  }

  /// 🌟 监听 App 前后台切换：当从后台切回前台时，自动检测并重连
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 [AppSshTunnel] 应用回到前台，执行隧道健康自检...");
      _checkAndHealTunnel();
    }
  }

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

  /// 🌟 增强型心跳：探测到断开立即触发重连
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (isTunnelActive.value && _sshClient != null) {
        try {
          // 向上游发送 SSH ping 报文探测活性
          await _sshClient?.ping().timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint("⚠️ [AppSshTunnel] 心跳探测失败，隧道已失效: $e");
          _checkAndHealTunnel();
        }
      }
    });
  }

  /// 🌟 自愈检测：若隧道假死或失效，自动静默拉起重连
  Future<void> _checkAndHealTunnel() async {
    if (_cachedAtClient == null || isReconnecting.value) return;

    bool isAlive = false;
    try {
      if (_sshClient != null && isTunnelActive.value) {
        await _sshClient!.ping().timeout(const Duration(seconds: 3));
        isAlive = true;
      }
    } catch (_) {
      isAlive = false;
    }

    if (!isAlive) {
      debugPrint("🔄 [AppSshTunnel] 触发自动重连自愈流程...");
      isReconnecting.value = true;
      await stopTunnel(silent: true);
      await startTunnel(_cachedAtClient!, silent: true);
      isReconnecting.value = false;
    }
  }

  Future<bool> startTunnel(AtClient atClient, {bool silent = false}) async {
    if (isTunnelActive.value && _sshClient != null) return true;

    _cachedAtClient = atClient;

    try {
      if (!silent) {
        _showToast("🔄 正在向 Atsign 节点发起握手...", const Color(0xFFE59819));
      }

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
      debugPrint("🚀 [AppSshTunnel] SOCKS5 代理已就绪: 127.0.0.1:$socksPort");

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

      if (!silent) {
        _showToast("✅ 全端 SOCKS5 隧道已就绪！", const Color(0xFF2E7D32), length: Toast.LENGTH_LONG);
      }
      return true;
    } catch (e, stackTrace) {
      debugPrint("❌ [AppSshTunnel] 启动失败: $e\n$stackTrace");
      if (!silent) {
        _showToast("❌ 连接失败: $e", const Color(0xFFC62828));
      }
      await stopTunnel(silent: silent);
      return false;
    }
  }

  Future<void> stopTunnel({bool silent = false}) async {
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

    try {
      _dynamicForward?.close();
    } catch (_) {}
    _dynamicForward = null;

    try {
      _sshClient?.close();
    } catch (_) {}
    _sshClient = null;

    try {
      await _npt?.close();
    } catch (_) {}
    _npt = null;

    await LocalMediaProxyServer.instance.stop();

    isTunnelActive.value = false;
    currentSocks5Port.value = 0;
    debugPrint("🔌 [AppSshTunnel] 隧道已彻底关闭");
    if (!silent) {
      _showToast("🔌 专用安全隧道已断开", const Color(0xFF424242));
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    stopTunnel();
    super.onClose();
  }
}