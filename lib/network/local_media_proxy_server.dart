import 'dart:io';
import 'package:flutter/foundation.dart';

class LocalMediaProxyServer {
  static final LocalMediaProxyServer instance = LocalMediaProxyServer._();
  LocalMediaProxyServer._();

  HttpServer? _server;
  int? localPort;

  // 🌟 性能核心 1：全局单例连接池，复用 TLS 会话与 SSH SOCKS5 通道
  HttpClient? _sharedClient;

  HttpClient get _client {
    _sharedClient ??= HttpClient()
        ..badCertificateCallback = ((cert, host, port) => true)
        ..connectionTimeout = const Duration(seconds: 15)
        ..idleTimeout = const Duration(seconds: 60)
        ..maxConnectionsPerHost = 30
      // 🌟 关键修复 1：流媒体代理必须设为 false，确保字节尺寸与 Range 分片头 100% 严格一致
        ..autoUncompress = false;
    return _sharedClient!;
  }

  /// 启动本地微型流分发服务器
  Future<int> start() async {
    if (_server != null) return localPort!;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    localPort = _server!.port;
    debugPrint("🚀 [LocalMediaProxy] 本地高性能流中继就绪: http://127.0.0.1:$localPort");

    _server!.listen(_handleRequest);
    return localPort!;
  }

  void _handleRequest(HttpRequest clientReq) async {
    final targetUrl = clientReq.uri.queryParameters['url'];
    if (targetUrl == null || targetUrl.isEmpty) {
      clientReq.response.statusCode = HttpStatus.badRequest;
      await clientReq.response.close();
      return;
    }

    try {
      // 🌟 性能核心 2：复用单例 client，自动由 AppHttpOverrides 分发至 SOCKS5
      final upstreamReq = await _client.getUrl(Uri.parse(targetUrl));

      // 透传 Range 请求头（支持播放器快进、后退、拖拽）
      final range = clientReq.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
      }
      upstreamReq.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );

      final upstreamResp = await upstreamReq.close();

      // 复制 HTTP 状态码（如 200 OK 或 206 Partial Content）
      clientReq.response.statusCode = upstreamResp.statusCode;

      // 🌟 关键修复 2：过滤掉 Hop-by-Hop 逐跳头，其余正常回拷
      upstreamResp.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower != 'transfer-encoding' && lower != 'connection' && lower != 'keep-alive') {
          for (var v in values) {
            clientReq.response.headers.add(name, v);
          }
        }
      });

      // 零拷贝直通推流
      await clientReq.response.addStream(upstreamResp);
      await clientReq.response.close();
    } catch (e) {
      // 🌟 关键修复 3：捕获用户快速滑屏或切歌时主动中止连接的异常，防止控制台刷屏报错
      if (e is! SocketException) {
        debugPrint("🔴 [LocalMediaProxy] 流传输异常: $e, url = $targetUrl");
      }
      try {
        clientReq.response.statusCode = HttpStatus.badGateway;
        await clientReq.response.close();
      } catch (_) {}
    }
  }

  /// 构造原生播放器或 Image 组件可直接加载的本地代理链接
  String buildPlayUrl(String remoteUrl) {
    if (localPort == null || remoteUrl.isEmpty) return remoteUrl;
    return 'http://127.0.0.1:$localPort/stream?url=${Uri.encodeComponent(remoteUrl)}';
  }

  Future<void> stop() async {
    _sharedClient?.close(force: true);
    _sharedClient = null;
    await _server?.close(force: true);
    _server = null;
    localPort = null;
    debugPrint("🔌 [LocalMediaProxy] 本地中继服务已释放");
  }
}