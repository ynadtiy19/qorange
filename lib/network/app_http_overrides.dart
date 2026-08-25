// lib/network/app_http_overrides.dart
import 'dart:io';

class AppHttpOverrides extends HttpOverrides {
  final int proxyPort;

  AppHttpOverrides({required this.proxyPort});

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (uri) {
        // 🌟 强制走本地代理隧道，不给任何直连泄露的机会
        return "PROXY 127.0.0.1:$proxyPort";
      }
      ..badCertificateCallback = (cert, host, port) => true;
  }
}