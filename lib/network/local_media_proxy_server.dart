import 'dart:io';
import 'package:flutter/foundation.dart';

class LocalMediaProxyServer {
  static final LocalMediaProxyServer instance = LocalMediaProxyServer._();
  LocalMediaProxyServer._();

  HttpServer? _server;
  int? localPort;
  HttpClient? _sharedClient;

  HttpClient get _client {
    _sharedClient ??= HttpClient()
      ..badCertificateCallback = ((cert, host, port) => true)
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 60)
      ..maxConnectionsPerHost = 30
      ..autoUncompress = false;
    return _sharedClient!;
  }

  /// 启动本地微型流分发服务器
  Future<int> start() async {
    if (_server != null) return localPort!;

    _sharedClient?.close(force: true);
    _sharedClient = null;

    // 依然绑定 loopback 环回地址 (127.0.0.1)
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    localPort = _server!.port;
    debugPrint("🚀 [LocalMediaProxy] 本地流中继就绪: http://localhost:$localPort");

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
      final upstreamReq = await _client.getUrl(Uri.parse(targetUrl));

      // 透传 Range 请求头（支持 ExoPlayer 播放器分片拉取与快进）
      final range = clientReq.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
      }
      upstreamReq.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );

      final upstreamResp = await upstreamReq.close();

      debugPrint("📥 [LocalMediaProxy] 中继成功 -> 状态: ${upstreamResp.statusCode}, 长度: ${upstreamResp.contentLength}, URL: $targetUrl");

      clientReq.response.statusCode = upstreamResp.statusCode;

      // 复制响应头（忽略 hop-by-hop 逐跳头）
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
      if (e is! SocketException) {
        debugPrint("🔴 [LocalMediaProxy] 传输异常: $e, URL: $targetUrl");
      }
      try {
        clientReq.response.statusCode = HttpStatus.badGateway;
        await clientReq.response.close();
      } catch (_) {}
    }
  }

  /// 🌟 构造原生播放器可直接加载的 localhost 代理链接
  String buildPlayUrl(String remoteUrl) {
    if (localPort == null || remoteUrl.isEmpty) return remoteUrl;
    return 'http://localhost:$localPort/stream?url=${Uri.encodeComponent(remoteUrl)}';
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