import 'dart:io';

class AppHttpOverrides extends HttpOverrides {
  final int proxyPort;

  // 引用计数管理
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

  AppHttpOverrides({required this.proxyPort});

  static const List<String> _proxyDomainWhitelist = [
    // YouTube 核心服务及媒体流与图片 CDN
    'youtube.com',
    'youtu.be',
    'youtube-nocookie.com',
    'googlevideo.com',
    'ytimg.com',
    'ggpht.com',
    'googleusercontent.com',

    // 🌟 解析 API 节点池与公共中继域名
    'cobalt.tools',
    'api.cobalt.tools',
    'kwiatekm.pl',
    'co.wuk.sh',
    'savefrom.net',
    'savefrom.in.net',

    // 🌟 Invidious / Piped 分布式节点
    'pipedapi.kavin.rocks',
    'api.piped.private.coffee',
    'pipedapi.tokhmi.xyz',
    'invidious.nerdvpn.de',
    'inv.tux.pizza',
    'yt.artemislena.eu',
    'invidious.jing.rocks',
    'invidious.privacydev.net',
    'invidious.drgns.space',

    // 基础海外与 Google API 链路
    'gstatic.com',
    'google.com',
    'googleapis.com',
    'gvt1.com',
    '1e100.net',
  ];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (Uri uri) {
        if (proxyEnabled && proxyPort > 0) {
          final host = uri.host.toLowerCase();
          final bool shouldProxy = _proxyDomainWhitelist.any((domain) {
            return host == domain || host.endsWith('.$domain');
          });
          if (shouldProxy) {
            return "PROXY 127.0.0.1:$proxyPort";
          }
        }
        return "DIRECT";
      }
      ..badCertificateCallback = (cert, host, port) => true;
  }
}