// lib/network/app_http_overrides.dart
import 'dart:io';

/// 全局网络请求拦截重写器
class AppHttpOverrides extends HttpOverrides {
  final int socksPort;

  AppHttpOverrides({required this.socksPort});

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (uri) {
        // 自动使用本地 SOCKS5 隧道处理所有出站 HTTP/HTTPS 流量
        return "SOCKS5 127.0.0.1:$socksPort; SOCKS 127.0.0.1:$socksPort; DIRECT";
      }
      ..badCertificateCallback = (cert, host, port) => true; // 避免自签名证书报错
  }
}