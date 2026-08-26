import 'dart:io';
import 'package:flutter/foundation.dart';

class LocalMediaProxyServer {
  static final LocalMediaProxyServer instance = LocalMediaProxyServer._();
  LocalMediaProxyServer._();

  HttpServer? _server;
  int? localPort;

  /// 启动本地微型流分发服务器
  Future<int> start() async {
    if (_server != null) return localPort!;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    localPort = _server!.port;
    debugPrint("🎬 [LocalMediaProxy] 本地播放流中继服务器已就绪: http://127.0.0.1:$localPort");

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
      // 🌟 修复级联解析歧义：单独配置 HttpClient 属性
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) => true;
      client.connectionTimeout = const Duration(seconds: 15);

      final upstreamReq = await client.getUrl(Uri.parse(targetUrl));

      // 透传 Range 请求头以支持播放器快进与图片分片
      final range = clientReq.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
      }
      upstreamReq.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );

      final upstreamResp = await upstreamReq.close();

      // 复制正确的 HTTP 响应状态
      clientReq.response.statusCode = upstreamResp.statusCode;

      // 复制必要的响应头（忽略传输编码头避免冲突）
      upstreamResp.headers.forEach((name, values) {
        if (name.toLowerCase() != 'transfer-encoding') {
          for (var v in values) {
            clientReq.response.headers.add(name, v);
          }
        }
      });

      // 零拷贝直通推流
      await clientReq.response.addStream(upstreamResp);
      await clientReq.response.close();
    } catch (e) {
      debugPrint("🔴 [LocalMediaProxy] 中继流传输异常: $e, url = $targetUrl");
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
    await _server?.close(force: true);
    _server = null;
    localPort = null;
  }
}