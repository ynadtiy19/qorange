import 'dart:io';
import 'package:flutter/foundation.dart';

class LocalMediaProxyServer {
  static final LocalMediaProxyServer instance = LocalMediaProxyServer._();
  LocalMediaProxyServer._();

  HttpServer? _server;
  int? localPort;

  // 🌟 性能核心 1：全局单例连接池，复用 TLS 会话与 SSH 通道，杜绝反复建连开销
  HttpClient? _sharedClient;

  HttpClient get _client {
    if (_sharedClient == null) {
      _sharedClient = HttpClient()
        ..badCertificateCallback = ((cert, host, port) => true)
        ..connectionTimeout = const Duration(seconds: 10)
        ..idleTimeout = const Duration(seconds: 60)
        ..maxConnectionsPerHost = 20
        ..autoUncompress = true;
    }
    return _sharedClient!;
  }

  /// 启动本地微型流分发服务器
  Future<int> start() async {
    if (_server != null) return localPort!;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    localPort = _server!.port;
    debugPrint("🚀 [LocalMediaProxy] 本地高性能中继就绪: http://127.0.0.1:$localPort");

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
      // 🌟 性能核心 2：复用单例 client，由底层连接池自动分发 Keep-Alive
      final upstreamReq = await _client.getUrl(Uri.parse(targetUrl));

      // 透传 Range 请求头以支持音视频分片与拖拽
      final range = clientReq.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
      }
      upstreamReq.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );

      final upstreamResp = await upstreamReq.close();

      clientReq.response.statusCode = upstreamResp.statusCode;

      // 复制必要的响应头（忽略传输编码头避免冲突）
      upstreamResp.headers.forEach((name, values) {
        if (name.toLowerCase() != 'transfer-encoding') {
          for (var v in values) {
            clientReq.response.headers.add(name, v);
          }
        }
      });

      // 零拷贝直接管道推流
      await clientReq.response.addStream(upstreamResp);
      await clientReq.response.close();
    } catch (e) {
      debugPrint("🔴 [LocalMediaProxy] 流传输异常: $e");
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
  }
}