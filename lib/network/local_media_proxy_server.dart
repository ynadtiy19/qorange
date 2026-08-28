// lib/network/local_media_proxy_server.dart
import 'dart:convert';
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
      ..maxConnectionsPerHost = 40
      ..autoUncompress = false;
    return _sharedClient!;
  }

  Future<int> start() async {
    if (_server != null) return localPort!;

    _sharedClient?.close(force: true);
    _sharedClient = null;

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
      final targetUri = Uri.parse(targetUrl);
      final upstreamReq = await _client.getUrl(targetUri);

      final range = clientReq.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
      }
      upstreamReq.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      );

      final upstreamResp = await upstreamReq.close();
      final contentType = upstreamResp.headers.contentType?.toString().toLowerCase() ?? '';
      final isM3u8 = targetUrl.contains('.m3u8') || contentType.contains('mpegurl');

      // 🌟 核心：递归重写 M3U8 内的所有子清单与音视频分片切片
      if (isM3u8 && upstreamResp.statusCode == 200) {
        final m3u8RawContent = await upstreamResp.transform(utf8.decoder).join();
        final lines = m3u8RawContent.split('\n');
        final rewrittenLines = <String>[];

        final baseUrl = '${targetUri.scheme}://${targetUri.authority}';

        for (var line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) {
            rewrittenLines.add(line);
          } else {
            String fullSegmentUrl = trimmed;
            if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
              if (trimmed.startsWith('/')) {
                fullSegmentUrl = '$baseUrl$trimmed';
              } else {
                final parentPath = targetUri.pathSegments.sublist(0, targetUri.pathSegments.length - 1).join('/');
                fullSegmentUrl = '$baseUrl/$parentPath/$trimmed';
              }
            }
            rewrittenLines.add(buildPlayUrl(fullSegmentUrl));
          }
        }

        final rewrittenBody = utf8.encode(rewrittenLines.join('\n'));
        clientReq.response.statusCode = HttpStatus.ok;
        clientReq.response.headers.set(HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl');
        clientReq.response.headers.set(HttpHeaders.contentLengthHeader, rewrittenBody.length);
        clientReq.response.add(rewrittenBody);
        await clientReq.response.close();
        return;
      }

      clientReq.response.statusCode = upstreamResp.statusCode;
      upstreamResp.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower != 'transfer-encoding' && lower != 'connection' && lower != 'keep-alive') {
          for (var v in values) {
            clientReq.response.headers.add(name, v);
          }
        }
      });

      await clientReq.response.addStream(upstreamResp);
      await clientReq.response.close();
    } catch (e) {
      try {
        clientReq.response.statusCode = HttpStatus.badGateway;
        await clientReq.response.close();
      } catch (_) {}
    }
  }

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