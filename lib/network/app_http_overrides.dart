import 'dart:io';
import 'package:socks5_proxy/socks_client.dart';

class AppHttpOverrides extends HttpOverrides {
  final int socks5Port;

  AppHttpOverrides({required this.socks5Port});

  // 🌟 核心修复：补全 YouTube 播放必须的 DoubleClick 探针与 Google 服务域名，彻底消除 152-4 报错
  static const List<String> _youtubeDomainWhitelist = [
    'youtube.com',
    'youtu.be',
    'youtube-nocookie.com',
    'googlevideo.com',
    'ytimg.com',
    'ggpht.com',
    'googleusercontent.com',
    'googleapis.com',
    'gstatic.com',
    // 🌟 解决 Error 152-4 必须的域名：
    'doubleclick.net',          // 核心：static.doubleclick.net 探针脚本
    'googlesyndication.com',    // Google 媒体聚合校验
    'googleadservices.com',     // 广告状态回执
    'google.com',               // Google 账户与安全基础服务
  ];

  static bool isYouTubeHost(String host) {
    final lower = host.toLowerCase();
    return _youtubeDomainWhitelist.any((d) => lower == d || lower.endsWith('.$d'));
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)
      ..badCertificateCallback = ((cert, host, port) => true)
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 60)
      ..maxConnectionsPerHost = 20;

    if (socks5Port > 0) {
      final proxies = [
        ProxySettings(InternetAddress.loopbackIPv4, socks5Port),
      ];
      SocksTCPClient.assignToHttpClient(client, proxies);
    }

    return client;
  }
}