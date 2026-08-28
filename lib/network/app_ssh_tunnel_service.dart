// lib/network/app_ssh_tunnel_service.dart
import 'dart:async';
import 'dart:io';
import 'package:at_client/at_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
  Timer? _networkDebounceTimer;
  AtClient? _cachedAtClient;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  int _consecutivePingFails = 0;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _initNetworkConnectivityListener();

    // 🌟 全局注册动态端口代理拦截器
    HttpOverrides.global = AppHttpOverrides(
      getSocks5Port: () => currentSocks5Port.value,
    );
  }

  /// 🌟 1. 核心特性：监听 Wi-Fi ↔ 4G/5G 物理网络切换事件
  void _initNetworkConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      _onNetworkChanged(results);
    });
  }

  void _onNetworkChanged(List<ConnectivityResult> results) {
    final hasConnection = results.any((r) => r != ConnectivityResult.none);
    if (!hasConnection) {
      debugPrint("📶 [AppSshTunnel] 设备处于断网状态...");
      return;
    }

    debugPrint("📶 [AppSshTunnel] 监测到物理网络切换 (Wi-Fi/流量): $results");

    // 防抖 800ms：等待手机操作系统完成新网卡的 IP 分配和路由表刷新
    _networkDebounceTimer?.cancel();
    _networkDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (_cachedAtClient != null) {
        debugPrint("🔄 [AppSshTunnel] 网络已切换就绪，立即重塑 SSH/Atsign 隧道...");
        _forceReconnectTunnel(reason: "网络切换自愈");
      }
    });
  }

  /// 🌟 2. 监听 App 切回前台
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("📱 [AppSshTunnel] 应用切回前台，执行隧道活性巡检...");
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

  /// 心跳探活
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _consecutivePingFails = 0;

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (isTunnelActive.value && _sshClient != null && !isReconnecting.value) {
        try {
          await _sshClient?.ping().timeout(const Duration(seconds: 10));
          _consecutivePingFails = 0;
        } catch (e) {
          _consecutivePingFails++;
          debugPrint("⚠️ [AppSshTunnel] 心跳探测超时 ($_consecutivePingFails/2): $e");
          if (_consecutivePingFails >= 2) {
            _checkAndHealTunnel();
          }
        }
      }
    });
  }

  /// 常规自检
  Future<void> _checkAndHealTunnel() async {
    if (_cachedAtClient == null || isReconnecting.value) return;

    bool isAlive = false;
    try {
      if (_sshClient != null && isTunnelActive.value) {
        await _sshClient!.ping().timeout(const Duration(seconds: 4));
        isAlive = true;
      }
    } catch (_) {
      isAlive = false;
    }

    if (!isAlive) {
      _forceReconnectTunnel(reason: "心跳失效自愈");
    }
  }

  /// 🌟 3. 强制重连执行器（带并发互斥锁与 DNS 预热）
  Future<void> _forceReconnectTunnel({required String reason}) async {
    if (_cachedAtClient == null || isReconnecting.value) return;

    isReconnecting.value = true;
    debugPrint("🔄 [AppSshTunnel] 开始执行 [$reason] 流程...");

    try {
      // 1. 立即强制断开死锁的旧 Socket
      await stopTunnel(silent: true);

      // 2. 快速探测外网 DNS 是否可达（确保新网卡能连外网）
      for (int i = 0; i < 3; i++) {
        try {
          final ips = await InternetAddress.lookup('root.atsign.org').timeout(const Duration(seconds: 2));
          if (ips.isNotEmpty) break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      // 3. 重新建立新网络下的 Atsign + SSH 隧道
      await startTunnel(_cachedAtClient!, silent: true);
      debugPrint("✅ [AppSshTunnel] [$reason] 成功！新 SOCKS5 端口: ${currentSocks5Port.value}");
    } catch (e) {
      debugPrint("❌ [AppSshTunnel] [$reason] 异常: $e");
    } finally {
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
      currentSocks5Port.value = socksPort; // 🌟 触发 AppHttpOverrides 自动指向新端口
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
    debugPrint("🔌 [AppSshTunnel] 隧道已释放");
    if (!silent) {
      _showToast("🔌 专用安全隧道已断开", const Color(0xFF424242));
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _networkDebounceTimer?.cancel();
    stopTunnel();
    super.onClose();
  }
}