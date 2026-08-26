import 'dart:io';
import 'package:socks5_proxy/socks_client.dart';

class AppHttpOverrides extends HttpOverrides {
  final int socks5Port;

  // 🌟 引用计数管理：页面进入时启用代理，退出时自动释放
  static int _activeProxyConsumers = 0;
  static bool get proxyEnabled => _activeProxyConsumers > 0;

  static void enableProxy() {
    _activeProxyConsumers++;
  }

  static void disableProxy() {
    if (_activeProxyConsumers > 0) {
      _activeProxyConsumers--;
    }
  }

  static set proxyEnabled(bool value) {
    if (value) {
      if (_activeProxyConsumers == 0) _activeProxyConsumers = 1;
    } else {
      _activeProxyConsumers = 0;
    }
  }

  AppHttpOverrides({required this.socks5Port});

  // 🌟 仅保留与 YouTube 视频、音频、图片 CDN 强相关的核心域名
  static const List<String> _youtubeDomainWhitelist = [
    'youtube.com',            // YouTube 核心服务与 API
    'youtu.be',               // YouTube 短链解析
    'youtube-nocookie.com',   // YouTube 无 Cookie 嵌入式播放源
    'googlevideo.com',        // 🌟 核心：YouTube 视频流与音频流媒体源 (ExoPlayer/AVPlayer 拉流关键)
    'ytimg.com',              // 🌟 核心：视频高清封面、缩略图 CDN (i.ytimg.com)
    'ggpht.com',              // 🌟 核心：UP主/频道头像与图片 CDN (yt3.ggpht.com)
    'googleusercontent.com',  // 用户生成内容与备用图片媒体
    'googleapis.com',         // YouTube Data API 与元数据检索
    'gstatic.com',            // Google 静态依赖与必要认证资源
  ];

  /// 判断当前请求 host 是否属于 YouTube 链路
  static bool isYouTubeHost(String host) {
    final lowerHost = host.toLowerCase();
    return _youtubeDomainWhitelist.any((domain) {
      return lowerHost == domain || lowerHost.endsWith('.$domain');
    });
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;

    // 🌟 只有在代理处于开启状态且端口有效时，才挂载 SOCKS5
    if (proxyEnabled && socks5Port > 0) {
      final proxies = [
        ProxySettings(InternetAddress.loopbackIPv4, socks5Port),
      ];

      // 接入 socks5_proxy 标准客户端，底层自动完成 RFC 1928 握手
      SocksTCPClient.assignToHttpClient(client, proxies);
    }

    return client;
  }
}