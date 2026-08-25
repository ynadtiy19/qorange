// lib/network/app_http_overrides.dart
import 'dart:io';

/// 具备智能域名分流的全局网络拦截器
class AppHttpOverrides extends HttpOverrides {
  final int proxyPort;

  AppHttpOverrides({required this.proxyPort});

  // 🌟 需要强制走海外代理隧道的域名白名单
  static const List<String> _proxyDomainWhitelist = [
    // YouTube 核心服务
    'youtube.com',
    'youtu.be',
    'youtube-nocookie.com',

    // YouTube 视频与音频分片传输核心域名（关键）
    'googlevideo.com',

    // 封面图、头像等静态资源
    'ytimg.com',
    'ggpht.com',
    'googleusercontent.com',

    // Google API 基础链路
    'googleapis.com',
    'gvt1.com',
    '1e100.net',
  ];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (Uri uri) {
        final host = uri.host.toLowerCase();

        // 🌟 1. 检查当前请求的域名是否命中海外白名单
        final bool shouldProxy = _proxyDomainWhitelist.any((domain) {
          return host == domain || host.endsWith('.$domain');
        });

        if (shouldProxy) {
          // 命中白名单：走本地 Atsign SSH 隧道代理出口
          return "PROXY 127.0.0.1:$proxyPort";
        }

        // 🌟 2. 其余所有流量（如你的 Zeabur 业务API、Cloudinary、支付等）一律走原生系统网络直连！
        return "DIRECT";
      }
      ..badCertificateCallback = (cert, host, port) => true;
  }
}