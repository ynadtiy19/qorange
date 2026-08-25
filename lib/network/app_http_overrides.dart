// lib/network/app_http_overrides.dart
import 'dart:io';

class AppHttpOverrides extends HttpOverrides {
  final int proxyPort;

  AppHttpOverrides({required this.proxyPort});

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (uri) {
        // 🌟 核心：Dart 原生标准的 HTTP/HTTPS 代理语法，100% 强制拦截所有请求走隧道！
        return "PROXY 127.0.0.1:$proxyPort; DIRECT";
      }
      ..badCertificateCallback = (cert, host, port) => true;
  }
}