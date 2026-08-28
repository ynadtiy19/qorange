// lib/network/app_http_overrides.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:socks5_proxy/socks_client.dart';

class AppHttpOverrides extends HttpOverrides {
  // 🌟 核心改进：传入动态端口回调函数，避免端口变化后走失效的老端口
  final ValueGetter<int> getSocks5Port;

  AppHttpOverrides({required this.getSocks5Port});

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
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'google.com',
    'invidious.io',
    'omada.cafe',
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
      ..maxConnectionsPerHost = 30;

    final currentPort = getSocks5Port();
    if (currentPort > 0) {
      final proxies = [
        ProxySettings(InternetAddress.loopbackIPv4, currentPort),
      ];
      SocksTCPClient.assignToHttpClient(client, proxies);
    }

    return client;
  }
}